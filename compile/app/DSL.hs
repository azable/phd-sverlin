{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LinearTypes #-}
{-# LANGUAGE RebindableSyntax #-}

module DSL where

import Control.Functor.Linear (Monad ((>>=)))
-- import Prelude.Linear

import NodeBase
import Prelude hiding (Monad, return, (>>=))

-- DSL layer

data KValue

data KOp

data NContent tag where
  V :: Value -> NContent KValue
  O :: Op -> NContent KOp

instance Show (NContent tag) where
  show (V val) = "V " ++ show val
  show (O op) = "O " ++ show op

type GraphBuilder = NBuilder NContent

type Ref tag = NRef NContent tag

type VRef = Ref KValue

type ORef = Ref KOp

data Value
  = I32 Int
  | F64 Double
  deriving stock (Show)

data Op
  = Add
  | Mul
  deriving stock (Show)

v :: Value -> GraphBuilder VRef
v val =
  make (V val)

o :: Op -> GraphBuilder ORef
o op =
  make (O op)

eval :: NContent KValue -> NContent KOp -> NContent KValue -> NContent KValue
eval (V (I32 x)) (O Add) (V (I32 y)) = V (I32 (x + y))
eval (V (I32 x)) (O Mul) (V (I32 y)) = V (I32 (x * y))
eval (V (F64 x)) (O Add) (V (F64 y)) = V (F64 (x + y))
eval (V (F64 x)) (O Mul) (V (F64 y)) = V (F64 (x * y))
eval lhs op rhs = error $ "Type mismatch" ++ displayContents
  where
    displayContents =
      "\n  LHS: "
        ++ show lhs
        ++ "\n  OP: "
        ++ show op
        ++ "\n  RHS: "
        ++ show rhs

e :: VRef %1 -> ORef %1 -> VRef %1 -> GraphBuilder VRef
e refA refOp refB = combine3 refA refOp refB eval

(.+.) :: VRef %1 -> VRef %1 -> GraphBuilder VRef
(.+.) a b = do
  add <- o Add
  e a add b

(.*.) :: VRef %1 -> VRef %1 -> GraphBuilder VRef
(.*.) a b = do
  mul <- o Mul
  e a mul b

run :: GraphBuilder tag -> [N NContent]
run = buildGraph
