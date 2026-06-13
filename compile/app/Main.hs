module Main where

import qualified NodeBase
import qualified Program

main :: IO ()
main = do
  NodeBase.printTrace Program.runProgram
