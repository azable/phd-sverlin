{-# LANGUAGE DataKinds #-}
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

import Control.Functor.Linear hiding ((<$>), (<*>))
import NodeBase
import Prelude.Linear
import Prelude qualified as P

data CType = CTInt | CTDouble

data KValue (ty :: CType)

data Value ty where
  I32 :: Int %1 -> Value 'CTInt
  F64 :: Double %1 -> Value 'CTDouble

data KOp (lhs :: CType) (rhs :: CType) (out :: CType)

data Op lhs rhs out where
  AddI :: Op 'CTInt 'CTInt 'CTInt
  MulI :: Op 'CTInt 'CTInt 'CTInt
  AddD :: Op 'CTDouble 'CTDouble 'CTDouble
  MulD :: Op 'CTDouble 'CTDouble 'CTDouble

data KVar (ty :: CType)

data NodeContent tag where
  Value ::
    Value ty %1 ->
    NodeContent (KValue ty)
  Op ::
    Op lhs rhs out %1 ->
    NodeContent (KOp lhs rhs out)
  Var ::
    String ->
    NodeContent (KVar ty)

data Desc acts where
  DLiteral :: Desc '[Create (KValue ty)]
  DOperator :: Desc '[Create (KOp lhs rhs out)]
  DDeclareVar ::
    Desc '[Create (KVar ty), Create (KValue ty)]
  DReadVar ::
    Desc '[Observe (KVar ty), Copy (KValue ty)]
  DWriteVar ::
    Desc '[Observe (KVar ty), Replace (KValue ty)]
  DEval ::
    Desc
      '[ Use (KValue lhs),
         Use (KOp lhs rhs out),
         Use (KValue rhs),
         Compute (KValue out)
       ]
  DDiscardVar ::
    Desc '[Destroy (KVar ty), Destroy (KValue ty)]
  DDiscardValue ::
    Desc '[Destroy (KValue ty)]

type Builder = GBuilder NodeContent Desc

type Node tag = N NodeContent tag

data VarNode ty where
  VarNode ::
    Node (KVar ty) %1 ->
    Node (KValue ty) %1 ->
    VarNode ty

declare ::
  String ->
  Value ty %1 ->
  Builder (VarNode ty)
declare name initial = do
  Created valueNode valueSeen <- create (Value initial)
  Created varNode varSeen <- create (Var name)

  emitDesc DDeclareVar (varSeen :~ valueSeen :~ ENil)

  return (VarNode varNode valueNode)

readVar ::
  VarNode ty %1 ->
  Builder (VarNode ty, Node (KValue ty))
readVar (VarNode var held) = do
  Observed var' varSeen <- observe var
  Copied held' copyNode copySeen <- copy held

  emitDesc DReadVar (varSeen :~ copySeen :~ ENil)

  return (VarNode var' held', copyNode)

writeVar ::
  VarNode ty %1 ->
  Node (KValue ty) %1 ->
  Builder (VarNode ty)
writeVar (VarNode var oldHeld) newValue = do
  Observed var' varSeen <- observe var
  Replaced newHeld replaceSeen <- replace oldHeld newValue

  emitDesc DWriteVar (varSeen :~ replaceSeen :~ ENil)

  return (VarNode var' newHeld)

discardVar ::
  VarNode ty %1 ->
  Builder ()
discardVar (VarNode var held) = do
  Destroyed varSeen <- destroy var
  Destroyed heldSeen <- destroy held

  emitDesc DDiscardVar (varSeen :~ heldSeen :~ ENil)

linearValueOp ::
  Op lhs rhs out %1 ->
  Value lhs %1 ->
  Value rhs %1 ->
  Value out
linearValueOp AddI (I32 x) (I32 y) =
  I32 (x + y)
linearValueOp MulI (I32 x) (I32 y) =
  I32 (x * y)
linearValueOp AddD (F64 x) (F64 y) =
  F64 (x + y)
linearValueOp MulD (F64 x) (F64 y) =
  F64 (x * y)

eval ::
  NodeContent (KValue lhs) %1 ->
  NodeContent (KOp lhs rhs out) %1 ->
  NodeContent (KValue rhs) %1 ->
  NodeContent (KValue out)
eval (Value lhs) (Op op) (Value rhs) =
  Value (linearValueOp op lhs rhs)

e ::
  Node (KValue lhs) %1 ->
  Node (KOp lhs rhs out) %1 ->
  Node (KValue rhs) %1 ->
  Builder (Node (KValue out))
e lhsNode opNode rhsNode = do
  Used lhs lhsSeen <- use lhsNode
  Used op opSeen <- use opNode
  Used rhs rhsSeen <- use rhsNode

  Computed outNode outSeen <- compute (eval <$> lhs <*> op <*> rhs)

  emitDesc
    DEval
    (lhsSeen :~ opSeen :~ rhsSeen :~ outSeen :~ ENil)

  return outNode

literal ::
  Value ty %1 ->
  Builder (Node (KValue ty))
literal val = do
  Created node seen <- create (Value val)

  emitDesc DLiteral (seen :~ ENil)

  return node

operator ::
  Op lhs rhs out %1 ->
  Builder (Node (KOp lhs rhs out))
operator op = do
  Created node seen <- create (Op op)

  emitDesc DOperator (seen :~ ENil)

  return node

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

example ::
  Builder ()
example = do
  x0 <- declare "x" (I32 10)
  (x1, a) <- readVar x0
  b <- literal (I32 20)
  c <- a .+. b
  x2 <- writeVar x1 c
  (x3, n5) <- readVar x2

  discardVar x3

  Destroyed n5Seen <- destroy n5

  emitDesc DDiscardValue (n5Seen :~ ENil)

run ::
  Builder () ->
  G NodeContent Desc
run = buildGraph

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
  show (I32 i) = show i
  show (F64 f) = show f

instance Show (Op lhs rhs out) where
  show AddI = "AddI"
  show MulI = "MulI"
  show AddD = "AddD"
  show MulD = "MulD"

instance Show (Desc acts) where
  show DLiteral = "Literal"
  show DOperator = "Operator"
  show DDeclareVar = "DeclareVar"
  show DReadVar = "ReadVar"
  show DWriteVar = "WriteVar"
  show DEval = "Eval"
  show DDiscardVar = "DiscardVar"
  show DDiscardValue = "DiscardValue"