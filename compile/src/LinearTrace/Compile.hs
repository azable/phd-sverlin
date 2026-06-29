{-# LANGUAGE GADTs             #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies      #-}

module LinearTrace.Compile
  ( RenderId(..)
  , StyleValue(..)
  , RenderStyle(..)
  , RenderBlock(..)
  , RenderOrigin(..)
  , RenderPatch(..)
  , RenderFrame(..)
  , Visualization(..)
  , withSeed
  , compileSolved
  , compileSolvedWithViewport
  , encodeCompiledPretty
  , hPrintCompiledJSON
  , printCompiledJSON
  , writeCompiledJSON
  ) where

import           Control.Monad
import           Control.Monad.State.Strict
import           Data.Aeson
import           Data.Aeson.Encode.Pretty     (encodePretty)
import qualified Data.Aeson.Key               as Key
import qualified Data.ByteString.Lazy         as BL
import           Data.Map.Strict              (Map)
import qualified Data.Map.Strict              as Map
import qualified LinearTrace.View             as V
import qualified LinearTrace.View.Materialize as VM
import qualified LinearTrace.View.Style       as VS
import           Numeric                      (showFFloat)
import           Prelude
import qualified Solver                       as S
import           System.IO                    (Handle, hFlush, stdout)

newtype RenderId =
  RenderId String
  deriving (Eq, Ord, Show)

freshRenderIdForPiece :: RenderBlock -> RenderId
freshRenderIdForPiece block =
  RenderId
    ("lineage."
       ++ show (renderBlockId block)
       ++ "."
       ++ renderNodeKey block
       ++ "."
       ++ renderPieceKey block)

--------------------------------------------------------------------------------
-- Compiled CSS style
--------------------------------------------------------------------------------
data StyleValue
  = StyleNumber Double
  | StylePixels Double
  | StyleText String
  | StyleColor String
  | StyleBool Bool
  deriving (Eq, Show)

data CssTarget =
  CssTarget

class StyleCompileTarget target where
  type TargetStyleValue target
  targetStyleAttrs ::
       target -> VM.ConcreteStyle -> Map String (TargetStyleValue target)

instance StyleCompileTarget CssTarget where
  type TargetStyleValue CssTarget = StyleValue
  targetStyleAttrs _ = cssStyleAttrs

data RenderStyle = RenderStyle
  { renderTop    :: Double
  , renderLeft   :: Double
  , renderWidth  :: Double
  , renderHeight :: Double
  , renderAttrs  :: Map String StyleValue
  } deriving (Eq, Show)

data RenderBlock = RenderBlock
  { renderBlockId  :: Int
  , renderNodeKey  :: String
  , renderPieceKey :: String
  , renderContent  :: String
  , renderKind     :: String
  , renderStyle    :: RenderStyle
  } deriving (Eq, Show)

data RenderOrigin = RenderOrigin
  { renderOriginId      :: RenderId
  , renderOriginElement :: RenderBlock
  } deriving (Eq, Show)

data RenderPatch
  = RenderCreate RenderId (Maybe RenderOrigin) RenderBlock
  | RenderUpdate RenderId RenderBlock RenderBlock
  | RenderDestroy RenderId RenderBlock
  deriving (Eq, Show)

newtype RenderFrame = RenderFrame
  { framePatches :: [RenderPatch]
  } deriving (Eq, Show)

data Visualization = Compiled
  { compiledSeed   :: Maybe Int
  , compiledWidth  :: Double
  , compiledHeight :: Double
  , frames         :: [RenderFrame]
  } deriving (Eq, Show)

withSeed :: Int -> Visualization -> Visualization
withSeed seed compiled = compiled {compiledSeed = Just seed}

defaultCompiledWidth :: Double
defaultCompiledWidth = 800

defaultCompiledHeight :: Double
defaultCompiledHeight = 600

--------------------------------------------------------------------------------
-- Compiler state
--------------------------------------------------------------------------------
newtype CompileState = CompileState
  { lineageByBlock :: Map RenderBlockKey RenderId
  } deriving (Eq, Show)

emptyCompileState :: CompileState
emptyCompileState = CompileState {lineageByBlock = Map.empty}

type CompileM = StateT CompileState (Either String)

type RenderBlockKey = (Int, String, String)

type RenderPieceKey = (String, String)

--------------------------------------------------------------------------------
-- Public compiler
--------------------------------------------------------------------------------
compileSolved :: S.Solution -> V.ViewGraph -> Either String Visualization
compileSolved =
  compileSolvedWithViewport defaultCompiledWidth defaultCompiledHeight

compileSolvedWithViewport ::
     Double
  -> Double
  -> S.Solution
  -> V.ViewGraph
  -> Either String Visualization
compileSolvedWithViewport viewportWidth viewportHeight solution graph =
  case VM.materializeViewGraph solution graph of
    Left err -> Left err
    Right concreteGraph -> do
      let blocksById = buildBlockLookup concreteGraph
      frames' <-
        evalStateT
          (compileFrames blocksById (VM.concreteViewRenderFrames concreteGraph))
          emptyCompileState
      pure
        Compiled
          { compiledSeed = Nothing
          , compiledWidth = roundLayout viewportWidth
          , compiledHeight = roundLayout viewportHeight
          , frames = frames'
          }

--------------------------------------------------------------------------------
-- Frame compilation
--------------------------------------------------------------------------------
compileFrames :: BlockLookup -> [[V.RenderIntent]] -> CompileM [RenderFrame]
compileFrames blocksById renderFrames = do
  frames' <- traverse (compileRenderFrame blocksById) renderFrames
  pure (filter (not . null . framePatches) frames')

compileRenderFrame :: BlockLookup -> [V.RenderIntent] -> CompileM RenderFrame
compileRenderFrame blocksById renderIntents = do
  patches <- compileRenderIntents blocksById renderIntents
  coalesced <- lift (coalesceFramePatches patches)
  pure RenderFrame {framePatches = coalesced}

compileRenderIntents ::
     BlockLookup -> [V.RenderIntent] -> CompileM [RenderPatch]
compileRenderIntents blocksById intents = do
  patches <- traverse (compileRenderIntent blocksById) intents
  pure (concat patches)

--------------------------------------------------------------------------------
-- Frame coalescing
--------------------------------------------------------------------------------
data CoalescedPatch
  = CoalescedCreate (Maybe RenderOrigin) RenderBlock
  | CoalescedUpdate RenderBlock RenderBlock
  | CoalescedDestroy RenderBlock
  deriving (Eq, Show)

data CoalesceState = CoalesceState
  { coalesceOrder   :: [RenderId]
  , coalescePatches :: Map RenderId CoalescedPatch
  } deriving (Eq, Show)

emptyCoalesceState :: CoalesceState
emptyCoalesceState =
  CoalesceState {coalesceOrder = [], coalescePatches = Map.empty}

coalesceFramePatches :: [RenderPatch] -> Either String [RenderPatch]
coalesceFramePatches patches = do
  finalState <- foldM coalescePatch emptyCoalesceState patches
  pure
    (renderCoalescedPatches
       (coalesceOrder finalState)
       (coalescePatches finalState))

coalescePatch :: CoalesceState -> RenderPatch -> Either String CoalesceState
coalescePatch coalesceState patch =
  case patch of
    RenderCreate renderId origin block ->
      updateCoalesced
        renderId
        (coalesceCreate renderId origin block)
        coalesceState
    RenderUpdate renderId fromBlock toBlock ->
      updateCoalesced
        renderId
        (coalesceUpdate renderId fromBlock toBlock)
        coalesceState
    RenderDestroy renderId block ->
      updateCoalesced renderId (coalesceDestroy renderId block) coalesceState

updateCoalesced ::
     RenderId
  -> (Maybe CoalescedPatch -> Either String (Maybe CoalescedPatch))
  -> CoalesceState
  -> Either String CoalesceState
updateCoalesced renderId reducer coalesceState = do
  reduced <- reducer (Map.lookup renderId (coalescePatches coalesceState))
  let order' = rememberRenderId renderId (coalesceOrder coalesceState)
  let patches' =
        case reduced of
          Nothing -> Map.delete renderId (coalescePatches coalesceState)
          Just patch ->
            Map.insert renderId patch (coalescePatches coalesceState)
  pure coalesceState {coalesceOrder = order', coalescePatches = patches'}

rememberRenderId :: RenderId -> [RenderId] -> [RenderId]
rememberRenderId renderId order =
  if renderId `elem` order
    then order
    else order ++ [renderId]

coalesceCreate ::
     RenderId
  -> Maybe RenderOrigin
  -> RenderBlock
  -> Maybe CoalescedPatch
  -> Either String (Maybe CoalescedPatch)
coalesceCreate renderId origin block existing =
  case existing of
    Nothing -> Right (Just (CoalescedCreate origin block))
    Just _  -> Left (duplicateLifecycleError "create" renderId)

coalesceUpdate ::
     RenderId
  -> RenderBlock
  -> RenderBlock
  -> Maybe CoalescedPatch
  -> Either String (Maybe CoalescedPatch)
coalesceUpdate renderId fromBlock toBlock existing =
  case existing of
    Nothing -> Right (Just (CoalescedUpdate fromBlock toBlock))
    Just existingPatch ->
      case existingPatch of
        CoalescedCreate origin currentBlock ->
          if currentBlock == fromBlock
            then Right (Just (CoalescedCreate origin toBlock))
            else Left (inconsistentLifecycleError "update" renderId)
        CoalescedUpdate firstBlock currentBlock ->
          if currentBlock == fromBlock
            then Right (Just (CoalescedUpdate firstBlock toBlock))
            else Left (inconsistentLifecycleError "update" renderId)
        CoalescedDestroy _ ->
          Left (invalidLifecycleError "update after destroy" renderId)

coalesceDestroy ::
     RenderId
  -> RenderBlock
  -> Maybe CoalescedPatch
  -> Either String (Maybe CoalescedPatch)
coalesceDestroy renderId block existing =
  case existing of
    Nothing -> Right (Just (CoalescedDestroy block))
    Just existingPatch ->
      case existingPatch of
        CoalescedCreate _ currentBlock ->
          if currentBlock == block
            then Right Nothing
            else Left (inconsistentLifecycleError "destroy" renderId)
        CoalescedUpdate firstBlock currentBlock ->
          if currentBlock == block
            then Right (Just (CoalescedDestroy firstBlock))
            else Left (inconsistentLifecycleError "destroy" renderId)
        CoalescedDestroy _ -> Left (duplicateLifecycleError "destroy" renderId)

renderCoalescedPatches ::
     [RenderId] -> Map RenderId CoalescedPatch -> [RenderPatch]
renderCoalescedPatches order patches =
  case order of
    [] -> []
    renderId:rest ->
      case Map.lookup renderId patches of
        Nothing -> renderCoalescedPatches rest patches
        Just patch ->
          renderCoalescedPatch renderId patch
            : renderCoalescedPatches rest patches

renderCoalescedPatch :: RenderId -> CoalescedPatch -> RenderPatch
renderCoalescedPatch renderId patch =
  case patch of
    CoalescedCreate origin block      -> RenderCreate renderId origin block
    CoalescedUpdate fromBlock toBlock -> RenderUpdate renderId fromBlock toBlock
    CoalescedDestroy block            -> RenderDestroy renderId block

duplicateLifecycleError :: String -> RenderId -> String
duplicateLifecycleError operation renderId =
  "duplicate render " ++ operation ++ " in one frame for " ++ show renderId

invalidLifecycleError :: String -> RenderId -> String
invalidLifecycleError operation renderId =
  "invalid render lifecycle: " ++ operation ++ " for " ++ show renderId

inconsistentLifecycleError :: String -> RenderId -> String
inconsistentLifecycleError operation renderId =
  "inconsistent render "
    ++ operation
    ++ " chain in one frame for "
    ++ show renderId

--------------------------------------------------------------------------------
-- Visual lifecycle semantics
--------------------------------------------------------------------------------
compileRenderIntent :: BlockLookup -> V.RenderIntent -> CompileM [RenderPatch]
compileRenderIntent blocksById intent =
  case intent of
    V.RenderFresh ref              -> createRef blocksById ref
    V.RenderContinue source target -> continueRef blocksById source target
    V.RenderFork source target     -> forkRef blocksById source target
    V.RenderRemove ref             -> destroyRef blocksById ref

createRef :: BlockLookup -> V.ViewRef tag -> CompileM [RenderPatch]
createRef blocksById ref = do
  blocks <- requireBlocksByRef blocksById ref
  traverse createBlock blocks

destroyRef :: BlockLookup -> V.ViewRef tag -> CompileM [RenderPatch]
destroyRef blocksById ref = do
  blocks <- requireBlocksByRef blocksById ref
  traverse destroyBlock blocks

continueRef ::
     BlockLookup
  -> V.ViewRef source
  -> V.ViewRef target
  -> CompileM [RenderPatch]
continueRef blocksById sourceRef targetRef = do
  sourceBlocks <- requireBlocksByRef blocksById sourceRef
  targetBlocks <- requireBlocksByRef blocksById targetRef
  continueBlocks sourceBlocks targetBlocks

forkRef ::
     BlockLookup
  -> V.ViewRef source
  -> V.ViewRef target
  -> CompileM [RenderPatch]
forkRef blocksById sourceRef targetRef = do
  sourceBlocks <- requireBlocksByRef blocksById sourceRef
  targetBlocks <- requireBlocksByRef blocksById targetRef
  traverse (forkBlock sourceBlocks) targetBlocks

createBlock :: RenderBlock -> CompileM RenderPatch
createBlock block = do
  let renderId = freshRenderIdForPiece block
  modify
    (\st ->
       st
         { lineageByBlock =
             Map.insert (renderBlockKey block) renderId (lineageByBlock st)
         })
  pure (RenderCreate renderId Nothing block)

destroyBlock :: RenderBlock -> CompileM RenderPatch
destroyBlock block = do
  renderId <- requireLineage block
  modify
    (\st ->
       st
         { lineageByBlock =
             Map.delete (renderBlockKey block) (lineageByBlock st)
         })
  pure (RenderDestroy renderId block)

continueBlocks :: [RenderBlock] -> [RenderBlock] -> CompileM [RenderPatch]
continueBlocks sourceBlocks targetBlocks = do
  updates <- traverse (continueTarget sourceBlocks) targetBlocks
  destroys <- traverse destroyBlock (sourceOnlyBlocks sourceBlocks targetBlocks)
  pure (updates ++ destroys)

continueTarget :: [RenderBlock] -> RenderBlock -> CompileM RenderPatch
continueTarget sourceBlocks targetBlock =
  case findMatchingPiece targetBlock sourceBlocks of
    Just sourceBlock -> do
      renderId <- requireLineage sourceBlock
      modify
        (\st ->
           st
             { lineageByBlock =
                 Map.insert
                   (renderBlockKey targetBlock)
                   renderId
                   (Map.delete (renderBlockKey sourceBlock) (lineageByBlock st))
             })
      pure (RenderUpdate renderId sourceBlock targetBlock)
    Nothing -> createBlock targetBlock

forkBlock :: [RenderBlock] -> RenderBlock -> CompileM RenderPatch
forkBlock sourceBlocks targetBlock = do
  let targetRenderId = freshRenderIdForPiece targetBlock
  origin <-
    case findMatchingPiece targetBlock sourceBlocks of
      Nothing -> pure Nothing
      Just sourceBlock -> do
        sourceRenderId <- requireLineage sourceBlock
        pure (Just (RenderOrigin sourceRenderId sourceBlock))
  modify
    (\st ->
       st
         { lineageByBlock =
             Map.insert
               (renderBlockKey targetBlock)
               targetRenderId
               (lineageByBlock st)
         })
  pure (RenderCreate targetRenderId origin targetBlock)

--------------------------------------------------------------------------------
-- Lineage lookup
--------------------------------------------------------------------------------
renderBlockKey :: RenderBlock -> RenderBlockKey
renderBlockKey block =
  (renderBlockId block, renderNodeKey block, renderPieceKey block)

renderPieceIdentity :: RenderBlock -> RenderPieceKey
renderPieceIdentity block = (renderNodeKey block, renderPieceKey block)

renderBlockKeyLabel :: RenderBlock -> String
renderBlockKeyLabel block =
  "B"
    ++ show (renderBlockId block)
    ++ "."
    ++ renderNodeKey block
    ++ "."
    ++ renderPieceKey block

findMatchingPiece :: RenderBlock -> [RenderBlock] -> Maybe RenderBlock
findMatchingPiece targetBlock sourceBlocks =
  case sourceBlocks of
    [] -> Nothing
    sourceBlock:rest ->
      if renderPieceIdentity sourceBlock == renderPieceIdentity targetBlock
        then Just sourceBlock
        else findMatchingPiece targetBlock rest

sourceOnlyBlocks :: [RenderBlock] -> [RenderBlock] -> [RenderBlock]
sourceOnlyBlocks sourceBlocks targetBlocks =
  filter
    (\sourceBlock ->
       renderPieceIdentity sourceBlock
         `notElem` map renderPieceIdentity targetBlocks)
    sourceBlocks

requireLineage :: RenderBlock -> CompileM RenderId
requireLineage block = do
  st <- get
  case Map.lookup (renderBlockKey block) (lineageByBlock st) of
    Just renderId -> pure renderId
    Nothing ->
      lift (Left ("no render lineage for " ++ renderBlockKeyLabel block))

--------------------------------------------------------------------------------
-- Solved block lookup
--------------------------------------------------------------------------------
type BlockLookup = Map Int [RenderBlock]

buildBlockLookup :: VM.ConcreteViewGraph -> BlockLookup
buildBlockLookup graph =
  foldl insertConcreteNode Map.empty (VM.concreteViewNodes graph)

insertConcreteNode :: BlockLookup -> VM.ConcreteViewNode -> BlockLookup
insertConcreteNode blocks node =
  let compiled = compileConcreteViewNode node
   in Map.insertWith (++) (renderBlockId compiled) [compiled] blocks

compileConcreteViewNode :: VM.ConcreteViewNode -> RenderBlock
compileConcreteViewNode node =
  case node of
    VM.ConcreteBlockViewNode block     -> compileConcreteBlock block
    VM.ConcreteVirtualViewNode virtual -> compileConcreteVirtual virtual

compileConcreteBlock :: VM.ConcreteBlockView tag -> RenderBlock
compileConcreteBlock block =
  RenderBlock
    { renderBlockId = blockIdOfRef (VM.concreteBlockRef block)
    , renderNodeKey = VM.concreteBlockNodeKey block
    , renderPieceKey = VM.concreteBlockPieceKey block
    , renderContent = VM.concreteBlockContent block
    , renderKind = payloadViewKind (VM.concreteBlockLabel block)
    , renderStyle = compileConcreteStyle CssTarget (VM.concreteBlockStyle block)
    }

compileConcreteVirtual :: VM.ConcreteVirtualView tag -> RenderBlock
compileConcreteVirtual virtual =
  RenderBlock
    { renderBlockId = blockIdOfRef (VM.concreteVirtualRef virtual)
    , renderNodeKey = VM.concreteVirtualNodeKey virtual
    , renderPieceKey = VM.concreteVirtualPieceKey virtual
    , renderContent = VM.concreteVirtualContent virtual
    , renderKind = payloadViewKind (VM.concreteVirtualLabel virtual)
    , renderStyle =
        compileConcreteStyle CssTarget (VM.concreteVirtualStyle virtual)
    }

compileConcreteStyle :: CssTarget -> VM.ConcreteStyle -> RenderStyle
compileConcreteStyle target style =
  RenderStyle
    { renderTop = roundLayout (VM.concreteTop style)
    , renderLeft = roundLayout (VM.concreteLeft style)
    , renderWidth = roundLayout (VM.concreteWidth style)
    , renderHeight = roundLayout (VM.concreteHeight style)
    , renderAttrs = targetStyleAttrs target style
    }

--------------------------------------------------------------------------------
-- CSS mapping
--------------------------------------------------------------------------------
cssStyleAttrs :: VM.ConcreteStyle -> Map String StyleValue
cssStyleAttrs style =
  Map.fromList
    (("position", StyleText "absolute")
       : concatMap (concreteFieldCssAttrs alphaValue) (VM.concreteFields style))
  where
    alphaValue = VM.concreteScalarValue "alpha" 1 style

concreteFieldCssAttrs :: Double -> VM.ConcreteField -> [(String, StyleValue)]
concreteFieldCssAttrs alphaValue field =
  case field of
    VM.ConcreteScalarField _ attrName value unit ->
      case (attrName, unit) of
        (Just name, VS.StyleNumber) -> [(name, StyleNumber (roundLayout value))]
        (Just name, VS.StylePixels) -> [(name, StylePixels (roundLayout value))]
        _                           -> []
    VM.ConcreteColorField _ attrName maybeHsl ->
      case (attrName, maybeHsl) of
        (Just name, Just hsl) -> [(name, StyleColor (hslToCss alphaValue hsl))]
        _                     -> []
    VM.ConcreteTextField _ attrName maybeText ->
      stringCssAttr attrName (VS.styleTextString <$> maybeText)
    VM.ConcreteChoiceField _ attrName maybeToken _ ->
      stringCssAttr attrName maybeToken

stringCssAttr :: Maybe String -> Maybe String -> [(String, StyleValue)]
stringCssAttr maybeName maybeValue =
  case (maybeName, maybeValue) of
    (Just name, Just value) -> [(name, StyleText value)]
    _                       -> []

hslToCss :: Double -> VM.ConcreteHsl -> String
hslToCss alpha hsl =
  let h = formatCssNumber (V.hue hsl)
      s = formatCssPercent01 (V.saturation hsl)
      l = formatCssPercent01 (V.lightness hsl)
      a = formatCssNumber (clamp 0 1 alpha)
   in "hsl(" ++ h ++ " " ++ s ++ " " ++ l ++ " / " ++ a ++ ")"

requireBlocksByRef :: BlockLookup -> V.ViewRef tag -> CompileM [RenderBlock]
requireBlocksByRef blocksById ref =
  case Map.lookup (blockIdOfRef ref) blocksById of
    Just blocks -> pure blocks
    Nothing     -> pure []

blockIdOfRef :: V.ViewRef tag -> Int
blockIdOfRef = V.viewRefInt

payloadViewKind :: V.ViewLabel -> String
payloadViewKind = V.viewLabelKind

--------------------------------------------------------------------------------
-- Number formatting and rounding
--------------------------------------------------------------------------------
roundLayout :: Double -> Double
roundLayout = roundTo 3

roundTo :: Int -> Double -> Double
roundTo places x =
  cleanNegativeZero (fromIntegral (round (x * scale) :: Integer) / scale)
  where
    scale = 10 ^ places

cleanNegativeZero :: Double -> Double
cleanNegativeZero x =
  if abs x < 0.0005
    then 0
    else x

clamp :: Double -> Double -> Double -> Double
clamp lo hi x = max lo (min hi x)

formatCssPixels :: Double -> String
formatCssPixels x = formatCssNumber x ++ "px"

formatCssPercent01 :: Double -> String
formatCssPercent01 x = formatCssNumber (100 * clamp 0 1 x) ++ "%"

formatCssNumber :: Double -> String
formatCssNumber value =
  trimTrailingZeros (showFFloat (Just 3) (roundLayout value) "")

trimTrailingZeros :: String -> String
trimTrailingZeros text =
  case break (== '.') text of
    (_whole, "") -> text
    (whole, dotAndFraction) ->
      let fraction = drop 1 dotAndFraction
          trimmedFraction = reverse (dropWhile (== '0') (reverse fraction))
       in case trimmedFraction of
            "" -> whole
            _  -> whole ++ "." ++ trimmedFraction

--------------------------------------------------------------------------------
-- JSON helpers
--------------------------------------------------------------------------------
instance ToJSON RenderId where
  toJSON (RenderId text) = toJSON text

instance ToJSON StyleValue where
  toJSON value =
    case value of
      StyleNumber x   -> toJSON (roundLayout x)
      StylePixels x   -> toJSON (formatCssPixels x)
      StyleText text  -> toJSON text
      StyleColor text -> toJSON text
      StyleBool bool  -> toJSON bool

instance ToJSON RenderStyle where
  toJSON style =
    object
      ([ "top" .= StylePixels (renderTop style)
       , "left" .= StylePixels (renderLeft style)
       , "width" .= StylePixels (renderWidth style)
       , "height" .= StylePixels (renderHeight style)
       ]
         ++ map styleAttrPair (Map.toAscList (renderAttrs style)))

styleAttrPair :: (KeyValue e kv, ToJSON v) => (String, v) -> kv
styleAttrPair (name, value) = Key.fromString name .= value

instance ToJSON RenderBlock where
  toJSON block =
    object
      [ "blockId" .= renderBlockId block
      , "nodeKey" .= renderNodeKey block
      , "pieceKey" .= renderPieceKey block
      , "kind" .= renderKind block
      , "content" .= renderContent block
      , "style" .= renderStyle block
      ]

instance ToJSON RenderOrigin where
  toJSON origin =
    object
      ["id" .= renderOriginId origin, "element" .= renderOriginElement origin]

instance ToJSON RenderPatch where
  toJSON patch =
    case patch of
      RenderCreate renderId origin block ->
        object
          (["kind" .= String "create", "id" .= renderId, "element" .= block]
             ++ maybe [] (\origin' -> ["origin" .= origin']) origin)
      RenderUpdate renderId fromBlock toBlock ->
        object
          [ "kind" .= String "update"
          , "id" .= renderId
          , "from" .= fromBlock
          , "to" .= toBlock
          ]
      RenderDestroy renderId block ->
        object
          ["kind" .= String "destroy", "id" .= renderId, "element" .= block]

instance ToJSON RenderFrame where
  toJSON (RenderFrame patches) = toJSON patches

instance ToJSON Visualization where
  toJSON compiled =
    object
      $ maybe [] (\seed -> ["seed" .= seed]) (compiledSeed compiled)
          ++ [ "canvas"
                 .= object
                      [ "width" .= roundLayout (compiledWidth compiled)
                      , "height" .= roundLayout (compiledHeight compiled)
                      ]
             , "frames" .= frames compiled
             ]

encodeCompiledPretty :: Visualization -> BL.ByteString
encodeCompiledPretty = encodePretty

writeCompiledJSON :: FilePath -> Visualization -> IO ()
writeCompiledJSON path compiled =
  BL.writeFile path (encodeCompiledPretty compiled)

printCompiledJSON :: Visualization -> IO ()
printCompiledJSON = hPrintCompiledJSON stdout

hPrintCompiledJSON :: Handle -> Visualization -> IO ()
hPrintCompiledJSON handle compiled = do
  BL.hPut handle (encodeCompiledPretty compiled)
  hFlush handle
