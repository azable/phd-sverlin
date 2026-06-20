module App
  ( OutputMode(..)
  , RunConfig(..)
  , defaultRunConfig
  , buildViewGraph
  , runVisualization
  ) where

import           Control.Monad       (when)
import qualified LinearTrace.Compile as Compile
import qualified LinearTrace.Print   as Print
import qualified LinearTrace.View    as View
import           System.IO           (Handle, stderr, stdout)

data OutputMode
  = OutputFile FilePath
  | OutputStdout

data RunConfig = RunConfig
  { runSeed        :: Int
  , runShowDetails :: Bool
  , runOutputMode  :: OutputMode
  , runPrintTrace  :: Bool
  }

defaultRunConfig :: RunConfig
defaultRunConfig =
  RunConfig
    { runSeed = 0
    , runShowDetails = False
    , runOutputMode = OutputFile "static/compiled.json"
    , runPrintTrace = True
    }

buildViewGraph :: View.VisualTraceGraph -> View.ViewGraph
buildViewGraph = View.buildCSP

runVisualization ::
     RunConfig
  -> View.VisualTraceGraph
  -> IO (Either String Compile.Visualization)
runVisualization config graph = do
  let diagnostics = diagnosticsHandle (runOutputMode config)
  when (runPrintTrace config) (Print.hPrintTrace diagnostics graph)
  let viewGraph = buildViewGraph graph
  solved <- View.solveCSPWithSeed (View.RandomSeed (runSeed config)) viewGraph
  Print.hPrintSolutionByStep
    diagnostics
    (runShowDetails config)
    solved
    viewGraph
  Print.hPrintSolutionSummary diagnostics solved
  case Compile.compileSolved solved viewGraph of
    Left err -> pure (Left err)
    Right compiled -> do
      let seededCompiled = Compile.withSeed (runSeed config) compiled
      writeCompiled (runOutputMode config) seededCompiled
      pure (Right seededCompiled)

diagnosticsHandle :: OutputMode -> Handle
diagnosticsHandle outputMode =
  case outputMode of
    OutputFile _ -> stdout
    OutputStdout -> stderr

writeCompiled :: OutputMode -> Compile.Visualization -> IO ()
writeCompiled outputMode compiled =
  case outputMode of
    OutputFile path -> do
      Compile.writeCompiledJSON path compiled
      putStrLn ("Compiled JSON at: " ++ path)
    OutputStdout -> Compile.printCompiledJSON compiled
