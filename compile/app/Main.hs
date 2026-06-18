{-# LANGUAGE DerivingStrategies #-}

module Main where

import           DSL.Main
import qualified LinearTrace
import           LinearTrace.Visualize
import           Options.Applicative
import           System.Random         (randomIO)

data Options = Options
  { optionShowSolverDetails :: Bool
  , optionSeed              :: Maybe Int
  }

main :: IO ()
main = do
  options <- execParser optionsParserInfo
  seedInt <- chooseSeed (optionSeed options)
  let graph = run example
  LinearTrace.printTrace graph
  let visGraph = LinearTrace.Visualize.buildCSP graph
  solved <- LinearTrace.Visualize.solveCSPWithSeed (RandomSeed seedInt) visGraph
  LinearTrace.printSolvedVisualization
    (optionShowSolverDetails options)
    solved
    visGraph
  case LinearTrace.compileSolvedVisualization solved visGraph of
    Left err -> putStrLn err
    Right compiled ->
      LinearTrace.writeCompiledVisualizationJSON "static/compiled.json" compiled
  putStrLn ("Compiled with solver seed: " ++ show seedInt)

chooseSeed :: Maybe Int -> IO Int
chooseSeed = maybe randomIO pure

optionsParserInfo :: ParserInfo Options
optionsParserInfo =
  info
    (optionsParser <**> helper)
    (fullDesc
       <> progDesc
            "Compile the example trace, solve its visualization, and write static/compiled.json")

optionsParser :: Parser Options
optionsParser =
  Options
    <$> switch
          (long "details"
             <> short 'd'
             <> help
                  "Print detailed visualization nodes, constraints, initial variables, and solved values")
    <*> optional
          (option
             auto
             (long "seed"
                <> short 's'
                <> metavar "INT"
                <> help
                     "Use a deterministic solver seed instead of generating a random one"))
