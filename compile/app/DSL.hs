{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE LinearTypes           #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RebindableSyntax      #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeFamilies          #-}

module DSL
  ( -- Literals
    int
  , double
  , -- Operations
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

data BinaryOp
  = TAdd
  | TMul

-- Tags only. These are not value-level payload datatypes.
data Value (ty :: PrimitiveType)

data Var (ty :: PrimitiveType)

data Op (op :: BinaryOp) (lhs :: PrimitiveType) (rhs :: PrimitiveType) (out :: PrimitiveType)

type instance Payload (Value 'TInt) = LInt (Value 'TInt)

type instance Payload (Value 'TDouble) = LDouble (Value 'TDouble)

type instance Payload (Op op lhs rhs out) = LUnit (Op op lhs rhs out)

type instance Payload (Var ty) = LString (Var ty)

int :: Int -> Payload (Value 'TInt)
int = LInt

double :: Double -> Payload (Value 'TDouble)
double = LDouble

data Event acts where
  Literal :: Event '[ Create (Value ty)]
  Operator :: Event '[ Create (Op op lhs rhs out)]
  DeclareVar :: Event '[ Create (Var ty), Create (Value ty)]
  ReadVar :: Event '[ Observe (Var ty), Copy (Value ty)]
  WriteVar :: Event '[ Observe (Var ty), Replace (Value ty)]
  Eval
    :: Event
         '[ Use (Value lhs)
          , Use (Op op lhs rhs out)
          , Use (Value rhs)
          , Compute (Value out)
          ]
  DiscardVar :: Event '[ Destroy (Var ty), Destroy (Value ty)]
  DiscardValue :: Event '[ Destroy (Value ty)]

type Builder a = TraceBuilder Event a

data VarNode ty where
  VarNode :: Node (Var ty) %1 -> Node (Value ty) %1 -> VarNode ty

declare ::
     forall ty. TracePayload (Value ty)
  => String
  -> Payload (Value ty)
     %1 -> Builder (VarNode ty)
declare name initial = do
  Created valueNode createValue <- create initial
  Created varNode createVar <- create (LString name :: Payload (Var ty))
  DeclareVar `explain` (createVar :~ createValue :~ Done)
  return (VarNode varNode valueNode)

readVar ::
     TracePayload (Value ty)
  => VarNode ty
     %1 -> Builder (VarNode ty, Node (Value ty))
readVar (VarNode var held) = do
  Observed var' observeVar <- observe var
  Copied held' copyNode copyHeld <- copy held
  ReadVar `explain` (observeVar :~ copyHeld :~ Done)
  return (VarNode var' held', copyNode)

writeVar ::
     TracePayload (Value ty)
  => VarNode ty
     %1 -> Node (Value ty)
     %1 -> Builder (VarNode ty)
writeVar (VarNode var oldHeld) newValue = do
  Observed var' observeVar <- observe var
  Replaced newHeld replaceHeld <- replace oldHeld newValue
  WriteVar `explain` (observeVar :~ replaceHeld :~ Done)
  return (VarNode var' newHeld)

discardVar :: TracePayload (Value ty) => VarNode ty %1 -> Builder ()
discardVar (VarNode var held) = do
  Destroyed destroyVar <- destroy var
  Destroyed destroyHeld <- destroy held
  DiscardVar `explain` (destroyVar :~ destroyHeld :~ Done)

class ( TracePayload (Value lhs)
      , TracePayload (Op op lhs rhs out)
      , TracePayload (Value rhs)
      , TracePayload (Value out)
      ) =>
      EvalOp op lhs rhs out
  where
  eval ::
       Payload (Value lhs)
       %1 -> Payload (Op op lhs rhs out)
       %1 -> Payload (Value rhs)
       %1 -> Payload (Value out)

instance EvalOp 'TAdd 'TInt 'TInt 'TInt where
  eval (LInt x) LUnit (LInt y) = LInt (x + y)

instance EvalOp 'TMul 'TInt 'TInt 'TInt where
  eval (LInt x) LUnit (LInt y) = LInt (x * y)

instance EvalOp 'TAdd 'TDouble 'TDouble 'TDouble where
  eval (LDouble x) LUnit (LDouble y) = LDouble (x + y)

instance EvalOp 'TMul 'TDouble 'TDouble 'TDouble where
  eval (LDouble x) LUnit (LDouble y) = LDouble (x * y)

e :: EvalOp op lhs rhs out
  => Node (Value lhs)
     %1 -> Node (Op op lhs rhs out)
     %1 -> Node (Value rhs)
     %1 -> Builder (Node (Value out))
e lhsNode opNode rhsNode = do
  Used lhs useLhs <- use lhsNode
  Used op useOp <- use opNode
  Used rhs useRhs <- use rhsNode
  Computed outNode computeOut <- compute (eval <$> lhs <*> op <*> rhs)
  Eval `explain` (useLhs :~ useOp :~ useRhs :~ computeOut :~ Done)
  return outNode

literal ::
     TracePayload (Value ty)
  => Payload (Value ty)
     %1 -> Builder (Node (Value ty))
literal payload = do
  Created node createVal <- create payload
  Literal `explain` (createVal :~ Done)
  return node

operator ::
     TracePayload (Op op lhs rhs out)
  => Payload (Op op lhs rhs out)
     %1 -> Builder (Node (Op op lhs rhs out))
operator payload = do
  Created node createOp <- create payload
  Operator `explain` (createOp :~ Done)
  return node

(.+.) ::
     Node (Value 'TInt)
     %1 -> Node (Value 'TInt)
     %1 -> Builder (Node (Value 'TInt))
(.+.) lhs rhs = do
  add <- operator (LUnit :: Payload (Op 'TAdd 'TInt 'TInt 'TInt))
  e lhs add rhs

(.*.) ::
     Node (Value 'TInt)
     %1 -> Node (Value 'TInt)
     %1 -> Builder (Node (Value 'TInt))
(.*.) lhs rhs = do
  mul <- operator (LUnit :: Payload (Op 'TMul 'TInt 'TInt 'TInt))
  e lhs mul rhs

data FibState where
  FibState :: VarNode 'TInt %1 -> VarNode 'TInt %1 -> FibState

iterateL :: Int -> (state %1 -> Builder state) -> state %1 -> Builder state
iterateL n step state'
  | n P.<= 0 = return state'
  | P.otherwise = do
    state'' <- step state'
    iterateL (n P.- 1) step state''

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
  a0 <- declare "a" (int 0)
  b0 <- declare "b" (int 1)
  final <- iterateL 5 fibStep (FibState a0 b0)
  case final of
    FibState aN bN -> do
      discardVar aN
      discardVar bN

run :: Builder () -> TraceGraph Event
run = buildGraph

-- Rendering logic
padRight :: Int -> String -> String
padRight n s = s P.++ P.replicate (P.max 0 (n P.- P.length s)) ' '

padRightF :: String -> String
padRightF = padRight 5

instance TracePayload (Value 'TInt) where
  payloadView _ (LInt i) = PayloadView (padRightF "Val" P.++ P.show i)

instance TracePayload (Value 'TDouble) where
  payloadView _ (LDouble f) = PayloadView (padRightF "Val" P.++ P.show f)

instance TracePayload (Var ty) where
  payloadView _ (LString name) = PayloadView (padRightF "Var" P.++ name)

instance TracePayload (Op 'TAdd 'TInt 'TInt 'TInt) where
  payloadView _ LUnit = PayloadView (padRightF "Op" P.++ "AddI")

instance TracePayload (Op 'TMul 'TInt 'TInt 'TInt) where
  payloadView _ LUnit = PayloadView (padRightF "Op" P.++ "MulI")

instance TracePayload (Op 'TAdd 'TDouble 'TDouble 'TDouble) where
  payloadView _ LUnit = PayloadView (padRightF "Op" P.++ "AddD")

instance TracePayload (Op 'TMul 'TDouble 'TDouble 'TDouble) where
  payloadView _ LUnit = PayloadView (padRightF "Op" P.++ "MulD")

instance PrintEvent Event where
  printEvent Literal      = "Literal"
  printEvent Operator     = "Operator"
  printEvent DeclareVar   = "DeclareVar"
  printEvent ReadVar      = "ReadVar"
  printEvent WriteVar     = "WriteVar"
  printEvent Eval         = "Eval"
  printEvent DiscardVar   = "DiscardVar"
  printEvent DiscardValue = "DiscardValue"
