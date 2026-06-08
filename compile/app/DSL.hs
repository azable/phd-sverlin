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

data NodeContent tag where
  Value :: Value ty -> NodeContent (KValue ty)
  Op :: Op lhs rhs out -> NodeContent (KOp lhs rhs out)
  Var :: String -> NSnapshot NodeContent (KValue ty) -> NodeContent (KVar ty)

type Builder = GBuilder NodeContent

type Node tag = N NodeContent tag

var ::
  String ->
  Value ty ->
  Builder (Node (KVar ty))
var name val = do
  valueNode <- [] >>> Value val

  case freeze valueNode of
    Ur snapshot@(NSnapshot valueParent _) ->
      [valueParent] >>> Var name snapshot

readVar ::
  Node (KVar ty) %1 ->
  Builder (Node (KVar ty), Node (KValue ty))
readVar varNode = do
  Observed varParent varContent <- (<<<) varNode

  let Var _ (NSnapshot sParent sValue) = varContent

  nextVar <- [varParent] >>> varContent
  value <- [sParent] >>> sValue

  return (nextVar, value)

writeVar ::
  Node (KVar ty) %1 ->
  Node (KValue ty) %1 ->
  Builder (Node (KVar ty))
writeVar varNode valueNode = do
  Observed varParent varContent <- (<<<) varNode
  Observed valueParent valueContent <- (<<<) valueNode

  let Var varName _ = varContent

  [varParent, valueParent] >>> Var varName (NSnapshot valueParent valueContent)

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
  Observed lhsParent lhsContent <- (<<<) lhsNode
  Observed opParent opContent <- (<<<) opNode
  Observed rhsParent rhsContent <- (<<<) rhsNode

  let outContent = eval lhsContent opContent rhsContent

  [lhsParent, opParent, rhsParent] >>> outContent

(.+.) ::
  Node (KValue 'CTInt) %1 ->
  Node (KValue 'CTInt) %1 ->
  Builder (Node (KValue 'CTInt))
(.+.) a b = do
  add <- (>>>) [] (Op AddI)
  e a add b

(.*.) ::
  Node (KValue 'CTInt) %1 ->
  Node (KValue 'CTInt) %1 ->
  Builder (Node (KValue 'CTInt))
(.*.) a b = do
  mul <- [] >>> Op MulI
  e a mul b

example :: Builder (Node (KValue 'CTInt))
example = do
  x0 <- var "x" (I32 10)

  (x1, a) <- readVar x0
  b <- [] >>> Value (I32 20)

  c <- a .+. b

  x3 <- writeVar x1 c

  (x4, n5) <- readVar x3
  discard x4

  return n5

fibIter :: Int -> Builder (Node (KValue 'CTInt))
fibIter n = do
  prev0 <- var "prev" (I32 0)
  curr0 <- var "curr" (I32 1)
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
