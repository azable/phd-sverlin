module Main where

import qualified MetricsTest
import qualified RenderGuardTest
import qualified SemanticTest
import           Test.Tasty      (defaultMain, testGroup)
import qualified TypographyTest

main :: IO ()
main =
  defaultMain
    (testGroup
       "Sverlin internals"
       [ MetricsTest.tests
       , SemanticTest.tests
       , RenderGuardTest.tests
       , TypographyTest.tests
       ])
