{-# LANGUAGE DerivingStrategies #-}

module Main where

import           App
import           DSL.Main
import           Options.Applicative
import           System.Exit         (exitFailure)
import           System.IO           (hPutStrLn, stderr)
import           System.Random       (randomRIO)

data Options = Options
  { optionShowSolverDetails :: Bool
  , optionSeed              :: Maybe Int
  , optionJson              :: Bool
  }

main :: IO ()
main = do
  options <- execParser optionsParserInfo
  seedInt <- chooseSeed (optionSeed options)
  let graph = run example
      config =
        App.defaultRunConfig
          { App.runSeed = seedInt
          , App.runShowDetails = optionShowSolverDetails options
          , App.runOutputMode =
              if optionJson options
                then App.OutputStdout
                else App.runOutputMode App.defaultRunConfig
          }
  result <- App.runVisualization config graph
  case result of
    Left err -> do
      if optionJson options
        then hPutStrLn stderr err
        else putStrLn err
      exitFailure
    Right _compiled -> pure ()

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
    <*> switch
          (long "json"
             <> help
                  "Write compiled visualization JSON to stdout instead of static/compiled.json")
