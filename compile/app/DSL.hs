{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LinearTypes #-}
{-# LANGUAGE RebindableSyntax #-}

module DSL
  ( NodeContent,
    CType (..),
    Value (..),
    Op (..),
    Desc (..),
    G (..),
    Node,
    VarNode,
    run,
    example,
    declare,
    readVar,
    writeVar,
    discardVar,
    e,
    literal,
    operator,
    (.+.),
    (.*.),
  )
where

import Control.Functor.Linear
import NodeBase
import Prelude.Linear
import Prelude qualified as P

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
  Var :: String -> NodeContent (KVar ty)

-- Positional event conventions:
--
--   DLiteral    [value]
--   DOperator   [operator]
--   DDeclareVar [var, initialValue]
--   DReadVar    [var, heldValue, copiedValue]
--   DWriteVar   [var, oldValue, newValue]
--   DEval       [lhs, op, rhs, out]
--   DDiscardVar [var, heldValue]
data Desc
  = DLiteral
  | DOperator
  | DDeclareVar
  | DReadVar
  | DWriteVar
  | DEval
  | DDiscardVar

type Builder =
  GBuilder NodeContent Desc

type Node tag =
  N NodeContent tag

data VarNode ty where
  VarNode ::
    Node (KVar ty) %1 ->
    Node (KValue ty) %1 ->
    VarNode ty

declare ::
  String ->
  Value ty ->
  Builder (VarNode ty)
declare name initial = do
  (valueNode, Evidence _ valueSeen) <-
    create (Value initial)

  (varNode, Evidence _ varSeen) <-
    create (Var name)

  describe2
    DDeclareVar
    varSeen
    valueSeen

  return (VarNode varNode valueNode)

readVar ::
  VarNode ty %1 ->
  Builder (VarNode ty, Node (KValue ty))
readVar (VarNode var held) = do
  (var', Evidence _ varSeen) <-
    observe var

  (held', Evidence _ heldSeen, copyNode, Evidence _ copySeen) <-
    copy held

  describe3
    DReadVar
    varSeen
    heldSeen
    copySeen

  return (VarNode var' held', copyNode)

writeVar ::
  VarNode ty %1 ->
  Node (KValue ty) %1 ->
  Builder (VarNode ty)
writeVar (VarNode var oldHeld) newValue = do
  (var', Evidence _ varSeen) <-
    observe var

  Evidence _ oldSeen <-
    destroy oldHeld

  (newValue', Evidence _ newSeen) <-
    observe newValue

  describe3
    DWriteVar
    varSeen
    oldSeen
    newSeen

  return (VarNode var' newValue')

discardVar ::
  VarNode ty %1 ->
  Builder ()
discardVar (VarNode var held) = do
  Evidence _ varSeen <-
    destroy var

  Evidence _ heldSeen <-
    destroy held

  describe2
    DDiscardVar
    varSeen
    heldSeen

binaryValueOp ::
  Op lhs rhs out ->
  Value lhs ->
  Value rhs ->
  Value out
binaryValueOp AddI (I32 x) (I32 y) =
  I32 (x + y)
binaryValueOp MulI (I32 x) (I32 y) =
  I32 (x * y)
binaryValueOp AddD (F64 x) (F64 y) =
  F64 (x + y)
binaryValueOp MulD (F64 x) (F64 y) =
  F64 (x * y)

eval ::
  NodeContent (KValue lhs) ->
  NodeContent (KOp lhs rhs out) ->
  NodeContent (KValue rhs) ->
  NodeContent (KValue out)
eval (Value lhs) (Op op) (Value rhs) =
  Value (binaryValueOp op lhs rhs)

e ::
  Node (KValue lhs) %1 ->
  Node (KOp lhs rhs out) %1 ->
  Node (KValue rhs) %1 ->
  Builder (Node (KValue out))
e lhsNode opNode rhsNode = do
  Evidence lhsObs lhsSeen <- use lhsNode
  Evidence opObs opSeen <- use opNode
  Evidence rhsObs rhsSeen <- use rhsNode

  (outNode, Evidence _ outSeen) <-
    create (eval (content lhsObs) (content opObs) (content rhsObs))

  describe4 DEval lhsSeen opSeen rhsSeen outSeen

  return outNode

literal ::
  Value ty ->
  Builder (Node (KValue ty))
literal val = do
  (node, Evidence _ seen) <-
    create (Value val)

  describe1
    DLiteral
    seen

  return node

operator ::
  Op lhs rhs out ->
  Builder (Node (KOp lhs rhs out))
operator op = do
  (node, Evidence _ seen) <-
    create (Op op)

  describe1
    DOperator
    seen

  return node

(.+.) ::
  Node (KValue 'CTInt) %1 ->
  Node (KValue 'CTInt) %1 ->
  Builder (Node (KValue 'CTInt))
(.+.) a b = do
  add <-
    operator AddI

  e a add b

(.*.) ::
  Node (KValue 'CTInt) %1 ->
  Node (KValue 'CTInt) %1 ->
  Builder (Node (KValue 'CTInt))
(.*.) a b = do
  mul <-
    operator MulI

  e a mul b

example ::
  Builder (Node (KValue 'CTInt))
example = do
  x0 <-
    declare "x" (I32 10)

  (x1, a) <-
    readVar x0

  b <-
    literal (I32 20)

  c <-
    a .+. b

  x2 <-
    writeVar x1 c

  (x3, n5) <-
    readVar x2

  discardVar x3

  return n5

run ::
  Builder (Node tag) ->
  G NodeContent Desc
run =
  buildGraph

padRight :: Int -> String -> String
padRight n s =
  s ++ replicate (n - P.length s) ' '

padRightF :: String -> String
padRightF =
  padRight 8

instance Show (NodeContent tag) where
  show (Value val) =
    padRightF "Val" ++ show val
  show (Op op) =
    padRightF "Op" ++ show op
  show (Var name) =
    padRightF "Var" ++ name

instance Show (Value ty) where
  show (I32 i) =
    show i
  show (F64 f) =
    show f

instance Show (Op lhs rhs out) where
  show AddI =
    "AddI"
  show MulI =
    "MulI"
  show AddD =
    "AddD"
  show MulD =
    "MulD"

instance Show Desc where
  show DLiteral =
    "Literal"
  show DOperator =
    "Operator"
  show DDeclareVar =
    "DeclareVar"
  show DReadVar =
    "ReadVar"
  show DWriteVar =
    "WriteVar"
  show DEval =
    "Eval"
  show DDiscardVar =
    "DiscardVar"