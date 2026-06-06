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
  Var :: String -> NPtr NContent KValue -> NContent KVar

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

type VarRef = Ref KVar

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

var :: String -> Value -> GraphBuilder VarRef
var name val = do
  valueRef <- v val
  case freezeRef valueRef of
    Ur valuePtr ->
      node (Var name valuePtr)

readVar :: VarRef %1 -> GraphBuilder (LPair VarRef VRef)
readVar ref =
  cloneNodeWith
    ref
    $ \(Var _ ptr) ->
      copyPtr ptr

writeVar :: VarRef %1 -> VRef %1 -> GraphBuilder VarRef
writeVar varRef valueRef =
  zipNode2WithId
    varRef
    valueRef
    ( \_ varContent valueId valueContent ->
        case varContent of
          Var name _ ->
            Var name (NPtr valueId valueContent)
    )

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
  x0 <- var "x" (I32 10)

  LPair x1 a <- readVar x0
  LPair x2 b <- readVar x1

  c <- a .+. b

  x3 <- writeVar x2 c

  LPair x4 n5 <- readVar x3
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
  prev0 <- var "prev" (I32 0)
  curr0 <- var "curr" (I32 1)
  go n prev0 curr0
  where
    go :: Int -> VarRef %1 -> VarRef %1 -> GraphBuilder VRef
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
