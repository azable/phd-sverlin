module Main where

import qualified DSL
import qualified Program

main :: IO ()
main = do
  let (DSL.G nodes descs) = Program.runProgram
  mapM_ print nodes
  mapM_ print descs
