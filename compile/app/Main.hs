module Main where

import           Control.Exception                        (evaluate)
import           Data.ByteString.Lazy                     qualified as BL
import           DSL.Main
import           GHC.Clock                                (getMonotonicTimeNSec)
import           LinearTrace.Choreography                 qualified as Choreography
import           LinearTrace.Visualization.Compile        qualified as Compile
import           LinearTrace.Visualization.IR             qualified as IR
import           LinearTrace.Visualization.Target         qualified as Target
import           Numeric                                  (showFFloat)
import           Options.Applicative
import           System.Exit                              (exitFailure)
import           System.IO                                (Handle, hPutStrLn,
                                                           stderr, stdout)
import           System.Random                            (randomRIO)

data Options = Options
  { optionSeed              :: Maybe Int
  , optionOutputPath        :: FilePath
  , optionTarget            :: Target.OutputTarget
  }

main :: IO ()
main = do
  options <- execParser optionsParserInfo
  seed <- chooseSeed (optionSeed options)
  result <- runVisualization options seed (run example)
  case result of
    Left err -> do
      hPutStrLn stderr err
      exitFailure
    Right _ -> pure ()

runVisualization ::
     Options
  -> Int
  -> Choreography.VisualTraceGraph
  -> IO (Either String IR.VisualizationPackage)
runVisualization options seed graph = do
  (viewGraph, viewGraphMs) <-
    timedPhase
      (evaluate (forceViewGraph (Choreography.buildViewGraph graph)))
  (solved, solveMs) <-
    timedPhase
      (Choreography.solveViewGraphWithSeed
         (Choreography.RandomSeed seed)
         viewGraph)
  (compiledResult, compileMs) <-
    timedPhase
      (evaluate
         (forceCompileResult
            (Compile.compileSolved dslSourcePath solved viewGraph)))
  case compiledResult of
    Left err -> pure (Left err)
    Right compiled -> do
      (encoded, encodeMs) <-
        timedPhase
          (evaluate (forceEncoded (optionTarget options) compiled))
      ((), writeMs) <-
        timedPhase (writeCompiled (optionOutputPath options) encoded)
      hPrintPhaseTimings
        stdout
        [ ("View graph", viewGraphMs)
        , ("Solve", solveMs)
        , ("IR compile", compileMs)
        , ("JSON encode", encodeMs)
        , ("JSON write", writeMs)
        ]
      pure (Right compiled)

dslSourcePath :: FilePath
dslSourcePath = "compile/app/DSL/Main.hs"

forceViewGraph :: Choreography.ViewGraph -> Choreography.ViewGraph
forceViewGraph graph =
  case Choreography.viewGraphStats graph of
    (nodes, constraints, steps) ->
      nodes `seq` constraints `seq` steps `seq` graph

forceCompileResult ::
     Either String IR.VisualizationPackage
  -> Either String IR.VisualizationPackage
forceCompileResult result =
  case result of
    Left err       -> length err `seq` result
    Right compiled -> compiled `seq` result

forceEncoded :: Target.OutputTarget -> IR.VisualizationPackage -> BL.ByteString
forceEncoded target compiled =
  let encoded = Target.compileTarget target compiled
   in BL.length encoded `seq` encoded

timedPhase :: IO a -> IO (a, Double)
timedPhase ioAction = do
  start <- getMonotonicTimeNSec
  result <- ioAction
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
formatMs milliseconds = showFFloat (Just 1) milliseconds "ms"

writeCompiled :: FilePath -> BL.ByteString -> IO ()
writeCompiled path encoded = do
  BL.writeFile path encoded
  putStrLn ("Compiled JSON at: " ++ path)

chooseSeed :: Maybe Int -> IO Int
chooseSeed = maybe (randomRIO (minSeed, maxSeed)) pure

minSeed :: Int
minSeed = -2147483648

maxSeed :: Int
maxSeed = 2147483646

optionsParserInfo :: ParserInfo Options
optionsParserInfo =
  info
    (optionsParser <**> helper)
    (fullDesc
       <> progDesc
            "Compile the example trace, solve its visualization, and write JSON to an output file")

optionsParser :: Parser Options
optionsParser =
  Options
    <$> optional
          (option
             auto
             (long "seed"
                <> short 's'
                <> metavar "INT"
                <> help
                     "Use a deterministic solver seed instead of generating a random one"))
    <*> strOption
          (long "output"
             <> short 'o'
             <> metavar "FILE"
             <> help "Write compiled visualization JSON to FILE")
    <*> option
          (eitherReader Target.parseOutputTarget)
          (long "target"
             <> metavar "TARGET"
             <> value Target.IrJson
             <> showDefaultWith Target.outputTargetName
             <> help "Compile to TARGET (currently: ir-json)")
