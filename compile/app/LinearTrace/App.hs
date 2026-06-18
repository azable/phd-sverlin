module LinearTrace.App
  ( RunConfig(..)
  , defaultRunConfig
  , buildViewGraph
  , runVisualization
  ) where

import           Control.Monad         (when)
import qualified LinearTrace.Compile   as Compile
import qualified LinearTrace.Core      as Core
import qualified LinearTrace.Print     as Print
import qualified LinearTrace.Solver    as Solver
import qualified LinearTrace.View       as View

data RunConfig = RunConfig
  { runSeed        :: Solver.RandomSeed
  , runShowDetails :: Bool
  , runOutputPath  :: FilePath
  , runPrintTrace  :: Bool
  }

defaultRunConfig :: RunConfig
defaultRunConfig =
  RunConfig
    { runSeed = Solver.defaultRandomSeed
    , runShowDetails = False
    , runOutputPath = "static/compiled.json"
    , runPrintTrace = True
    }

buildViewGraph ::
     View.ViewEvents events
  => Core.TraceGraph events
  -> View.ViewGraph events
buildViewGraph = View.buildCSP

runVisualization ::
     (Print.PrintEvents events, View.ViewEvents events)
  => RunConfig
  -> Core.TraceGraph events
  -> IO (Either String Compile.CompiledVisualization)
runVisualization config graph = do
  when (runPrintTrace config) (Print.printTrace graph)
  let viewGraph = buildViewGraph graph
  solved <- View.solveCSPWithSeed (runSeed config) viewGraph
  Print.printSolvedVisualization (runShowDetails config) solved viewGraph
  case Compile.compileSolvedVisualization solved viewGraph of
    Left err -> pure (Left err)
    Right compiled -> do
      Compile.writeCompiledVisualizationJSON (runOutputPath config) compiled
      pure (Right compiled)
