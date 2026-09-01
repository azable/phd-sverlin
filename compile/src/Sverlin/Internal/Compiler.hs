{-# LANGUAGE GADTs       #-}
{-# LANGUAGE LinearTypes #-}

-- | Private host compiler behind the generated-source packaging boundary.
module Sverlin.Internal.Compiler
  ( SverlinProgram
  , sverlinProgram
  , compileProgramBatch
  ) where

import           Control.Exception                  (ErrorCall,
                                                     displayException, evaluate,
                                                     try)
import qualified LinearTrace.Visualization.Resource as Resource
import qualified Sverlin.Internal.Metrics           as Metrics
import           Sverlin.Internal.Render            (Render,
                                                     RenderDiagnostic (..),
                                                     RenderPlan (..),
                                                     buildRenderPlan)
import qualified Sverlin.Internal.Render.Compile    as Render
import           Sverlin.Internal.Semantic          (Domain, Program,
                                                     SemanticTrace (..),
                                                     runSemanticScenario)

data SverlinProgram where
  SverlinProgram
    :: Domain initial
    -> (initial %1 -> Program ())
    -> Render ()
    -> SverlinProgram

sverlinProgram ::
     Domain initial -> (initial %1 -> Program ()) -> Render () -> SverlinProgram
sverlinProgram = SverlinProgram

-- | Compile one generated scenario and sample its prepared Render design space
-- for every seed in order. The first seed selects the Domain input and also
-- serves as the first view seed.
compileProgramBatch ::
     Metrics.MetricsRecorder
  -> FilePath
  -> String
  -> [Int]
  -> SverlinProgram
  -> IO (Either String Resource.CompilationPackage)
compileProgramBatch _ _ _ [] _ =
  pure (Left "the compiler requires at least one scenario/view seed")
compileProgramBatch recorder sourcePath sourceContent seeds@(scenarioSeed:_) program = do
  attempted <-
    try (compileAction scenarioSeed) :: IO
      (Either ErrorCall (Either String Resource.CompilationPackage))
  pure
    (case attempted of
       Left exception ->
         Left
           ("Sverlin construction failed for "
              ++ sourcePath
              ++ ": "
              ++ displayException exception)
       Right result -> result)
  where
    compileAction seed =
      case program of
        SverlinProgram domain runProgram render -> do
          planResult <-
            Metrics.measurePhase recorder "renderPlanBuild"
              $ evaluate (forcePlanResult (buildRenderPlan render))
          case planResult of
            Left diagnostic -> do
              Metrics.markFailedPhase recorder "renderPlanBuild"
              pure (Left (renderDiagnosticMessage diagnostic))
            Right plan -> do
              recordPlanCounts recorder plan
              trace <-
                Metrics.measurePhase recorder "semanticTraceBuild"
                  $ evaluate
                      (forceTrace (runSemanticScenario seed domain runProgram))
              recordTraceCounts recorder trace
              compiled <-
                Render.compileRenderBatch
                  recorder
                  sourcePath
                  sourceContent
                  seeds
                  trace
                  plan
              case compiled of
                Left err      -> pure (Left (formatRenderCompileError err))
                Right package -> pure (Right package)

forcePlanResult ::
     Either RenderDiagnostic RenderPlan -> Either RenderDiagnostic RenderPlan
forcePlanResult result =
  case result of
    Left diagnostic -> length (renderDiagnosticMessage diagnostic) `seq` result
    Right plan      -> length (show plan) `seq` result

forceTrace :: SemanticTrace -> SemanticTrace
forceTrace trace = length (show trace) `seq` trace

recordTraceCounts :: Metrics.MetricsRecorder -> SemanticTrace -> IO ()
recordTraceCounts recorder trace = do
  Metrics.recordCount
    recorder
    "semanticDeclarations"
    (length (semanticTraceDeclarations trace))
  Metrics.recordCount
    recorder
    "semanticVariables"
    (length (semanticTraceVariables trace))
  Metrics.recordCount
    recorder
    "semanticBlocks"
    (length (semanticTraceBlocks trace))
  Metrics.recordCount
    recorder
    "semanticRelations"
    (length (semanticTraceRelations trace))
  Metrics.recordCount
    recorder
    "semanticSteps"
    (length (semanticTraceSteps trace))
  Metrics.recordCount
    recorder
    "semanticEvents"
    (length (semanticTraceEvents trace))

recordPlanCounts :: Metrics.MetricsRecorder -> RenderPlan -> IO ()
recordPlanCounts recorder plan = do
  Metrics.recordCount recorder "planSelections" (length (planSelections plan))
  Metrics.recordCount
    recorder
    "planRelationSelections"
    (length (planRelationSelections plan))
  Metrics.recordCount recorder "planNodes" (length (planNodes plan))
  Metrics.recordCount recorder "planFrames" (length (planFrames plan))
  Metrics.recordCount recorder "planConstraints" (length (planConstraints plan))
  Metrics.recordCount recorder "planContents" (length (planContents plan))
  Metrics.recordCount recorder "planChoices" (length (planChoices plan))
  Metrics.recordCount recorder "planConnectors" (length (planConnectors plan))

formatRenderCompileError :: Render.RenderCompileError -> String
formatRenderCompileError err =
  case err of
    Render.InvalidRenderPlan message          -> message
    Render.UnsupportedRenderPlan message      -> message
    Render.RenderDesignSpaceError designError -> show designError
