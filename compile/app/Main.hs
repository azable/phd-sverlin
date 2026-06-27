{-# LANGUAGE DerivingStrategies #-}

module Main where

import           App
import           DSL.Main
import           Options.Applicative
import           System.Exit         (exitFailure)
import           System.IO           (Handle, hFlush, hPutStrLn, stderr, stdout)
import           System.Posix.IO     (OpenMode (WriteOnly), closeFd,
                                      defaultFileFlags, dup, dupTo, fdToHandle,
                                      openFd, stdOutput)
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
  outputMode <-
    if optionJson options
      then App.OutputStdout <$> prepareJsonStdout
      else pure (App.runOutputMode App.defaultRunConfig)
  let graph = run example
      config =
        App.defaultRunConfig
          { App.runSeed = seedInt
          , App.runShowDetails = optionShowSolverDetails options
          , App.runOutputMode = outputMode
          , App.runDiagnostics =
              not (optionJson options) || optionShowSolverDetails options
          }
  result <- App.runVisualization config graph
  case result of
    Left err -> do
      if optionJson options
        then hPutStrLn stderr err
        else putStrLn err
      exitFailure
    Right _compiled -> pure ()

prepareJsonStdout :: IO Handle
prepareJsonStdout = do
  hFlush stdout
  jsonOutput <- fdToHandle =<< dup stdOutput
  nullOutput <- openFd "/dev/null" WriteOnly defaultFileFlags
  _ <- dupTo nullOutput stdOutput
  closeFd nullOutput
  pure jsonOutput

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
