{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs              #-}
{-# LANGUAGE LinearTypes        #-}
{-# LANGUAGE RebindableSyntax   #-}

module Program
  ( runProgram
  , G
  , Desc
  ) where

import           DSL

runProgram :: G Desc
runProgram = run example
