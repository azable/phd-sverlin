{-# LANGUAGE DataKinds               #-}
{-# LANGUAGE FlexibleContexts        #-}
{-# LANGUAGE FlexibleInstances       #-}
{-# LANGUAGE GADTs                   #-}
{-# LANGUAGE LinearTypes             #-}
{-# LANGUAGE MultiParamTypeClasses   #-}
{-# LANGUAGE QualifiedDo             #-}
{-# LANGUAGE RebindableSyntax        #-}
{-# LANGUAGE ScopedTypeVariables     #-}
{-# LANGUAGE TypeFamilies            #-}
{-# LANGUAGE TypeOperators           #-}
{-# LANGUAGE UndecidableInstances    #-}
{-# LANGUAGE UndecidableSuperClasses #-}

module DSL.Main
  ( -- * Public program types
    Builder
  , Step(..)
  , Performed(..)
  , step
  , (:*)(..)
  , run
  , -- * DSL type vocabulary
    PrimitiveType(..)
  , BinaryOp(..)
  , Value
  , Var
  , Op
  , VarBlock(..)
  , IntBlock
  , DoubleBlock
  , IntVar
  , DoubleVar
  , -- * Result types
    ReadVarResult(..)
  , -- * Event types
    Literal(..)
  , Operator(..)
  , DeclareVar(..)
  , ReadVar(..)
  , WriteVar(..)
  , Eval(..)
  , DiscardVar(..)
  , DiscardValue(..)
  , -- * Action-list aliases
    LiteralActs
  , OperatorActs
  , DeclareVarActs
  , ReadVarActs
  , WriteVarActs
  , EvalActs
  , DiscardVarActs
  , DiscardValueActs
  , -- * Literals
    int
  , double
  , literal
  , -- * Variables
    declare
  , readVar
  , writeVar
  , discardVar
  , -- * Values
    discardValue
  , -- * Operators
    operator
  , apply
  , (.+.)
  , (.*.)
  , -- * Example
    ExampleEvents
  , example
  ) where

import           Control.Functor.Linear hiding ((<$>), (<*>))
import           Control.Monad.Reader   (ask)
import           Data.Kind              (Type)
import           Data.Proxy             (Proxy (..))
import           LinearTrace
import           LinearTrace.Visualize

import qualified Prelude                as P
import           Prelude.Linear

infixr 4 :*
--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------
labelWidth :: Int
labelWidth = 5

--------------------------------------------------------------------------------
-- Builder / step protocol
--------------------------------------------------------------------------------
type Builder events a = TraceBuilder events a

data (:*) a b where
  (:*) :: a %1 -> b %1 -> a :* b

data Performed event result where
  Performed
    :: result %1 -> EvidenceList (EventActs event) %1 -> Performed event result

class TraceEventSpec event =>
      Step event
  where
  type StepInput event :: Type
  type StepResult event :: Type
  perform ::
       event
    -> StepInput event
       %1 -> Builder events (Performed event (StepResult event))

step ::
     forall event events. (Step event, Member event events)
  => event
  -> StepInput event
     %1 -> Builder events (StepResult event)
step event input = do
  Performed result evidence <- perform event input
  event `explain` evidence
  return result

run :: Builder events () -> TraceGraph events
run = buildGraph

--------------------------------------------------------------------------------
-- DSL type vocabulary
--------------------------------------------------------------------------------
data PrimitiveType
  = TInt
  | TDouble

data BinaryOp
  = TAdd
  | TMul

data Value (ty :: PrimitiveType)

data Var (ty :: PrimitiveType)

data Op (op :: BinaryOp) (lhs :: PrimitiveType) (rhs :: PrimitiveType) (out :: PrimitiveType)

type instance Payload (Value 'TInt) = LInt (Value 'TInt)

type instance Payload (Value 'TDouble) = LDouble (Value 'TDouble)

type instance Payload (Var ty) = LString (Var ty)

type instance Payload (Op op lhs rhs out) = LUnit (Op op lhs rhs out)

type IntBlock = Block (Value 'TInt)

type DoubleBlock = Block (Value 'TDouble)

type IntVar = VarBlock 'TInt

type DoubleVar = VarBlock 'TDouble

data VarBlock ty where
  VarBlock :: Block (Var ty) %1 -> Slot (Var ty) (Value ty) %1 -> VarBlock ty

--------------------------------------------------------------------------------
-- Payload constructors
--------------------------------------------------------------------------------
int :: Int -> Payload (Value 'TInt)
int = LInt

double :: Double -> Payload (Value 'TDouble)
double = LDouble

--------------------------------------------------------------------------------
-- Literal step
--------------------------------------------------------------------------------
type LiteralActs ty = '[ Create (Value ty)]

data Literal (ty :: PrimitiveType) =
  Literal

instance TraceEventSpec (Literal ty) where
  type EventActs (Literal ty) = LiteralActs ty

instance TraceBlock (Value ty) => Step (Literal ty) where
  type StepInput (Literal ty) = Payload (Value ty)
  type StepResult (Literal ty) = Block (Value ty)
  perform Literal payload = do
    Created block createValue <- create payload
    return (Performed block (createValue :~ Done))

literal ::
     (TraceBlock (Value ty), Member (Literal ty) events)
  => Payload (Value ty)
     %1 -> Builder events (Block (Value ty))
literal = step Literal

instance PrintEvent (Literal ty) where
  printEvent Literal = "Literal"

--------------------------------------------------------------------------------
-- Declare variable step
--------------------------------------------------------------------------------
type DeclareVarActs ty
  = '[ Create (Value ty), Create (Var ty), Seal (Var ty) (Value ty)]

newtype DeclareVar (ty :: PrimitiveType) =
  DeclareVar String

instance TraceEventSpec (DeclareVar ty) where
  type EventActs (DeclareVar ty) = DeclareVarActs ty

instance (TraceBlock (Value ty), TraceBlock (Var ty)) => Step (DeclareVar ty) where
  type StepInput (DeclareVar ty) = Payload (Value ty)
  type StepResult (DeclareVar ty) = VarBlock ty
  perform (DeclareVar name) initial = do
    Created valueBlock createValue <- create initial
    Created varBlock createVar <- create (LString name :: Payload (Var ty))
    Sealed varBlock' valueSlot sealValue <- seal varBlock valueBlock
    return
      (Performed
         (VarBlock varBlock' valueSlot)
         (createValue :~ createVar :~ sealValue :~ Done))

declare ::
     forall events ty.
     (TraceBlock (Value ty), TraceBlock (Var ty), Member (DeclareVar ty) events)
  => String
  -> Payload (Value ty)
     %1 -> Builder events (VarBlock ty)
declare name = step (DeclareVar name)

instance PrintEvent (DeclareVar ty) where
  printEvent (DeclareVar name) = "DeclareVar " P.++ name

--------------------------------------------------------------------------------
-- Read variable step
--------------------------------------------------------------------------------
type ReadVarActs ty
  = '[ Unseal (Var ty) (Value ty), Copy (Value ty), Seal (Var ty) (Value ty)]

data ReadVar (ty :: PrimitiveType) =
  ReadVar

data ReadVarResult ty where
  ReadVarResult :: VarBlock ty %1 -> Block (Value ty) %1 -> ReadVarResult ty

instance TraceEventSpec (ReadVar ty) where
  type EventActs (ReadVar ty) = ReadVarActs ty

instance (TraceBlock (Value ty), TraceBlock (Var ty)) => Step (ReadVar ty) where
  type StepInput (ReadVar ty) = VarBlock ty
  type StepResult (ReadVar ty) = ReadVarResult ty
  perform ReadVar (VarBlock varBlock valueSlot) = do
    Unsealed var1 held unsealValue <- unseal varBlock valueSlot
    Copied held' copyBlock copyValue <- copy held
    Sealed var2 valueSlot' sealValue <- seal var1 held'
    return
      (Performed
         (ReadVarResult (VarBlock var2 valueSlot') copyBlock)
         (unsealValue :~ copyValue :~ sealValue :~ Done))

readVar ::
     (TraceBlock (Value ty), TraceBlock (Var ty), Member (ReadVar ty) events)
  => VarBlock ty
     %1 -> Builder events (VarBlock ty, Block (Value ty))
readVar varBlock = do
  ReadVarResult nextVar value <- step ReadVar varBlock
  return (nextVar, value)

instance PrintEvent (ReadVar ty) where
  printEvent ReadVar = "ReadVar"

--------------------------------------------------------------------------------
-- Write variable step
--------------------------------------------------------------------------------
type WriteVarActs ty
  = '[ Unseal (Var ty) (Value ty), Replace (Value ty), Seal (Var ty) (Value ty)]

data WriteVar (ty :: PrimitiveType) =
  WriteVar

instance TraceEventSpec (WriteVar ty) where
  type EventActs (WriteVar ty) = WriteVarActs ty

instance (TraceBlock (Value ty), TraceBlock (Var ty)) => Step (WriteVar ty) where
  type StepInput (WriteVar ty) = VarBlock ty :* Block (Value ty)
  type StepResult (WriteVar ty) = VarBlock ty
  perform WriteVar (VarBlock varBlock valueSlot :* newValue) = do
    Unsealed var1 oldValue unsealValue <- unseal varBlock valueSlot
    Replaced currentValue replaceValue <- replace oldValue newValue
    Sealed var2 valueSlot' sealValue <- seal var1 currentValue
    return
      (Performed
         (VarBlock var2 valueSlot')
         (unsealValue :~ replaceValue :~ sealValue :~ Done))

writeVar ::
     (TraceBlock (Value ty), TraceBlock (Var ty), Member (WriteVar ty) events)
  => VarBlock ty
     %1 -> Block (Value ty)
     %1 -> Builder events (VarBlock ty)
writeVar varBlock newValue = step WriteVar (varBlock :* newValue)

instance PrintEvent (WriteVar ty) where
  printEvent WriteVar = "WriteVar"

--------------------------------------------------------------------------------
-- Discard variable step
--------------------------------------------------------------------------------
type DiscardVarActs ty
  = '[ Unseal (Var ty) (Value ty), Destroy (Var ty), Destroy (Value ty)]

data DiscardVar (ty :: PrimitiveType) =
  DiscardVar

instance TraceEventSpec (DiscardVar ty) where
  type EventActs (DiscardVar ty) = DiscardVarActs ty

instance (TraceBlock (Value ty), TraceBlock (Var ty)) => Step (DiscardVar ty) where
  type StepInput (DiscardVar ty) = VarBlock ty
  type StepResult (DiscardVar ty) = ()
  perform DiscardVar (VarBlock varBlock valueSlot) = do
    Unsealed var1 held unsealValue <- unseal varBlock valueSlot
    Destroyed destroyVar <- destroy var1
    Destroyed destroyHeld <- destroy held
    return (Performed () (unsealValue :~ destroyVar :~ destroyHeld :~ Done))

discardVar ::
     (TraceBlock (Value ty), TraceBlock (Var ty), Member (DiscardVar ty) events)
  => VarBlock ty
     %1 -> Builder events ()
discardVar = step DiscardVar

instance PrintEvent (DiscardVar ty) where
  printEvent DiscardVar = "DiscardVar"

--------------------------------------------------------------------------------
-- Discard value step
--------------------------------------------------------------------------------
type DiscardValueActs ty = '[ Destroy (Value ty)]

data DiscardValue (ty :: PrimitiveType) =
  DiscardValue

instance TraceEventSpec (DiscardValue ty) where
  type EventActs (DiscardValue ty) = DiscardValueActs ty

instance TraceBlock (Value ty) => Step (DiscardValue ty) where
  type StepInput (DiscardValue ty) = Block (Value ty)
  type StepResult (DiscardValue ty) = ()
  perform DiscardValue value = do
    Destroyed destroyValue <- destroy value
    return (Performed () (destroyValue :~ Done))

discardValue ::
     (TraceBlock (Value ty), Member (DiscardValue ty) events)
  => Block (Value ty)
     %1 -> Builder events ()
discardValue = step DiscardValue

instance PrintEvent (DiscardValue ty) where
  printEvent DiscardValue = "DiscardValue"

--------------------------------------------------------------------------------
-- Operator step
--------------------------------------------------------------------------------
type OperatorActs op lhs rhs out = '[ Create (Op op lhs rhs out)]

data Operator (op :: BinaryOp) (lhs :: PrimitiveType) (rhs :: PrimitiveType) (out :: PrimitiveType) =
  Operator

instance TraceEventSpec (Operator op lhs rhs out) where
  type EventActs (Operator op lhs rhs out) = OperatorActs op lhs rhs out

instance TraceBlock (Op op lhs rhs out) => Step (Operator op lhs rhs out) where
  type StepInput (Operator op lhs rhs out) = Payload (Op op lhs rhs out)
  type StepResult (Operator op lhs rhs out) = Block (Op op lhs rhs out)
  perform Operator payload = do
    Created block createOp <- create payload
    return (Performed block (createOp :~ Done))

operator ::
     (TraceBlock (Op op lhs rhs out), Member (Operator op lhs rhs out) events)
  => Payload (Op op lhs rhs out)
     %1 -> Builder events (Block (Op op lhs rhs out))
operator = step Operator

instance PrintEvent (Operator op lhs rhs out) where
  printEvent Operator = "Operator"

--------------------------------------------------------------------------------
-- Evaluation support
--------------------------------------------------------------------------------
class ( TraceBlock (Value lhs)
      , TraceBlock (Op op lhs rhs out)
      , TraceBlock (Value rhs)
      , TraceBlock (Value out)
      ) =>
      EvalOp op lhs rhs out
  where
  evalPayload ::
       Payload (Value lhs)
       %1 -> Payload (Op op lhs rhs out)
       %1 -> Payload (Value rhs)
       %1 -> Payload (Value out)

instance EvalOp 'TAdd 'TInt 'TInt 'TInt where
  evalPayload (LInt x) LUnit (LInt y) = LInt (x + y)

instance EvalOp 'TMul 'TInt 'TInt 'TInt where
  evalPayload (LInt x) LUnit (LInt y) = LInt (x * y)

instance EvalOp 'TAdd 'TDouble 'TDouble 'TDouble where
  evalPayload (LDouble x) LUnit (LDouble y) = LDouble (x + y)

instance EvalOp 'TMul 'TDouble 'TDouble 'TDouble where
  evalPayload (LDouble x) LUnit (LDouble y) = LDouble (x * y)

--------------------------------------------------------------------------------
-- Eval step
--------------------------------------------------------------------------------
type EvalActs op lhs rhs out
  = '[ Use (Value lhs)
     , Use (Op op lhs rhs out)
     , Use (Value rhs)
     , Compute (Value out)
     ]

data Eval (op :: BinaryOp) (lhs :: PrimitiveType) (rhs :: PrimitiveType) (out :: PrimitiveType) =
  Eval

instance TraceEventSpec (Eval op lhs rhs out) where
  type EventActs (Eval op lhs rhs out) = EvalActs op lhs rhs out

instance EvalOp op lhs rhs out => Step (Eval op lhs rhs out) where
  type StepInput (Eval op lhs rhs out) = Block (Value lhs) :* Block
    (Op op lhs rhs out) :* Block (Value rhs)
  type StepResult (Eval op lhs rhs out) = Block (Value out)
  perform Eval (lhsBlock :* opBlock :* rhsBlock) = do
    Used lhs useLhs <- use lhsBlock
    Used opPayload useOp <- use opBlock
    Used rhs useRhs <- use rhsBlock
    Computed outBlock computeOut <-
      compute (evalPayload <$> lhs <*> opPayload <*> rhs)
    return
      (Performed outBlock (useLhs :~ useOp :~ useRhs :~ computeOut :~ Done))

apply ::
     (EvalOp op lhs rhs out, Member (Eval op lhs rhs out) events)
  => Block (Value lhs)
     %1 -> Block (Op op lhs rhs out)
     %1 -> Block (Value rhs)
     %1 -> Builder events (Block (Value out))
apply lhsBlock opBlock rhsBlock = step Eval (lhsBlock :* opBlock :* rhsBlock)

instance PrintEvent (Eval op lhs rhs out) where
  printEvent Eval = "Eval"

--------------------------------------------------------------------------------
-- Operator convenience combinators
--------------------------------------------------------------------------------
(.+.) ::
     forall events ty.
     ( EvalOp 'TAdd ty ty ty
     , Member (Operator 'TAdd ty ty ty) events
     , Member (Eval 'TAdd ty ty ty) events
     )
  => Block (Value ty)
     %1 -> Block (Value ty)
     %1 -> Builder events (Block (Value ty))
(.+.) lhs rhs = do
  op <- operator (LUnit :: Payload (Op 'TAdd ty ty ty))
  apply lhs op rhs

(.*.) ::
     forall events ty.
     ( EvalOp 'TMul ty ty ty
     , Member (Operator 'TMul ty ty ty) events
     , Member (Eval 'TMul ty ty ty) events
     )
  => Block (Value ty)
     %1 -> Block (Value ty)
     %1 -> Builder events (Block (Value ty))
(.*.) lhs rhs = do
  op <- operator (LUnit :: Payload (Op 'TMul ty ty ty))
  apply lhs op rhs

--------------------------------------------------------------------------------
-- Example
--------------------------------------------------------------------------------
type ExampleEvents
  = '[ DeclareVar 'TInt
     , ReadVar 'TInt
     , Operator 'TAdd 'TInt 'TInt 'TInt
     , Eval 'TAdd 'TInt 'TInt 'TInt
     , WriteVar 'TInt
     , DiscardVar 'TInt
     ]

data FibState where
  FibState :: IntVar %1 -> IntVar %1 -> FibState

iterateL ::
     Int
  -> (state %1 -> Builder ExampleEvents state)
  -> state
     %1 -> Builder ExampleEvents state
iterateL n stepOnce state'
  | n P.<= 0 = return state'
  | P.otherwise = do
    state'' <- stepOnce state'
    iterateL (n P.- 1) stepOnce state''

fibStep :: FibState %1 -> Builder ExampleEvents FibState
fibStep (FibState a0 b0) = do
  (a1, aValue) <- readVar a0
  (b1, bForA) <- readVar b0
  (b2, bForSum) <- readVar b1
  next <- aValue .+. bForSum
  a2 <- writeVar a1 bForA
  b3 <- writeVar b2 next
  return (FibState a2 b3)

example :: Builder ExampleEvents ()
example = do
  a0 <- declare "a" (int 0)
  b0 <- declare "b" (int 1)
  FibState aN bN <- iterateL 5 fibStep (FibState a0 b0)
  discardVar aN
  discardVar bN

--------------------------------------------------------------------------------
-- Payload labels
--------------------------------------------------------------------------------
padRight :: Int -> String -> String
padRight n s = s P.++ P.replicate (P.max 0 (n P.- P.length s)) ' '

padRightF :: String -> String
padRightF = padRight labelWidth

class PrimitiveLabel ty where
  primitiveLabel :: Proxy ty -> String

instance PrimitiveLabel 'TInt where
  primitiveLabel _ = "I"

instance PrimitiveLabel 'TDouble where
  primitiveLabel _ = "D"

class BinaryOpLabel op where
  binaryOpLabel :: Proxy op -> String

instance BinaryOpLabel 'TAdd where
  binaryOpLabel _ = "Add"

instance BinaryOpLabel 'TMul where
  binaryOpLabel _ = "Mul"

instance TracePayload (Value 'TInt) where
  payloadView _ (LInt i) = PayloadView (padRightF "Val" P.++ P.show i)

instance TraceBlock (Value 'TInt)

instance TracePayload (Value 'TDouble) where
  payloadView _ (LDouble f) = PayloadView (padRightF "Val" P.++ P.show f)

instance TraceBlock (Value 'TDouble)

instance TracePayload (Var ty) where
  payloadView _ (LString name) = PayloadView (padRightF "Var" P.++ name)

instance TraceBlock (Var ty)

instance ( BinaryOpLabel op
         , PrimitiveLabel lhs
         , PrimitiveLabel rhs
         , PrimitiveLabel out
         ) =>
         TracePayload (Op op lhs rhs out) where
  payloadView _ LUnit =
    PayloadView
      (padRightF "Op"
         P.++ binaryOpLabel (Proxy :: Proxy op)
         P.++ primitiveLabel (Proxy :: Proxy lhs)
         P.++ primitiveLabel (Proxy :: Proxy rhs)
         P.++ primitiveLabel (Proxy :: Proxy out))

instance ( BinaryOpLabel op
         , PrimitiveLabel lhs
         , PrimitiveLabel rhs
         , PrimitiveLabel out
         ) =>
         TraceBlock (Op op lhs rhs out)

--------------------------------------------------------------------------------
-- Block visualisation
--------------------------------------------------------------------------------
blockSize :: Expr
blockSize = global "blockSize"

cellBlock :: BlockView tag -> ViewBuilder events ()
cellBlock block = P.do
  ensure $ equals (widthOf block) blockSize
  ensure $ equals (heightOf block) blockSize

instance VisualizeBlock (Value 'TInt) where
  visualizeBlock = cellBlock

instance VisualizeBlock (Value 'TDouble) where
  visualizeBlock = cellBlock

instance VisualizeBlock (Var ty) where
  visualizeBlock = cellBlock

instance ( BinaryOpLabel op
         , PrimitiveLabel lhs
         , PrimitiveLabel rhs
         , PrimitiveLabel out
         ) =>
         VisualizeBlock (Op op lhs rhs out) where
  visualizeBlock = cellBlock

--------------------------------------------------------------------------------
-- Event visualisation
--------------------------------------------------------------------------------
instance VisualizeBlock (Value ty) => VisualizeEvent (Literal ty) where
  visualizeEvent Literal audit =
    case audit of
      VCreated value :& VDone -> P.do
        visualizeBlock value

instance (VisualizeBlock (Value ty), VisualizeBlock (Var ty)) =>
         VisualizeEvent (DeclareVar ty) where
  visualizeEvent (DeclareVar _) audit =
    case audit of
      VCreated valueB :& VCreated varB :& VSealed _ _ :& VDone -> P.do
        sameBounds valueB varB

instance (VisualizeBlock (Value ty), VisualizeBlock (Var ty)) =>
         VisualizeEvent (ReadVar ty) where
  visualizeEvent ReadVar audit =
    case audit of
      VUnsealed varB held :& VCopied _heldOriginal copied :& VSealed _ _ :& VDone -> P.do
        P.pure ()

instance (VisualizeBlock (Value ty), VisualizeBlock (Var ty)) =>
         VisualizeEvent (WriteVar ty) where
  visualizeEvent WriteVar audit =
    case audit of
      VUnsealed varB oldValue :& VReplaced _old newValue :& VSealed _ _ :& VDone -> P.do
        sameBounds varB newValue

instance (VisualizeBlock (Value ty), VisualizeBlock (Var ty)) =>
         VisualizeEvent (DiscardVar ty) where
  visualizeEvent DiscardVar audit =
    case audit of
      VUnsealed varB value :& VDestroyed _ :& VDestroyed _ :& VDone -> P.do
        P.pure ()

instance VisualizeBlock (Value ty) => VisualizeEvent (DiscardValue ty) where
  visualizeEvent DiscardValue audit =
    case audit of
      VDestroyed value :& VDone -> P.do
        P.pure ()

instance VisualizeBlock (Op op lhs rhs out) =>
         VisualizeEvent (Operator op lhs rhs out) where
  visualizeEvent Operator audit =
    case audit of
      VCreated op :& VDone -> P.do
        P.pure ()

instance ( VisualizeBlock (Value lhs)
         , VisualizeBlock (Op op lhs rhs out)
         , VisualizeBlock (Value rhs)
         , VisualizeBlock (Value out)
         ) =>
         VisualizeEvent (Eval op lhs rhs out) where
  visualizeEvent Eval audit =
    case audit of
      VUsed lhs :& VUsed op :& VUsed rhs :& VComputed result :& VDone -> P.do
        lhs |=| op
        op |=| rhs
        rhs |=| result
