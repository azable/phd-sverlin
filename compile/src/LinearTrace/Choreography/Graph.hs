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
visualTraceCore graph =
  case graph of
    VisualTraceGraph _ coreGraph -> coreGraph

buildViewGraph :: VisualTraceGraph -> ViewGraph
buildViewGraph graph =
  case graph of
    VisualTraceGraph spec coreGraph ->
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

viewTraceSteps :: MatchSpec -> [C.TraceStep] -> BuiltViewSteps
viewTraceSteps spec = viewTraceStepsWith (viewTraceStep spec) [] [] [] [] [] []

viewTraceStepsWith ::
     ([V.RenderIntent] -> record -> BuiltViewStep)
  -> [V.ViewStep]
  -> [V.ViewNode]
  -> [S.Constraint]
  -> [S.ChoiceConstraint]
  -> [[V.RenderIntent]]
  -> [V.RenderIntent]
  -> [record]
  -> BuiltViewSteps
viewTraceStepsWith buildStep steps nodes constraints choiceConstraints renderFrames pending records =
  case records of
    [] ->
      let finalOutput =
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
    record:rest ->
      let builtStep = buildStep pending record
       in viewTraceStepsWith
            buildStep
            (steps P.++ [stepView builtStep])
            (nodes P.++ stepNodes builtStep)
            (constraints P.++ stepConstraints builtStep)
            (choiceConstraints P.++ stepChoiceConstraints builtStep)
            (renderFrames P.++ stepRenderFrames builtStep)
            (stepPendingRenderIntents builtStep)
            rest

viewTraceStep :: MatchSpec -> [V.RenderIntent] -> C.TraceStep -> BuiltViewStep
viewTraceStep spec pending = C.foldTraceStep onCheckpoint onDiscarded
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
    onDiscarded reason _events =
      BuiltViewStep
        { stepView = V.ViewStep ("Discarded: " P.++ reason) [] [] []
        , stepNodes = []
        , stepConstraints = []
        , stepChoiceConstraints = []
        , stepRenderFrames = []
        , stepPendingRenderIntents = pending
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
