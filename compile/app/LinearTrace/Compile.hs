{-# LANGUAGE GADTs             #-}
{-# LANGUAGE OverloadedStrings #-}

module LinearTrace.Compile
  ( RenderId(..)
  , -- * Compiled geometry
    RenderStyle(..)
  , RenderBlock(..)
  , -- * Lifecycle patches
    RenderPatch(..)
  , RenderFrame(..)
  , CompiledVisualization(..)
  , -- * Compilation
    compileSolvedVisualization
  , printCompiledVisualizationJSON
  , writeCompiledVisualizationJSON
  ) where

import           Control.Monad
import           Control.Monad.State.Strict
import           Data.Aeson
import           Data.Aeson.Encode.Pretty   (encodePretty)
import qualified Data.ByteString.Lazy       as BL
import           Data.Map.Strict            (Map)
import qualified Data.Map.Strict            as Map
import qualified LinearTrace.Core           as C
import qualified LinearTrace.Solver         as S
import qualified LinearTrace.Visualize      as V
import           Prelude

newtype RenderId =
  RenderId String
  deriving (Eq, Ord, Show)

freshRenderIdForBlock :: C.BlockId -> RenderId
freshRenderIdForBlock blockId = RenderId ("lineage." ++ show blockId)

--------------------------------------------------------------------------------
-- Compiled geometry
--------------------------------------------------------------------------------
data RenderStyle = RenderStyle
  { renderTop    :: Double
  , renderLeft   :: Double
  , renderWidth  :: Double
  , renderHeight :: Double
  } deriving (Eq, Show)

data RenderBlock = RenderBlock
  { renderBlockId :: C.BlockId
  , renderLabel   :: String
  , renderStyle   :: RenderStyle
  } deriving (Eq, Show)

data RenderPatch
  = RenderCreate RenderId RenderBlock
  | RenderUpdate RenderId RenderBlock RenderBlock
  | RenderDestroy RenderId RenderBlock
  deriving (Eq, Show)

data RenderFrame = RenderFrame
  { frameIndex   :: Int
  , framePatches :: [RenderPatch]
  } deriving (Eq, Show)

newtype CompiledVisualization = CompiledVisualization
  { frames :: [RenderFrame]
  } deriving (Eq, Show)

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
compileSolvedVisualization solution graph =
  case buildBlockLookup solution graph of
    Left err -> Left err
    Right blocksById -> do
      frames <-
        evalStateT
          (compileFrames blocksById (V.viewSteps graph))
          emptyCompileState
      pure CompiledVisualization {frames = frames}

--------------------------------------------------------------------------------
-- Frame compilation
--------------------------------------------------------------------------------
compileFrames ::
     Map C.BlockId RenderBlock -> [V.ViewStep events] -> CompileM [RenderFrame]
compileFrames blocksById steps =
  traverse (\(ix, step) -> compileFrame blocksById ix step) (zip [0 ..] steps)

compileFrame ::
     Map C.BlockId RenderBlock
  -> Int
  -> V.ViewStep events
  -> CompileM RenderFrame
compileFrame blocksById ix step =
  case step of
    V.ViewStep traceEvent _nodes _constraints -> do
      patches <- compileTraceEvent blocksById traceEvent
      pure RenderFrame {frameIndex = ix, framePatches = patches}

compileTraceEvent ::
     Map C.BlockId RenderBlock -> C.TraceEvent events -> CompileM [RenderPatch]
compileTraceEvent blocksById traceEvent =
  case traceEvent of
    C.TraceEvent _event audit -> compileAudit blocksById audit

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
    C.CreateStep snapshot -> createSnapshot blocksById snapshot
    C.ObserveStep _snapshot -> pure []
    C.InspectStep _snapshot -> pure []
    C.UseStep snapshot -> destroySnapshot blocksById snapshot
    C.CopyStep _original copy' -> createSnapshot blocksById copy'
    C.ReplaceStep old incoming output ->
      replaceSnapshot blocksById old incoming output
    C.ComputeStep snapshot -> createSnapshot blocksById snapshot
    C.DestroyStep snapshot -> destroySnapshot blocksById snapshot
    C.SealStep _owner _child -> pure []
    C.UnsealStep _owner _child -> pure []
    C.DecideStep _snapshot -> pure []

--------------------------------------------------------------------------------
-- Primitive lifecycle operations
--------------------------------------------------------------------------------
createSnapshot ::
     Map C.BlockId RenderBlock -> C.BlockSnapshot tag -> CompileM [RenderPatch]
createSnapshot blocksById snapshot = do
  block <- requireBlock blocksById snapshot
  let renderId = freshRenderIdForBlock (renderBlockId block)
  modify
    (\st ->
       st
         { lineageByBlock =
             Map.insert (renderBlockId block) renderId (lineageByBlock st)
         })
  pure [RenderCreate renderId block]

destroySnapshot ::
     Map C.BlockId RenderBlock -> C.BlockSnapshot tag -> CompileM [RenderPatch]
destroySnapshot blocksById snapshot = do
  block <- requireBlock blocksById snapshot
  renderId <- requireLineage block
  modify
    (\st ->
       st
         {lineageByBlock = Map.delete (renderBlockId block) (lineageByBlock st)})
  pure [RenderDestroy renderId block]

replaceSnapshot ::
     Map C.BlockId RenderBlock
  -> C.BlockSnapshot tag
  -> C.BlockSnapshot tag
  -> C.BlockSnapshot tag
  -> CompileM [RenderPatch]
replaceSnapshot blocksById oldSnapshot incomingSnapshot outputSnapshot = do
  oldBlock <- requireBlock blocksById oldSnapshot
  incomingBlock <- requireBlock blocksById incomingSnapshot
  outputBlock <- requireBlock blocksById outputSnapshot
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
    Nothing -> Left "could not materialize a view node from the solver solution"
    Just materialized ->
      case materialized of
        V.MaterializedBlockViewNode block ->
          let compiled = compileMaterializedBlock block
           in Right (Map.insert (renderBlockId compiled) compiled blocks)

compileMaterializedBlock :: V.MaterializedBlockView tag -> RenderBlock
compileMaterializedBlock block =
  RenderBlock
    { renderBlockId = blockIdOfRef (V.materializedBlockRef block)
    , renderLabel = payloadViewText (V.materializedBlockLabel block)
    , renderStyle = compileMaterializedStyle (V.materializedBlockStyle block)
    }

compileMaterializedStyle :: V.MaterializedStyle -> RenderStyle
compileMaterializedStyle style =
  RenderStyle
    { renderTop = V.materializedTop style
    , renderLeft = V.materializedLeft style
    , renderWidth = V.materializedWidth style
    , renderHeight = V.materializedHeight style
    }

requireBlock :: BlockLookup -> C.BlockSnapshot tag -> CompileM RenderBlock
requireBlock blocksById snapshot =
  case Map.lookup (snapshotBlockId snapshot) blocksById of
    Just block -> pure block
    Nothing ->
      lift
        (Left ("no materialized block for B" ++ show (snapshotBlockId snapshot)))

--------------------------------------------------------------------------------
-- Core helpers
--------------------------------------------------------------------------------
snapshotBlockId :: C.BlockSnapshot tag -> C.BlockId
snapshotBlockId snapshot =
  case snapshot of
    C.BlockSnapshot ref _payload _view -> blockIdOfRef ref

blockIdOfRef :: C.BlockRef tag -> C.BlockId
blockIdOfRef ref =
  case ref of
    C.BlockRef blockId -> blockId

payloadViewText :: C.PayloadView -> String
payloadViewText payloadView =
  case payloadView of
    C.PayloadView text -> text

--------------------------------------------------------------------------------
-- JSON helpers
--------------------------------------------------------------------------------
instance ToJSON RenderId where
  toJSON (RenderId text) = toJSON text

instance ToJSON RenderStyle where
  toJSON style =
    object
      [ "top" .= renderTop style
      , "left" .= renderLeft style
      , "width" .= renderWidth style
      , "height" .= renderHeight style
      ]

instance ToJSON RenderBlock where
  toJSON block =
    object
      [ "blockId" .= renderBlockId block
      , "label" .= renderLabel block
      , "style" .= renderStyle block
      ]

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
  toJSON frame =
    object ["index" .= frameIndex frame, "patches" .= framePatches frame]

instance ToJSON CompiledVisualization where
  toJSON compiled = object ["frames" .= frames compiled]

encodeCompiledVisualizationPretty :: CompiledVisualization -> BL.ByteString
encodeCompiledVisualizationPretty = encodePretty

writeCompiledVisualizationJSON :: FilePath -> CompiledVisualization -> IO ()
writeCompiledVisualizationJSON path compiled =
  BL.writeFile path (encodeCompiledVisualizationPretty compiled)

printCompiledVisualizationJSON :: CompiledVisualization -> IO ()
printCompiledVisualizationJSON compiled =
  BL.putStr (encodeCompiledVisualizationPretty compiled)
