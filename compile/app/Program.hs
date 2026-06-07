{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LinearTypes #-}
{-# LANGUAGE RebindableSyntax #-}

module Program where

-- import Control.Functor.Linear
import DSL
import NodeBase qualified
import Prelude.Linear

-- example' :: GraphBuilder ValRef
-- example' = do
--   n1 <- v (I32 42)
--   n2 <- v (I32 100)

--   n3 <- n1 .*. n2
--   n4 <- v (I32 10)

--   n3 .+. n4

runProgram :: [NodeBase.N NContent]
runProgram = run $ fibIter 20
