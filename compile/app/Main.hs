-- {-# LANGUAGE GADTs #-}
-- {-# LANGUAGE LinearTypes #-}

module Main where

import NodeBase qualified

graph :: [NodeBase.N]
graph = NodeBase.buildGraph NodeBase.example

main :: IO ()
main = do
  mapM_ print graph
