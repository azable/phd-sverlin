{-# LANGUAGE GADTs #-}

-- | Choreography graph facade and event-to-view replay.
module LinearTrace.Choreography.Graph
  ( VisualTraceGraph
  , ViewGraph
  , visualTraceCore
  , buildViewGraph
  , solveViewGraphWithSeed
  , viewGraphStats
  , runChoreography
  , runChoreographyWith
  ) where

import           LinearTrace.Choreography.Match (MatchSpec,
                                                 buildMatchedViewGraph,
                                                 emptyMatchSpec,
                                                 matchedNodeOutput,
                                                 traceNodeOfEventBlock)
import           LinearTrace.Choreography.Trace (Choreography)
import qualified LinearTrace.Core               as C
import qualified LinearTrace.View               as V
import qualified Prelude                        as P
import qualified Solver                         as S
import           Solver                         (RandomSeed)

data VisualTraceGraph =
  VisualTraceGraph MatchSpec C.TraceGraph

type ViewGraph = V.ViewGraph

visualTraceCore :: VisualTraceGraph -> C.TraceGraph
visualTraceCore (VisualTraceGraph _ coreGraph) = coreGraph

buildViewGraph :: VisualTraceGraph -> ViewGraph
buildViewGraph (VisualTraceGraph spec coreGraph) =
  let stepsOutput = viewTraceSteps spec (C.traceGraphSteps coreGraph)
   in buildMatchedViewGraph
        spec
        (builtSteps stepsOutput)
        (builtNodes stepsOutput)
        (builtConstraints stepsOutput)
        (builtChoiceConstraints stepsOutput)
        (builtRenderFrames stepsOutput)

solveViewGraphWithSeed :: RandomSeed -> ViewGraph -> P.IO S.Solution
solveViewGraphWithSeed = V.solveCSPWithSeed

viewGraphStats :: ViewGraph -> (P.Int, P.Int, P.Int, P.Int)
viewGraphStats graph =
  ( P.length (V.viewNodes graph)
  , P.length (V.viewSteps graph)
  , P.length (V.viewConstraints graph)
  , P.length (V.viewRenderFrames graph))

data BuiltViewStep = BuiltViewStep
  { stepView                 :: V.ViewStep
  , stepNodes                :: [V.ViewNode]
  , stepConstraints          :: [S.Constraint]
  , stepChoiceConstraints    :: [S.ChoiceConstraint]
  , stepRenderFrames         :: [[V.RenderIntent]]
  , stepPendingRenderIntents :: [V.RenderIntent]
  }

data BuiltViewSteps = BuiltViewSteps
  { builtSteps             :: [V.ViewStep]
  , builtNodes             :: [V.ViewNode]
  , builtConstraints       :: [S.Constraint]
  , builtChoiceConstraints :: [S.ChoiceConstraint]
  , builtRenderFrames      :: [[V.RenderIntent]]
  }

data ViewTraceAccumulator = ViewTraceAccumulator
  { viewSteps                :: [V.ViewStep]
  , viewNodes                :: [V.ViewNode]
  , viewConstraints          :: [S.Constraint]
  , viewChoiceConstraints    :: [S.ChoiceConstraint]
  , viewRenderFrames         :: [[V.RenderIntent]]
  , viewPendingRenderIntents :: [V.RenderIntent]
  }

emptyViewTraceAccumulator :: ViewTraceAccumulator
emptyViewTraceAccumulator =
  ViewTraceAccumulator
    { viewSteps = []
    , viewNodes = []
    , viewConstraints = []
    , viewChoiceConstraints = []
    , viewRenderFrames = []
    , viewPendingRenderIntents = []
    }

viewTraceSteps :: MatchSpec -> [C.TraceStep] -> BuiltViewSteps
viewTraceSteps spec records =
  let buildStep = viewTraceStep spec
      ViewTraceAccumulator { viewSteps = steps
                           , viewNodes = nodes
                           , viewConstraints = constraints
                           , viewChoiceConstraints = choiceConstraints
                           , viewRenderFrames = renderFrames
                           , viewPendingRenderIntents = pending
                           } =
        P.foldl (advanceViewTrace buildStep) emptyViewTraceAccumulator records
      finalOutput =
        V.flushViewOutput
          V.ViewOutput
            { V.emittedNodes = []
            , V.emittedConstraints = []
            , V.emittedChoiceConstraints = []
            , V.emittedRenderFrames = []
            , V.pendingRenderIntents = pending
            }
      finalFrames = renderFrames P.++ V.emittedRenderFrames finalOutput
      finalChoiceConstraints =
        choiceConstraints P.++ V.emittedChoiceConstraints finalOutput
   in BuiltViewSteps
        { builtSteps = steps
        , builtNodes = nodes
        , builtConstraints = constraints
        , builtChoiceConstraints = finalChoiceConstraints
        , builtRenderFrames = V.withImplicitInitialFrame finalFrames
        }

advanceViewTrace ::
     ([V.RenderIntent] -> C.TraceStep -> BuiltViewStep)
  -> ViewTraceAccumulator
  -> C.TraceStep
  -> ViewTraceAccumulator
advanceViewTrace buildStep accumulator record =
  let builtStep = buildStep (viewPendingRenderIntents accumulator) record
   in ViewTraceAccumulator
        { viewSteps = viewSteps accumulator P.++ [stepView builtStep]
        , viewNodes = viewNodes accumulator P.++ stepNodes builtStep
        , viewConstraints =
            viewConstraints accumulator P.++ stepConstraints builtStep
        , viewChoiceConstraints =
            viewChoiceConstraints accumulator
              P.++ stepChoiceConstraints builtStep
        , viewRenderFrames =
            viewRenderFrames accumulator P.++ stepRenderFrames builtStep
        , viewPendingRenderIntents = stepPendingRenderIntents builtStep
        }

viewTraceStep :: MatchSpec -> [V.RenderIntent] -> C.TraceStep -> BuiltViewStep
viewTraceStep spec pending = C.foldTraceStep onCheckpoint
  where
    onCheckpoint label _payload events =
      let rawOutput = V.flushViewOutput (buildTraceEventsOutput spec events)
          output = V.mergeInitialRenderIntents pending rawOutput
          nodes = V.emittedNodes output
          constraints = V.emittedConstraints output
          choiceConstraints = V.emittedChoiceConstraints output
          renderFrames = V.emittedRenderFrames output
       in BuiltViewStep
            { stepView = V.ViewStep label nodes constraints []
            , stepNodes = nodes
            , stepConstraints = constraints
            , stepChoiceConstraints = choiceConstraints
            , stepRenderFrames = renderFrames
            , stepPendingRenderIntents = V.pendingRenderIntents output
            }

buildTraceEventsOutput :: MatchSpec -> C.TraceEvents -> V.ViewOutput
buildTraceEventsOutput spec =
  C.foldTraceEvents
    (\output event -> V.appendViewOutput output (viewOutputForEvent spec event))
    V.emptyViewOutput

viewOutputForEvent :: MatchSpec -> C.TraceEvent -> V.ViewOutput
viewOutputForEvent spec event =
  case event of
    C.TraceCreate block ->
      V.appendViewOutput
        (matchedNodeOutput spec block)
        (renderEventBlock V.RenderFresh block)
    C.TraceObserve _block -> V.emptyViewOutput
    C.TraceUse block -> renderEventBlock V.RenderRemove block
    C.TraceCopy originalBlock copyBlock ->
      V.appendViewOutput
        (matchedNodeOutput spec copyBlock)
        (renderEventBlocks V.RenderFork originalBlock copyBlock)
    C.TraceReplace oldBlock outputBlock ->
      V.appendViewOutput
        (matchedNodeOutput spec outputBlock)
        (renderEventBlocks V.RenderContinue oldBlock outputBlock)
    C.TraceApply1 opBlock argBlock outputBlock ->
      V.appendViewOutput
        (matchedNodeOutput spec outputBlock)
        (V.appendViewOutput
           (renderEventBlock V.RenderFresh outputBlock)
           (V.appendViewOutput
              (renderEventBlock V.RenderRemove opBlock)
              (renderEventBlock V.RenderRemove argBlock)))
    C.TraceApply2 opBlock lhsBlock rhsBlock outputBlock ->
      V.appendViewOutput
        (matchedNodeOutput spec outputBlock)
        (V.appendViewOutput
           (renderEventBlock V.RenderFresh outputBlock)
           (V.appendViewOutput
              (renderEventBlock V.RenderRemove opBlock)
              (V.appendViewOutput
                 (renderEventBlock V.RenderRemove lhsBlock)
                 (renderEventBlock V.RenderRemove rhsBlock))))
    C.TraceDestroy block -> renderEventBlock V.RenderRemove block
    C.TraceSeal _ownerBlock _childBlock -> V.emptyViewOutput
    C.TraceUnseal _ownerBlock _childBlock -> V.emptyViewOutput

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

runChoreography :: Choreography () -> VisualTraceGraph
runChoreography = runChoreographyWith emptyMatchSpec

runChoreographyWith :: MatchSpec -> Choreography () -> VisualTraceGraph
runChoreographyWith spec builder = VisualTraceGraph spec (C.buildGraph builder)
