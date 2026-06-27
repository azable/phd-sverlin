{-# LANGUAGE OverloadedStrings #-}

module Main where

import           Control.Monad              (forM, forM_, unless, when)
import           Data.Aeson                 (object, (.=))
import qualified Data.Aeson                 as Aeson
import qualified Data.ByteString.Lazy.Char8 as ByteString
import           Data.List                  (intercalate, sort)
import           GHC.Clock                  (getMonotonicTimeNSec)
import           Solver
import           Solver.TestFixtures
import           System.Environment         (getArgs)
import           System.Exit                (exitFailure, exitSuccess)
import           System.IO                  (hPutStrLn, stderr)
import           Text.Printf                (printf)

data Options = Options
  { optionFixtureNames :: [String]
  , optionSeeds        :: [RandomSeed]
  , optionIterations   :: Int
  , optionWarmup       :: Int
  , optionJson         :: Bool
  , optionHelp         :: Bool
  }

defaultOptions :: Options
defaultOptions =
  Options
    { optionFixtureNames = []
    , optionSeeds = defaultBenchmarkSeeds
    , optionIterations = 1
    , optionWarmup = 1
    , optionJson = False
    , optionHelp = False
    }

data BenchRun = BenchRun
  { benchFixtureName   :: String
  , benchSeed          :: Int
  , benchIteration     :: Int
  , benchDurationMs    :: Double
  , benchSolverSuccess :: Bool
  , benchEnergy        :: Double
  , benchFailures      :: [String]
  }

main :: IO ()
main = do
  options <- parseArgs defaultOptions <$> getArgs
  when (optionHelp options) $ do
    printHelp
    exitSuccess
  fixtures <- resolveFixtures (optionFixtureNames options)
  runWarmup options fixtures
  runs <-
    concat
      <$> forM [1 .. optionIterations options] (runIteration options fixtures)
  printBenchmark options fixtures runs
  unless (all (null . benchFailures) runs) exitFailure

runWarmup :: Options -> [SolverFixture] -> IO ()
runWarmup options fixtures =
  forM_ [1 .. optionWarmup options] $ \_ ->
    case (fixtures, optionSeeds options) of
      (fixture:_, seed:_) -> do
        _ <- solveFixture fixture seed
        pure ()
      _ -> pure ()

runIteration :: Options -> [SolverFixture] -> Int -> IO [BenchRun]
runIteration options fixtures iteration =
  concat
    <$> forM fixtures (forM (optionSeeds options) . timeFixtureSolve iteration)

timeFixtureSolve :: Int -> SolverFixture -> RandomSeed -> IO BenchRun
timeFixtureSolve iteration fixture seed = do
  start <- getMonotonicTimeNSec
  solution <- solveFixture fixture seed
  end <- getMonotonicTimeNSec
  let failures = validateFixtureSolution fixture solution
  pure
    BenchRun
      { benchFixtureName = fixtureName fixture
      , benchSeed = seedInt seed
      , benchIteration = iteration
      , benchDurationMs = fromIntegral (end - start) / 1000000
      , benchSolverSuccess = solutionSuccess solution
      , benchEnergy = solutionEnergy solution
      , benchFailures = failures
      }

resolveFixtures :: [String] -> IO [SolverFixture]
resolveFixtures names =
  case names of
    [] -> pure availableFixtures
    _  -> traverse resolve names
  where
    resolve name =
      case fixtureByName name of
        Just fixture -> pure fixture
        Nothing -> do
          hPutStrLn
            stderr
            ("Unknown fixture "
               ++ show name
               ++ ". Available fixtures: "
               ++ intercalate ", " (map fixtureName availableFixtures))
          exitFailure

parseArgs :: Options -> [String] -> Options
parseArgs options args =
  case args of
    [] -> options
    "--":rest -> parseArgs options rest
    "--fixture":value:rest ->
      parseArgs
        options
          {optionFixtureNames = optionFixtureNames options ++ splitComma value}
        rest
    "--seed":value:rest ->
      parseArgs options {optionSeeds = parseSeeds value} rest
    "--seeds":value:rest ->
      parseArgs options {optionSeeds = parseSeeds value} rest
    "--iterations":value:rest ->
      parseArgs
        options {optionIterations = positiveInt "--iterations" value}
        rest
    "--warmup":value:rest ->
      parseArgs options {optionWarmup = nonNegativeInt "--warmup" value} rest
    "--json":rest -> parseArgs options {optionJson = True} rest
    "--help":rest -> parseArgs options {optionHelp = True} rest
    "-h":rest -> parseArgs options {optionHelp = True} rest
    flag:_ -> error ("Unknown solver-bench argument: " ++ flag)

parseSeeds :: String -> [RandomSeed]
parseSeeds value =
  case traverse parseInt (splitComma value) of
    Just seeds
      | not (null seeds) -> map RandomSeed seeds
    _ -> error "--seed must be a comma-separated list of integers"

splitComma :: String -> [String]
splitComma value =
  case break (== ',') value of
    ("", "")            -> []
    (part, "")          -> [part | not (null part)]
    (part, _comma:rest) -> [part | not (null part)] ++ splitComma rest

parseInt :: String -> Maybe Int
parseInt value =
  case reads value of
    [(parsed, "")] -> Just parsed
    _              -> Nothing

positiveInt :: String -> String -> Int
positiveInt flag value =
  case parseInt value of
    Just parsed
      | parsed > 0 -> parsed
    _ -> error (flag ++ " must be a positive integer")

nonNegativeInt :: String -> String -> Int
nonNegativeInt flag value =
  case parseInt value of
    Just parsed
      | parsed >= 0 -> parsed
    _ -> error (flag ++ " must be a non-negative integer")

printBenchmark :: Options -> [SolverFixture] -> [BenchRun] -> IO ()
printBenchmark options fixtures runs =
  if optionJson options
    then ByteString.putStrLn
           (Aeson.encode (benchmarkJson options fixtures runs))
    else printTextBenchmark fixtures runs

benchmarkJson :: Options -> [SolverFixture] -> [BenchRun] -> Aeson.Value
benchmarkJson options fixtures runs =
  object
    [ "mode" .= ("solver" :: String)
    , "fixtures" .= map fixtureName fixtures
    , "seeds" .= map seedInt (optionSeeds options)
    , "iterations" .= optionIterations options
    , "warmup" .= optionWarmup options
    , "summary" .= summaryJson runs
    , "runs" .= map runJson runs
    ]

summaryJson :: [BenchRun] -> Aeson.Value
summaryJson runs =
  object
    [ "runCount" .= length runs
    , "successCount" .= length (filter (null . benchFailures) runs)
    , "failureCount" .= length (filter (not . null . benchFailures) runs)
    , "durationMs" .= statsJson (map benchDurationMs runs)
    ]

statsJson :: [Double] -> Aeson.Value
statsJson values =
  let summary = stats values
   in object
        [ "min" .= statMin summary
        , "mean" .= statMean summary
        , "median" .= statMedian summary
        , "p95" .= statP95 summary
        , "max" .= statMax summary
        ]

runJson :: BenchRun -> Aeson.Value
runJson run =
  object
    [ "fixture" .= benchFixtureName run
    , "seed" .= benchSeed run
    , "iteration" .= benchIteration run
    , "durationMs" .= benchDurationMs run
    , "solverSuccess" .= benchSolverSuccess run
    , "energy" .= benchEnergy run
    , "ok" .= null (benchFailures run)
    , "failures" .= benchFailures run
    ]

printTextBenchmark :: [SolverFixture] -> [BenchRun] -> IO ()
printTextBenchmark fixtures runs = do
  putStrLn "Solver benchmark"
  putStrLn "----------------"
  putStrLn ("fixtures: " ++ intercalate ", " (map fixtureName fixtures))
  forM_ runs $ \run ->
    putStrLn
      (unwords
         [ "iter=" ++ show (benchIteration run)
         , "fixture=" ++ benchFixtureName run
         , "seed=" ++ show (benchSeed run)
         , "status="
             ++ if null (benchFailures run)
                  then "ok"
                  else "fail"
         , "duration=" ++ formatMs (benchDurationMs run)
         , "energy=" ++ printf "%.6g" (benchEnergy run)
         ])
  let summary = stats (map benchDurationMs runs)
  putStrLn ""
  putStrLn ("runs:     " ++ show (length runs))
  putStrLn ("success:  " ++ show (length (filter (null . benchFailures) runs)))
  putStrLn
    ("failures: " ++ show (length (filter (not . null . benchFailures) runs)))
  putStrLn ("min:      " ++ formatMaybeMs (statMin summary))
  putStrLn ("mean:     " ++ formatMaybeMs (statMean summary))
  putStrLn ("median:   " ++ formatMaybeMs (statMedian summary))
  putStrLn ("p95:      " ++ formatMaybeMs (statP95 summary))
  putStrLn ("max:      " ++ formatMaybeMs (statMax summary))

data Stats = Stats
  { statMin    :: Maybe Double
  , statMean   :: Maybe Double
  , statMedian :: Maybe Double
  , statP95    :: Maybe Double
  , statMax    :: Maybe Double
  }

stats :: [Double] -> Stats
stats values =
  case sort values of
    [] -> Stats Nothing Nothing Nothing Nothing Nothing
    sorted ->
      let count = length sorted
          total = sum sorted
          p95Index = max 0 (ceiling (fromIntegral count * 0.95 :: Double) - 1)
       in Stats
            { statMin = Just (head sorted)
            , statMean = Just (total / fromIntegral count)
            , statMedian = Just (percentile sorted 0.5)
            , statP95 = Just (sorted !! p95Index)
            , statMax = Just (last sorted)
            }

percentile :: [Double] -> Double -> Double
percentile sorted p =
  case sorted of
    [] -> 0
    [_] -> head sorted
    _ ->
      let index = fromIntegral (length sorted - 1) * p
          lower = floor index
          upper = ceiling index
          weight = index - fromIntegral lower
       in sorted !! lower * (1 - weight) + sorted !! upper * weight

formatMaybeMs :: Maybe Double -> String
formatMaybeMs = maybe "n/a" formatMs

formatMs :: Double -> String
formatMs = printf "%.1fms"

seedInt :: RandomSeed -> Int
seedInt seed =
  case seed of
    RandomSeed value -> value

printHelp :: IO ()
printHelp =
  putStrLn
    (unlines
       [ "Usage: cabal run solver-bench -- [options]"
       , ""
       , "Options:"
       , "  --fixture NAME    Fixture to run. Can be repeated. Default: all"
       , "  --seed A,B,C      Override the default seed list"
       , "  --iterations N    Runs per seed and fixture. Default: 1"
       , "  --warmup N        Warmup solves before measurement. Default: 1"
       , "  --json            Print machine-readable JSON"
       , "  --help            Show this message"
       ])
