{-# LANGUAGE GADTs             #-}
{-# LANGUAGE OverloadedStrings #-}

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
  , printCompiledJSON
  , writeCompiledJSON
  ) where

import           Control.Monad
import           Control.Monad.State.Strict
import           Data.Aeson
import           Data.Aeson.Encode.Pretty   (encodePretty)
import qualified Data.Aeson.Key             as Key
import qualified Data.ByteString.Lazy       as BL
import           Data.Map.Strict            (Map)
import qualified Data.Map.Strict            as Map
import qualified LinearTrace.Core.Internal  as C
import qualified LinearTrace.Solver         as S
import qualified LinearTrace.View           as V
import           Numeric                    (showFFloat)
import           Prelude

newtype RenderId =
  RenderId String
  deriving (Eq, Ord, Show)

freshRenderIdForBlock :: C.BlockId -> RenderId
freshRenderIdForBlock blockId = RenderId ("lineage." ++ show blockId)

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

data RenderStyle = RenderStyle
  { renderTop    :: Double
  , renderLeft   :: Double
  , renderWidth  :: Double
  , renderHeight :: Double
  , renderAttrs  :: Map String StyleValue
  } deriving (Eq, Show)

data RenderBlock = RenderBlock
  { renderBlockId   :: C.BlockId
  , renderContent   :: String
  , renderKind      :: String
  , renderStyle     :: RenderStyle
  , renderClassName :: Maybe String
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
  { lineageByBlock :: Map C.BlockId RenderId
  } deriving (Eq, Show)

emptyCompileState :: CompileState
emptyCompileState = CompileState {lineageByBlock = Map.empty}

type CompileM = StateT CompileState (Either String)

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
  case buildBlockLookup solution graph of
    Left err -> Left err
    Right blocksById -> do
      frames' <-
        evalStateT
          (compileFrames blocksById (V.viewRenderFrames graph))
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
compileFrames ::
     Map C.BlockId RenderBlock -> [[V.RenderIntent]] -> CompileM [RenderFrame]
compileFrames blocksById renderFrames = do
  frames' <- traverse (compileRenderFrame blocksById) renderFrames
  pure (filter (not . null . framePatches) frames')

compileRenderFrame ::
     Map C.BlockId RenderBlock -> [V.RenderIntent] -> CompileM RenderFrame
compileRenderFrame blocksById renderIntents = do
  patches <- compileRenderIntents blocksById renderIntents
  coalesced <- lift (coalesceFramePatches patches)
  pure RenderFrame {framePatches = coalesced}

compileRenderIntents ::
     Map C.BlockId RenderBlock -> [V.RenderIntent] -> CompileM [RenderPatch]
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
compileRenderIntent ::
     Map C.BlockId RenderBlock -> V.RenderIntent -> CompileM [RenderPatch]
compileRenderIntent blocksById intent =
  case intent of
    V.RenderFresh ref              -> createRef blocksById ref
    V.RenderContinue source target -> continueRef blocksById source target
    V.RenderFork source target     -> forkRef blocksById source target
    V.RenderRemove ref             -> destroyRef blocksById ref

createRef ::
     Map C.BlockId RenderBlock -> C.BlockRef tag -> CompileM [RenderPatch]
createRef blocksById ref = do
  block <- requireBlockByRef blocksById ref
  let renderId = freshRenderIdForBlock (renderBlockId block)
  modify
    (\st ->
       st
         { lineageByBlock =
             Map.insert (renderBlockId block) renderId (lineageByBlock st)
         })
  pure [RenderCreate renderId Nothing block]

destroyRef ::
     Map C.BlockId RenderBlock -> C.BlockRef tag -> CompileM [RenderPatch]
destroyRef blocksById ref = do
  block <- requireBlockByRef blocksById ref
  renderId <- requireLineage block
  modify
    (\st ->
       st
         {lineageByBlock = Map.delete (renderBlockId block) (lineageByBlock st)})
  pure [RenderDestroy renderId block]

continueRef ::
     Map C.BlockId RenderBlock
  -> C.BlockRef source
  -> C.BlockRef target
  -> CompileM [RenderPatch]
continueRef blocksById sourceRef targetRef = do
  sourceBlock <- requireBlockByRef blocksById sourceRef
  targetBlock <- requireBlockByRef blocksById targetRef
  renderId <- requireLineage sourceBlock
  modify
    (\st ->
       st
         { lineageByBlock =
             Map.insert
               (renderBlockId targetBlock)
               renderId
               (Map.delete (renderBlockId sourceBlock) (lineageByBlock st))
         })
  pure [RenderUpdate renderId sourceBlock targetBlock]

forkRef ::
     Map C.BlockId RenderBlock
  -> C.BlockRef source
  -> C.BlockRef target
  -> CompileM [RenderPatch]
forkRef blocksById sourceRef targetRef = do
  sourceBlock <- requireBlockByRef blocksById sourceRef
  sourceRenderId <- requireLineage sourceBlock
  targetBlock <- requireBlockByRef blocksById targetRef
  let targetRenderId = freshRenderIdForBlock (renderBlockId targetBlock)
  modify
    (\st ->
       st
         { lineageByBlock =
             Map.insert
               (renderBlockId targetBlock)
               targetRenderId
               (lineageByBlock st)
         })
  pure
    [ RenderCreate
        targetRenderId
        (Just (RenderOrigin sourceRenderId sourceBlock))
        targetBlock
    ]

--------------------------------------------------------------------------------
-- Lineage lookup
--------------------------------------------------------------------------------
requireLineage :: RenderBlock -> CompileM RenderId
requireLineage block = do
  st <- get
  case Map.lookup (renderBlockId block) (lineageByBlock st) of
    Just renderId -> pure renderId
    Nothing ->
      lift
        (Left ("no render lineage for block B" ++ show (renderBlockId block)))

--------------------------------------------------------------------------------
-- Materialized block lookup
--------------------------------------------------------------------------------
type BlockLookup = Map C.BlockId RenderBlock

buildBlockLookup :: S.Solution -> V.ViewGraph -> Either String BlockLookup
buildBlockLookup solution graph =
  foldM (insertMaterializedNode solution) Map.empty (V.viewNodes graph)

insertMaterializedNode ::
     S.Solution -> BlockLookup -> V.ViewNode -> Either String BlockLookup
insertMaterializedNode solution blocks node =
  case V.materializeViewNode solution node of
    Nothing ->
      Left
        "could not materialize a view node from the solver solution; \
       \a style or geometry Expr probably references a variable that was not \
       \included in any constraint"
    Just materialized ->
      case materialized of
        V.MaterializedBlockViewNode block ->
          let compiled = compileMaterializedBlock block
           in Right (Map.insert (renderBlockId compiled) compiled blocks)

compileMaterializedBlock :: V.MaterializedBlockView tag -> RenderBlock
compileMaterializedBlock block =
  let payload = V.materializedBlockLabel block
      style = V.materializedBlockStyle block
   in RenderBlock
        { renderBlockId = blockIdOfRef (V.materializedBlockRef block)
        , renderContent = payloadViewContent payload
        , renderKind = payloadViewKind payload
        , renderStyle = compileMaterializedStyle style
        , renderClassName = compileCssClass style
        }

compileMaterializedStyle :: V.MaterializedStyle -> RenderStyle
compileMaterializedStyle style =
  RenderStyle
    { renderTop = roundLayout (V.materializedTop style)
    , renderLeft = roundLayout (V.materializedLeft style)
    , renderWidth = roundLayout (V.materializedWidth style)
    , renderHeight = roundLayout (V.materializedHeight style)
    , renderAttrs = compileCssAttrs style
    }

--------------------------------------------------------------------------------
-- CSS mapping
--------------------------------------------------------------------------------
compileCssAttrs :: V.MaterializedStyle -> Map String StyleValue
compileCssAttrs style =
  Map.fromList
    (("position", StyleText "absolute")
       : V.materializedCssAttrsWith
           (StyleNumber . roundLayout)
           (StylePixels . roundLayout)
           StyleText
           (\alpha hsl -> StyleColor (materializedHslToCss alpha hsl))
           style)

compileCssClass :: V.MaterializedStyle -> Maybe String
compileCssClass = V.materializedClassName

materializedHslToCss :: Double -> V.MaterializedHsl -> String
materializedHslToCss alpha hsl =
  let h = formatCssNumber (V.hue hsl)
      s = formatCssPercent01 (V.saturation hsl)
      l = formatCssPercent01 (V.lightness hsl)
      a = formatCssNumber (clamp 0 1 alpha)
   in "hsl(" ++ h ++ " " ++ s ++ " " ++ l ++ " / " ++ a ++ ")"

requireBlockByRef :: BlockLookup -> C.BlockRef tag -> CompileM RenderBlock
requireBlockByRef blocksById ref =
  case Map.lookup (blockIdOfRef ref) blocksById of
    Just block -> pure block
    Nothing ->
      lift (Left ("no materialized block for B" ++ show (blockIdOfRef ref)))

blockIdOfRef :: C.BlockRef tag -> C.BlockId
blockIdOfRef ref =
  case ref of
    C.BlockRef blockId -> blockId

payloadViewContent :: C.PayloadView -> String
payloadViewContent payloadView =
  case payloadView of
    C.PayloadView _kind content -> content

payloadViewKind :: C.PayloadView -> String
payloadViewKind payloadView =
  case payloadView of
    C.PayloadView kind _content -> kind

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
      ([ "blockId" .= renderBlockId block
       , "kind" .= renderKind block
       , "content" .= renderContent block
       , "style" .= renderStyle block
       ]
         ++ maybe
              []
              (\className -> ["className" .= className])
              (renderClassName block))

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
printCompiledJSON compiled = BL.putStr (encodeCompiledPretty compiled)
