module Main where

import qualified RenderGuardTest
import qualified SemanticTest
import           Test.Tasty      (defaultMain, testGroup)
import qualified TypographyTest

main :: IO ()
main =
  defaultMain
    (testGroup
       "Sverlin internals"
       [SemanticTest.tests, RenderGuardTest.tests, TypographyTest.tests])
