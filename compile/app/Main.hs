{-# LANGUAGE DerivingStrategies #-}

module Main where

import           App
import           DSL.Main
import           Options.Applicative
import qualified LinearTrace.Visualization.Target as Target
import           System.Exit         (exitFailure)
import           System.IO           (hPutStrLn, stderr)
import           System.Random       (randomRIO)

data Options = Options
  { optionShowSolverDetails :: Bool
  , optionSeed              :: Maybe Int
  , optionOutputPath        :: FilePath
  , optionTarget            :: Target.OutputTarget
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
          , App.runOutputPath = optionOutputPath options
          , App.runDiagnostics = True
          , App.runOutputTarget = optionTarget options
          }
  result <- App.runVisualization config graph
  case result of
    Left err -> do
      hPutStrLn stderr err
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
            "Compile the example trace, solve its visualization, and write JSON to an output file")

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
    <*> strOption
          (long "output"
             <> short 'o'
             <> metavar "FILE"
             <> help "Write compiled visualization JSON to FILE")
    <*> option
          (eitherReader Target.parseOutputTarget)
          (long "target"
             <> metavar "TARGET"
             <> value Target.IrJson
             <> showDefaultWith Target.outputTargetName
             <> help "Compile to TARGET (currently: ir-json)")
