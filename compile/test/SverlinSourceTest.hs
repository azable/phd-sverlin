module Main where

import           Data.List        (findIndex, isInfixOf, isPrefixOf, tails)
import           Data.Maybe       (fromMaybe)
import           Sverlin.Source   (GeneratedSource (..), SourceUnit (..),
                                   elaborateSource)
import           Test.Tasty       (defaultMain, testGroup)
import           Test.Tasty.HUnit

main :: IO ()
main =
  defaultMain
    (testGroup
       "Sverlin source elaboration"
       [ testCase "wraps a body with the fixed public contract" $ do
           let generated = elaborateSource fixtureSource
               has expected = expected `isInfixOf` generatedModuleText generated
           mapM_
             (\(expected, message) -> has expected @? message)
             [ ( "module Sverlin.Generated (_sverlinResult) where"
               , "generated module header")
             , ( "{-# LINE 1 \"examples/Custom.sverlin\" #-}"
               , "source-labelled line pragma")
             , ("program :: Choreography ()", "source body")
             , ( "runChoreographyWith (visualize visualization) program"
               , "fixed runner")
             ]
       , testCase "places declarations after the source boundary" $ do
           let generated = generatedModuleText (elaborateSource fixtureSource)
               boundary = "_sverlinSourceBoundary = ()"
               body = "program :: Choreography ()"
           assertBool
             "the body follows a declaration, so module headers and imports cannot be injected"
             (indexOf boundary generated < indexOf body generated)
       ])

fixtureSource :: SourceUnit
fixtureSource =
  SourceUnit
    { sourceDisplayPath = "examples/Custom.sverlin"
    , sourceBody =
        unlines
          [ "program :: Choreography ()"
          , "program = pure ()"
          , ""
          , "visualization :: VisualizationBuilder ()"
          , "visualization = pure ()"
          ]
    }

indexOf :: String -> String -> Int
indexOf needle = fromMaybe maxBound . findIndex (isPrefixOf needle) . tails
