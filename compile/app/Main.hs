{-# LANGUAGE DerivingStrategies #-}

module Main where

import           DSL.Main
import qualified LinearTrace
import           LinearTrace.Visualize
import           System.Random         (randomIO)

main :: IO ()
main = do
  let graph = run example
  LinearTrace.printTrace graph
  let visGraph = LinearTrace.Visualize.buildCSP graph
  seedInt <- randomIO :: IO Int
  let seed = RandomSeed seedInt
  solved <- LinearTrace.Visualize.solveCSPWithSeed seed visGraph
  LinearTrace.printSolvedVisualization True solved visGraph
  case LinearTrace.compileSolvedVisualization solved visGraph of
    Left err -> putStrLn err
    Right compiled ->
      LinearTrace.writeCompiledVisualizationJSON "static/compiled.json" compiled
  putStrLn ("Compiled with solver seed: " ++ show seedInt)
