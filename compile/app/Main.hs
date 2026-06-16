{-# LANGUAGE DerivingStrategies #-}

module Main where

import           DSL.Main
import qualified LinearTrace
import           LinearTrace.Visualize

-- import           LinearTrace.View
-- import           Solver
main :: IO ()
main = do
  let graph = run example
  LinearTrace.printTrace graph
  let visGraph = LinearTrace.Visualize.buildVisualizationCSP graph
  LinearTrace.printVisualization visGraph
  let solved =
        LinearTrace.Visualize.solveVisualizationCSP
          LinearTrace.Visualize.defaultSolveConfig
          visGraph
  LinearTrace.printVisualizationCSPSolution =<< solved
  -- test
