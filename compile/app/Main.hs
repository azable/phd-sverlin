module Main where

import           Control.Exception            (IOException, evaluate, try)
import           Control.Monad                (unless, when)
import qualified Data.ByteString              as BS
import qualified Data.ByteString.Lazy         as BL
import qualified Data.Map.Strict              as Map
import           Data.Maybe                   (fromMaybe)
import           Data.Word                    (Word64)
import           GHC.Clock                    (getMonotonicTimeNSec)
import           Language.Haskell.Interpreter (GhcError (..),
                                               InterpreterError (..))
import           Numeric                      (showFFloat)
import           Options.Applicative
import qualified Sverlin.Internal.Compiler    as Compiler
import qualified Sverlin.Internal.Metrics     as Metrics
import           Sverlin.Interpreter          (withVisualization)
import qualified Sverlin.Output.IR            as IR
import qualified Sverlin.Output.Resource      as Resource
import qualified Sverlin.Output.Target        as Target
import           Sverlin.Source               (GeneratedSource (..),
                                               SourceUnit (..), elaborateSource)
import           System.Directory             (createDirectoryIfMissing)
import           System.Exit                  (exitFailure)
import           System.FilePath              (takeDirectory, (</>))
import           System.IO                    (Handle, hPutStrLn, stderr,
                                               stdout)
import           System.Random                (randomRIO)

data Options = Options
  { optionSourcePath  :: FilePath
  , optionSourceLabel :: Maybe FilePath
  , optionEmitHaskell :: Maybe FilePath
  , optionSeed        :: Maybe Int
  , optionOutputPath  :: FilePath
  , optionTarget      :: Target.OutputTarget
  , optionMetricsPath :: Maybe FilePath
  , optionDetails     :: Bool
  , optionCount       :: Int
  , optionViewSeeds   :: [Int]
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
      seeds <- resolveSeeds options seed
      recorder <- Metrics.newMetricsRecorder seeds
      sourceStarted <- getMonotonicTimeNSec
      interpreted <-
        withVisualization generated $ \program -> do
          sourceFinished <- getMonotonicTimeNSec
          Metrics.recordPhase
            recorder
            "sourceInterpretation"
            (elapsedMs sourceStarted sourceFinished)
          runVisualization
            options
            recorder
            sourceLabel
            sourceBody'
            sourceStarted
            seeds
            program
      sourceFinished <- getMonotonicTimeNSec
      recorded <- Metrics.readCompilerMetrics recorder
      unless
        (Map.member
           "sourceInterpretation"
           (Metrics.compilerMetricPhasesMs recorded)) $ do
        Metrics.recordPhase
          recorder
          "sourceInterpretation"
          (elapsedMs sourceStarted sourceFinished)
        Metrics.markFailedPhase recorder "sourceInterpretation"
      afterSource <- Metrics.readCompilerMetrics recorder
      unless
        (Map.member
           "compilerInternalTotal"
           (Metrics.compilerMetricPhasesMs afterSource))
        $ Metrics.recordPhase
            recorder
            "compilerInternalTotal"
            (elapsedMs sourceStarted sourceFinished)
      finalMetrics <- Metrics.readCompilerMetrics recorder
      writeMetrics options finalMetrics
      when (optionDetails options) (hPrintCompilerMetrics stdout finalMetrics)
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
  -> Metrics.MetricsRecorder
  -> FilePath
  -> String
  -> Word64
  -> [Int]
  -> Compiler.SverlinProgram
  -> IO (Either String [IR.Visualization])
runVisualization options recorder sourcePath sourceBody compilerStarted seeds program = do
  compiledResult <-
    Compiler.compileProgramBatch recorder sourcePath sourceBody seeds program
  case compiledResult of
    Left err -> pure (Left err)
    Right package -> do
      bundleResult <-
        Metrics.measurePhase recorder "targetEncoding"
          $ evaluate
              (forceTargetBundle
                 (Target.compileTarget
                    (Target.defaultTargetRequest (optionTarget options))
                    (forcePackage package)))
      case bundleResult of
        Left (Target.TargetError err) -> do
          Metrics.markFailedPhase recorder "targetEncoding"
          pure (Left err)
        Right bundle -> do
          Metrics.measurePhase recorder "targetWriting"
            $ writeCompiled (optionOutputPath options) bundle
          compilerFinished <- getMonotonicTimeNSec
          Metrics.recordPhase
            recorder
            "compilerInternalTotal"
            (elapsedMs compilerStarted compilerFinished)
          pure (Right (Resource.compilationPackageVisualizations package))

forcePackageResult ::
     Either String Resource.CompilationPackage
  -> Either String Resource.CompilationPackage
forcePackageResult result =
  case result of
    Left err -> length err `seq` result
    Right package ->
      let visualizationCount =
            length (Resource.compilationPackageVisualizations package)
          resourceBytes =
            sum
              (map
                 (BS.length . Resource.resourceBlobBytes)
                 (Resource.compilationPackageResources package))
       in visualizationCount `seq` resourceBytes `seq` result

forcePackage :: Resource.CompilationPackage -> Resource.CompilationPackage
forcePackage package =
  case forcePackageResult (Right package) of
    Right forced -> forced
    Left _       -> package

forceTargetBundle ::
     Either Target.TargetError Target.TargetBundle
  -> Either Target.TargetError Target.TargetBundle
forceTargetBundle result =
  case result of
    Left err -> length (show err) `seq` result
    Right bundle ->
      let byteCount =
            BS.length
              (Target.targetArtifactBytes (Target.targetBundlePrimary bundle))
              + sum
                  (map
                     (BS.length . Target.targetArtifactBytes)
                     (Target.targetBundleAttachments bundle))
       in byteCount `seq` result

elapsedMs :: Word64 -> Word64 -> Double
elapsedMs start end = fromIntegral (end - start) / 1000000

hPrintCompilerMetrics :: Handle -> Metrics.CompilerMetrics -> IO ()
hPrintCompilerMetrics handle metrics = do
  hPutStrLn handle "Phase timings:"
  mapM_ printTiming available
  unless (Map.null counts) $ do
    hPutStrLn handle "Workload counts:"
    mapM_ printCount (Map.toAscList counts)
  mapM_ printView (Metrics.compilerMetricViews metrics)
  where
    phases = Metrics.compilerMetricPhasesMs metrics
    counts = Metrics.compilerMetricCounts metrics
    available =
      [ (label, milliseconds)
      | (name, label) <- phaseLabels
      , Just milliseconds <- [Map.lookup name phases]
      ]
    printTiming (name, ms) =
      hPutStrLn handle ("  " ++ name ++ ": " ++ formatMs ms)
    printCount (name, count) =
      hPutStrLn handle ("  " ++ name ++ ": " ++ show count)
    printView view = do
      hPutStrLn
        handle
        ("View workload (seed " ++ show (Metrics.viewMetricSeed view) ++ "):")
      hPutStrLn
        handle
        ("  materializationMs: "
           ++ formatMs (Metrics.viewMetricMaterializationMs view))
      mapM_ printCount (Map.toAscList (Metrics.viewMetricCounts view))
      mapM_ printLabel (Map.toAscList (Metrics.viewMetricLabels view))
    printLabel (name, labelValue) =
      hPutStrLn handle ("  " ++ name ++ ": " ++ labelValue)

phaseLabels :: [(String, String)]
phaseLabels =
  [ ("sourceInterpretation", "Source interpretation")
  , ("renderPlanBuild", "Render plan build")
  , ("semanticTraceBuild", "Semantic trace build")
  , ("renderExpansion", "Render expansion")
  , ("typographyPreparation", "Typography preparation")
  , ("constraintLowering", "Constraint lowering")
  , ("designSpaceCompilation", "Design-space compilation")
  , ("designSpaceSampling", "Design-space sampling")
  , ("irMaterialization", "IR materialization")
  , ("targetEncoding", "Target encode")
  , ("targetWriting", "Target write")
  , ("compilerInternalTotal", "Compiler internal total")
  ]

writeMetrics :: Options -> Metrics.CompilerMetrics -> IO ()
writeMetrics options metrics =
  case optionMetricsPath options of
    Nothing -> pure ()
    Just path -> do
      createDirectoryIfMissing True (takeDirectory path)
      Metrics.writeCompilerMetrics path metrics

formatMs :: Double -> String
formatMs milliseconds = showFFloat (Just 1) milliseconds "ms"

writeCompiled :: FilePath -> Target.TargetBundle -> IO ()
writeCompiled path bundle = do
  createDirectoryIfMissing True (takeDirectory path)
  BS.writeFile
    path
    (Target.targetArtifactBytes (Target.targetBundlePrimary bundle))
  mapM_ writeAttachment (Target.targetBundleAttachments bundle)
  BL.writeFile (path ++ ".manifest.json") (Target.targetManifestFor path bundle)
  putStrLn ("Compiled target at: " ++ path)
  where
    writeAttachment artifact = do
      let destination =
            takeDirectory path </> Target.targetArtifactRelativePath artifact
      createDirectoryIfMissing True (takeDirectory destination)
      BS.writeFile destination (Target.targetArtifactBytes artifact)

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
    <*> optional
          (strOption
             (long "metrics-output"
                <> metavar "FILE"
                <> help "Write structured compiler metrics to FILE"))
    <*> switch
          (long "details" <> help "Print phase timings and workload counts")
    <*> option
          (eitherReader positiveInt)
          (long "count"
             <> metavar "INT"
             <> value 1
             <> showDefault
             <> help
                  "Generate INT seeded samples; counts above one write a JSON array")
    <*> many
          (option
             auto
             (long "view-seed"
                <> metavar "INT"
                <> help
                     "Add an explicit view seed to the scenario selected by --seed"))

positiveInt :: String -> Either String Int
positiveInt input =
  case reads input of
    [(parsed, "")]
      | parsed > 0 -> Right parsed
    _ -> Left "expected a positive integer"

resolveSeeds :: Options -> Int -> IO [Int]
resolveSeeds options scenarioSeed =
  case optionViewSeeds options of
    [] -> pure (take (optionCount options) [scenarioSeed ..])
    viewSeeds
      | optionCount options == 1 -> pure (scenarioSeed : viewSeeds)
      | otherwise ->
        fail "--count and explicit --view-seed values cannot be used together"

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
