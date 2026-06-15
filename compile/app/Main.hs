{-# LANGUAGE DerivingStrategies #-}

module Main where

import           DSL.Core
import qualified LinearTrace
import           LinearTrace.Visualize

-- import           LinearTrace.View
-- import           Solver
main :: IO ()
main = do
  let graph = run example
  LinearTrace.printTrace graph
  let visGraph = LinearTrace.Visualize.buildVisualization graph
  LinearTrace.printVisualization visGraph
  -- test
