{-# LANGUAGE GADTs #-}

-- | Choreography graph facade and event-to-view replay.
module LinearTrace.Choreography.Graph
  ( VisualTraceGraph
  , ViewGraph
  , buildViewGraph
  , solveViewGraphWithSeed
  , solveViewGraphWithSeeds
  , viewGraphStats
  , runChoreography
  , runChoreographyWith
  ) where

import           LinearTrace.Choreography.Match (MatchSpec,
                                                 buildMatchedViewGraph,
                                                 emptyMatchSpec,
                                                 matchedNodeOutput,
                                                 traceNodeOfEventBlock)
import qualified LinearTrace.Core               as C
import qualified LinearTrace.View.Build         as V
import qualified LinearTrace.View.Graph         as V
import qualified LinearTrace.View.Solve         as V
import qualified Prelude                        as P
import qualified Solver                         as S
import           Solver                         (RandomSeed)

data VisualTraceGraph =
  VisualTraceGraph MatchSpec C.TraceGraph

type ViewGraph = V.ViewGraph

buildViewGraph :: VisualTraceGraph -> ViewGraph
buildViewGraph (VisualTraceGraph spec coreGraph) =
  let output = viewTraceSteps spec (C.traceGraphSteps coreGraph)
   in buildMatchedViewGraph spec (viewNodes output) (viewSteps output)

solveViewGraphWithSeed :: RandomSeed -> ViewGraph -> P.IO S.Solution
solveViewGraphWithSeed = V.solveCSPWithSeed

solveViewGraphWithSeeds :: [RandomSeed] -> ViewGraph -> P.IO [S.Solution]
solveViewGraphWithSeeds = V.solveCSPWithSeeds

viewGraphStats :: ViewGraph -> (P.Int, P.Int, P.Int)
viewGraphStats graph =
  ( P.length (V.viewNodes graph)
  , P.length (V.viewConstraints graph)
  , P.length (V.viewSteps graph))

data ViewTraceAccumulator = ViewTraceAccumulator
  { viewNodes :: [V.ViewNode]
  , viewSteps :: [V.ViewStep]
  }

emptyViewTraceAccumulator :: ViewTraceAccumulator
emptyViewTraceAccumulator =
  ViewTraceAccumulator {viewNodes = [], viewSteps = []}

viewTraceSteps :: MatchSpec -> [C.TraceStep] -> ViewTraceAccumulator
viewTraceSteps spec = P.foldl (advanceViewTrace spec) emptyViewTraceAccumulator

advanceViewTrace ::
     MatchSpec -> ViewTraceAccumulator -> C.TraceStep -> ViewTraceAccumulator
advanceViewTrace spec accumulator record =
  let (label, output) = viewTraceStep spec record
      nodes = V.emittedNodes output
   in ViewTraceAccumulator
        { viewNodes = viewNodes accumulator P.++ nodes
        , viewSteps =
            viewSteps accumulator
              P.++ [V.ViewStep label (V.emittedRenderIntents output)]
        }

viewTraceStep :: MatchSpec -> C.TraceStep -> (P.String, V.ViewOutput)
viewTraceStep spec = C.foldTraceStep onCheckpoint
  where
    onCheckpoint label events = (label, buildTraceEventsOutput spec events)

buildTraceEventsOutput :: MatchSpec -> C.TraceEvents -> V.ViewOutput
buildTraceEventsOutput spec =
  C.foldTraceEvents
    (\output event -> output P.<> viewOutputForEvent spec event)
    P.mempty

viewOutputForEvent :: MatchSpec -> C.TraceEvent -> V.ViewOutput
viewOutputForEvent spec event =
  case event of
    C.TraceCreate block ->
      matchedNodeOutput spec block P.<> renderEventBlock V.RenderFresh block
    C.TraceObserve _block -> P.mempty
    C.TraceUse block -> renderEventBlock V.RenderRemove block
    C.TraceCopy originalBlock copyBlock ->
      matchedNodeOutput spec copyBlock
        P.<> renderEventBlocks V.RenderFork originalBlock copyBlock
    C.TraceReplace oldBlock outputBlock ->
      matchedNodeOutput spec outputBlock
        P.<> renderEventBlocks V.RenderContinue oldBlock outputBlock
    C.TraceApply1 opBlock argBlock outputBlock ->
      P.mconcat
        [ matchedNodeOutput spec outputBlock
        , renderEventBlock V.RenderFresh outputBlock
        , renderEventBlock V.RenderRemove opBlock
        , renderEventBlock V.RenderRemove argBlock
        ]
    C.TraceApply2 opBlock lhsBlock rhsBlock outputBlock ->
      P.mconcat
        [ matchedNodeOutput spec outputBlock
        , renderEventBlock V.RenderFresh outputBlock
        , renderEventBlock V.RenderRemove opBlock
        , renderEventBlock V.RenderRemove lhsBlock
        , renderEventBlock V.RenderRemove rhsBlock
        ]
    C.TraceDestroy block -> renderEventBlock V.RenderRemove block
    C.TraceSeal _ownerBlock _childBlock -> P.mempty
    C.TraceUnseal _ownerBlock _childBlock -> P.mempty

renderEventBlock ::
     (V.ViewRef tag -> V.RenderIntent) -> C.BlockSnapshot tag -> V.ViewOutput
renderEventBlock makeIntent block =
  V.renderIntentOutput (makeIntent (eventBlockViewRef block))

renderEventBlocks ::
     (V.ViewRef source -> V.ViewRef target -> V.RenderIntent)
  -> C.BlockSnapshot source
  -> C.BlockSnapshot target
  -> V.ViewOutput
renderEventBlocks makeIntent sourceBlock targetBlock =
  V.renderIntentOutput
    (makeIntent (eventBlockViewRef sourceBlock) (eventBlockViewRef targetBlock))

eventBlockViewRef :: C.BlockSnapshot tag -> V.ViewRef tag
eventBlockViewRef block = V.nodeRef (traceNodeOfEventBlock block)

runChoreography :: C.TraceBuilder () -> VisualTraceGraph
runChoreography = runChoreographyWith emptyMatchSpec

runChoreographyWith :: MatchSpec -> C.TraceBuilder () -> VisualTraceGraph
runChoreographyWith spec builder = VisualTraceGraph spec (C.buildGraph builder)
