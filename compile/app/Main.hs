module Main where

import DSL qualified
import Program qualified

main :: IO ()
main = do
  let (DSL.G nodes descs) = Program.runProgram
  mapM_ print nodes
  mapM_ print descs
