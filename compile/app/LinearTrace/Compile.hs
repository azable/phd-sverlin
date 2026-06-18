{-# LANGUAGE GADTs             #-}
{-# LANGUAGE OverloadedStrings #-}

module LinearTrace.Compile
  ( RenderId(..)
  , StyleValue(..)
  , RenderStyle(..)
  , RenderBlock(..)
  , RenderPatch(..)
  , RenderFrame(..)
  , CompiledVisualization(..)
  , compileSolvedVisualization
  , compileSolvedVisualizationWithViewport
  , encodeCompiledVisualizationPretty
  , printCompiledVisualizationJSON
  , writeCompiledVisualizationJSON
  ) where

import           Control.Monad
import           Control.Monad.State.Strict
import           Data.Aeson
import           Data.Aeson.Encode.Pretty   (encodePretty)
import qualified Data.Aeson.Key             as Key
import qualified Data.ByteString.Lazy       as BL
import           Data.Map.Strict            (Map)
import qualified Data.Map.Strict            as Map
import qualified LinearTrace.Core           as C
import qualified LinearTrace.Solver         as S
import qualified LinearTrace.Visualize      as V
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

data RenderPatch
  = RenderCreate RenderId RenderBlock
  | RenderUpdate RenderId RenderBlock RenderBlock
  | RenderDestroy RenderId RenderBlock
  deriving (Eq, Show)

newtype RenderFrame = RenderFrame
  { framePatches :: [RenderPatch]
  } deriving (Eq, Show)

data CompiledVisualization = CompiledVisualization
  { compiledWidth  :: Double
  , compiledHeight :: Double
  , frames         :: [RenderFrame]
  } deriving (Eq, Show)

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
compileSolvedVisualization ::
     S.Solution -> V.ViewGraph events -> Either String CompiledVisualization
compileSolvedVisualization =
  compileSolvedVisualizationWithViewport
    defaultCompiledWidth
    defaultCompiledHeight

compileSolvedVisualizationWithViewport ::
     Double
  -> Double
  -> S.Solution
  -> V.ViewGraph events
  -> Either String CompiledVisualization
compileSolvedVisualizationWithViewport viewportWidth viewportHeight solution graph =
  case buildBlockLookup solution graph of
    Left err -> Left err
    Right blocksById -> do
      frames' <-
        evalStateT
          (compileFrames blocksById (V.viewSteps graph))
          emptyCompileState
      pure
        CompiledVisualization
          { compiledWidth = roundLayout viewportWidth
          , compiledHeight = roundLayout viewportHeight
          , frames = frames'
          }

--------------------------------------------------------------------------------
-- Frame compilation
--------------------------------------------------------------------------------
compileFrames ::
     Map C.BlockId RenderBlock -> [V.ViewStep events] -> CompileM [RenderFrame]
compileFrames blocksById = traverse (compileFrame blocksById)

compileFrame ::
     Map C.BlockId RenderBlock -> V.ViewStep events -> CompileM RenderFrame
compileFrame blocksById step =
  case step of
    V.ViewStep recordedEvent _nodes _constraints -> do
      patches <- compileRecordedEvent blocksById recordedEvent
      pure RenderFrame {framePatches = patches}

compileRecordedEvent ::
     Map C.BlockId RenderBlock
  -> C.RecordedEvent events
  -> CompileM [RenderPatch]
compileRecordedEvent blocksById recordedEvent =
  case recordedEvent of
    C.RecordedEvent _event audit -> compileAudit blocksById audit

compileAudit ::
     Map C.BlockId RenderBlock -> C.Audit acts -> CompileM [RenderPatch]
compileAudit blocksById audit =
  case audit of
    C.EmptyAudit -> pure []
    step C.:> rest -> do
      here <- compileAuditStep blocksById step
      later <- compileAudit blocksById rest
      pure (here ++ later)

--------------------------------------------------------------------------------
-- Audit-step lifecycle semantics
--------------------------------------------------------------------------------
compileAuditStep ::
     Map C.BlockId RenderBlock -> C.AuditStep act -> CompileM [RenderPatch]
compileAuditStep blocksById step =
  case step of
    C.CreateStep node -> createNode blocksById node
    C.ObserveStep _node -> pure []
    C.InspectStep _node -> pure []
    C.UseStep node -> destroyNode blocksById node
    C.CopyStep _original copy' -> createNode blocksById copy'
    C.ReplaceStep old incoming output ->
      replaceNode blocksById old incoming output
    C.ComputeStep node -> createNode blocksById node
    C.DestroyStep node -> destroyNode blocksById node
    C.SealStep _owner _child -> pure []
    C.UnsealStep _owner _child -> pure []
    C.DecideStep _node -> pure []

--------------------------------------------------------------------------------
-- Primitive lifecycle operations
--------------------------------------------------------------------------------
type TraceNode tag = C.BlockSnapshot tag

createNode ::
     Map C.BlockId RenderBlock -> TraceNode tag -> CompileM [RenderPatch]
createNode blocksById node = do
  block <- requireBlock blocksById node
  let renderId = freshRenderIdForBlock (renderBlockId block)
  modify
    (\st ->
       st
         { lineageByBlock =
             Map.insert (renderBlockId block) renderId (lineageByBlock st)
         })
  pure [RenderCreate renderId block]

destroyNode ::
     Map C.BlockId RenderBlock -> TraceNode tag -> CompileM [RenderPatch]
destroyNode blocksById node = do
  block <- requireBlock blocksById node
  renderId <- requireLineage block
  modify
    (\st ->
       st
         {lineageByBlock = Map.delete (renderBlockId block) (lineageByBlock st)})
  pure [RenderDestroy renderId block]

replaceNode ::
     Map C.BlockId RenderBlock
  -> TraceNode tag
  -> TraceNode tag
  -> TraceNode tag
  -> CompileM [RenderPatch]
replaceNode blocksById oldNode incomingNode outputNode = do
  oldBlock <- requireBlock blocksById oldNode
  incomingBlock <- requireBlock blocksById incomingNode
  outputBlock <- requireBlock blocksById outputNode
  oldRenderId <- requireLineage oldBlock
  incomingRenderId <- requireLineage incomingBlock
  modify
    (\st ->
       st
         { lineageByBlock =
             Map.insert
               (renderBlockId outputBlock)
               incomingRenderId
               (Map.delete
                  (renderBlockId incomingBlock)
                  (Map.delete (renderBlockId oldBlock) (lineageByBlock st)))
         })
  let destroyOld =
        [RenderDestroy oldRenderId oldBlock | oldRenderId /= incomingRenderId]
  pure (destroyOld ++ [RenderUpdate incomingRenderId incomingBlock outputBlock])

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

buildBlockLookup ::
     S.Solution -> V.ViewGraph events -> Either String BlockLookup
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
    ([("position", StyleText "absolute")]
       ++ V.materializedCssAttrsWith
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

--------------------------------------------------------------------------------
-- Render lookup helpers
--------------------------------------------------------------------------------
requireBlock :: BlockLookup -> TraceNode tag -> CompileM RenderBlock
requireBlock blocksById node =
  case Map.lookup (nodeBlockId node) blocksById of
    Just block -> pure block
    Nothing ->
      lift (Left ("no materialized block for B" ++ show (nodeBlockId node)))

nodeBlockId :: TraceNode tag -> C.BlockId
nodeBlockId node =
  case node of
    C.BlockSnapshot ref _payload _view -> blockIdOfRef ref

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

instance ToJSON RenderPatch where
  toJSON patch =
    case patch of
      RenderCreate renderId block ->
        object ["kind" .= String "create", "id" .= renderId, "element" .= block]
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

instance ToJSON CompiledVisualization where
  toJSON compiled =
    object
      [ "canvas"
          .= object
               [ "width" .= roundLayout (compiledWidth compiled)
               , "height" .= roundLayout (compiledHeight compiled)
               ]
      , "frames" .= frames compiled
      ]

encodeCompiledVisualizationPretty :: CompiledVisualization -> BL.ByteString
encodeCompiledVisualizationPretty = encodePretty

writeCompiledVisualizationJSON :: FilePath -> CompiledVisualization -> IO ()
writeCompiledVisualizationJSON path compiled =
  BL.writeFile path (encodeCompiledVisualizationPretty compiled)

printCompiledVisualizationJSON :: CompiledVisualization -> IO ()
printCompiledVisualizationJSON compiled =
  BL.putStr (encodeCompiledVisualizationPretty compiled)
