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
import           Sverlin.Internal.Render            (Render,
                                                     RenderDiagnostic (..),
                                                     RenderPlan,
                                                     buildRenderPlan)
import qualified Sverlin.Internal.Render.Compile    as Render
import           Sverlin.Internal.Semantic          (Domain, Program,
                                                     SemanticTrace,
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

data CompiledScenario = CompiledScenario
  { compiledScenarioTrace      :: SemanticTrace
  , compiledScenarioRenderPlan :: RenderPlan
  }

compileScenario ::
     Int -> SverlinProgram -> Either RenderDiagnostic CompiledScenario
compileScenario scenarioSeed (SverlinProgram domain program render) = do
  plan <- buildRenderPlan render
  pure
    CompiledScenario
      { compiledScenarioTrace = runSemanticScenario scenarioSeed domain program
      , compiledScenarioRenderPlan = plan
      }

-- | Compile one generated scenario and sample its prepared Render design space
-- for every seed in order. The first seed selects the Domain input and also
-- serves as the first view seed.
compileProgramBatch ::
     FilePath
  -> String
  -> [Int]
  -> SverlinProgram
  -> IO (Either String Resource.CompilationPackage)
compileProgramBatch _ _ [] _ =
  pure (Left "the compiler requires at least one scenario/view seed")
compileProgramBatch sourcePath sourceContent seeds@(scenarioSeed:_) program = do
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
    compileAction seed = do
      scenarioResult <-
        evaluate (forceScenarioResult (compileScenario seed program))
      case scenarioResult of
        Left diagnostic -> pure (Left (renderDiagnosticMessage diagnostic))
        Right scenario -> do
          compiled <-
            Render.compileRenderBatch
              sourcePath
              sourceContent
              seeds
              (compiledScenarioTrace scenario)
              (compiledScenarioRenderPlan scenario)
          case compiled of
            Left err      -> pure (Left (formatRenderCompileError err))
            Right package -> pure (Right package)

forceScenarioResult ::
     Either RenderDiagnostic CompiledScenario
  -> Either RenderDiagnostic CompiledScenario
forceScenarioResult result =
  case result of
    Left diagnostic -> length (renderDiagnosticMessage diagnostic) `seq` result
    Right scenario ->
      length (show (compiledScenarioTrace scenario))
        `seq` length (show (compiledScenarioRenderPlan scenario))
        `seq` result

formatRenderCompileError :: Render.RenderCompileError -> String
formatRenderCompileError err =
  case err of
    Render.InvalidRenderPlan message          -> message
    Render.UnsupportedRenderPlan message      -> message
    Render.RenderDesignSpaceError designError -> show designError
