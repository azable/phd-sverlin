{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LinearTypes #-}
{-# LANGUAGE RebindableSyntax #-}

module DSL where

import Control.Functor.Linear
import NodeBase
import Prelude.Linear
import Prelude qualified as P

-- DSL layer

data CType
  = CTInt
  | CTDouble
  | CTBool

data KValue (ty :: CType)

data Value ty where
  I32 :: Int -> Value 'CTInt
  F64 :: Double -> Value 'CTDouble

instance Show (Value ty) where
  show (I32 i) = show i
  show (F64 f) = show f

data KOp (lhs :: CType) (rhs :: CType) (out :: CType)

data Op lhs rhs out where
  AddI :: Op 'CTInt 'CTInt 'CTInt
  MulI :: Op 'CTInt 'CTInt 'CTInt
  AddD :: Op 'CTDouble 'CTDouble 'CTDouble
  MulD :: Op 'CTDouble 'CTDouble 'CTDouble

instance Show (Op lhs rhs out) where
  show AddI = "AddI"
  show MulI = "MulI"
  show AddD = "AddD"
  show MulD = "MulD"

data KVar (ty :: CType)

data NContent tag where
  Val :: Value ty -> NContent (KValue ty)
  Op :: Op lhs rhs out -> NContent (KOp lhs rhs out)
  Var ::
    String ->
    NPtr NContent (KValue ty) ->
    NContent (KVar ty)

padRight :: Int -> String -> String
padRight n s = s ++ replicate (n - P.length s) ' '

padRightF :: String -> String
padRightF = padRight 8

instance Show (NContent tag) where
  show (Val val) = padRightF "=>" ++ show val
  show (Op op) = padRightF "Op " ++ show op
  show (Var name val) = padRightF "===" ++ name ++ " = " ++ show val

type GraphBuilder = NBuilder NContent

type Ref tag = NRef NContent tag

v ::
  Value ty ->
  GraphBuilder (Ref (KValue ty))
v val = node (Val val)

o ::
  Op lhs rhs out ->
  GraphBuilder (Ref (KOp lhs rhs out))
o op = node (Op op)

var ::
  String ->
  Value ty ->
  GraphBuilder (Ref (KVar ty))
var name val = do
  valueRef <- v val
  case freezeRef valueRef of
    Ur valuePtr ->
      node (Var name valuePtr)

readVar ::
  Ref (KVar ty) %1 ->
  GraphBuilder (LPair (Ref (KVar ty)) (Ref (KValue ty)))
readVar ref =
  cloneNodeWith
    ref
    $ \(Var _ ptr) ->
      copyPtr ptr

writeVar ::
  Ref (KVar ty) %1 ->
  Ref (KValue ty) %1 ->
  GraphBuilder (Ref (KVar ty))
writeVar varRef valueRef =
  zipNode2WithId
    varRef
    valueRef
    ( \_ varContent valueId valueContent ->
        case varContent of
          Var name _ ->
            Var name (NPtr valueId valueContent)
    )

binaryValueOp ::
  Op lhs rhs out ->
  Value lhs ->
  Value rhs ->
  Value out
binaryValueOp AddI (I32 x) (I32 y) = I32 (x + y)
binaryValueOp MulI (I32 x) (I32 y) = I32 (x * y)
binaryValueOp AddD (F64 x) (F64 y) = F64 (x + y)
binaryValueOp MulD (F64 x) (F64 y) = F64 (x * y)

eval ::
  NContent (KValue lhs) ->
  NContent (KOp lhs rhs out) ->
  NContent (KValue rhs) ->
  NContent (KValue out)
eval (Val lhs) (Op op) (Val rhs) = Val (binaryValueOp op lhs rhs)

e ::
  Ref (KValue lhs) %1 ->
  Ref (KOp lhs rhs out) %1 ->
  Ref (KValue rhs) %1 ->
  GraphBuilder (Ref (KValue out))
e refA refOp refB = zipNode3 refA refOp refB eval

(.+.) ::
  Ref (KValue 'CTInt) %1 ->
  Ref (KValue 'CTInt) %1 ->
  GraphBuilder (Ref (KValue 'CTInt))
(.+.) a b = do
  add <- o AddI
  e a add b

(.*.) ::
  Ref (KValue 'CTInt) %1 ->
  Ref (KValue 'CTInt) %1 ->
  GraphBuilder (Ref (KValue 'CTInt))
(.*.) a b = do
  mul <- o MulI
  e a mul b

example :: GraphBuilder (Ref (KValue 'CTInt))
example = do
  x0 <- var "x" (I32 10)

  LPair x1 a <- readVar x0
  b <- v (I32 20)

  c <- a .+. b

  x3 <- writeVar x1 c

  LPair x4 n5 <- readVar x3
  dropNodeM x4

  return n5

fib :: Int -> GraphBuilder (Ref (KValue 'CTInt))
fib 0 = v (I32 0)
fib 1 = v (I32 1)
fib n = do
  n1 <- fib (n - 1)
  n2 <- fib (n - 2)
  n1 .+. n2

fibIter :: Int -> GraphBuilder (Ref (KValue 'CTInt))
fibIter n = do
  prev0 <- var "prev" (I32 0)
  curr0 <- var "curr" (I32 1)
  go n prev0 curr0
  where
    go ::
      Int ->
      Ref (KVar 'CTInt) %1 ->
      Ref (KVar 'CTInt) %1 ->
      GraphBuilder (Ref (KValue 'CTInt))
    go 0 prev curr = do
      LPair prev' result <- readVar prev
      dropNodeM curr
      dropNodeM prev'
      return result
    go k prev curr = do
      LPair prev1 prevVal <- readVar prev

      LPair curr1 currValForNext <- readVar curr
      nextVal <- prevVal .+. currValForNext

      LPair curr2 currValForPrev <- readVar curr1
      prev2 <- writeVar prev1 currValForPrev
      curr3 <- writeVar curr2 nextVal

      go (k - 1) prev2 curr3

run :: GraphBuilder tag -> [N NContent]
run = buildGraph
