module Sverlin.Interpreter
  ( withVisualization
  ) where

import           Control.Monad.IO.Class              (liftIO)
import           Language.Haskell.Interpreter        (InterpreterError, as,
                                                      interpret, loadModules,
                                                      setTopLevelModules)
import           Language.Haskell.Interpreter.Unsafe (unsafeRunInterpreterWithArgs)
import           LinearTrace.Choreography            (VisualTraceGraph)
import           Sverlin.Source                      (GeneratedSource (..))
import           System.Directory                    (createDirectoryIfMissing)
import           System.Environment                  (lookupEnv)
import           System.FilePath                     ((</>))
import           System.IO.Temp                      (withSystemTempDirectory)

withVisualization ::
     GeneratedSource
  -> (VisualTraceGraph -> IO a)
  -> IO (Either InterpreterError a)
withVisualization generated useVisualization =
  withSystemTempDirectory "sverlin-source" $ \temporaryDirectory -> do
    let moduleDirectory = temporaryDirectory </> "Sverlin"
        modulePath = moduleDirectory </> "Generated.hs"
    createDirectoryIfMissing True moduleDirectory
    writeFile modulePath (generatedModuleText generated)
    packageEnvironment <- lookupEnv "GHC_ENVIRONMENT"
    unsafeRunInterpreterWithArgs (packageEnvironmentArgs packageEnvironment) $ do
      loadModules [modulePath]
      setTopLevelModules [generatedModuleName generated]
      visualization <- interpret "_sverlinResult" (as :: VisualTraceGraph)
      liftIO (useVisualization visualization)

packageEnvironmentArgs :: Maybe FilePath -> [String]
packageEnvironmentArgs = maybe [] (\path -> ["-package-env=" ++ path])
