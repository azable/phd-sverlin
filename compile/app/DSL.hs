{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs             #-}
{-# LANGUAGE LinearTypes       #-}
{-# LANGUAGE RebindableSyntax  #-}
{-# LANGUAGE TypeFamilies      #-}

module DSL
  ( -- Operations
    declare
  , readVar
  , writeVar
  , discardVar
  , eval
  , literal
  , operator
  , (.+.)
  , (.*.)
  , -- Runners/examples
    run
  , example
  ) where

import           Control.Functor.Linear hiding ((<$>), (<*>))
import           LinearTrace
import qualified Prelude                as P
import           Prelude.Linear

data PrimitiveType
  = TInt
  | TDouble

data Var ty where
  Var :: String -> Var ty

data Value ty where
  I32 :: Int %1 -> Value 'TInt
  F64 :: Double %1 -> Value 'TDouble

data Op lhs rhs out where
  AddI :: Op 'TInt 'TInt 'TInt
  MulI :: Op 'TInt 'TInt 'TInt
  AddD :: Op 'TDouble 'TDouble 'TDouble
  MulD :: Op 'TDouble 'TDouble 'TDouble

type instance Payload (Value ty) = Value ty

type instance Payload (Op lhs rhs out) = Op lhs rhs out

type instance Payload (Var ty) = Var ty

data Desc acts where
  DLiteral :: Desc '[ Create (Value ty)]
  DOperator :: Desc '[ Create (Op lhs rhs out)]
  DDeclareVar :: Desc '[ Create (Var ty), Create (Value ty)]
  DReadVar :: Desc '[ Observe (Var ty), Copy (Value ty)]
  DWriteVar :: Desc '[ Observe (Var ty), Replace (Value ty)]
  DEval
    :: Desc
         '[ Use (Value lhs)
          , Use (Op lhs rhs out)
          , Use (Value rhs)
          , Compute (Value out)
          ]
  DDiscardVar :: Desc '[ Destroy (Var ty), Destroy (Value ty)]
  DDiscardValue :: Desc '[ Destroy (Value ty)]

type Builder a = TraceBuilder Desc a

data VarNode ty where
  VarNode :: Node (Var ty) %1 -> Node (Value ty) %1 -> VarNode ty

declare :: String -> Value ty %1 -> Builder (VarNode ty)
declare name initial = do
  Created valueNode createValue <- create initial
  Created varNode createVar <- create (Var name)
  DDeclareVar `explain` (createVar :~ createValue :~ PaidDebt)
  return (VarNode varNode valueNode)

readVar :: VarNode ty %1 -> Builder (VarNode ty, Node (Value ty))
readVar (VarNode var held) = do
  Observed var' observeVar <- observe var
  Copied held' copyNode copyHeld <- copy held
  DReadVar `explain` (observeVar :~ copyHeld :~ PaidDebt)
  return (VarNode var' held', copyNode)

writeVar :: VarNode ty %1 -> Node (Value ty) %1 -> Builder (VarNode ty)
writeVar (VarNode var oldHeld) newValue = do
  Observed var' observeVar <- observe var
  Replaced newHeld replaceHeld <- replace oldHeld newValue
  DWriteVar `explain` (observeVar :~ replaceHeld :~ PaidDebt)
  return (VarNode var' newHeld)

discardVar :: VarNode ty %1 -> Builder ()
discardVar (VarNode var held) = do
  Destroyed destroyVar <- destroy var
  Destroyed destroyHeld <- destroy held
  DDiscardVar `explain` (destroyVar :~ destroyHeld :~ PaidDebt)

eval :: Value lhs %1 -> Op lhs rhs out %1 -> Value rhs %1 -> Value out
eval (I32 x) AddI (I32 y) = I32 (x + y)
eval (I32 x) MulI (I32 y) = I32 (x * y)
eval (F64 x) AddD (F64 y) = F64 (x + y)
eval (F64 x) MulD (F64 y) = F64 (x * y)

e :: Node (Value lhs)
     %1 -> Node (Op lhs rhs out)
     %1 -> Node (Value rhs)
     %1 -> Builder (Node (Value out))
e lhsNode opNode rhsNode = do
  Used lhs useLhs <- use lhsNode
  Used op useOp <- use opNode
  Used rhs useRhs <- use rhsNode
  Computed outNode computeOut <- compute (eval <$> lhs <*> op <*> rhs)
  DEval `explain` (useLhs :~ useOp :~ useRhs :~ computeOut :~ PaidDebt)
  return outNode

literal :: Value ty %1 -> Builder (Node (Value ty))
literal val = do
  Created node createVal <- create val
  DLiteral `explain` (createVal :~ PaidDebt)
  return node

operator :: Op lhs rhs out %1 -> Builder (Node (Op lhs rhs out))
operator op = do
  Created node createOp <- create op
  DOperator `explain` (createOp :~ PaidDebt)
  return node

(.+.) ::
     Node (Value 'TInt)
     %1 -> Node (Value 'TInt)
     %1 -> Builder (Node (Value 'TInt))
(.+.) lhs rhs = do
  add <- operator AddI
  e lhs add rhs

(.*.) ::
     Node (Value 'TInt)
     %1 -> Node (Value 'TInt)
     %1 -> Builder (Node (Value 'TInt))
(.*.) lhs rhs = do
  mul <- operator MulI
  e lhs mul rhs

data FibState where
  FibState :: VarNode 'TInt %1 -> VarNode 'TInt %1 -> FibState

iterateLinear :: Int -> (state %1 -> Builder state) -> state %1 -> Builder state
iterateLinear n step state'
  | n P.<= 0 = return state'
  | P.otherwise = do
    state'' <- step state'
    iterateLinear (n P.- 1) step state''

fibStep :: FibState %1 -> Builder FibState
fibStep (FibState a0 b0) = do
  (a1, aValue) <- readVar a0
  (b1, bForA) <- readVar b0
  (b2, bForSum) <- readVar b1
  next <- aValue .+. bForSum
  a2 <- writeVar a1 bForA
  b3 <- writeVar b2 next
  return (FibState a2 b3)

example :: Builder ()
example = do
  a0 <- declare "a" (I32 0)
  b0 <- declare "b" (I32 1)
  final <- iterateLinear 5 fibStep (FibState a0 b0)
  case final of
    FibState aN bN -> do
      discardVar aN
      discardVar bN

run :: Builder () -> TraceGraph Desc
run = buildGraph

-- Rendering logic
padRight :: Int -> String -> String
padRight n s = s P.++ P.replicate (P.max 0 (n P.- P.length s)) ' '

padRightF :: String -> String
padRightF = padRight 5

instance TracePayload (Value ty) where
  payloadView _ (I32 i) = PayloadView (padRightF "Val" P.++ P.show i)
  payloadView _ (F64 f) = PayloadView (padRightF "Val" P.++ P.show f)

instance TracePayload (Op lhs rhs out) where
  payloadView _ AddI = PayloadView (padRightF "Op" P.++ "AddI")
  payloadView _ MulI = PayloadView (padRightF "Op" P.++ "MulI")
  payloadView _ AddD = PayloadView (padRightF "Op" P.++ "AddD")
  payloadView _ MulD = PayloadView (padRightF "Op" P.++ "MulD")

instance TracePayload (Var ty) where
  payloadView _ (Var name) = PayloadView (padRightF "Var" P.++ name)

instance PrintDesc Desc where
  printDesc DLiteral      = "Literal"
  printDesc DOperator     = "Operator"
  printDesc DDeclareVar   = "DeclareVar"
  printDesc DReadVar      = "ReadVar"
  printDesc DWriteVar     = "WriteVar"
  printDesc DEval         = "Eval"
  printDesc DDiscardVar   = "DiscardVar"
  printDesc DDiscardValue = "DiscardValue"
