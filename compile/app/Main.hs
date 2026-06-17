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
  solved <-
    LinearTrace.Visualize.solveCSP
      LinearTrace.Visualize.defaultSolveConfig
      visGraph
  LinearTrace.printSolvedVisualization True solved visGraph
  -- LinearTrace.printVisualizationCSPSolution solved
  case LinearTrace.compileSolvedVisualization solved visGraph of
    Left err -> putStrLn err
    Right compiled ->
      LinearTrace.writeCompiledVisualizationJSON "static/compiled.json" compiled
