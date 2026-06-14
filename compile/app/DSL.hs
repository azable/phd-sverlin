{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE LinearTypes           #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RebindableSyntax      #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE UndecidableInstances  #-}

module DSL
  ( -- * Public program types
    Builder
  , PrimitiveType(..)
  , BinaryOp(..)
  , Value
  , Var
  , Op
  , VarBlock
  , IntBlock
  , DoubleBlock
  , IntVar
  , DoubleVar
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
  , -- * Runners/examples
    run
  , example
  ) where

import           Control.Functor.Linear hiding ((<$>), (<*>))
import           Data.Proxy             (Proxy (..))
import           LinearTrace
import qualified Prelude                as P
import           Prelude.Linear

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------
labelWidth :: Int
labelWidth = 5

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

type Builder a = TraceBuilder Event a

type IntBlock = Block (Value 'TInt)

type DoubleBlock = Block (Value 'TDouble)

type IntVar = VarBlock 'TInt

type DoubleVar = VarBlock 'TDouble

data VarBlock ty where
  VarBlock :: Block (Var ty) %1 -> Slot (Var ty) (Value ty) %1 -> VarBlock ty

--------------------------------------------------------------------------------
-- Event vocabulary
--------------------------------------------------------------------------------
data Event acts where
  Literal :: Event '[ Create (Value ty)]
  Operator :: Event '[ Create (Op op lhs rhs out)]
  DeclareVar
    :: Event '[ Create (Value ty), Create (Var ty), Seal (Var ty) (Value ty)]
  ReadVar
    :: Event
         '[ Unseal (Var ty) (Value ty)
          , Copy (Value ty)
          , Seal (Var ty) (Value ty)
          ]
  WriteVar
    :: Event
         '[ Unseal (Var ty) (Value ty)
          , Replace (Value ty)
          , Seal (Var ty) (Value ty)
          ]
  Eval
    :: Event
         '[ Use (Value lhs)
          , Use (Op op lhs rhs out)
          , Use (Value rhs)
          , Compute (Value out)
          ]
  DiscardVar
    :: Event
         '[ Unseal (Var ty) (Value ty), Destroy (Var ty), Destroy (Value ty)]
  DiscardValue :: Event '[ Destroy (Value ty)]

--------------------------------------------------------------------------------
-- Literals
--------------------------------------------------------------------------------
int :: Int -> Payload (Value 'TInt)
int = LInt

double :: Double -> Payload (Value 'TDouble)
double = LDouble

literal ::
     TracePayload (Value ty)
  => Payload (Value ty)
     %1 -> Builder (Block (Value ty))
literal payload = do
  Created block createValue <- create payload
  Literal `explain` (createValue :~ Done)
  return block

--------------------------------------------------------------------------------
-- Variables
--------------------------------------------------------------------------------
declare ::
     forall ty. TracePayload (Value ty)
  => String
  -> Payload (Value ty)
     %1 -> Builder (VarBlock ty)
declare name initial = do
  Created valueBlock createValue <- create initial
  Created varBlock createVar <- create (LString name :: Payload (Var ty))
  Sealed varBlock' valueSlot sealValue <- seal varBlock valueBlock
  DeclareVar `explain` (createValue :~ createVar :~ sealValue :~ Done)
  return (VarBlock varBlock' valueSlot)

readVar ::
     TracePayload (Value ty)
  => VarBlock ty
     %1 -> Builder (VarBlock ty, Block (Value ty))
readVar (VarBlock var valueSlot) = do
  Unsealed var1 held unsealValue <- unseal var valueSlot
  Copied held' copyBlock copyValue <- copy held
  Sealed var2 valueSlot' sealValue <- seal var1 held'
  ReadVar `explain` (unsealValue :~ copyValue :~ sealValue :~ Done)
  return (VarBlock var2 valueSlot', copyBlock)

writeVar ::
     TracePayload (Value ty)
  => VarBlock ty
     %1 -> Block (Value ty)
     %1 -> Builder (VarBlock ty)
writeVar (VarBlock var valueSlot) newValue = do
  Unsealed var1 oldValue unsealValue <- unseal var valueSlot
  Replaced currentValue replaceValue <- replace oldValue newValue
  Sealed var2 valueSlot' sealValue <- seal var1 currentValue
  WriteVar `explain` (unsealValue :~ replaceValue :~ sealValue :~ Done)
  return (VarBlock var2 valueSlot')

discardVar :: TracePayload (Value ty) => VarBlock ty %1 -> Builder ()
discardVar (VarBlock var valueSlot) = do
  Unsealed var1 held unsealValue <- unseal var valueSlot
  Destroyed destroyVar <- destroy var1
  Destroyed destroyHeld <- destroy held
  DiscardVar `explain` (unsealValue :~ destroyVar :~ destroyHeld :~ Done)

--------------------------------------------------------------------------------
-- Values
--------------------------------------------------------------------------------
discardValue :: TracePayload (Value ty) => Block (Value ty) %1 -> Builder ()
discardValue value = do
  Destroyed destroyValue <- destroy value
  DiscardValue `explain` (destroyValue :~ Done)

--------------------------------------------------------------------------------
-- Operators
--------------------------------------------------------------------------------
operator ::
     TracePayload (Op op lhs rhs out)
  => Payload (Op op lhs rhs out)
     %1 -> Builder (Block (Op op lhs rhs out))
operator payload = do
  Created block createOp <- create payload
  Operator `explain` (createOp :~ Done)
  return block

class ( TracePayload (Value lhs)
      , TracePayload (Op op lhs rhs out)
      , TracePayload (Value rhs)
      , TracePayload (Value out)
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

apply ::
     EvalOp op lhs rhs out
  => Block (Value lhs)
     %1 -> Block (Op op lhs rhs out)
     %1 -> Block (Value rhs)
     %1 -> Builder (Block (Value out))
apply lhsBlock opBlock rhsBlock = do
  Used lhs useLhs <- use lhsBlock
  Used opPayload useOp <- use opBlock
  Used rhs useRhs <- use rhsBlock
  Computed outBlock computeOut <-
    compute (evalPayload <$> lhs <*> opPayload <*> rhs)
  Eval `explain` (useLhs :~ useOp :~ useRhs :~ computeOut :~ Done)
  return outBlock

(.+.) ::
     forall ty. EvalOp 'TAdd ty ty ty
  => Block (Value ty)
     %1 -> Block (Value ty)
     %1 -> Builder (Block (Value ty))
(.+.) lhs rhs = do
  add <- operator (LUnit :: Payload (Op 'TAdd ty ty ty))
  apply lhs add rhs

(.*.) ::
     forall ty. EvalOp 'TMul ty ty ty
  => Block (Value ty)
     %1 -> Block (Value ty)
     %1 -> Builder (Block (Value ty))
(.*.) lhs rhs = do
  mul <- operator (LUnit :: Payload (Op 'TMul ty ty ty))
  apply lhs mul rhs

--------------------------------------------------------------------------------
-- Example
--------------------------------------------------------------------------------
data FibState where
  FibState :: IntVar %1 -> IntVar %1 -> FibState

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
  FibState aN bN <- iterateL 5 fibStep (FibState a0 b0)
  discardVar aN
  discardVar bN

run :: Builder () -> TraceGraph Event
run = buildGraph

--------------------------------------------------------------------------------
-- Rendering
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

instance TracePayload (Value 'TDouble) where
  payloadView _ (LDouble f) = PayloadView (padRightF "Val" P.++ P.show f)

instance TracePayload (Var ty) where
  payloadView _ (LString name) = PayloadView (padRightF "Var" P.++ name)

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

instance PrintEvent Event where
  printEvent Literal      = "Literal"
  printEvent Operator     = "Operator"
  printEvent DeclareVar   = "DeclareVar"
  printEvent ReadVar      = "ReadVar"
  printEvent WriteVar     = "WriteVar"
  printEvent Eval         = "Eval"
  printEvent DiscardVar   = "DiscardVar"
  printEvent DiscardValue = "DiscardValue"
