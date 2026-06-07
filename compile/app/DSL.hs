{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LinearTypes #-}
{-# LANGUAGE RebindableSyntax #-}

module DSL
  ( Node,
    run,
    example,
    fib,
    fibIter,
    v,
    o,
    var,
    readVar,
    writeVar,
    e,
    (.+.),
    (.*.),
  )
where

import Control.Functor.Linear
import NodeBase
import Prelude.Linear
import Prelude qualified as P

-- DSL layer

data CType
  = CTInt
  | CTDouble

data KValue (ty :: CType)

data Value ty where
  I32 :: Int -> Value 'CTInt
  F64 :: Double -> Value 'CTDouble

data KOp (lhs :: CType) (rhs :: CType) (out :: CType)

data Op lhs rhs out where
  AddI :: Op 'CTInt 'CTInt 'CTInt
  MulI :: Op 'CTInt 'CTInt 'CTInt
  AddD :: Op 'CTDouble 'CTDouble 'CTDouble
  MulD :: Op 'CTDouble 'CTDouble 'CTDouble

data KVar (ty :: CType)

data Node tag where
  NValue :: Value ty -> Node (KValue ty)
  NOp :: Op lhs rhs out -> Node (KOp lhs rhs out)
  NVar :: String -> NPtr Node (KValue ty) -> Node (KVar ty)

type Builder = NBuilder Node

type NodeRef tag = NRef Node tag

v ::
  Value ty ->
  Builder (NodeRef (KValue ty))
v val = node (NValue val)

o ::
  Op lhs rhs out ->
  Builder (NodeRef (KOp lhs rhs out))
o op = node (NOp op)

var ::
  String ->
  Value ty ->
  Builder (NodeRef (KVar ty))
var name val = do
  valueRef <- v val
  case freezeRef valueRef of
    Ur valuePtr ->
      node (NVar name valuePtr)

readVar ::
  NodeRef (KVar ty) %1 ->
  Builder (NodeRef (KVar ty), NodeRef (KValue ty))
readVar ref =
  cloneNodeWith
    ref
    $ \(NVar _ ptr) ->
      copyPtr ptr

writeVar ::
  NodeRef (KVar ty) %1 ->
  NodeRef (KValue ty) %1 ->
  Builder (NodeRef (KVar ty))
writeVar varRef valueRef =
  zipNode2WithId
    varRef
    valueRef
    ( \_ varContent valueId valueContent ->
        case varContent of
          NVar name _ ->
            NVar name (NPtr valueId valueContent)
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
  Node (KValue lhs) ->
  Node (KOp lhs rhs out) ->
  Node (KValue rhs) ->
  Node (KValue out)
eval (NValue lhs) (NOp op) (NValue rhs) = NValue (binaryValueOp op lhs rhs)

e ::
  NodeRef (KValue lhs) %1 ->
  NodeRef (KOp lhs rhs out) %1 ->
  NodeRef (KValue rhs) %1 ->
  Builder (NodeRef (KValue out))
e refA refOp refB = zipNode3 refA refOp refB eval

(.+.) ::
  NodeRef (KValue 'CTInt) %1 ->
  NodeRef (KValue 'CTInt) %1 ->
  Builder (NodeRef (KValue 'CTInt))
(.+.) a b = do
  add <- o AddI
  e a add b

(.*.) ::
  NodeRef (KValue 'CTInt) %1 ->
  NodeRef (KValue 'CTInt) %1 ->
  Builder (NodeRef (KValue 'CTInt))
(.*.) a b = do
  mul <- o MulI
  e a mul b

example :: Builder (NodeRef (KValue 'CTInt))
example = do
  x0 <- var "x" (I32 10)

  (x1, a) <- readVar x0
  b <- v (I32 20)

  c <- a .+. b

  x3 <- writeVar x1 c

  (x4, n5) <- readVar x3
  dropNodeM x4

  return n5

fib :: Int -> Builder (NodeRef (KValue 'CTInt))
fib 0 = v (I32 0)
fib 1 = v (I32 1)
fib n = do
  n1 <- fib (n - 1)
  n2 <- fib (n - 2)
  n1 .+. n2

fibIter :: Int -> Builder (NodeRef (KValue 'CTInt))
fibIter n = do
  prev0 <- var "prev" (I32 0)
  curr0 <- var "curr" (I32 1)
  go n prev0 curr0
  where
    go ::
      Int ->
      NodeRef (KVar 'CTInt) %1 ->
      NodeRef (KVar 'CTInt) %1 ->
      Builder (NodeRef (KValue 'CTInt))
    go 0 prev curr = do
      (prev', result) <- readVar prev
      dropNodeM curr
      dropNodeM prev'
      return result
    go k prev curr = do
      (prev1, prevVal) <- readVar prev

      (curr1, currValForNext) <- readVar curr
      nextVal <- prevVal .+. currValForNext

      (curr2, currValForPrev) <- readVar curr1
      prev2 <- writeVar prev1 currValForPrev
      curr3 <- writeVar curr2 nextVal

      go (k - 1) prev2 curr3

run :: Builder tag -> [N Node]
run = buildGraph

--- Formatting typeclasses

padRight :: Int -> String -> String
padRight n s = s ++ replicate (n - P.length s) ' '

padRightF :: String -> String
padRightF = padRight 8

instance Show (Node tag) where
  show (NValue val) = padRightF "=>" ++ show val
  show (NOp op) = padRightF "Op " ++ show op
  show (NVar name val) = padRightF "===" ++ name ++ " = " ++ show val

instance Show (Value ty) where
  show (I32 i) = show i
  show (F64 f) = show f

instance Show (Op lhs rhs out) where
  show AddI = "AddI"
  show MulI = "MulI"
  show AddD = "AddD"
  show MulD = "MulD"
