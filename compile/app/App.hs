module App
  ( RunConfig(..)
  , defaultRunConfig
  , buildViewGraph
  , runVisualization
  ) where

import           Control.Monad       (when)
import qualified LinearTrace.Compile as Compile
import qualified LinearTrace.Print   as Print
import qualified LinearTrace.View    as View

data RunConfig = RunConfig
  { runSeed        :: Int
  , runShowDetails :: Bool
  , runOutputPath  :: FilePath
  , runPrintTrace  :: Bool
  }

defaultRunConfig :: RunConfig
defaultRunConfig =
  RunConfig
    { runSeed = 0
    , runShowDetails = False
    , runOutputPath = "static/compiled.json"
    , runPrintTrace = True
    }

buildViewGraph :: View.VisualTraceGraph -> View.ViewGraph
buildViewGraph = View.buildCSP

runVisualization ::
     RunConfig
  -> View.VisualTraceGraph
  -> IO (Either String Compile.Visualization)
runVisualization config graph = do
  when (runPrintTrace config) (Print.printTrace graph)
  let viewGraph = buildViewGraph graph
  solved <- View.solveCSPWithSeed (View.RandomSeed (runSeed config)) viewGraph
  Print.printSolutionByStep (runShowDetails config) solved viewGraph
  Print.printSolutionSummary solved
  case Compile.compileSolved solved viewGraph of
    Left err -> pure (Left err)
    Right compiled -> do
      Compile.writeCompiledJSON (runOutputPath config) compiled
      putStrLn ("Compiled JSON at: " ++ runOutputPath config)
      pure (Right compiled)
