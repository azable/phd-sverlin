module Main where

import           Control.Exception                    (IOException, evaluate,
                                                       try)
import           Control.Monad                        (when, zipWithM)
import qualified Data.ByteString                      as BS
import qualified Data.ByteString.Lazy                 as BL
import           Data.Maybe                           (fromMaybe)
import           Data.Word                            (Word64)
import           GHC.Clock                            (getMonotonicTimeNSec)
import           Language.Haskell.Interpreter         (GhcError (..),
                                                       InterpreterError (..))
import qualified LinearTrace.Choreography             as Choreography
import qualified LinearTrace.Visualization.Compile    as Compile
import qualified LinearTrace.Visualization.IR         as IR
import qualified LinearTrace.Visualization.Resource   as Resource
import qualified LinearTrace.Visualization.Target     as Target
import qualified LinearTrace.Visualization.Typography as Typography
import           Numeric                              (showFFloat)
import           Options.Applicative
import qualified Solver                               as S
import           Sverlin.Interpreter                  (withVisualization)
import           Sverlin.Source                       (GeneratedSource (..),
                                                       SourceUnit (..),
                                                       elaborateSource)
import           System.Directory                     (createDirectoryIfMissing)
import           System.Exit                          (exitFailure)
import           System.FilePath                      (takeDirectory, (</>))
import           System.IO                            (Handle, hPutStrLn,
                                                       stderr, stdout)
import           System.Random                        (randomRIO)

data Options = Options
  { optionSourcePath  :: FilePath
  , optionSourceLabel :: Maybe FilePath
  , optionEmitHaskell :: Maybe FilePath
  , optionSeed        :: Maybe Int
  , optionOutputPath  :: FilePath
  , optionTarget      :: Target.OutputTarget
  , optionDetails     :: Bool
  , optionCount       :: Int
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
      let seeds = take (optionCount options) [seed ..]
      sourceStarted <- getMonotonicTimeNSec
      interpreted <-
        withVisualization generated $ \graph -> do
          sourceFinished <- getMonotonicTimeNSec
          runVisualization
            options
            sourceLabel
            (elapsedMs sourceStarted sourceFinished)
            seeds
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
  -> [Int]
  -> Choreography.VisualTraceGraph
  -> IO (Either String [IR.Visualization])
runVisualization options sourcePath sourceLoadMs seeds graph = do
  (viewGraph, viewGraphMs) <-
    timedPhase (evaluate (forceViewGraph (Choreography.buildViewGraph graph)))
  (initialSolutions, solveMs) <-
    timedPhase
      (Choreography.solveViewGraphWithSeeds
         (map Choreography.RandomSeed seeds)
         viewGraph)
  (preparedResult, typographyMs) <-
    timedPhase
      (fmap
         sequence
         (zipWithM
            (\_seed solution -> Typography.prepareTypography solution viewGraph)
            seeds
            initialSolutions))
  case preparedResult of
    Left err -> pure (Left err)
    Right prepared -> do
      (solutions, constraintSolveMs) <-
        timedPhase
          (zipWithM
             (\seed (initial, typography) ->
                solvePrepared seed initial typography)
             seeds
             (zip initialSolutions prepared))
      (compiledResult, compileMs) <-
        timedPhase
          (evaluate
             (forcePackageResult (compilePrepared sourcePath solutions prepared)))
      case compiledResult of
        Left err -> pure (Left err)
        Right package -> do
          (bundleResult, encodeMs) <-
            timedPhase
              (evaluate
                 (forceTargetBundle
                    (Target.compileTarget
                       (Target.defaultTargetRequest (optionTarget options))
                       package)))
          case bundleResult of
            Left (Target.TargetError err) -> pure (Left err)
            Right bundle -> do
              ((), writeMs) <-
                timedPhase (writeCompiled (optionOutputPath options) bundle)
              when (optionDetails options) $ do
                case solutions of
                  solution:_ -> hPrintSolverDetails stdout solution
                  []         -> pure ()
                hPrintPhaseTimings
                  stdout
                  [ ("Source load", sourceLoadMs)
                  , ("View graph", viewGraphMs)
                  , ("Aesthetic solve", solveMs)
                  , ("Text prepare", typographyMs)
                  , ("Constraint solve", constraintSolveMs)
                  , ("IR compile", compileMs)
                  , ("Target encode", encodeMs)
                  , ("Target write", writeMs)
                  ]
              pure (Right (Resource.compilationPackageVisualizations package))
  where
    solvePrepared seed initial prepared
      | Typography.preparedTypographyNeedsResolve prepared =
        Choreography.solveViewGraphWithPinnedSolution
          (Choreography.RandomSeed seed)
          initial
          (Typography.preparedTypographyGraph prepared)
      | otherwise = pure initial

compilePrepared ::
     FilePath
  -> [S.Solution]
  -> [Typography.PreparedTypography]
  -> Either String Resource.CompilationPackage
compilePrepared sourcePath solutions prepared = do
  outputs <- zipWithM Typography.materializeTypography solutions prepared
  visualizations <-
    sequence
      [ Compile.compileSolvedWithTypography
        sourcePath
        solution
        (Typography.preparedTypographyGraph typography)
        output
      | (solution, typography, output) <- zip3 solutions prepared outputs
      ]
  pure
    Resource.CompilationPackage
      { Resource.compilationPackageVisualizations = visualizations
      , Resource.compilationPackageResources =
          Resource.deduplicateResourceBlobs
            (concatMap Typography.typographyOutputResources outputs)
      , Resource.compilationPackageProvenance =
          Typography.typographyCompilationProvenance
      }

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

forceViewGraph :: Choreography.ViewGraph -> Choreography.ViewGraph
forceViewGraph graph =
  case Choreography.viewGraphStats graph of
    (nodes, constraints, steps) ->
      nodes `seq` constraints `seq` steps `seq` graph

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

hPrintSolverDetails :: Handle -> S.Solution -> IO ()
hPrintSolverDetails handle solution = do
  hPutStrLn handle "Solver details:"
  hPutStrLn handle ("  Backend: " ++ backendName (S.solutionBackend solution))
  case S.solutionBackendStatistics solution of
    S.AffineSamplingStatistics statistics -> do
      hPutStrLn
        handle
        ("  Reduced dimension: " ++ show (S.samplingReducedDimension statistics))
      hPutStrLn
        handle
        ("  Burn-in steps: " ++ show (S.samplingBurnInSteps statistics))
    S.PenaltyOptimizationStatistics statistics -> do
      hPutStrLn
        handle
        ("  Iterations: " ++ show (S.optimizationIterations statistics))
      hPutStrLn
        handle
        ("  Function evaluations: "
           ++ show (S.optimizationFunctionEvaluations statistics))

backendName :: S.NumericBackend -> String
backendName backend =
  case backend of
    S.AffineSampler    -> "affine-sampler"
    S.PenaltyOptimizer -> "penalty-optimizer"

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
    <*> switch (long "details" <> help "Print phase timings")
    <*> option
          (eitherReader positiveInt)
          (long "count"
             <> metavar "INT"
             <> value 1
             <> showDefault
             <> help
                  "Generate INT seeded samples; counts above one write a JSON array")

positiveInt :: String -> Either String Int
positiveInt input =
  case reads input of
    [(parsed, "")]
      | parsed > 0 -> Right parsed
    _ -> Left "expected a positive integer"

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
