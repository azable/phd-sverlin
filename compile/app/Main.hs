{-# LANGUAGE DerivingStrategies #-}

module Main where

import qualified DSL
import qualified LinearTrace
import           Solver

main :: IO ()
main = do
  -- LinearTrace.printTrace (DSL.run DSL.example)
  test
