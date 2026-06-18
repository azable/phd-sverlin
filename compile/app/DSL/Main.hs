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
    LiteralActions
  , OperatorActions
  , DeclareVarActions
  , ReadVarActions
  , WriteVarActions
  , EvalActions
  , DiscardVarActions
  , DiscardValueActions
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
import           Data.Kind              (Type)
import           Data.Typeable          (Typeable)
import           LinearTrace
import           LinearTrace.Visualize

import qualified Prelude                as P
import           Prelude.Linear

infixr 4 :*
--------------------------------------------------------------------------------
-- Builder / step protocol
--------------------------------------------------------------------------------
type Builder events a = TraceBuilder events a

data (:*) a b where
  (:*) :: a %1 -> b %1 -> a :* b

data Performed event result where
  Performed
    :: result %1 -> EvidenceList (Actions event) %1 -> Performed event result

class Step event where
  type Input event :: Type
  type Output event :: Type
  perform ::
       event
    -> Input event
       %1 -> Builder events (Performed event (Output event))

step ::
     forall event events. (Step event, Member event events)
  => event
  -> Input event
     %1 -> Builder events (Output event)
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

instance Traceable (Value 'TInt)

instance Traceable (Value 'TDouble)

instance Typeable ty => Traceable (Var ty)

instance (Typeable op, Typeable lhs, Typeable rhs, Typeable out) =>
         Traceable (Op op lhs rhs out)

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
type LiteralActions ty = '[ Create (Value ty)]

data Literal (ty :: PrimitiveType) =
  Literal

type instance Actions (Literal ty) = LiteralActions ty

instance Traceable (Value ty) => Step (Literal ty) where
  type Input (Literal ty) = Payload (Value ty)
  type Output (Literal ty) = Block (Value ty)
  perform Literal payload = do
    Created block createValue <- create payload
    return (Performed block (createValue :~ Done))

literal ::
     (Traceable (Value ty), Member (Literal ty) events)
  => Payload (Value ty)
     %1 -> Builder events (Block (Value ty))
literal = step Literal

instance PrintEvent (Literal ty) where
  printEvent Literal = "Literal"

--------------------------------------------------------------------------------
-- Declare variable step
--------------------------------------------------------------------------------
type DeclareVarActions ty
  = '[ Create (Value ty), Create (Var ty), Seal (Var ty) (Value ty)]

newtype DeclareVar (ty :: PrimitiveType) =
  DeclareVar String

type instance Actions (DeclareVar ty) = DeclareVarActions ty

instance (Traceable (Value ty), Traceable (Var ty)) => Step (DeclareVar ty) where
  type Input (DeclareVar ty) = Payload (Value ty)
  type Output (DeclareVar ty) = VarBlock ty
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
     (Traceable (Value ty), Traceable (Var ty), Member (DeclareVar ty) events)
  => String
  -> Payload (Value ty)
     %1 -> Builder events (VarBlock ty)
declare name = step (DeclareVar name)

instance PrintEvent (DeclareVar ty) where
  printEvent (DeclareVar name) = "DeclareVar " P.++ name

--------------------------------------------------------------------------------
-- Read variable step
--------------------------------------------------------------------------------
type ReadVarActions ty
  = '[ Unseal (Var ty) (Value ty), Copy (Value ty), Seal (Var ty) (Value ty)]

data ReadVar (ty :: PrimitiveType) =
  ReadVar

data ReadVarResult ty where
  ReadVarResult :: VarBlock ty %1 -> Block (Value ty) %1 -> ReadVarResult ty

type instance Actions (ReadVar ty) = ReadVarActions ty

instance (Traceable (Value ty), Traceable (Var ty)) => Step (ReadVar ty) where
  type Input (ReadVar ty) = VarBlock ty
  type Output (ReadVar ty) = ReadVarResult ty
  perform ReadVar (VarBlock varBlock valueSlot) = do
    Unsealed var1 held unsealValue <- unseal varBlock valueSlot
    Copied held' copyBlock copyValue <- copy held
    Sealed var2 valueSlot' sealValue <- seal var1 held'
    return
      (Performed
         (ReadVarResult (VarBlock var2 valueSlot') copyBlock)
         (unsealValue :~ copyValue :~ sealValue :~ Done))

readVar ::
     (Traceable (Value ty), Traceable (Var ty), Member (ReadVar ty) events)
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
type WriteVarActions ty
  = '[ Unseal (Var ty) (Value ty), Replace (Value ty), Seal (Var ty) (Value ty)]

data WriteVar (ty :: PrimitiveType) =
  WriteVar

type instance Actions (WriteVar ty) = WriteVarActions ty

instance (Traceable (Value ty), Traceable (Var ty)) => Step (WriteVar ty) where
  type Input (WriteVar ty) = VarBlock ty :* Block (Value ty)
  type Output (WriteVar ty) = VarBlock ty
  perform WriteVar (VarBlock varBlock valueSlot :* newValue) = do
    Unsealed var1 oldValue unsealValue <- unseal varBlock valueSlot
    Replaced currentValue replaceValue <- replace oldValue newValue
    Sealed var2 valueSlot' sealValue <- seal var1 currentValue
    return
      (Performed
         (VarBlock var2 valueSlot')
         (unsealValue :~ replaceValue :~ sealValue :~ Done))

writeVar ::
     (Traceable (Value ty), Traceable (Var ty), Member (WriteVar ty) events)
  => VarBlock ty
     %1 -> Block (Value ty)
     %1 -> Builder events (VarBlock ty)
writeVar varBlock newValue = step WriteVar (varBlock :* newValue)

instance PrintEvent (WriteVar ty) where
  printEvent WriteVar = "WriteVar"

--------------------------------------------------------------------------------
-- Discard variable step
--------------------------------------------------------------------------------
type DiscardVarActions ty
  = '[ Unseal (Var ty) (Value ty), Destroy (Var ty), Destroy (Value ty)]

data DiscardVar (ty :: PrimitiveType) =
  DiscardVar

type instance Actions (DiscardVar ty) = DiscardVarActions ty

instance (Traceable (Value ty), Traceable (Var ty)) => Step (DiscardVar ty) where
  type Input (DiscardVar ty) = VarBlock ty
  type Output (DiscardVar ty) = ()
  perform DiscardVar (VarBlock varBlock valueSlot) = do
    Unsealed var1 held unsealValue <- unseal varBlock valueSlot
    Destroyed destroyVar <- destroy var1
    Destroyed destroyHeld <- destroy held
    return (Performed () (unsealValue :~ destroyVar :~ destroyHeld :~ Done))

discardVar ::
     (Traceable (Value ty), Traceable (Var ty), Member (DiscardVar ty) events)
  => VarBlock ty
     %1 -> Builder events ()
discardVar = step DiscardVar

instance PrintEvent (DiscardVar ty) where
  printEvent DiscardVar = "DiscardVar"

--------------------------------------------------------------------------------
-- Discard value step
--------------------------------------------------------------------------------
type DiscardValueActions ty = '[ Destroy (Value ty)]

data DiscardValue (ty :: PrimitiveType) =
  DiscardValue

type instance Actions (DiscardValue ty) = DiscardValueActions ty

instance Traceable (Value ty) => Step (DiscardValue ty) where
  type Input (DiscardValue ty) = Block (Value ty)
  type Output (DiscardValue ty) = ()
  perform DiscardValue value = do
    Destroyed destroyValue <- destroy value
    return (Performed () (destroyValue :~ Done))

discardValue ::
     (Traceable (Value ty), Member (DiscardValue ty) events)
  => Block (Value ty)
     %1 -> Builder events ()
discardValue = step DiscardValue

instance PrintEvent (DiscardValue ty) where
  printEvent DiscardValue = "DiscardValue"

--------------------------------------------------------------------------------
-- Operator step
--------------------------------------------------------------------------------
type OperatorActions op lhs rhs out = '[ Create (Op op lhs rhs out)]

data Operator (op :: BinaryOp) (lhs :: PrimitiveType) (rhs :: PrimitiveType) (out :: PrimitiveType) =
  Operator

type instance Actions (Operator op lhs rhs out) = OperatorActions op lhs rhs out

instance Traceable (Op op lhs rhs out) => Step (Operator op lhs rhs out) where
  type Input (Operator op lhs rhs out) = Payload (Op op lhs rhs out)
  type Output (Operator op lhs rhs out) = Block (Op op lhs rhs out)
  perform Operator payload = do
    Created block createOp <- create payload
    return (Performed block (createOp :~ Done))

operator ::
     (Traceable (Op op lhs rhs out), Member (Operator op lhs rhs out) events)
  => Payload (Op op lhs rhs out)
     %1 -> Builder events (Block (Op op lhs rhs out))
operator = step Operator

instance PrintEvent (Operator op lhs rhs out) where
  printEvent Operator = "Operator"

--------------------------------------------------------------------------------
-- Evaluation support
--------------------------------------------------------------------------------
class ( Traceable (Value lhs)
      , Traceable (Op op lhs rhs out)
      , Traceable (Value rhs)
      , Traceable (Value out)
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
type EvalActions op lhs rhs out
  = '[ Use (Value lhs)
     , Use (Op op lhs rhs out)
     , Use (Value rhs)
     , Compute (Value out)
     ]

data Eval (op :: BinaryOp) (lhs :: PrimitiveType) (rhs :: PrimitiveType) (out :: PrimitiveType) =
  Eval

type instance Actions (Eval op lhs rhs out) = EvalActions op lhs rhs out

instance EvalOp op lhs rhs out => Step (Eval op lhs rhs out) where
  type Input (Eval op lhs rhs out) = Block (Value lhs) :* Block
    (Op op lhs rhs out) :* Block (Value rhs)
  type Output (Eval op lhs rhs out) = Block (Value out)
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
     , Literal 'TInt
     , Operator 'TAdd 'TInt 'TInt 'TInt
     , Operator 'TMul 'TInt 'TInt 'TInt
     , Eval 'TAdd 'TInt 'TInt 'TInt
     , Eval 'TMul 'TInt 'TInt 'TInt
     , WriteVar 'TInt
     , DiscardVar 'TInt
     , DiscardValue 'TInt
     ]

example :: Builder ExampleEvents ()
example = do
  x0 <- declare "x" (int 10)
  (x1, xValue) <- readVar x0
  two <- literal (int 2)
  sumValue <- xValue .+. two
  three <- literal (int 3)
  result <- sumValue .*. three
  x2 <- writeVar x1 result
  discardVar x2

--------------------------------------------------------------------------------
-- Block visualisation
--------------------------------------------------------------------------------
blockSize :: LayoutExpr
blockSize = num 100

valueRadiusName :: LayoutExpr
valueRadiusName = global "value.radius"

valueFontSizeName :: LayoutExpr
valueFontSizeName = global "value.fontSize"

varRadiusName :: LayoutExpr
varRadiusName = global "var.radius"

varFontSizeName :: LayoutExpr
varFontSizeName = global "var.fontSize"

opRadiusName :: LayoutExpr
opRadiusName = global "op.radius"

opFontSizeName :: LayoutExpr
opFontSizeName = global "op.fontSize"

black :: HslExpr
black = Hsl {hue = num 0, saturation = num 0, lightness = num 0}

valueFill :: HslExpr
valueFill =
  Hsl
    {hue = global "hue", saturation = global "saturation", lightness = num 0.52}

varFill :: HslExpr
varFill =
  Hsl
    { hue = global "hue"
    , saturation = global "saturation" @*@ num 0.35
    , lightness = num 0.88
    }

opFill :: HslExpr
opFill =
  Hsl
    { hue = global "hue"
    , saturation = global "saturation" @*@ num 0.2
    , lightness = num 0.96
    }

fixedSize ::
     HasBounds block
  => LayoutExpr
  -> LayoutExpr
  -> block
  -> ViewBuilder events ()
fixedSize w h block = P.do
  ensure $ width block @=@ w
  ensure $ height block @=@ h

square :: HasBounds block => LayoutExpr -> block -> ViewBuilder events ()
square size' = fixedSize size' size'

proportionalRadius ::
     (HasBounds block, HasStyle block)
  => LayoutExpr
  -> block
  -> ViewBuilder events ()
proportionalRadius divisor block =
  ensure $ radius block @=@ width block / divisor

proportionalFontSize ::
     (HasBounds block, HasStyle block)
  => LayoutExpr
  -> block
  -> ViewBuilder events ()
proportionalFontSize divisor block =
  ensure $ fontSize block @=@ height block / divisor

valueStyle :: Style -> Style
valueStyle =
  setFill valueFill
    P.. setStroke black
    P.. setStrokeWidth (num 4)
    P.. setRadius valueRadiusName
    P.. setFontSize valueFontSizeName
    P.. setFontFamily "Verdana"
    P.. setFontWeight FontWeightBold
    P.. setTextAlign TextAlignCenter
    P.. setWhiteSpace WhiteSpaceNoWrap
    P.. setBorderStyle BorderSolid
    P.. setOpacity (num 1)
    P.. setAlpha (num 1)
    P.. setZIndex (num 1)

varStyle :: Style -> Style
varStyle =
  setFill varFill
    P.. setRadius varRadiusName
    P.. setFontSize varFontSizeName
    P.. setFontFamily "Verdana"
    P.. setFontWeight FontWeightBold
    P.. setTextAlign TextAlignCenter
    P.. setWhiteSpace WhiteSpaceNoWrap
    P.. setOpacity (num 1)
    P.. setAlpha (num 1)
    P.. setZIndex (num (-1))

opStyle :: Style -> Style
opStyle =
  setFill opFill
    P.. setStroke black
    P.. setStrokeWidth (num 3)
    P.. setRadius opRadiusName
    P.. setFontSize opFontSizeName
    P.. setFontFamily "Verdana"
    P.. setFontWeight FontWeightBold
    P.. setTextAlign TextAlignCenter
    P.. setWhiteSpace WhiteSpaceNoWrap
    P.. setBorderStyle BorderSolid
    P.. setOpacity (num 1)
    P.. setAlpha (num 1)
    P.. setZIndex (num 2)

valueBlockV :: BlockView tag -> ViewBuilder events ()
valueBlockV block = P.do
  square blockSize block
  proportionalRadius (num 10) block
  proportionalFontSize (num 2) block

varBlockV :: BlockView tag -> ViewBuilder events ()
varBlockV block = P.do
  square (blockSize @+@ num 20) block
  proportionalRadius (num 12) block
  proportionalFontSize (num 2.4) block

opBlockV :: BlockView tag -> ViewBuilder events ()
opBlockV block = P.do
  square (blockSize @*@ num 0.75) block
  proportionalRadius (num 6) block
  proportionalFontSize (num 2.4) block

instance Traceable (Value ty) => ViewBlock (Value ty) where
  styleBlock _ = valueStyle
  viewBlock = valueBlockV

instance Typeable ty => ViewBlock (Var ty) where
  styleBlock _ = varStyle
  viewBlock = varBlockV

instance Traceable (Op op lhs rhs out) => ViewBlock (Op op lhs rhs out) where
  styleBlock _ = opStyle
  viewBlock = opBlockV

--------------------------------------------------------------------------------
-- Event visualisation
--------------------------------------------------------------------------------
instance ViewEvent (Literal ty) where
  viewEvent Literal audit =
    case audit of
      VCreated _value :& VDone -> P.do
        P.pure ()

instance ViewEvent (DeclareVar ty) where
  viewEvent (DeclareVar _) audit =
    case audit of
      VCreated valueB :& VCreated varB :& VSealed _ _ :& VDone -> P.do
        valueB `centeredWithin` varB

instance ViewEvent (ReadVar ty) where
  viewEvent ReadVar audit =
    case audit of
      VUnsealed _varB _held :& VCopied _heldOriginal _copied :& VSealed _ _ :& VDone -> P.do
        P.pure ()

instance ViewEvent (WriteVar ty) where
  viewEvent WriteVar audit =
    case audit of
      VUnsealed _varB _oldValue :& VReplaced old _incoming stored :& VSealed _ _ :& VDone -> P.do
        ensure $ center stored @=@ center old

instance ViewEvent (DiscardVar ty) where
  viewEvent DiscardVar audit =
    case audit of
      VUnsealed _varB _value :& VDestroyed _ :& VDestroyed _ :& VDone -> P.do
        P.pure ()

instance ViewEvent (DiscardValue ty) where
  viewEvent DiscardValue audit =
    case audit of
      VDestroyed _value :& VDone -> P.do
        P.pure ()

instance ViewEvent (Operator op lhs rhs out) where
  viewEvent Operator audit =
    case audit of
      VCreated _op :& VDone -> P.do
        P.pure ()

instance ViewEvent (Eval op lhs rhs out) where
  viewEvent Eval audit =
    case audit of
      VUsed lhs :& VUsed op :& VUsed rhs :& VComputed result :& VDone -> P.do
        besideWithGap (num 12) lhs op
        besideWithGap (num 12) op rhs
        besideWithGap (num 16) rhs result
        ensure $ centerY lhs @=@ centerY result
