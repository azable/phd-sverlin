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
  , VarNode
  , ArrayNode
  , ArrayRead(..)
  , ArrayWrite(..)
  , IntNode
  , DoubleNode
  , BoolNode
  , IndexNode
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
labelWidth = 5

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

type instance Payload (Value 'TInt) = LInt (Value 'TInt)

type instance Payload (Value 'TDouble) = LDouble (Value 'TDouble)

type instance Payload (Value 'TBool) = LBool (Value 'TBool)

type instance Payload (Var tag) = LString (Var tag)

type instance Payload (Op op lhs rhs out) = LUnit (Op op lhs rhs out)

type instance Payload Index = LInt Index

type instance Payload (Array ty) = LString (Array ty)

type Builder a = TraceBuilder Event a

type IntNode = Node (Value 'TInt)

type DoubleNode = Node (Value 'TDouble)

type BoolNode = Node (Value 'TBool)

type IndexNode = Node Index

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
  BranchTrue
    :: Event
         '[ Use (Value 'TBool), Compute (Value 'TBool), Destroy (Value 'TBool)]
  BranchFalse
    :: Event
         '[ Use (Value 'TBool), Compute (Value 'TBool), Destroy (Value 'TBool)]
  CreateArray :: Event '[ Create (Array ty)]
  InitArrayCell :: Event '[ Create (Value ty), Seal (Array ty) (Value ty)]
  ReadArray
    :: Event
         '[ Observe Index
          , Destroy Index
          , Unseal (Array ty) (Value ty)
          , Copy (Value ty)
          , Seal (Array ty) (Value ty)
          ]
  ReadArrayOutOfBounds :: Event '[ Observe Index, Destroy Index]
  WriteArray
    :: Event
         '[ Observe Index
          , Destroy Index
          , Unseal (Array ty) (Value ty)
          , Replace (Value ty)
          , Seal (Array ty) (Value ty)
          ]
  WriteArrayOutOfBounds :: Event '[ Observe Index, Destroy Index]
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

identityValue :: Payload (Value ty) %1 -> Payload (Value ty)
identityValue payload = payload

recordBranch :: Bool -> BoolNode %1 -> Builder ()
recordBranch True condition = do
  Used conditionPayload useCondition <- use condition
  Computed recordedCondition computeCondition <-
    compute (identityValue <$> conditionPayload)
  Destroyed destroyRecordedCondition <- destroy recordedCondition
  BranchTrue
    `explain` (useCondition
                 :~ computeCondition
                 :~ destroyRecordedCondition
                 :~ Done)
recordBranch False condition = do
  Used conditionPayload useCondition <- use condition
  Computed recordedCondition computeCondition <-
    compute (identityValue <$> conditionPayload)
  Destroyed destroyRecordedCondition <- destroy recordedCondition
  BranchFalse
    `explain` (useCondition
                 :~ computeCondition
                 :~ destroyRecordedCondition
                 :~ Done)

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

data ReadCell ty where
  ReadCell
    :: Node (Array ty)
       %1 -> ArraySlots ty
       %1 -> Node (Value ty)
       %1 -> Evidence (Unseal (Array ty) (Value ty))
       %1 -> Evidence (Copy (Value ty))
       %1 -> Evidence (Seal (Array ty) (Value ty))
       %1 -> ReadCell ty

data ReadCellResult ty where
  ReadCellFound :: ReadCell ty %1 -> ReadCellResult ty
  ReadCellMissing :: Node (Array ty) %1 -> ArraySlots ty %1 -> ReadCellResult ty

data WriteCell ty where
  WriteCell
    :: Node (Array ty)
       %1 -> ArraySlots ty
       %1 -> Evidence (Unseal (Array ty) (Value ty))
       %1 -> Evidence (Replace (Value ty))
       %1 -> Evidence (Seal (Array ty) (Value ty))
       %1 -> WriteCell ty

data WriteCellResult ty where
  WriteCellFound :: WriteCell ty %1 -> WriteCellResult ty
  WriteCellMissing
    :: Node (Array ty)
       %1 -> ArraySlots ty
       %1 -> Node (Value ty)
       %1 -> WriteCellResult ty

readCellAt ::
     TracePayload (Value ty)
  => Int
  -> Node (Array ty)
     %1 -> ArraySlots ty
     %1 -> Builder (ReadCellResult ty)
readCellAt _ arrayNode EmptySlots =
  return (ReadCellMissing arrayNode EmptySlots)
readCellAt position arrayNode (SlotCons slot rest)
  | position <= 0 = do
    Unsealed arrayNode' held unsealValue <- unseal arrayNode slot
    Copied held' copyNode copyValue <- copy held
    Sealed arrayNode'' slot' sealValue <- seal arrayNode' held'
    return
      (ReadCellFound
         (ReadCell
            arrayNode''
            (SlotCons slot' rest)
            copyNode
            unsealValue
            copyValue
            sealValue))
  | otherwise = do
    result <- readCellAt (position - 1) arrayNode rest
    case result of
      ReadCellFound (ReadCell arrayNode' rest' copyNode unsealValue copyValue sealValue) ->
        return
          (ReadCellFound
             (ReadCell
                arrayNode'
                (SlotCons slot rest')
                copyNode
                unsealValue
                copyValue
                sealValue))
      ReadCellMissing arrayNode' rest' ->
        return (ReadCellMissing arrayNode' (SlotCons slot rest'))

writeCellAt ::
     TracePayload (Value ty)
  => Int
  -> Node (Array ty)
     %1 -> ArraySlots ty
     %1 -> Node (Value ty)
     %1 -> Builder (WriteCellResult ty)
writeCellAt _ arrayNode EmptySlots newValue =
  return (WriteCellMissing arrayNode EmptySlots newValue)
writeCellAt position arrayNode (SlotCons slot rest) newValue
  | position <= 0 = do
    Unsealed arrayNode' oldValue unsealValue <- unseal arrayNode slot
    Replaced currentValue replaceValue <- replace oldValue newValue
    Sealed arrayNode'' slot' sealValue <- seal arrayNode' currentValue
    return
      (WriteCellFound
         (WriteCell
            arrayNode''
            (SlotCons slot' rest)
            unsealValue
            replaceValue
            sealValue))
  | otherwise = do
    result <- writeCellAt (position - 1) arrayNode rest newValue
    case result of
      WriteCellFound (WriteCell arrayNode' rest' unsealValue replaceValue sealValue) ->
        return
          (WriteCellFound
             (WriteCell
                arrayNode'
                (SlotCons slot rest')
                unsealValue
                replaceValue
                sealValue))
      WriteCellMissing arrayNode' rest' newValue' ->
        return (WriteCellMissing arrayNode' (SlotCons slot rest') newValue')

readArrayAt ::
     TracePayload (Value ty) => Int -> ArrayNode ty %1 -> Builder (ArrayRead ty)
readArrayAt position arrayNode = do
  indexNode <- index position
  readArrayAtNode position arrayNode indexNode

readArrayAtNode ::
     TracePayload (Value ty)
  => Int
  -> ArrayNode ty
     %1 -> IndexNode
     %1 -> Builder (ArrayRead ty)
readArrayAtNode position (ArrayNode arrayNode slots) indexNode = do
  Observed indexNode' observeIndex <- observe indexNode
  Destroyed destroyIndex <- destroy indexNode'
  result <- readCellAt position arrayNode slots
  case result of
    ReadCellFound (ReadCell arrayNode' slots' valueNode unsealValue copyValue sealValue) -> do
      ReadArray
        `explain` (observeIndex
                     :~ destroyIndex
                     :~ unsealValue
                     :~ copyValue
                     :~ sealValue
                     :~ Done)
      return (ArrayRead (ArrayNode arrayNode' slots') valueNode)
    ReadCellMissing arrayNode' slots' -> do
      ReadArrayOutOfBounds `explain` (observeIndex :~ destroyIndex :~ Done)
      return (ArrayReadOutOfBounds (ArrayNode arrayNode' slots'))

writeArrayAt ::
     TracePayload (Value ty)
  => Int
  -> ArrayNode ty
     %1 -> Node (Value ty)
     %1 -> Builder (ArrayWrite ty)
writeArrayAt position arrayNode value = do
  indexNode <- index position
  writeArrayAtNode position arrayNode indexNode value

writeArrayAtNode ::
     TracePayload (Value ty)
  => Int
  -> ArrayNode ty
     %1 -> IndexNode
     %1 -> Node (Value ty)
     %1 -> Builder (ArrayWrite ty)
writeArrayAtNode position (ArrayNode arrayNode slots) indexNode newValue = do
  Observed indexNode' observeIndex <- observe indexNode
  Destroyed destroyIndex <- destroy indexNode'
  result <- writeCellAt position arrayNode slots newValue
  case result of
    WriteCellFound (WriteCell arrayNode' slots' unsealValue replaceValue sealValue) -> do
      WriteArray
        `explain` (observeIndex
                     :~ destroyIndex
                     :~ unsealValue
                     :~ replaceValue
                     :~ sealValue
                     :~ Done)
      return (ArrayWrite (ArrayNode arrayNode' slots'))
    WriteCellMissing arrayNode' slots' newValue' -> do
      WriteArrayOutOfBounds `explain` (observeIndex :~ destroyIndex :~ Done)
      return (ArrayWriteOutOfBounds (ArrayNode arrayNode' slots') newValue')

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
-- Checked array helpers
--------------------------------------------------------------------------------
readIntArrayAtNodeChecked ::
     Int -> IntArray %1 -> IndexNode %1 -> Builder (IntArray, IntNode)
readIntArrayAtNodeChecked position values indexNode = do
  result <- readArrayAtNode position values indexNode
  case result of
    ArrayRead values' value -> return (values', value)
    ArrayReadOutOfBounds values' -> do
      fallback <- literal (int 0)
      return (values', fallback)

writeArrayAtNodeChecked ::
     TracePayload (Value ty)
  => Int
  -> ArrayNode ty
     %1 -> IndexNode
     %1 -> Node (Value ty)
     %1 -> Builder (ArrayNode ty)
writeArrayAtNodeChecked position values indexNode value = do
  result <- writeArrayAtNode position values indexNode value
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
-- Host schedule helpers
--------------------------------------------------------------------------------
hostLength :: [a] -> Int
hostLength []       = 0
hostLength (_:rest) = 1 + hostLength rest

hostAt :: Int -> [Int] -> Int
hostAt _ [] = 0
hostAt position (value:rest)
  | position <= 0 = value
  | otherwise = hostAt (position - 1) rest

hostSet :: Int -> Int -> [Int] -> [Int]
hostSet _ _ [] = []
hostSet position newValue (_:rest)
  | position <= 0 = newValue : rest
hostSet position newValue (value:rest) =
  value : hostSet (position - 1) newValue rest

--------------------------------------------------------------------------------
-- Insertion sort
--------------------------------------------------------------------------------
data OuterResult where
  OuterResult
    :: IntArray
       %1 -> IndexVar
       %1 -> IndexVar
       %1 -> IntVar
       %1 -> [Int]
    -> OuterResult

data InnerResult where
  InnerResult
    :: IntArray %1 -> IndexVar %1 -> IntVar %1 -> Int -> [Int] -> InnerResult

insertionSort :: [Int] -> IntArray %1 -> Builder IntArray
insertionSort initial values = do
  i <- declare "i" (idx 1)
  j <- declare "j" (idx 0)
  key <- declare "key" (int 0)
  OuterResult sorted i' j' key' _ <-
    insertionSortOuter (hostLength initial) 1 initial i j key values
  discardVar i'
  discardVar j'
  discardVar key'
  return sorted

insertionSortOuter ::
     Int
  -> Int
  -> [Int]
  -> IndexVar
     %1 -> IndexVar
     %1 -> IntVar
     %1 -> IntArray
     %1 -> Builder OuterResult
insertionSortOuter size position mirror i j key values
  | position >= size = return (OuterResult values i j key mirror)
  | otherwise = do
    let keyHost = hostAt position mirror
    (i1, iIndexForRead) <- readVar i
    (values1, keyValue) <-
      readIntArrayAtNodeChecked position values iIndexForRead
    key1 <- writeVar key keyValue
    (i2, iIndexForJ) <- readVar i1
    jStart <- decIndex iIndexForJ
    j1 <- writeVar j jStart
    InnerResult values2 j2 key2 insertPosition mirror2 <-
      insertionSortInner (position - 1) keyHost mirror j1 key1 values1
    (j3, jIndexForInsert) <- readVar j2
    insertIndex <- incIndex jIndexForInsert
    (key3, keyValue') <- readVar key2
    values3 <-
      writeArrayAtNodeChecked (insertPosition + 1) values2 insertIndex keyValue'
    let mirror3 = hostSet (insertPosition + 1) keyHost mirror2
    (i3, iIndexForInc) <- readVar i2
    nextI <- incIndex iIndexForInc
    i4 <- writeVar i3 nextI
    insertionSortOuter size (position + 1) mirror3 i4 j3 key3 values3

insertionSortInner ::
     Int
  -> Int
  -> [Int]
  -> IndexVar
     %1 -> IntVar
     %1 -> IntArray
     %1 -> Builder InnerResult
insertionSortInner position keyHost mirror j key values
  | position < 0 = return (InnerResult values j key position mirror)
  | otherwise = do
    let currentHost = hostAt position mirror
    (j1, jIndexForCompare) <- readVar j
    (values1, currentForCompare) <-
      readIntArrayAtNodeChecked position values jIndexForCompare
    (key1, keyForCompare) <- readVar key
    isGreaterNode <- currentForCompare .>. keyForCompare
    recordBranch (currentHost > keyHost) isGreaterNode
    insertionSortInnerDecision
      (currentHost > keyHost)
      position
      keyHost
      currentHost
      mirror
      j1
      key1
      values1

insertionSortInnerDecision ::
     Bool
  -> Int
  -> Int
  -> Int
  -> [Int]
  -> IndexVar
     %1 -> IntVar
     %1 -> IntArray
     %1 -> Builder InnerResult
insertionSortInnerDecision True position keyHost currentHost mirror j key values = do
  (j1, jIndexForShift) <- readVar j
  (values1, currentForShift) <-
    readIntArrayAtNodeChecked position values jIndexForShift
  (j2, jIndexForTarget) <- readVar j1
  targetIndex <- incIndex jIndexForTarget
  values2 <-
    writeArrayAtNodeChecked (position + 1) values1 targetIndex currentForShift
  (j3, jIndexForDec) <- readVar j2
  nextJ <- decIndex jIndexForDec
  j4 <- writeVar j3 nextJ
  let mirror2 = hostSet (position + 1) currentHost mirror
  insertionSortInner (position - 1) keyHost mirror2 j4 key values2
insertionSortInnerDecision False position _keyHost _currentHost mirror j key values =
  return (InnerResult values j key position mirror)

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
  printEvent Literal               = "Literal"
  printEvent IndexLiteral          = "Index"
  printEvent Operator              = "Operator"
  printEvent DeclareVar            = "DeclareVar"
  printEvent ReadVar               = "ReadVar"
  printEvent WriteVar              = "WriteVar"
  printEvent Eval                  = "Eval"
  printEvent IncIndex              = "IncIndex"
  printEvent DecIndex              = "DecIndex"
  printEvent BranchTrue            = "BranchTrue"
  printEvent BranchFalse           = "BranchFalse"
  printEvent CreateArray           = "CreateArray"
  printEvent InitArrayCell         = "InitArrayCell"
  printEvent ReadArray             = "ReadArray"
  printEvent ReadArrayOutOfBounds  = "ReadArrayOutOfBounds"
  printEvent WriteArray            = "WriteArray"
  printEvent WriteArrayOutOfBounds = "WriteArrayOutOfBounds"
  printEvent DiscardArrayCell      = "DiscardArrayCell"
  printEvent DiscardArray          = "DiscardArray"
  printEvent DiscardVar            = "DiscardVar"
  printEvent DiscardValue          = "DiscardValue"
