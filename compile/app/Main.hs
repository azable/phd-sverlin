module Main where

import DSL qualified
import Program qualified

main :: IO ()
main = do
  let (DSL.G nodes) = Program.runProgram
  mapM_ print nodes
