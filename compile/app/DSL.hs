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
  , Index
  , Array
  , InsertionBranch
  , InnerLoopStatus
  , OuterLoopStatus
  , IndexNegative
  , IndexZero
  , VarNode
  , ArrayNode
  , ArrayRead(..)
  , ArrayWrite(..)
  , IntNode
  , DoubleNode
  , BoolNode
  , IndexNode
  , InsertionBranchNode
  , InnerLoopStatusNode
  , OuterLoopStatusNode
  , IndexNegativeNode
  , IndexZeroNode
  , IntVar
  , DoubleVar
  , BoolVar
  , IndexVar
  , IntArray
  , DoubleArray
  , -- * Literals
    int
  , double
  , bool
  , idx
  , literal
  , index
  , -- * Variables
    declare
  , readVar
  , writeVar
  , discardVar
  , -- * Values
    discardValue
  , -- * Arrays
    array
  , intArray
  , doubleArray
  , readArrayAt
  , readArrayAtNode
  , writeArrayAt
  , writeArrayAtNode
  , discardArray
  , -- * Index operations
    incIndex
  , decIndex
  , -- * Semantic decisions
    classifyInsertionBranch
  , decideInsertionBranch
  , classifyInnerLoopStatus
  , decideInnerLoopStatus
  , classifyOuterLoopStatus
  , decideOuterLoopStatus
  , classifyIndexNegative
  , decideIndexNegative
  , classifyIndexZero
  , decideIndexZero
  , -- * Operators
    operator
  , apply
  , (.+.)
  , (.*.)
  , (.>.)
  , -- * Algorithms
    insertionSort
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
labelWidth = 8

--------------------------------------------------------------------------------
-- DSL type vocabulary
--------------------------------------------------------------------------------
data PrimitiveType
  = TInt
  | TDouble
  | TBool

data BinaryOp
  = TAdd
  | TMul
  | TGreater

data Value (ty :: PrimitiveType)

data Var tag

data Op (op :: BinaryOp) (lhs :: PrimitiveType) (rhs :: PrimitiveType) (out :: PrimitiveType)

data Index

data Array (ty :: PrimitiveType)

-- | Semantic branch decision for insertion sort.
--
--   True  = shift
--   False = stop
data InsertionBranch

-- | Semantic inner-loop status.
--
--   True  = continue
--   False = done
data InnerLoopStatus

-- | Semantic outer-loop status.
--
--   True  = continue
--   False = done
data OuterLoopStatus

-- | Semantic index-negative status.
--
--   True  = negative
--   False = non-negative
data IndexNegative

-- | Semantic index-zero status.
--
--   True  = zero
--   False = non-zero
data IndexZero

type instance Payload (Value 'TInt) = LInt (Value 'TInt)

type instance Payload (Value 'TDouble) = LDouble (Value 'TDouble)

type instance Payload (Value 'TBool) = LBool (Value 'TBool)

type instance Payload (Var tag) = LString (Var tag)

type instance Payload (Op op lhs rhs out) = LUnit (Op op lhs rhs out)

type instance Payload Index = LInt Index

type instance Payload (Array ty) = LString (Array ty)

type instance Payload InsertionBranch = LBool InsertionBranch

type instance Payload InnerLoopStatus = LBool InnerLoopStatus

type instance Payload OuterLoopStatus = LBool OuterLoopStatus

type instance Payload IndexNegative = LBool IndexNegative

type instance Payload IndexZero = LBool IndexZero

type Builder a = TraceBuilder Event a

type IntNode = Node (Value 'TInt)

type DoubleNode = Node (Value 'TDouble)

type BoolNode = Node (Value 'TBool)

type IndexNode = Node Index

type InsertionBranchNode = Node InsertionBranch

type InnerLoopStatusNode = Node InnerLoopStatus

type OuterLoopStatusNode = Node OuterLoopStatus

type IndexNegativeNode = Node IndexNegative

type IndexZeroNode = Node IndexZero

type IntVar = VarNode (Value 'TInt)

type DoubleVar = VarNode (Value 'TDouble)

type BoolVar = VarNode (Value 'TBool)

type IndexVar = VarNode Index

type IntArray = ArrayNode 'TInt

type DoubleArray = ArrayNode 'TDouble

data VarNode tag where
  VarNode :: Node (Var tag) %1 -> Slot (Var tag) tag %1 -> VarNode tag

data ArraySlots ty where
  EmptySlots :: ArraySlots ty
  SlotCons :: Slot (Array ty) (Value ty) %1 -> ArraySlots ty %1 -> ArraySlots ty

data ArrayNode ty where
  ArrayNode :: Node (Array ty) %1 -> ArraySlots ty %1 -> ArrayNode ty

data ArrayRead ty where
  ArrayRead :: ArrayNode ty %1 -> Node (Value ty) %1 -> ArrayRead ty
  ArrayReadOutOfBounds :: ArrayNode ty %1 -> ArrayRead ty

data ArrayWrite ty where
  ArrayWrite :: ArrayNode ty %1 -> ArrayWrite ty
  ArrayWriteOutOfBounds
    :: ArrayNode ty %1 -> Node (Value ty) %1 -> ArrayWrite ty

--------------------------------------------------------------------------------
-- Event vocabulary
--------------------------------------------------------------------------------
data Event acts where
  Literal :: Event '[ Create (Value ty)]
  IndexLiteral :: Event '[ Create Index]
  Operator :: Event '[ Create (Op op lhs rhs out)]
  DeclareVar :: Event '[ Create tag, Create (Var tag), Seal (Var tag) tag]
  ReadVar :: Event '[ Unseal (Var tag) tag, Copy tag, Seal (Var tag) tag]
  WriteVar :: Event '[ Unseal (Var tag) tag, Replace tag, Seal (Var tag) tag]
  Eval
    :: Event
         '[ Use (Value lhs)
          , Use (Op op lhs rhs out)
          , Use (Value rhs)
          , Compute (Value out)
          ]
  IncIndex :: Event '[ Use Index, Compute Index]
  DecIndex :: Event '[ Use Index, Compute Index]
  ClassifyInsertionBranch
    :: Event '[ Use (Value 'TBool), Compute InsertionBranch]
  TakeShiftBranch :: Event '[ Decide InsertionBranch]
  TakeStopBranch :: Event '[ Decide InsertionBranch]
  ClassifyInnerLoopStatus :: Event '[ Use Index, Compute InnerLoopStatus]
  TakeInnerLoopContinue :: Event '[ Decide InnerLoopStatus]
  TakeInnerLoopDone :: Event '[ Decide InnerLoopStatus]
  ClassifyOuterLoopStatus
    :: Event '[ Use Index, Use Index, Compute OuterLoopStatus]
  TakeOuterLoopContinue :: Event '[ Decide OuterLoopStatus]
  TakeOuterLoopDone :: Event '[ Decide OuterLoopStatus]
  ClassifyIndexNegative :: Event '[ Inspect Index, Compute IndexNegative]
  TakeIndexNegative :: Event '[ Decide IndexNegative]
  TakeIndexNonNegative :: Event '[ Decide IndexNegative]
  ClassifyIndexZero :: Event '[ Inspect Index, Compute IndexZero]
  TakeIndexZero :: Event '[ Decide IndexZero]
  TakeIndexNonZero :: Event '[ Decide IndexZero]
  CreateArray :: Event '[ Create (Array ty)]
  InitArrayCell :: Event '[ Create (Value ty), Seal (Array ty) (Value ty)]
  ReadArray
    :: Event
         '[ Destroy Index
          , Unseal (Array ty) (Value ty)
          , Copy (Value ty)
          , Seal (Array ty) (Value ty)
          ]
  ReadArrayOutOfBounds :: Event '[ Destroy Index]
  WriteArray
    :: Event
         '[ Destroy Index
          , Unseal (Array ty) (Value ty)
          , Replace (Value ty)
          , Seal (Array ty) (Value ty)
          ]
  WriteArrayOutOfBounds :: Event '[ Destroy Index]
  DiscardArrayCell :: Event '[ Unseal (Array ty) (Value ty), Destroy (Value ty)]
  DiscardArray :: Event '[ Destroy (Array ty)]
  DiscardVar :: Event '[ Unseal (Var tag) tag, Destroy (Var tag), Destroy tag]
  DiscardValue :: Event '[ Destroy (Value ty)]

--------------------------------------------------------------------------------
-- Literals
--------------------------------------------------------------------------------
int :: Int -> Payload (Value 'TInt)
int = LInt

double :: Double -> Payload (Value 'TDouble)
double = LDouble

bool :: Bool -> Payload (Value 'TBool)
bool = LBool

idx :: Int -> Payload Index
idx = LInt

literal ::
     TracePayload (Value ty)
  => Payload (Value ty)
     %1 -> Builder (Node (Value ty))
literal payload = do
  Created node createValue <- create payload
  Literal `explain` (createValue :~ Done)
  return node

index :: Int -> Builder IndexNode
index value = do
  Created node createIndex <- create (idx value)
  IndexLiteral `explain` (createIndex :~ Done)
  return node

--------------------------------------------------------------------------------
-- Variables
--------------------------------------------------------------------------------
declare :: TracePayload tag => String -> Payload tag %1 -> Builder (VarNode tag)
declare name initial = do
  Created valueNode createValue <- create initial
  Created varNode createVar <- create (LString name :: Payload (Var tag))
  Sealed varNode' valueSlot sealValue <- seal varNode valueNode
  DeclareVar `explain` (createValue :~ createVar :~ sealValue :~ Done)
  return (VarNode varNode' valueSlot)

readVar :: TracePayload tag => VarNode tag %1 -> Builder (VarNode tag, Node tag)
readVar (VarNode var valueSlot) = do
  Unsealed var1 held unsealValue <- unseal var valueSlot
  Copied held' copyNode copyValue <- copy held
  Sealed var2 valueSlot' sealValue <- seal var1 held'
  ReadVar `explain` (unsealValue :~ copyValue :~ sealValue :~ Done)
  return (VarNode var2 valueSlot', copyNode)

writeVar ::
     TracePayload tag => VarNode tag %1 -> Node tag %1 -> Builder (VarNode tag)
writeVar (VarNode var valueSlot) newValue = do
  Unsealed var1 oldValue unsealValue <- unseal var valueSlot
  Replaced currentValue replaceValue <- replace oldValue newValue
  Sealed var2 valueSlot' sealValue <- seal var1 currentValue
  WriteVar `explain` (unsealValue :~ replaceValue :~ sealValue :~ Done)
  return (VarNode var2 valueSlot')

discardVar :: TracePayload tag => VarNode tag %1 -> Builder ()
discardVar (VarNode var valueSlot) = do
  Unsealed var1 held unsealValue <- unseal var valueSlot
  Destroyed destroyVar <- destroy var1
  Destroyed destroyHeld <- destroy held
  DiscardVar `explain` (unsealValue :~ destroyVar :~ destroyHeld :~ Done)

--------------------------------------------------------------------------------
-- Values
--------------------------------------------------------------------------------
discardValue :: TracePayload (Value ty) => Node (Value ty) %1 -> Builder ()
discardValue value = do
  Destroyed destroyValue <- destroy value
  DiscardValue `explain` (destroyValue :~ Done)

--------------------------------------------------------------------------------
-- Arrays
--------------------------------------------------------------------------------
array ::
     forall ty. TracePayload (Value ty)
  => String
  -> [Payload (Value ty)]
  -> Builder (ArrayNode ty)
array name values = do
  Created arrayNode createArray <- create (LString name :: Payload (Array ty))
  CreateArray `explain` (createArray :~ Done)
  (arrayNode', slots) <- initArraySlots arrayNode values
  return (ArrayNode arrayNode' slots)

intArray :: String -> [Int] -> Builder IntArray
intArray name values = array name (intPayloads values)

doubleArray :: String -> [Double] -> Builder DoubleArray
doubleArray name values = array name (doublePayloads values)

intPayloads :: [Int] -> [Payload (Value 'TInt)]
intPayloads []           = []
intPayloads (value:rest) = int value : intPayloads rest

doublePayloads :: [Double] -> [Payload (Value 'TDouble)]
doublePayloads []           = []
doublePayloads (value:rest) = double value : doublePayloads rest

initArraySlots ::
     TracePayload (Value ty)
  => Node (Array ty)
     %1 -> [Payload (Value ty)]
  -> Builder (Node (Array ty), ArraySlots ty)
initArraySlots arrayNode [] = return (arrayNode, EmptySlots)
initArraySlots arrayNode (payload:payloads) = do
  Created valueNode createValue <- create payload
  Sealed arrayNode' slot sealValue <- seal arrayNode valueNode
  InitArrayCell `explain` (createValue :~ sealValue :~ Done)
  (arrayNode'', slots) <- initArraySlots arrayNode' payloads
  return (arrayNode'', SlotCons slot slots)

readArrayAt ::
     TracePayload (Value ty) => Int -> ArrayNode ty %1 -> Builder (ArrayRead ty)
readArrayAt position arrayNode = do
  indexNode <- index position
  readArrayAtNode arrayNode indexNode

readArrayAtNode ::
     TracePayload (Value ty)
  => ArrayNode ty
     %1 -> IndexNode
     %1 -> Builder (ArrayRead ty)
readArrayAtNode (ArrayNode arrayNode slots) indexNode =
  readCellAtNode arrayNode slots indexNode

writeArrayAt ::
     TracePayload (Value ty)
  => Int
  -> ArrayNode ty
     %1 -> Node (Value ty)
     %1 -> Builder (ArrayWrite ty)
writeArrayAt position arrayNode value = do
  indexNode <- index position
  writeArrayAtNode arrayNode indexNode value

writeArrayAtNode ::
     TracePayload (Value ty)
  => ArrayNode ty
     %1 -> IndexNode
     %1 -> Node (Value ty)
     %1 -> Builder (ArrayWrite ty)
writeArrayAtNode (ArrayNode arrayNode slots) indexNode value =
  writeCellAtNode arrayNode slots indexNode value

discardArray :: TracePayload (Value ty) => ArrayNode ty %1 -> Builder ()
discardArray (ArrayNode arrayNode slots) = do
  arrayNode' <- discardArraySlots arrayNode slots
  Destroyed destroyArray <- destroy arrayNode'
  DiscardArray `explain` (destroyArray :~ Done)

discardArraySlots ::
     TracePayload (Value ty)
  => Node (Array ty)
     %1 -> ArraySlots ty
     %1 -> Builder (Node (Array ty))
discardArraySlots arrayNode EmptySlots = return arrayNode
discardArraySlots arrayNode (SlotCons slot rest) = do
  Unsealed arrayNode' held unsealValue <- unseal arrayNode slot
  Destroyed destroyValue <- destroy held
  DiscardArrayCell `explain` (unsealValue :~ destroyValue :~ Done)
  discardArraySlots arrayNode' rest

--------------------------------------------------------------------------------
-- Node-driven array traversal
--------------------------------------------------------------------------------
readCellAtNode ::
     TracePayload (Value ty)
  => Node (Array ty)
     %1 -> ArraySlots ty
     %1 -> IndexNode
     %1 -> Builder (ArrayRead ty)
readCellAtNode arrayNode EmptySlots indexNode = do
  Destroyed destroyIndex <- destroy indexNode
  ReadArrayOutOfBounds `explain` (destroyIndex :~ Done)
  return (ArrayReadOutOfBounds (ArrayNode arrayNode EmptySlots))
readCellAtNode arrayNode slots indexNode = do
  (indexNode1, negativeNode) <- classifyIndexNegative indexNode
  negativeDecision <- decideIndexNegative negativeNode
  readCellAtNodeNegativeDecision negativeDecision arrayNode slots indexNode1

readCellAtNodeNegativeDecision ::
     TracePayload (Value ty)
  => Decided IndexNegative
     %1 -> Node (Array ty)
     %1 -> ArraySlots ty
     %1 -> IndexNode
     %1 -> Builder (ArrayRead ty)
readCellAtNodeNegativeDecision (DecidedTrue decideNegative) arrayNode slots indexNode = do
  TakeIndexNegative `explain` (decideNegative :~ Done)
  Destroyed destroyIndex <- destroy indexNode
  ReadArrayOutOfBounds `explain` (destroyIndex :~ Done)
  return (ArrayReadOutOfBounds (ArrayNode arrayNode slots))
readCellAtNodeNegativeDecision (DecidedFalse decideNegative) arrayNode slots indexNode = do
  TakeIndexNonNegative `explain` (decideNegative :~ Done)
  (indexNode1, zeroNode) <- classifyIndexZero indexNode
  zeroDecision <- decideIndexZero zeroNode
  readCellAtNodeZeroDecision zeroDecision arrayNode slots indexNode1

readCellAtNodeZeroDecision ::
     TracePayload (Value ty)
  => Decided IndexZero
     %1 -> Node (Array ty)
     %1 -> ArraySlots ty
     %1 -> IndexNode
     %1 -> Builder (ArrayRead ty)
readCellAtNodeZeroDecision (DecidedTrue decideZero) arrayNode EmptySlots indexNode = do
  TakeIndexZero `explain` (decideZero :~ Done)
  Destroyed destroyIndex <- destroy indexNode
  ReadArrayOutOfBounds `explain` (destroyIndex :~ Done)
  return (ArrayReadOutOfBounds (ArrayNode arrayNode EmptySlots))
readCellAtNodeZeroDecision (DecidedTrue decideZero) arrayNode (SlotCons slot rest) indexNode = do
  TakeIndexZero `explain` (decideZero :~ Done)
  Destroyed destroyIndex <- destroy indexNode
  Unsealed arrayNode' held unsealValue <- unseal arrayNode slot
  Copied held' copyNode copyValue <- copy held
  Sealed arrayNode'' slot' sealValue <- seal arrayNode' held'
  ReadArray
    `explain` (destroyIndex :~ unsealValue :~ copyValue :~ sealValue :~ Done)
  return (ArrayRead (ArrayNode arrayNode'' (SlotCons slot' rest)) copyNode)
readCellAtNodeZeroDecision (DecidedFalse decideZero) arrayNode EmptySlots indexNode = do
  TakeIndexNonZero `explain` (decideZero :~ Done)
  Destroyed destroyIndex <- destroy indexNode
  ReadArrayOutOfBounds `explain` (destroyIndex :~ Done)
  return (ArrayReadOutOfBounds (ArrayNode arrayNode EmptySlots))
readCellAtNodeZeroDecision (DecidedFalse decideZero) arrayNode (SlotCons slot rest) indexNode = do
  TakeIndexNonZero `explain` (decideZero :~ Done)
  nextIndex <- decIndex indexNode
  result <- readCellAtNode arrayNode rest nextIndex
  case result of
    ArrayRead (ArrayNode arrayNode' rest') value ->
      return (ArrayRead (ArrayNode arrayNode' (SlotCons slot rest')) value)
    ArrayReadOutOfBounds (ArrayNode arrayNode' rest') ->
      return (ArrayReadOutOfBounds (ArrayNode arrayNode' (SlotCons slot rest')))

writeCellAtNode ::
     TracePayload (Value ty)
  => Node (Array ty)
     %1 -> ArraySlots ty
     %1 -> IndexNode
     %1 -> Node (Value ty)
     %1 -> Builder (ArrayWrite ty)
writeCellAtNode arrayNode EmptySlots indexNode value = do
  Destroyed destroyIndex <- destroy indexNode
  WriteArrayOutOfBounds `explain` (destroyIndex :~ Done)
  return (ArrayWriteOutOfBounds (ArrayNode arrayNode EmptySlots) value)
writeCellAtNode arrayNode slots indexNode value = do
  (indexNode1, negativeNode) <- classifyIndexNegative indexNode
  negativeDecision <- decideIndexNegative negativeNode
  writeCellAtNodeNegativeDecision
    negativeDecision
    arrayNode
    slots
    indexNode1
    value

writeCellAtNodeNegativeDecision ::
     TracePayload (Value ty)
  => Decided IndexNegative
     %1 -> Node (Array ty)
     %1 -> ArraySlots ty
     %1 -> IndexNode
     %1 -> Node (Value ty)
     %1 -> Builder (ArrayWrite ty)
writeCellAtNodeNegativeDecision (DecidedTrue decideNegative) arrayNode slots indexNode value = do
  TakeIndexNegative `explain` (decideNegative :~ Done)
  Destroyed destroyIndex <- destroy indexNode
  WriteArrayOutOfBounds `explain` (destroyIndex :~ Done)
  return (ArrayWriteOutOfBounds (ArrayNode arrayNode slots) value)
writeCellAtNodeNegativeDecision (DecidedFalse decideNegative) arrayNode slots indexNode value = do
  TakeIndexNonNegative `explain` (decideNegative :~ Done)
  (indexNode1, zeroNode) <- classifyIndexZero indexNode
  zeroDecision <- decideIndexZero zeroNode
  writeCellAtNodeZeroDecision zeroDecision arrayNode slots indexNode1 value

writeCellAtNodeZeroDecision ::
     TracePayload (Value ty)
  => Decided IndexZero
     %1 -> Node (Array ty)
     %1 -> ArraySlots ty
     %1 -> IndexNode
     %1 -> Node (Value ty)
     %1 -> Builder (ArrayWrite ty)
writeCellAtNodeZeroDecision (DecidedTrue decideZero) arrayNode EmptySlots indexNode value = do
  TakeIndexZero `explain` (decideZero :~ Done)
  Destroyed destroyIndex <- destroy indexNode
  WriteArrayOutOfBounds `explain` (destroyIndex :~ Done)
  return (ArrayWriteOutOfBounds (ArrayNode arrayNode EmptySlots) value)
writeCellAtNodeZeroDecision (DecidedTrue decideZero) arrayNode (SlotCons slot rest) indexNode value = do
  TakeIndexZero `explain` (decideZero :~ Done)
  Destroyed destroyIndex <- destroy indexNode
  Unsealed arrayNode' oldValue unsealValue <- unseal arrayNode slot
  Replaced currentValue replaceValue <- replace oldValue value
  Sealed arrayNode'' slot' sealValue <- seal arrayNode' currentValue
  WriteArray
    `explain` (destroyIndex :~ unsealValue :~ replaceValue :~ sealValue :~ Done)
  return (ArrayWrite (ArrayNode arrayNode'' (SlotCons slot' rest)))
writeCellAtNodeZeroDecision (DecidedFalse decideZero) arrayNode EmptySlots indexNode value = do
  TakeIndexNonZero `explain` (decideZero :~ Done)
  Destroyed destroyIndex <- destroy indexNode
  WriteArrayOutOfBounds `explain` (destroyIndex :~ Done)
  return (ArrayWriteOutOfBounds (ArrayNode arrayNode EmptySlots) value)
writeCellAtNodeZeroDecision (DecidedFalse decideZero) arrayNode (SlotCons slot rest) indexNode value = do
  TakeIndexNonZero `explain` (decideZero :~ Done)
  nextIndex <- decIndex indexNode
  result <- writeCellAtNode arrayNode rest nextIndex value
  case result of
    ArrayWrite (ArrayNode arrayNode' rest') ->
      return (ArrayWrite (ArrayNode arrayNode' (SlotCons slot rest')))
    ArrayWriteOutOfBounds (ArrayNode arrayNode' rest') value' ->
      return
        (ArrayWriteOutOfBounds
           (ArrayNode arrayNode' (SlotCons slot rest'))
           value')

--------------------------------------------------------------------------------
-- Checked array helpers
--------------------------------------------------------------------------------
readIntArrayAtNodeChecked ::
     IntArray %1 -> IndexNode %1 -> Builder (IntArray, IntNode)
readIntArrayAtNodeChecked values indexNode = do
  result <- readArrayAtNode values indexNode
  case result of
    ArrayRead values' value -> return (values', value)
    ArrayReadOutOfBounds values' -> do
      fallback <- literal (int 0)
      return (values', fallback)

writeArrayAtNodeChecked ::
     TracePayload (Value ty)
  => ArrayNode ty
     %1 -> IndexNode
     %1 -> Node (Value ty)
     %1 -> Builder (ArrayNode ty)
writeArrayAtNodeChecked values indexNode value = do
  result <- writeArrayAtNode values indexNode value
  case result of
    ArrayWrite values' -> return values'
    ArrayWriteOutOfBounds values' value' -> do
      discardValue value'
      return values'

--------------------------------------------------------------------------------
-- Index operations
--------------------------------------------------------------------------------
incIndexPayload :: Payload Index %1 -> Payload Index
incIndexPayload (LInt value) = LInt (value + 1)

decIndexPayload :: Payload Index %1 -> Payload Index
decIndexPayload (LInt value) = LInt (value - 1)

incIndex :: IndexNode %1 -> Builder IndexNode
incIndex indexNode = do
  Used indexPayload useIndex <- use indexNode
  Computed nextIndex computeIndex <- compute (incIndexPayload <$> indexPayload)
  IncIndex `explain` (useIndex :~ computeIndex :~ Done)
  return nextIndex

decIndex :: IndexNode %1 -> Builder IndexNode
decIndex indexNode = do
  Used indexPayload useIndex <- use indexNode
  Computed nextIndex computeIndex <- compute (decIndexPayload <$> indexPayload)
  DecIndex `explain` (useIndex :~ computeIndex :~ Done)
  return nextIndex

--------------------------------------------------------------------------------
-- Semantic insertion branches
--------------------------------------------------------------------------------
boolToInsertionBranch :: Payload (Value 'TBool) %1 -> Payload InsertionBranch
boolToInsertionBranch (LBool True)  = LBool True
boolToInsertionBranch (LBool False) = LBool False

isShiftBranch :: Payload InsertionBranch %1 -> Bool
isShiftBranch (LBool True)  = True
isShiftBranch (LBool False) = False

classifyInsertionBranch :: BoolNode %1 -> Builder InsertionBranchNode
classifyInsertionBranch condition = do
  Used conditionPayload useCondition <- use condition
  Computed branchNode computeBranch <-
    compute (boolToInsertionBranch <$> conditionPayload)
  ClassifyInsertionBranch `explain` (useCondition :~ computeBranch :~ Done)
  return branchNode

decideInsertionBranch ::
     InsertionBranchNode %1 -> Builder (Decided InsertionBranch)
decideInsertionBranch = decide isShiftBranch

--------------------------------------------------------------------------------
-- Semantic inner-loop status
--------------------------------------------------------------------------------
indexToInnerLoopStatus :: Payload Index %1 -> Payload InnerLoopStatus
indexToInnerLoopStatus (LInt value) =
  case value >= 0 of
    True  -> LBool True
    False -> LBool False

isInnerLoopContinue :: Payload InnerLoopStatus %1 -> Bool
isInnerLoopContinue (LBool True)  = True
isInnerLoopContinue (LBool False) = False

classifyInnerLoopStatus :: IndexNode %1 -> Builder InnerLoopStatusNode
classifyInnerLoopStatus jIndex = do
  Used jPayload useJ <- use jIndex
  Computed statusNode computeStatus <-
    compute (indexToInnerLoopStatus <$> jPayload)
  ClassifyInnerLoopStatus `explain` (useJ :~ computeStatus :~ Done)
  return statusNode

decideInnerLoopStatus ::
     InnerLoopStatusNode %1 -> Builder (Decided InnerLoopStatus)
decideInnerLoopStatus = decide isInnerLoopContinue

--------------------------------------------------------------------------------
-- Semantic outer-loop status
--------------------------------------------------------------------------------
indicesToOuterLoopStatus ::
     Payload Index %1 -> Payload Index %1 -> Payload OuterLoopStatus
indicesToOuterLoopStatus (LInt i) (LInt n) =
  case i < n of
    True  -> LBool True
    False -> LBool False

isOuterLoopContinue :: Payload OuterLoopStatus %1 -> Bool
isOuterLoopContinue (LBool True)  = True
isOuterLoopContinue (LBool False) = False

classifyOuterLoopStatus ::
     IndexNode %1 -> IndexNode %1 -> Builder OuterLoopStatusNode
classifyOuterLoopStatus iIndex nIndex = do
  Used iPayload useI <- use iIndex
  Used nPayload useN <- use nIndex
  Computed statusNode computeStatus <-
    compute (indicesToOuterLoopStatus <$> iPayload <*> nPayload)
  ClassifyOuterLoopStatus `explain` (useI :~ useN :~ computeStatus :~ Done)
  return statusNode

decideOuterLoopStatus ::
     OuterLoopStatusNode %1 -> Builder (Decided OuterLoopStatus)
decideOuterLoopStatus = decide isOuterLoopContinue

--------------------------------------------------------------------------------
-- Semantic index decisions
--------------------------------------------------------------------------------
indexToNegative :: Payload Index %1 -> Payload IndexNegative
indexToNegative (LInt value) =
  case value < 0 of
    True  -> LBool True
    False -> LBool False

indexToZero :: Payload Index %1 -> Payload IndexZero
indexToZero (LInt value) =
  case value == 0 of
    True  -> LBool True
    False -> LBool False

isIndexNegative :: Payload IndexNegative %1 -> Bool
isIndexNegative (LBool True)  = True
isIndexNegative (LBool False) = False

isIndexZero :: Payload IndexZero %1 -> Bool
isIndexZero (LBool True)  = True
isIndexZero (LBool False) = False

classifyIndexNegative :: IndexNode %1 -> Builder (IndexNode, IndexNegativeNode)
classifyIndexNegative indexNode = do
  Inspected indexNode' indexPayload inspectIndex <- inspect indexNode
  Computed negativeNode computeNegative <-
    compute (indexToNegative <$> indexPayload)
  ClassifyIndexNegative `explain` (inspectIndex :~ computeNegative :~ Done)
  return (indexNode', negativeNode)

decideIndexNegative :: IndexNegativeNode %1 -> Builder (Decided IndexNegative)
decideIndexNegative = decide isIndexNegative

classifyIndexZero :: IndexNode %1 -> Builder (IndexNode, IndexZeroNode)
classifyIndexZero indexNode = do
  Inspected indexNode' indexPayload inspectIndex <- inspect indexNode
  Computed zeroNode computeZero <- compute (indexToZero <$> indexPayload)
  ClassifyIndexZero `explain` (inspectIndex :~ computeZero :~ Done)
  return (indexNode', zeroNode)

decideIndexZero :: IndexZeroNode %1 -> Builder (Decided IndexZero)
decideIndexZero = decide isIndexZero

--------------------------------------------------------------------------------
-- Operators
--------------------------------------------------------------------------------
operator ::
     TracePayload (Op op lhs rhs out)
  => Payload (Op op lhs rhs out)
     %1 -> Builder (Node (Op op lhs rhs out))
operator payload = do
  Created node createOp <- create payload
  Operator `explain` (createOp :~ Done)
  return node

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

instance EvalOp 'TGreater 'TInt 'TInt 'TBool where
  evalPayload (LInt x) LUnit (LInt y) = LBool (x > y)

instance EvalOp 'TAdd 'TDouble 'TDouble 'TDouble where
  evalPayload (LDouble x) LUnit (LDouble y) = LDouble (x + y)

instance EvalOp 'TMul 'TDouble 'TDouble 'TDouble where
  evalPayload (LDouble x) LUnit (LDouble y) = LDouble (x * y)

instance EvalOp 'TGreater 'TDouble 'TDouble 'TBool where
  evalPayload (LDouble x) LUnit (LDouble y) = LBool (x > y)

apply ::
     EvalOp op lhs rhs out
  => Node (Value lhs)
     %1 -> Node (Op op lhs rhs out)
     %1 -> Node (Value rhs)
     %1 -> Builder (Node (Value out))
apply lhsNode opNode rhsNode = do
  Used lhs useLhs <- use lhsNode
  Used opPayload useOp <- use opNode
  Used rhs useRhs <- use rhsNode
  Computed outNode computeOut <-
    compute (evalPayload <$> lhs <*> opPayload <*> rhs)
  Eval `explain` (useLhs :~ useOp :~ useRhs :~ computeOut :~ Done)
  return outNode

(.+.) ::
     forall ty. EvalOp 'TAdd ty ty ty
  => Node (Value ty)
     %1 -> Node (Value ty)
     %1 -> Builder (Node (Value ty))
(.+.) lhs rhs = do
  add <- operator (LUnit :: Payload (Op 'TAdd ty ty ty))
  apply lhs add rhs

(.*.) ::
     forall ty. EvalOp 'TMul ty ty ty
  => Node (Value ty)
     %1 -> Node (Value ty)
     %1 -> Builder (Node (Value ty))
(.*.) lhs rhs = do
  mul <- operator (LUnit :: Payload (Op 'TMul ty ty ty))
  apply lhs mul rhs

(.>.) ::
     forall ty. EvalOp 'TGreater ty ty 'TBool
  => Node (Value ty)
     %1 -> Node (Value ty)
     %1 -> Builder BoolNode
(.>.) lhs rhs = do
  greater <- operator (LUnit :: Payload (Op 'TGreater ty ty 'TBool))
  apply lhs greater rhs

--------------------------------------------------------------------------------
-- Host initialisation helpers
--------------------------------------------------------------------------------
hostLength :: [a] -> Int
hostLength []       = 0
hostLength (_:rest) = 1 + hostLength rest

--------------------------------------------------------------------------------
-- Insertion sort
--------------------------------------------------------------------------------
data OuterResult where
  OuterResult
    :: IntArray
       %1 -> IndexVar
       %1 -> IndexVar
       %1 -> IndexVar
       %1 -> IntVar
       %1 -> OuterResult

data InnerResult where
  InnerResult :: IntArray %1 -> IndexVar %1 -> IntVar %1 -> InnerResult

insertionSort :: [Int] -> IntArray %1 -> Builder IntArray
insertionSort initial values = do
  i <- declare "i" (idx 1)
  j <- declare "j" (idx 0)
  n <- declare "n" (idx (hostLength initial))
  key <- declare "key" (int 0)
  OuterResult sorted i' j' n' key' <- insertionSortOuter i j n key values
  discardVar i'
  discardVar j'
  discardVar n'
  discardVar key'
  return sorted

--------------------------------------------------------------------------------
-- Outer loop
--------------------------------------------------------------------------------
insertionSortOuter ::
     IndexVar
     %1 -> IndexVar
     %1 -> IndexVar
     %1 -> IntVar
     %1 -> IntArray
     %1 -> Builder OuterResult
insertionSortOuter i j n key values = do
  (i1, iIndexForStatus) <- readVar i
  (n1, nIndexForStatus) <- readVar n
  statusNode <- classifyOuterLoopStatus iIndexForStatus nIndexForStatus
  statusDecision <- decideOuterLoopStatus statusNode
  insertionSortOuterStatusDecision statusDecision i1 j n1 key values

insertionSortOuterStatusDecision ::
     Decided OuterLoopStatus
     %1 -> IndexVar
     %1 -> IndexVar
     %1 -> IndexVar
     %1 -> IntVar
     %1 -> IntArray
     %1 -> Builder OuterResult
insertionSortOuterStatusDecision (DecidedFalse decideStatus) i j n key values = do
  TakeOuterLoopDone `explain` (decideStatus :~ Done)
  return (OuterResult values i j n key)
insertionSortOuterStatusDecision (DecidedTrue decideStatus) i j n key values = do
  TakeOuterLoopContinue `explain` (decideStatus :~ Done)
  (i1, iIndexForRead) <- readVar i
  (values1, keyValue) <- readIntArrayAtNodeChecked values iIndexForRead
  key1 <- writeVar key keyValue
  (i2, iIndexForJ) <- readVar i1
  jStart <- decIndex iIndexForJ
  j1 <- writeVar j jStart
  InnerResult values2 j2 key2 <- insertionSortInner j1 key1 values1
  (j3, jIndexForInsert) <- readVar j2
  insertIndex <- incIndex jIndexForInsert
  (key3, keyValue') <- readVar key2
  values3 <- writeArrayAtNodeChecked values2 insertIndex keyValue'
  (i3, iIndexForInc) <- readVar i2
  nextI <- incIndex iIndexForInc
  i4 <- writeVar i3 nextI
  insertionSortOuter i4 j3 n key3 values3

--------------------------------------------------------------------------------
-- Inner loop
--------------------------------------------------------------------------------
insertionSortInner ::
     IndexVar %1 -> IntVar %1 -> IntArray %1 -> Builder InnerResult
insertionSortInner j key values = do
  (j1, jIndexForStatus) <- readVar j
  statusNode <- classifyInnerLoopStatus jIndexForStatus
  statusDecision <- decideInnerLoopStatus statusNode
  insertionSortInnerStatusDecision statusDecision j1 key values

insertionSortInnerStatusDecision ::
     Decided InnerLoopStatus
     %1 -> IndexVar
     %1 -> IntVar
     %1 -> IntArray
     %1 -> Builder InnerResult
insertionSortInnerStatusDecision (DecidedFalse decideStatus) j key values = do
  TakeInnerLoopDone `explain` (decideStatus :~ Done)
  return (InnerResult values j key)
insertionSortInnerStatusDecision (DecidedTrue decideStatus) j key values = do
  TakeInnerLoopContinue `explain` (decideStatus :~ Done)
  insertionSortInnerCompare j key values

insertionSortInnerCompare ::
     IndexVar %1 -> IntVar %1 -> IntArray %1 -> Builder InnerResult
insertionSortInnerCompare j key values = do
  (j1, jIndexForCompare) <- readVar j
  (values1, currentForCompare) <-
    readIntArrayAtNodeChecked values jIndexForCompare
  (key1, keyForCompare) <- readVar key
  isGreaterNode <- currentForCompare .>. keyForCompare
  branchNode <- classifyInsertionBranch isGreaterNode
  branchDecision <- decideInsertionBranch branchNode
  insertionSortInnerBranchDecision branchDecision j1 key1 values1

insertionSortInnerBranchDecision ::
     Decided InsertionBranch
     %1 -> IndexVar
     %1 -> IntVar
     %1 -> IntArray
     %1 -> Builder InnerResult
insertionSortInnerBranchDecision (DecidedFalse decideBranch) j key values = do
  TakeStopBranch `explain` (decideBranch :~ Done)
  return (InnerResult values j key)
insertionSortInnerBranchDecision (DecidedTrue decideBranch) j key values = do
  TakeShiftBranch `explain` (decideBranch :~ Done)
  (j1, jIndexForShift) <- readVar j
  (values1, currentForShift) <- readIntArrayAtNodeChecked values jIndexForShift
  (j2, jIndexForTarget) <- readVar j1
  targetIndex <- incIndex jIndexForTarget
  values2 <- writeArrayAtNodeChecked values1 targetIndex currentForShift
  (j3, jIndexForDec) <- readVar j2
  nextJ <- decIndex jIndexForDec
  j4 <- writeVar j3 nextJ
  insertionSortInner j4 key values2

--------------------------------------------------------------------------------
-- Example
--------------------------------------------------------------------------------
example :: Builder ()
example = do
  values <- intArray "xs" [5, 2, 4, 6, 1, 3]
  sorted <- insertionSort [5, 2, 4, 6, 1, 3] values
  discardArray sorted

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

instance PrimitiveLabel 'TBool where
  primitiveLabel _ = "B"

class BinaryOpLabel op where
  binaryOpLabel :: Proxy op -> String

instance BinaryOpLabel 'TAdd where
  binaryOpLabel _ = "Add"

instance BinaryOpLabel 'TMul where
  binaryOpLabel _ = "Mul"

instance BinaryOpLabel 'TGreater where
  binaryOpLabel _ = "Gt"

instance TracePayload (Value 'TInt) where
  payloadView _ (LInt i) = PayloadView (padRightF "Val" P.++ P.show i)

instance TracePayload (Value 'TDouble) where
  payloadView _ (LDouble f) = PayloadView (padRightF "Val" P.++ P.show f)

instance TracePayload (Value 'TBool) where
  payloadView _ (LBool True)  = PayloadView (padRightF "Bool" P.++ "True")
  payloadView _ (LBool False) = PayloadView (padRightF "Bool" P.++ "False")

instance TracePayload Index where
  payloadView _ (LInt i) = PayloadView (padRightF "Idx" P.++ P.show i)

instance TracePayload InsertionBranch where
  payloadView _ (LBool True)  = PayloadView (padRightF "Branch" P.++ "shift")
  payloadView _ (LBool False) = PayloadView (padRightF "Branch" P.++ "stop")

instance TracePayload InnerLoopStatus where
  payloadView _ (LBool True)  = PayloadView (padRightF "Inner" P.++ "continue")
  payloadView _ (LBool False) = PayloadView (padRightF "Inner" P.++ "done")

instance TracePayload OuterLoopStatus where
  payloadView _ (LBool True)  = PayloadView (padRightF "Outer" P.++ "continue")
  payloadView _ (LBool False) = PayloadView (padRightF "Outer" P.++ "done")

instance TracePayload IndexNegative where
  payloadView _ (LBool True)  = PayloadView (padRightF "IdxNeg" P.++ "true")
  payloadView _ (LBool False) = PayloadView (padRightF "IdxNeg" P.++ "false")

instance TracePayload IndexZero where
  payloadView _ (LBool True)  = PayloadView (padRightF "IdxZero" P.++ "true")
  payloadView _ (LBool False) = PayloadView (padRightF "IdxZero" P.++ "false")

instance TracePayload (Var tag) where
  payloadView _ (LString name) = PayloadView (padRightF "Var" P.++ name)

instance TracePayload (Array ty) where
  payloadView _ (LString name) = PayloadView (padRightF "Arr" P.++ name)

instance (BinaryOpLabel op, PrimitiveLabel out) =>
         TracePayload (Op op lhs rhs out) where
  payloadView _ LUnit =
    PayloadView
      (padRightF "Op"
         P.++ binaryOpLabel (Proxy :: Proxy op)
         P.++ primitiveLabel (Proxy :: Proxy out))

instance PrintEvent Event where
  printEvent Literal                 = "Literal"
  printEvent IndexLiteral            = "Index"
  printEvent Operator                = "Operator"
  printEvent DeclareVar              = "DeclareVar"
  printEvent ReadVar                 = "ReadVar"
  printEvent WriteVar                = "WriteVar"
  printEvent Eval                    = "Eval"
  printEvent IncIndex                = "IncIndex"
  printEvent DecIndex                = "DecIndex"
  printEvent ClassifyInsertionBranch = "ClassifyInsertionBranch"
  printEvent TakeShiftBranch         = "TakeShiftBranch"
  printEvent TakeStopBranch          = "TakeStopBranch"
  printEvent ClassifyInnerLoopStatus = "ClassifyInnerLoopStatus"
  printEvent TakeInnerLoopContinue   = "TakeInnerLoopContinue"
  printEvent TakeInnerLoopDone       = "TakeInnerLoopDone"
  printEvent ClassifyOuterLoopStatus = "ClassifyOuterLoopStatus"
  printEvent TakeOuterLoopContinue   = "TakeOuterLoopContinue"
  printEvent TakeOuterLoopDone       = "TakeOuterLoopDone"
  printEvent ClassifyIndexNegative   = "ClassifyIndexNegative"
  printEvent TakeIndexNegative       = "TakeIndexNegative"
  printEvent TakeIndexNonNegative    = "TakeIndexNonNegative"
  printEvent ClassifyIndexZero       = "ClassifyIndexZero"
  printEvent TakeIndexZero           = "TakeIndexZero"
  printEvent TakeIndexNonZero        = "TakeIndexNonZero"
  printEvent CreateArray             = "CreateArray"
  printEvent InitArrayCell           = "InitArrayCell"
  printEvent ReadArray               = "ReadArray"
  printEvent ReadArrayOutOfBounds    = "ReadArrayOutOfBounds"
  printEvent WriteArray              = "WriteArray"
  printEvent WriteArrayOutOfBounds   = "WriteArrayOutOfBounds"
  printEvent DiscardArrayCell        = "DiscardArrayCell"
  printEvent DiscardArray            = "DiscardArray"
  printEvent DiscardVar              = "DiscardVar"
  printEvent DiscardValue            = "DiscardValue"
