{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LinearTypes #-}
{-# LANGUAGE RebindableSyntax #-}

module DSL where

import Control.Functor.Linear
import NodeBase
import Prelude.Linear
import Prelude qualified as P

-- DSL layer

data KValue

data KOp

data KInfo

data KVar

data NContent tag where
  EVal :: Value -> NContent KValue
  Op :: Op -> NContent KOp
  Info :: String -> NContent KInfo
  Var :: String -> Value -> NContent KVar

padRight :: Int -> String -> String
padRight n s = s ++ replicate (n - P.length s) ' '

padRightF :: String -> String
padRightF = padRight 8

instance Show (NContent tag) where
  show (EVal val) = padRightF "=>" ++ show val
  show (Op op) = padRightF "Op " ++ show op
  show (Info info) = padRightF "Inf " ++ info
  show (Var name val) = padRightF "===" ++ name ++ " = " ++ show val

type GraphBuilder = NBuilder NContent

type Ref tag = NRef NContent tag

type VRef = Ref KValue

type ORef = Ref KOp

type InfoRef = Ref KInfo

type CellRef = Ref KVar

data Value
  = I32 Int
  | F64 Double

instance Show Value where
  show (I32 i) = show i
  show (F64 f) = show f

data Op
  = Add
  | Mul
  deriving stock (Show)

v :: Value -> GraphBuilder VRef
v val = node (EVal val)

o :: Op -> GraphBuilder ORef
o op = node (Op op)

cell :: String -> Value -> GraphBuilder CellRef
cell name val = node (Var name val)

readCell :: CellRef %1 -> GraphBuilder (LPair CellRef VRef)
readCell ref = cloneNode ref $ \(Var _ val) -> EVal val

writeCell :: CellRef %1 -> VRef %1 -> GraphBuilder CellRef
writeCell cellRef valueRef =
  zipNode2 cellRef valueRef $ \cellContent valueContent ->
    case (cellContent, valueContent) of
      (Var name _, EVal val) ->
        Var name val

binaryValueOp :: Op -> Value -> Value -> Value
binaryValueOp Add (I32 x) (I32 y) = I32 (x + y)
binaryValueOp Mul (I32 x) (I32 y) = I32 (x * y)
binaryValueOp Add (F64 x) (F64 y) = F64 (x + y)
binaryValueOp Mul (F64 x) (F64 y) = F64 (x * y)
binaryValueOp op lhs rhs =
  error $
    "Type mismatch"
      ++ "\n  LHS: "
      ++ show lhs
      ++ "\n  OP: "
      ++ show op
      ++ "\n  RHS: "
      ++ show rhs

eval :: NContent KValue -> NContent KOp -> NContent KValue -> NContent KValue
eval (EVal lhs) (Op op) (EVal rhs) =
  EVal (binaryValueOp op lhs rhs)

e :: VRef %1 -> ORef %1 -> VRef %1 -> GraphBuilder VRef
e refA refOp refB = zipNode3 refA refOp refB eval

(.+.) :: VRef %1 -> VRef %1 -> GraphBuilder VRef
(.+.) a b = do
  add <- o Add
  e a add b

(.*.) :: VRef %1 -> VRef %1 -> GraphBuilder VRef
(.*.) a b = do
  mul <- o Mul
  e a mul b

example :: GraphBuilder InfoRef
example = do
  x0 <- cell "x" (I32 10)

  LPair x1 a <- readCell x0
  LPair x2 b <- readCell x1

  c <- a .+. b

  x3 <- writeCell x2 c

  LPair x4 n5 <- readCell x3
  dropNodeM x4

  mapNode n5 $ \result ->
    Info $ "The result is: " ++ show result

fib :: Int -> GraphBuilder VRef
fib 0 = v (I32 0)
fib 1 = v (I32 1)
fib n = do
  n1 <- fib (n - 1)
  n2 <- fib (n - 2)
  n1 .+. n2

fibIter :: Int -> GraphBuilder VRef
fibIter n = do
  prev0 <- cell "prev" (I32 0)
  curr0 <- cell "curr" (I32 1)
  go n prev0 curr0
  where
    go :: Int -> CellRef %1 -> CellRef %1 -> GraphBuilder VRef
    go 0 prev curr = do
      LPair prev' result <- readCell prev
      dropNodeM curr
      dropNodeM prev'
      return result
    go k prev curr = do
      LPair prev1 prevVal <- readCell prev

      LPair curr1 currValForNext <- readCell curr
      nextVal <- prevVal .+. currValForNext

      LPair curr2 currValForPrev <- readCell curr1
      prev2 <- writeCell prev1 currValForPrev

      curr3 <- writeCell curr2 nextVal

      go (k - 1) prev2 curr3

run :: GraphBuilder tag -> [N NContent]
run = buildGraph
