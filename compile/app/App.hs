-- | Executable workflow wrapper around choreography, solving, compilation, and
-- JSON writing. The compile server and CLI path call this module rather than
-- reaching into lower layers directly.
module App
  ( -- * Run configuration
    -- | Runtime options for diagnostics, seed selection, and output file path.
    RunConfig(..)
  , defaultRunConfig
  , -- * Workflow
    -- | Build and run the current visualization graph through solve,
    -- canonical IR compilation, target encoding, and file output.
    buildViewGraph
  , runVisualization
  ) where

import           Control.Exception        (evaluate)
import           Control.Monad            (when)
import qualified Data.ByteString.Lazy     as BL
import           GHC.Clock                (getMonotonicTimeNSec)
import qualified LinearTrace.Choreography as Choreography
import qualified LinearTrace.Compile      as Compile
import qualified LinearTrace.Print        as Print
import qualified LinearTrace.Visualization.Target as Target
import           Numeric                  (showFFloat)
import           System.IO                (Handle, hPutStrLn, stdout)

data RunConfig = RunConfig
  { runSeed        :: Int
  , runShowDetails :: Bool
  , runOutputPath  :: FilePath
  , runDiagnostics :: Bool
  , runPrintTrace  :: Bool
  , runOutputTarget :: Target.OutputTarget
  }

defaultRunConfig :: RunConfig
defaultRunConfig =
  RunConfig
    { runSeed = 0
    , runShowDetails = False
    , runOutputPath = "static/compiled.json"
    , runDiagnostics = True
    , runPrintTrace = True
    , runOutputTarget = Target.IrJson
    }

buildViewGraph :: Choreography.VisualTraceGraph -> Choreography.ViewGraph
buildViewGraph = Choreography.buildViewGraph

runVisualization ::
     RunConfig
  -> Choreography.VisualTraceGraph
  -> IO (Either String Compile.Visualization)
runVisualization config graph = do
  let diagnostics = stdout
  when
    (runDiagnostics config && runPrintTrace config)
    (Print.hPrintTrace diagnostics (Choreography.visualTraceCore graph))
  (viewGraph, viewGraphMs) <-
    timedPhase (evaluate (forceViewGraph (buildViewGraph graph)))
  (solved, solveMs) <-
    timedPhase
      (Choreography.solveViewGraphWithSeed
         (Choreography.RandomSeed (runSeed config))
         viewGraph)
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
      (encoded, encodeMs) <-
        timedPhase
          (evaluate
             (forceEncoded (runOutputTarget config) compiled))
      ((), writeMs) <- timedPhase (writeCompiled (runOutputPath config) encoded)
      when
        (runDiagnostics config)
        (hPrintPhaseTimings
           diagnostics
           [ ("View graph", viewGraphMs)
           , ("Solve", solveMs)
           , ("IR compile", compileMs)
           , ("JSON encode", encodeMs)
           , ("JSON write", writeMs)
           ])
      pure (Right compiled)

forceViewGraph :: Choreography.ViewGraph -> Choreography.ViewGraph
forceViewGraph graph =
  case Choreography.viewGraphStats graph of
    (nodes, steps, constraints, renderFrames) ->
      nodes `seq` steps `seq` constraints `seq` renderFrames `seq` graph

forceCompileResult ::
     Either String Compile.Visualization -> Either String Compile.Visualization
forceCompileResult result =
  case result of
    Left err       -> length err `seq` result
    Right compiled -> compiled `seq` result

forceEncoded :: Target.OutputTarget -> Compile.Visualization -> BL.ByteString
forceEncoded target compiled =
  let encoded = Target.compileTarget target compiled
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

writeCompiled :: FilePath -> BL.ByteString -> IO ()
writeCompiled path encoded = do
  BL.writeFile path encoded
  putStrLn ("Compiled JSON at: " ++ path)
