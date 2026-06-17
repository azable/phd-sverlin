{-# LANGUAGE DerivingStrategies #-}

module Main where

import           DSL.Main
import qualified LinearTrace
import           LinearTrace.Visualize

main :: IO ()
main = do
  let graph = run example
  LinearTrace.printTrace graph
  let visGraph = LinearTrace.Visualize.buildCSP graph
  LinearTrace.printVisualization visGraph
  solved <-
    LinearTrace.Visualize.solveCSP
      LinearTrace.Visualize.defaultSolveConfig
      visGraph
  LinearTrace.printVisualizationCSPSolution solved
  LinearTrace.printSolvedVisualization solved visGraph
  let compiled = LinearTrace.compileSolvedVisualization solved visGraph
  print compiled
