{-# LANGUAGE DerivingStrategies #-}

module Main where

import           DSL.Core
import qualified LinearTrace

-- import           LinearTrace.View
-- import           Solver
main :: IO ()
main = do
  LinearTrace.printTrace (run example)
  -- test
