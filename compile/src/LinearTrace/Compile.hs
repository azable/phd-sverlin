{-# LANGUAGE GADTs             #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies      #-}

-- | Compile solved view graphs into the JSON visualization model consumed by
-- the Svelte app. This exposed module depends on the internal view facade and
-- materialization boundary but does not expose symbolic view internals.
module LinearTrace.Compile
  ( -- * Render model
    -- | Concrete JSON-facing render identifiers, style values, elements,
    -- patches, frames, and visualization wrapper produced after solving.
    RenderId(..)
  , StyleValue(..)
  , RenderStyle(..)
  , RenderElement(..)
  , RenderOrigin(..)
  , RenderPatch(..)
  , RenderFrame(..)
  , Visualization(..)
  , -- * Compilation
    -- | Compile a solved symbolic view graph to render frames. The viewport
    -- variant is useful for tests or future non-default canvases.
    withSeed
  , compileSolved
  , compileSolvedWithViewport
  , -- * JSON output
    -- | Encoding and writing helpers used by the executable and top-level
    -- facade. Diagnostics/printing are handled by 'LinearTrace.Print'.
    encodeCompiledPretty
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

freshRenderIdForElement :: RenderElement -> RenderId
freshRenderIdForElement element =
  RenderId
    ("lineage." ++ show (renderNodeId element) ++ "." ++ renderNodeKey element)

--------------------------------------------------------------------------------
-- Compiled CSS style
--------------------------------------------------------------------------------
data StyleValue
  = StyleNumber Double
  | StylePixels Double
  | StyleText String
  | StyleColor String
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

data RenderElement = RenderElement
  { renderNodeId  :: Int
  , renderNodeKey :: String
  , renderContent :: String
  , renderKind    :: String
  , renderStyle   :: RenderStyle
  } deriving (Eq, Show)

data RenderOrigin = RenderOrigin
  { renderOriginId      :: RenderId
  , renderOriginElement :: RenderElement
  } deriving (Eq, Show)

data RenderPatch
  = RenderCreate RenderId (Maybe RenderOrigin) RenderElement
  | RenderUpdate RenderId RenderElement RenderElement
  | RenderDestroy RenderId RenderElement
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
  { lineageByElement :: Map RenderElementKey RenderId
  } deriving (Eq, Show)

emptyCompileState :: CompileState
emptyCompileState = CompileState {lineageByElement = Map.empty}

type CompileM = StateT CompileState (Either String)

type RenderElementKey = (Int, String)

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
      let elementsById = buildElementLookup concreteGraph
      frames' <-
        evalStateT
          (compileFrames
             elementsById
             (VM.concreteViewRenderFrames concreteGraph))
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
compileFrames :: ElementLookup -> [[V.RenderIntent]] -> CompileM [RenderFrame]
compileFrames elementsById renderFrames = do
  frames' <- traverse (compileRenderFrame elementsById) renderFrames
  pure (filter (not . null . framePatches) frames')

compileRenderFrame :: ElementLookup -> [V.RenderIntent] -> CompileM RenderFrame
compileRenderFrame elementsById renderIntents = do
  patches <- compileRenderIntents elementsById renderIntents
  coalesced <- lift (coalesceFramePatches patches)
  pure RenderFrame {framePatches = coalesced}

compileRenderIntents ::
     ElementLookup -> [V.RenderIntent] -> CompileM [RenderPatch]
compileRenderIntents elementsById intents = do
  patches <- traverse (compileRenderIntent elementsById) intents
  pure (concat patches)

--------------------------------------------------------------------------------
-- Frame coalescing
--------------------------------------------------------------------------------
data CoalescedPatch
  = CoalescedCreate (Maybe RenderOrigin) RenderElement
  | CoalescedUpdate RenderElement RenderElement
  | CoalescedDestroy RenderElement
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
    RenderCreate renderId origin element ->
      updateCoalesced
        renderId
        (coalesceCreate renderId origin element)
        coalesceState
    RenderUpdate renderId fromElement toElement ->
      updateCoalesced
        renderId
        (coalesceUpdate renderId fromElement toElement)
        coalesceState
    RenderDestroy renderId element ->
      updateCoalesced renderId (coalesceDestroy renderId element) coalesceState

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
  -> RenderElement
  -> Maybe CoalescedPatch
  -> Either String (Maybe CoalescedPatch)
coalesceCreate renderId origin element existing =
  case existing of
    Nothing -> Right (Just (CoalescedCreate origin element))
    Just _  -> Left (duplicateLifecycleError "create" renderId)

coalesceUpdate ::
     RenderId
  -> RenderElement
  -> RenderElement
  -> Maybe CoalescedPatch
  -> Either String (Maybe CoalescedPatch)
coalesceUpdate renderId fromElement toElement existing =
  case existing of
    Nothing -> Right (Just (CoalescedUpdate fromElement toElement))
    Just existingPatch ->
      case existingPatch of
        CoalescedCreate origin currentElement ->
          if currentElement == fromElement
            then Right (Just (CoalescedCreate origin toElement))
            else Left (inconsistentLifecycleError "update" renderId)
        CoalescedUpdate firstElement currentElement ->
          if currentElement == fromElement
            then Right (Just (CoalescedUpdate firstElement toElement))
            else Left (inconsistentLifecycleError "update" renderId)
        CoalescedDestroy _ ->
          Left (invalidLifecycleError "update after destroy" renderId)

coalesceDestroy ::
     RenderId
  -> RenderElement
  -> Maybe CoalescedPatch
  -> Either String (Maybe CoalescedPatch)
coalesceDestroy renderId element existing =
  case existing of
    Nothing -> Right (Just (CoalescedDestroy element))
    Just existingPatch ->
      case existingPatch of
        CoalescedCreate _ currentElement ->
          if currentElement == element
            then Right Nothing
            else Left (inconsistentLifecycleError "destroy" renderId)
        CoalescedUpdate firstElement currentElement ->
          if currentElement == element
            then Right (Just (CoalescedDestroy firstElement))
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
    CoalescedCreate origin element -> RenderCreate renderId origin element
    CoalescedUpdate fromElement toElement ->
      RenderUpdate renderId fromElement toElement
    CoalescedDestroy element -> RenderDestroy renderId element

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
compileRenderIntent :: ElementLookup -> V.RenderIntent -> CompileM [RenderPatch]
compileRenderIntent elementsById intent =
  case intent of
    V.RenderFresh ref              -> createRef elementsById ref
    V.RenderContinue source target -> continueRef elementsById source target
    V.RenderFork source target     -> forkRef elementsById source target
    V.RenderRemove ref             -> destroyRef elementsById ref

createRef :: ElementLookup -> V.ViewRef tag -> CompileM [RenderPatch]
createRef elementsById ref = do
  elements <- requireElementsByRef elementsById ref
  traverse createElement elements

destroyRef :: ElementLookup -> V.ViewRef tag -> CompileM [RenderPatch]
destroyRef elementsById ref = do
  elements <- requireElementsByRef elementsById ref
  traverse destroyElement elements

continueRef ::
     ElementLookup
  -> V.ViewRef source
  -> V.ViewRef target
  -> CompileM [RenderPatch]
continueRef elementsById sourceRef targetRef = do
  sourceElements <- requireElementsByRef elementsById sourceRef
  targetElements <- requireElementsByRef elementsById targetRef
  continueElements sourceElements targetElements

forkRef ::
     ElementLookup
  -> V.ViewRef source
  -> V.ViewRef target
  -> CompileM [RenderPatch]
forkRef elementsById sourceRef targetRef = do
  sourceElements <- requireElementsByRef elementsById sourceRef
  targetElements <- requireElementsByRef elementsById targetRef
  traverse (forkElement sourceElements) targetElements

createElement :: RenderElement -> CompileM RenderPatch
createElement element = do
  let renderId = freshRenderIdForElement element
  modify
    (\st ->
       st
         { lineageByElement =
             Map.insert
               (renderElementKey element)
               renderId
               (lineageByElement st)
         })
  pure (RenderCreate renderId Nothing element)

destroyElement :: RenderElement -> CompileM RenderPatch
destroyElement element = do
  renderId <- requireLineage element
  modify
    (\st ->
       st
         { lineageByElement =
             Map.delete (renderElementKey element) (lineageByElement st)
         })
  pure (RenderDestroy renderId element)

continueElements :: [RenderElement] -> [RenderElement] -> CompileM [RenderPatch]
continueElements sourceElements targetElements = do
  updates <- traverse (continueTarget sourceElements) targetElements
  destroys <-
    traverse destroyElement (sourceOnlyElements sourceElements targetElements)
  pure (updates ++ destroys)

continueTarget :: [RenderElement] -> RenderElement -> CompileM RenderPatch
continueTarget sourceElements targetElement =
  case findMatchingElement targetElement sourceElements of
    Just sourceElement -> do
      renderId <- requireLineage sourceElement
      modify
        (\st ->
           st
             { lineageByElement =
                 Map.insert
                   (renderElementKey targetElement)
                   renderId
                   (Map.delete
                      (renderElementKey sourceElement)
                      (lineageByElement st))
             })
      pure (RenderUpdate renderId sourceElement targetElement)
    Nothing -> createElement targetElement

forkElement :: [RenderElement] -> RenderElement -> CompileM RenderPatch
forkElement sourceElements targetElement = do
  let targetRenderId = freshRenderIdForElement targetElement
  origin <-
    case findMatchingElement targetElement sourceElements of
      Nothing -> pure Nothing
      Just sourceElement -> do
        sourceRenderId <- requireLineage sourceElement
        pure (Just (RenderOrigin sourceRenderId sourceElement))
  modify
    (\st ->
       st
         { lineageByElement =
             Map.insert
               (renderElementKey targetElement)
               targetRenderId
               (lineageByElement st)
         })
  pure (RenderCreate targetRenderId origin targetElement)

--------------------------------------------------------------------------------
-- Lineage lookup
--------------------------------------------------------------------------------
renderElementKey :: RenderElement -> RenderElementKey
renderElementKey element = (renderNodeId element, renderNodeKey element)

renderElementKeyLabel :: RenderElement -> String
renderElementKeyLabel element =
  "N" ++ show (renderNodeId element) ++ "." ++ renderNodeKey element

findMatchingElement :: RenderElement -> [RenderElement] -> Maybe RenderElement
findMatchingElement targetElement sourceElements =
  case sourceElements of
    [] -> Nothing
    sourceElement:rest ->
      if renderNodeKey sourceElement == renderNodeKey targetElement
        then Just sourceElement
        else findMatchingElement targetElement rest

sourceOnlyElements :: [RenderElement] -> [RenderElement] -> [RenderElement]
sourceOnlyElements sourceElements targetElements =
  filter
    (\sourceElement ->
       renderNodeKey sourceElement `notElem` map renderNodeKey targetElements)
    sourceElements

requireLineage :: RenderElement -> CompileM RenderId
requireLineage element = do
  st <- get
  case Map.lookup (renderElementKey element) (lineageByElement st) of
    Just renderId -> pure renderId
    Nothing ->
      lift (Left ("no render lineage for " ++ renderElementKeyLabel element))

--------------------------------------------------------------------------------
-- Concrete element lookup
--------------------------------------------------------------------------------
type ElementLookup = Map Int [RenderElement]

buildElementLookup :: VM.ConcreteViewGraph -> ElementLookup
buildElementLookup graph =
  foldl insertConcreteNode Map.empty (VM.concreteViewNodes graph)

insertConcreteNode :: ElementLookup -> VM.ConcreteNode -> ElementLookup
insertConcreteNode elements node =
  let compiled = compileConcreteNode node
   in Map.insertWith (++) (renderNodeId compiled) [compiled] elements

compileConcreteNode :: VM.ConcreteNode -> RenderElement
compileConcreteNode node =
  RenderElement
    { renderNodeId = nodeIdOfViewId (VM.concreteNodeId node)
    , renderNodeKey = VM.concreteNodeKey node
    , renderContent = VM.concreteNodeContent node
    , renderKind = payloadViewKind (VM.concreteNodeLabel node)
    , renderStyle = compileConcreteStyle CssTarget (VM.concreteNodeStyle node)
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
    VM.ConcreteColorField _ attrName hsl ->
      case attrName of
        Just name -> [(name, StyleColor (hslToCss alphaValue hsl))]
        Nothing   -> []
    VM.ConcreteTokenField _ attrName token -> stringCssAttr attrName token

stringCssAttr :: Maybe String -> String -> [(String, StyleValue)]
stringCssAttr maybeName value =
  case maybeName of
    Just name -> [(name, StyleText value)]
    Nothing   -> []

hslToCss :: Double -> VM.ConcreteHsl -> String
hslToCss alpha hsl =
  let h = formatCssNumber (V.hue hsl)
      s = formatCssPercent01 (V.saturation hsl)
      l = formatCssPercent01 (V.lightness hsl)
      a = formatCssNumber (clamp 0 1 alpha)
   in "hsl(" ++ h ++ " " ++ s ++ " " ++ l ++ " / " ++ a ++ ")"

requireElementsByRef ::
     ElementLookup -> V.ViewRef tag -> CompileM [RenderElement]
requireElementsByRef elementsById ref =
  case Map.lookup (nodeIdOfRef ref) elementsById of
    Just elements -> pure elements
    Nothing       -> pure []

nodeIdOfRef :: V.ViewRef tag -> Int
nodeIdOfRef = V.viewRefInt

nodeIdOfViewId :: V.ViewId -> Int
nodeIdOfViewId = V.viewIdInt

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

instance ToJSON RenderElement where
  toJSON element =
    object
      [ "nodeId" .= renderNodeId element
      , "nodeKey" .= renderNodeKey element
      , "kind" .= renderKind element
      , "content" .= renderContent element
      , "style" .= renderStyle element
      ]

instance ToJSON RenderOrigin where
  toJSON origin =
    object
      ["id" .= renderOriginId origin, "element" .= renderOriginElement origin]

instance ToJSON RenderPatch where
  toJSON patch =
    case patch of
      RenderCreate renderId origin element ->
        object
          (["kind" .= String "create", "id" .= renderId, "element" .= element]
             ++ maybe [] (\origin' -> ["origin" .= origin']) origin)
      RenderUpdate renderId fromElement toElement ->
        object
          [ "kind" .= String "update"
          , "id" .= renderId
          , "from" .= fromElement
          , "to" .= toElement
          ]
      RenderDestroy renderId element ->
        object
          ["kind" .= String "destroy", "id" .= renderId, "element" .= element]

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
