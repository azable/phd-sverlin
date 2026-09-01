{-# LANGUAGE OverloadedStrings #-}

-- | Versioned performance measurements shared by the compiler executable and
-- its private compilation stages. These values describe work; they never
-- participate in seeded output or visualization identity.
module Sverlin.Internal.Metrics
  ( MetricsRecorder
  , CompilerMetrics(..)
  , ViewMetrics(..)
  , newMetricsRecorder
  , measurePhase
  , measureDuration
  , recordPhase
  , recordCount
  , recordViews
  , markFailedPhase
  , readCompilerMetrics
  , writeCompilerMetrics
  ) where

import           Control.Exception        (SomeException, throwIO, try)
import           Data.Aeson               (ToJSON (..), Value, object, (.=))
import qualified Data.Aeson.Encode.Pretty as Aeson
import qualified Data.Aeson.Key           as Key
import qualified Data.ByteString.Lazy     as BL
import           Data.IORef               (IORef, modifyIORef', newIORef,
                                           readIORef)
import           Data.Map.Strict          (Map)
import qualified Data.Map.Strict          as Map
import           Data.Word                (Word64)
import           GHC.Clock                (getMonotonicTimeNSec)
import           Prelude

data ViewMetrics = ViewMetrics
  { viewMetricSeed              :: Int
  , viewMetricMaterializationMs :: Double
  , viewMetricCounts            :: Map String Int
  , viewMetricLabels            :: Map String String
  } deriving (Eq, Show)

data CompilerMetrics = CompilerMetrics
  { compilerMetricSchemaVersion :: Int
  , compilerMetricViewSeeds     :: [Int]
  , compilerMetricPhasesMs      :: Map String Double
  , compilerMetricCounts        :: Map String Int
  , compilerMetricViews         :: [ViewMetrics]
  , compilerMetricFailedPhase   :: Maybe String
  } deriving (Eq, Show)

newtype MetricsRecorder =
  MetricsRecorder (IORef CompilerMetrics)

newMetricsRecorder :: [Int] -> IO MetricsRecorder
newMetricsRecorder seeds =
  MetricsRecorder
    <$> newIORef
          CompilerMetrics
            { compilerMetricSchemaVersion = 1
            , compilerMetricViewSeeds = seeds
            , compilerMetricPhasesMs = Map.empty
            , compilerMetricCounts = Map.empty
            , compilerMetricViews = []
            , compilerMetricFailedPhase = Nothing
            }

measurePhase :: MetricsRecorder -> String -> IO value -> IO value
measurePhase recorder name action = do
  (attempted, duration) <- measureDuration (try action)
  recordPhase recorder name duration
  case attempted of
    Left exception -> do
      markFailedPhase recorder name
      throwIO (exception :: SomeException)
    Right value -> pure value

measureDuration :: IO value -> IO (value, Double)
measureDuration action = do
  started <- getMonotonicTimeNSec
  value <- action
  finished <- getMonotonicTimeNSec
  pure (value, elapsedMs started finished)

recordPhase :: MetricsRecorder -> String -> Double -> IO ()
recordPhase (MetricsRecorder reference) name duration =
  modifyIORef' reference $ \metrics ->
    metrics
      { compilerMetricPhasesMs =
          Map.insert
            name
            (roundMilliseconds duration)
            (compilerMetricPhasesMs metrics)
      }

recordCount :: MetricsRecorder -> String -> Int -> IO ()
recordCount (MetricsRecorder reference) name count =
  modifyIORef' reference $ \metrics ->
    metrics
      { compilerMetricCounts =
          Map.insert name count (compilerMetricCounts metrics)
      }

recordViews :: MetricsRecorder -> [ViewMetrics] -> IO ()
recordViews (MetricsRecorder reference) views =
  modifyIORef' reference $ \metrics -> metrics {compilerMetricViews = views}

markFailedPhase :: MetricsRecorder -> String -> IO ()
markFailedPhase (MetricsRecorder reference) name =
  modifyIORef' reference $ \metrics ->
    metrics {compilerMetricFailedPhase = Just name}

readCompilerMetrics :: MetricsRecorder -> IO CompilerMetrics
readCompilerMetrics (MetricsRecorder reference) = readIORef reference

writeCompilerMetrics :: FilePath -> CompilerMetrics -> IO ()
writeCompilerMetrics path = BL.writeFile path . Aeson.encodePretty

instance ToJSON CompilerMetrics where
  toJSON metrics =
    object
      [ "schemaVersion" .= compilerMetricSchemaVersion metrics
      , "viewSeeds" .= compilerMetricViewSeeds metrics
      , "phasesMs" .= stringMap (compilerMetricPhasesMs metrics)
      , "counts" .= stringMap (compilerMetricCounts metrics)
      , "views" .= compilerMetricViews metrics
      , "failedPhase" .= compilerMetricFailedPhase metrics
      ]

instance ToJSON ViewMetrics where
  toJSON metrics =
    object
      [ "seed" .= viewMetricSeed metrics
      , "materializationMs"
          .= roundMilliseconds (viewMetricMaterializationMs metrics)
      , "counts" .= stringMap (viewMetricCounts metrics)
      , "labels" .= stringMap (viewMetricLabels metrics)
      ]

stringMap :: ToJSON value => Map String value -> Value
stringMap values =
  object [Key.fromString name .= value | (name, value) <- Map.toAscList values]

elapsedMs :: Word64 -> Word64 -> Double
elapsedMs started finished = fromIntegral (finished - started) / 1000000

roundMilliseconds :: Double -> Double
roundMilliseconds value = fromIntegral (round (value * 10) :: Integer) / 10
