module Main where

import Program qualified

main :: IO ()
main = do
  let graph = Program.runProgram
  mapM_ print graph
