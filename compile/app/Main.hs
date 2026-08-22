module Main where

import           Control.Exception                 (IOException, evaluate, try)
import           Control.Monad                     (when)
import qualified Data.ByteString.Lazy              as BL
import           Data.Maybe                        (fromMaybe)
import           Data.Word                         (Word64)
import           GHC.Clock                         (getMonotonicTimeNSec)
import           Language.Haskell.Interpreter      (GhcError (..),
                                                    InterpreterError (..))
import qualified LinearTrace.Choreography          as Choreography
import qualified LinearTrace.Visualization.Compile as Compile
import qualified LinearTrace.Visualization.IR      as IR
import qualified LinearTrace.Visualization.Target  as Target
import           Numeric                           (showFFloat)
import           Options.Applicative
import           Sverlin.Interpreter               (withVisualization)
import           Sverlin.Source                    (GeneratedSource (..),
                                                    SourceUnit (..),
                                                    elaborateSource)
import           System.Directory                  (createDirectoryIfMissing)
import           System.Exit                       (exitFailure)
import           System.FilePath                   (takeDirectory)
import           System.IO                         (Handle, hPutStrLn, stderr,
                                                    stdout)
import           System.Random                     (randomRIO)

data Options = Options
  { optionSourcePath  :: FilePath
  , optionSourceLabel :: Maybe FilePath
  , optionEmitHaskell :: Maybe FilePath
  , optionSeed        :: Maybe Int
  , optionOutputPath  :: FilePath
  , optionTarget      :: Target.OutputTarget
  , optionDetails     :: Bool
  }

main :: IO ()
main = do
  options <- execParser optionsParserInfo
  sourceResult <- try (readFile (optionSourcePath options))
  case sourceResult of
    Left err -> failWith (formatSourceReadError options err)
    Right sourceBody' -> do
      let sourceLabel =
            fromMaybe (optionSourcePath options) (optionSourceLabel options)
          generated =
            elaborateSource
              SourceUnit
                {sourceDisplayPath = sourceLabel, sourceBody = sourceBody'}
      emitGeneratedSource (optionEmitHaskell options) generated
      seed <- chooseSeed (optionSeed options)
      sourceStarted <- getMonotonicTimeNSec
      interpreted <-
        withVisualization generated $ \graph -> do
          sourceFinished <- getMonotonicTimeNSec
          runVisualization
            options
            sourceLabel
            (elapsedMs sourceStarted sourceFinished)
            seed
            graph
      case interpreted of
        Left err -> failWith (formatInterpreterError err)
        Right result ->
          case result of
            Left err -> failWith err
            Right _  -> pure ()
  where
    failWith err = do
      hPutStrLn stderr err
      exitFailure

runVisualization ::
     Options
  -> FilePath
  -> Double
  -> Int
  -> Choreography.VisualTraceGraph
  -> IO (Either String IR.CompiledVisualization)
runVisualization options sourcePath sourceLoadMs seed graph = do
  (viewGraph, viewGraphMs) <-
    timedPhase (evaluate (forceViewGraph (Choreography.buildViewGraph graph)))
  (solved, solveMs) <-
    timedPhase
      (Choreography.solveViewGraphWithSeed
         (Choreography.RandomSeed seed)
         viewGraph)
  (compiledResult, compileMs) <-
    timedPhase
      (evaluate
         (forceCompileResult (Compile.compileSolved sourcePath solved viewGraph)))
  case compiledResult of
    Left err -> pure (Left err)
    Right compiled -> do
      (encoded, encodeMs) <-
        timedPhase (evaluate (forceEncoded (optionTarget options) compiled))
      ((), writeMs) <-
        timedPhase (writeCompiled (optionOutputPath options) encoded)
      when (optionDetails options)
        $ hPrintPhaseTimings
            stdout
            [ ("Source load", sourceLoadMs)
            , ("View graph", viewGraphMs)
            , ("Solve", solveMs)
            , ("IR compile", compileMs)
            , ("JSON encode", encodeMs)
            , ("JSON write", writeMs)
            ]
      pure (Right compiled)

forceViewGraph :: Choreography.ViewGraph -> Choreography.ViewGraph
forceViewGraph graph =
  case Choreography.viewGraphStats graph of
    (nodes, constraints, steps) ->
      nodes `seq` constraints `seq` steps `seq` graph

forceCompileResult ::
     Either String IR.CompiledVisualization
  -> Either String IR.CompiledVisualization
forceCompileResult result =
  case result of
    Left err       -> length err `seq` result
    Right compiled -> compiled `seq` result

forceEncoded :: Target.OutputTarget -> IR.CompiledVisualization -> BL.ByteString
forceEncoded target compiled =
  let encoded = Target.compileTarget target compiled
   in BL.length encoded `seq` encoded

timedPhase :: IO a -> IO (a, Double)
timedPhase ioAction = do
  start <- getMonotonicTimeNSec
  result <- ioAction
  end <- getMonotonicTimeNSec
  pure (result, elapsedMs start end)

elapsedMs :: Word64 -> Word64 -> Double
elapsedMs start end = fromIntegral (end - start) / 1000000

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
            "Compile a Sverlin source file, solve its visualization, and write JSON to an output file")

optionsParser :: Parser Options
optionsParser =
  Options
    <$> strOption
          (long "source"
             <> metavar "FILE"
             <> help "Read the Sverlin definition from FILE")
    <*> optional
          (strOption
             (long "source-label"
                <> metavar "PATH"
                <> help "Use PATH in source diagnostics and compiled metadata"))
    <*> optional
          (strOption
             (long "emit-haskell"
                <> metavar "FILE"
                <> help "Also write the generated Haskell module to FILE"))
    <*> optional
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
    <*> switch (long "details" <> help "Print phase timings")

emitGeneratedSource :: Maybe FilePath -> GeneratedSource -> IO ()
emitGeneratedSource output generated =
  case output of
    Nothing -> pure ()
    Just path -> do
      createDirectoryIfMissing True (takeDirectory path)
      writeFile path (generatedModuleText generated)

formatSourceReadError :: Options -> IOException -> String
formatSourceReadError options err =
  "Could not read Sverlin source "
    ++ show (optionSourcePath options)
    ++ ": "
    ++ show err

formatInterpreterError :: InterpreterError -> String
formatInterpreterError (WontCompile errors) = unlines (map errMsg errors)
formatInterpreterError err                  = show err
