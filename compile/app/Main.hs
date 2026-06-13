module Main where

import qualified LinearTrace
import qualified Program

main :: IO ()
main = do
  LinearTrace.printTrace Program.runProgram
