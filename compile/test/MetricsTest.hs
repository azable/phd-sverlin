module MetricsTest
  ( tests
  ) where

import           Control.Exception        (IOException, try)
import qualified Data.Map.Strict          as Map
import qualified Sverlin.Internal.Metrics as Metrics
import           Test.Tasty               (TestTree, testGroup)
import           Test.Tasty.HUnit         (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "compiler metrics"
    [ testCase "records a measured phase without changing its result" $ do
        recorder <- Metrics.newMetricsRecorder [11, 29]
        result <- Metrics.measurePhase recorder "measured" (pure (42 :: Int))
        Metrics.recordCount recorder "work" 7
        recorded <- Metrics.readCompilerMetrics recorder
        result @?= 42
        Metrics.compilerMetricViewSeeds recorded @?= [11, 29]
        Metrics.compilerMetricCounts recorded @?= Map.singleton "work" 7
        assertRecordedDuration "measured" recorded
    , testCase "attributes an exception to the phase that failed" $ do
        recorder <- Metrics.newMetricsRecorder [3]
        attempted <-
          try
            (Metrics.measurePhase
               recorder
               "broken"
               (ioError (userError "expected failure"))) :: IO
            (Either IOException ())
        recorded <- Metrics.readCompilerMetrics recorder
        assertBool
          "expected the measured action to fail"
          (either (const True) (const False) attempted)
        Metrics.compilerMetricFailedPhase recorded @?= Just "broken"
        assertRecordedDuration "broken" recorded
    ]

assertRecordedDuration :: String -> Metrics.CompilerMetrics -> IO ()
assertRecordedDuration name recorded =
  case Map.lookup name (Metrics.compilerMetricPhasesMs recorded) of
    Nothing -> fail ("missing measured phase " ++ show name)
    Just duration ->
      assertBool "phase duration must be non-negative" (duration >= 0)
