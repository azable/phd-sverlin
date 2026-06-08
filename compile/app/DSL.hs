{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LinearTypes #-}
{-# LANGUAGE RebindableSyntax #-}

module DSL
  ( NodeContent,
    G (..),
    run,
    example,
    fibIter,
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

data NodeContent tag where
  Value :: Value ty -> NodeContent (KValue ty)
  Op :: Op lhs rhs out -> NodeContent (KOp lhs rhs out)
  Var :: String -> NSnapshot NodeContent (KValue ty) -> NodeContent (KVar ty)

type Builder = GBuilder NodeContent

type Node tag = N NodeContent tag

declare ::
  String ->
  Value ty ->
  Builder (Node (KVar ty))
declare name val = do
  valueNode <- () >>> Value val

  case freeze valueNode of
    Ur snapshot ->
      snapshot >>> Var name snapshot

readVar ::
  Node (KVar ty) %1 ->
  Builder (Node (KVar ty), Node (KValue ty))
readVar varNode = do
  Observed var <- (<<<) varNode

  let varContent@(Var _ snapshot@(NSnapshot _ snapshotValue)) = content var

  nextVar <- var >>> varContent
  value <- snapshot >>> snapshotValue

  return (nextVar, value)

writeVar ::
  Node (KVar ty) %1 ->
  Node (KValue ty) %1 ->
  Builder (Node (KVar ty))
writeVar varNode valueNode = do
  Observed var <- (<<<) varNode
  Observed value <- (<<<) valueNode

  let Var varName _ = content var

  (var, value) >>> Var varName (NSnapshot (ref value) (content value))

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
  NodeContent (KValue lhs) ->
  NodeContent (KOp lhs rhs out) ->
  NodeContent (KValue rhs) ->
  NodeContent (KValue out)
eval (Value lhs) (Op op) (Value rhs) = Value (binaryValueOp op lhs rhs)

e ::
  Node (KValue lhs) %1 ->
  Node (KOp lhs rhs out) %1 ->
  Node (KValue rhs) %1 ->
  Builder (Node (KValue out))
e lhsNode opNode rhsNode = do
  Observed lhs <- (<<<) lhsNode
  Observed op <- (<<<) opNode
  Observed rhs <- (<<<) rhsNode

  (lhs, op, rhs) >>> eval (content lhs) (content op) (content rhs)

literal :: Value ty -> Builder (Node (KValue ty))
literal val = () >>> Value val

operator :: Op lhs rhs out -> Builder (Node (KOp lhs rhs out))
operator op = () >>> Op op

(.+.) ::
  Node (KValue 'CTInt) %1 ->
  Node (KValue 'CTInt) %1 ->
  Builder (Node (KValue 'CTInt))
(.+.) a b = do
  add <- operator AddI
  e a add b

(.*.) ::
  Node (KValue 'CTInt) %1 ->
  Node (KValue 'CTInt) %1 ->
  Builder (Node (KValue 'CTInt))
(.*.) a b = do
  mul <- operator MulI
  e a mul b

example :: Builder (Node (KValue 'CTInt))
example = do
  x0 <- declare "x" (I32 10)

  (x1, a) <- readVar x0
  b <- literal (I32 20)

  c <- a .+. b

  x3 <- writeVar x1 c

  (x4, n5) <- readVar x3
  discard x4

  return n5

fibIter :: Int -> Builder (Node (KValue 'CTInt))
fibIter n = do
  prev0 <- declare "prev" (I32 0)
  curr0 <- declare "curr" (I32 1)
  go n prev0 curr0
  where
    go ::
      Int ->
      Node (KVar 'CTInt) %1 ->
      Node (KVar 'CTInt) %1 ->
      Builder (Node (KValue 'CTInt))
    go 0 prev curr = do
      (prev', result) <- readVar prev
      discard curr
      discard prev'
      return result
    go k prev curr = do
      (prev1, prevVal) <- readVar prev

      (curr1, currValForNext) <- readVar curr
      nextVal <- prevVal .+. currValForNext

      (curr2, currValForPrev) <- readVar curr1
      prev2 <- writeVar prev1 currValForPrev
      curr3 <- writeVar curr2 nextVal

      go (k - 1) prev2 curr3

run :: Builder (Node tag) -> G NodeContent
run = buildGraph

--- Formatting typeclasses

padRight :: Int -> String -> String
padRight n s = s ++ replicate (n - P.length s) ' '

padRightF :: String -> String
padRightF = padRight 8

instance Show (NodeContent tag) where
  show (Value val) = padRightF "=>" ++ show val
  show (Op op) = padRightF "Op " ++ show op
  show (Var name val) = padRightF "===" ++ name ++ " = " ++ show val

instance Show (Value ty) where
  show (I32 i) = show i
  show (F64 f) = show f

instance Show (Op lhs rhs out) where
  show AddI = "AddI"
  show MulI = "MulI"
  show AddD = "AddD"
  show MulD = "MulD"