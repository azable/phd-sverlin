module App
  ( OutputMode(..)
  , RunConfig(..)
  , defaultRunConfig
  , buildViewGraph
  , runVisualization
  ) where

import           Control.Exception    (evaluate)
import           Control.Monad        (when)
import qualified Data.ByteString.Lazy as BL
import           GHC.Clock            (getMonotonicTimeNSec)
import qualified LinearTrace.Compile  as Compile
import qualified LinearTrace.Print    as Print
import qualified LinearTrace.View     as View
import           Numeric              (showFFloat)
import           System.IO            (Handle, hFlush, hPutStrLn, stderr,
                                       stdout)

data OutputMode
  = OutputFile FilePath
  | OutputStdout Handle

data RunConfig = RunConfig
  { runSeed        :: Int
  , runShowDetails :: Bool
  , runOutputMode  :: OutputMode
  , runDiagnostics :: Bool
  , runPrintTrace  :: Bool
  }

defaultRunConfig :: RunConfig
defaultRunConfig =
  RunConfig
    { runSeed = 0
    , runShowDetails = False
    , runOutputMode = OutputFile "static/compiled.json"
    , runDiagnostics = True
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
  when
    (runDiagnostics config && runPrintTrace config)
    (Print.hPrintTrace diagnostics (View.visualTraceCore graph))
  (viewGraph, viewGraphMs) <-
    timedPhase (evaluate (forceViewGraph (buildViewGraph graph)))
  (solved, solveMs) <-
    timedPhase
      (View.solveCSPWithSeed (View.RandomSeed (runSeed config)) viewGraph)
  when (runDiagnostics config) $ do
    Print.hPrintSolutionByStep
      diagnostics
      (runShowDetails config)
      solved
      viewGraph
    Print.hPrintSolutionSummary diagnostics solved
  (compiledResult, compileMs) <-
    timedPhase
      (evaluate (forceCompileResult (Compile.compileSolved solved viewGraph)))
  case compiledResult of
    Left err -> pure (Left err)
    Right compiled -> do
      let seededCompiled = Compile.withSeed (runSeed config) compiled
      (encoded, encodeMs) <- timedPhase (evaluate (forceEncoded seededCompiled))
      ((), writeMs) <- timedPhase (writeCompiled (runOutputMode config) encoded)
      when
        (runDiagnostics config)
        (hPrintPhaseTimings
           diagnostics
           [ ("View graph", viewGraphMs)
           , ("Solve", solveMs)
           , ("Materialize", compileMs)
           , ("JSON encode", encodeMs)
           , ("JSON write", writeMs)
           ])
      pure (Right seededCompiled)

forceViewGraph :: View.ViewGraph -> View.ViewGraph
forceViewGraph graph =
  length (View.viewNodes graph)
    `seq` length (View.viewSteps graph)
    `seq` length (View.viewConstraints graph)
    `seq` length (View.viewRenderFrames graph)
    `seq` graph

forceCompileResult ::
     Either String Compile.Visualization -> Either String Compile.Visualization
forceCompileResult result =
  case result of
    Left err       -> length err `seq` result
    Right compiled -> compiled `seq` result

forceEncoded :: Compile.Visualization -> BL.ByteString
forceEncoded compiled =
  let encoded = Compile.encodeCompiledPretty compiled
   in BL.length encoded `seq` encoded

timedPhase :: IO a -> IO (a, Double)
timedPhase action = do
  start <- getMonotonicTimeNSec
  result <- action
  end <- getMonotonicTimeNSec
  pure (result, fromIntegral (end - start) / 1000000)

hPrintPhaseTimings :: Handle -> [(String, Double)] -> IO ()
hPrintPhaseTimings handle timings = do
  hPutStrLn handle "Phase timings:"
  mapM_ printTiming timings
  where
    printTiming (name, ms) =
      hPutStrLn handle ("  " ++ name ++ ": " ++ formatMs ms)

formatMs :: Double -> String
formatMs value = showFFloat (Just 1) value "ms"

diagnosticsHandle :: OutputMode -> Handle
diagnosticsHandle outputMode =
  case outputMode of
    OutputFile _       -> stdout
    OutputStdout _json -> stderr

writeCompiled :: OutputMode -> BL.ByteString -> IO ()
writeCompiled outputMode encoded =
  case outputMode of
    OutputFile path -> do
      BL.writeFile path encoded
      putStrLn ("Compiled JSON at: " ++ path)
    OutputStdout handle -> do
      BL.hPut handle encoded
      hPutStrLn handle ""
      hFlush handle
