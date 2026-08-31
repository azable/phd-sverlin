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
             , ("domain :: Domain ()", "source body")
             , ("Compiler.sverlinProgram domain program render", "fixed runner")
             , ("import Data.String (fromString)", "overloaded string support")
             , ( "import Prelude.Linear (($))"
               , "multiplicity-polymorphic application")
             ]
       , testCase "places declarations after the source boundary" $ do
           let generated = generatedModuleText (elaborateSource fixtureSource)
               boundary = "_sverlinSourceBoundary = ()"
               body = "domain :: Domain ()"
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
          [ "data Done"
          , ""
          , "domain :: Domain ()"
          , "domain = declareSteps @'[Done]"
          , ""
          , "program :: () %1 -> Program ()"
          , "program () = step @Done (pure ())"
          , ""
          , "render :: Render ()"
          , "render = always (frame @Done)"
          ]
    }

indexOf :: String -> String -> Int
indexOf needle = fromMaybe maxBound . findIndex (isPrefixOf needle) . tails
