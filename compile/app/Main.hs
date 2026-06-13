module Main where

import qualified NodeBase
import qualified Program

main :: IO ()
main = do
  NodeBase.printGraph Program.runProgram
