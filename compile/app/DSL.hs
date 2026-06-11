{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LinearTypes #-}
{-# LANGUAGE RebindableSyntax #-}
{-# LANGUAGE TypeOperators #-}

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

-- Description schemas.
--
-- These are no longer plain labels. Each constructor carries, at the type
-- level, the lifecycle protocol that must be discharged when emitting it.
--
-- Flattened observation order:
--
--   DLiteral    [value]
--   DOperator   [operator]
--   DDeclareVar [var, initialValue]
--   DReadVar    [var, copiedFrom, copiedTo]
--   DWriteVar   [var, replacedFrom, replacedTo]
--   DEval       [lhs, op, rhs, out]
--   DDiscardVar [var, heldValue]
data Desc acts where
  DLiteral ::
    Desc
      '[ Create (KValue ty)
       ]
  DOperator ::
    Desc
      '[ Create (KOp lhs rhs out)
       ]
  DDeclareVar ::
    Desc
      '[ Create (KVar ty),
         Create (KValue ty)
       ]
  DReadVar ::
    Desc
      '[ Observe (KVar ty),
         Copy (KValue ty)
       ]
  DWriteVar ::
    Desc
      '[ Observe (KVar ty),
         Replace (KValue ty)
       ]
  DEval ::
    Desc
      '[ Use (KValue lhs),
         Use (KOp lhs rhs out),
         Use (KValue rhs),
         Create (KValue out)
       ]
  DDiscardVar ::
    Desc
      '[ Destroy (KVar ty),
         Destroy (KValue ty)
       ]

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
  (valueNode, Evidence _ valueSeen) <- create (Value initial)
  (varNode, Evidence _ varSeen) <- create (Var name)

  emitDesc DDeclareVar (EvCreate varSeen :~ EvCreate valueSeen :~ ENil)

  return (VarNode varNode valueNode)

readVar ::
  VarNode ty %1 ->
  Builder (VarNode ty, Node (KValue ty))
readVar (VarNode var held) = do
  (var', Evidence _ varSeen) <- observe var
  (held', Evidence _ copiedFromSeen, copyNode, Evidence _ copiedToSeen) <-
    copy held

  emitDesc
    DReadVar
    ( EvObserve varSeen
        :~ EvCopy copiedFromSeen copiedToSeen
        :~ ENil
    )

  return (VarNode var' held', copyNode)

writeVar ::
  VarNode ty %1 ->
  Node (KValue ty) %1 ->
  Builder (VarNode ty)
writeVar (VarNode var oldHeld) newValue = do
  (var', Evidence _ varSeen) <- observe var
  (newHeld, Evidence _ replacedFromSeen, Evidence _ replacedToSeen) <-
    replace oldHeld newValue

  emitDesc
    DWriteVar
    ( EvObserve varSeen
        :~ EvReplace replacedFromSeen replacedToSeen
        :~ ENil
    )

  return (VarNode var' newHeld)

discardVar ::
  VarNode ty %1 ->
  Builder ()
discardVar (VarNode var held) = do
  Evidence _ varSeen <- destroy var
  Evidence _ heldSeen <- destroy held

  emitDesc
    DDiscardVar
    ( EvDestroy varSeen
        :~ EvDestroy heldSeen
        :~ ENil
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

  emitDesc
    DEval
    ( EvUse lhsSeen
        :~ EvUse opSeen
        :~ EvUse rhsSeen
        :~ EvCreate outSeen
        :~ ENil
    )

  return outNode

literal ::
  Value ty ->
  Builder (Node (KValue ty))
literal val = do
  (node, Evidence _ seen) <-
    create (Value val)

  emitDesc
    DLiteral
    ( EvCreate seen
        :~ ENil
    )

  return node

operator ::
  Op lhs rhs out ->
  Builder (Node (KOp lhs rhs out))
operator op = do
  (node, Evidence _ seen) <-
    create (Op op)

  emitDesc
    DOperator
    ( EvCreate seen
        :~ ENil
    )

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

instance Show (Desc acts) where
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