{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE KindSignatures        #-}
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
  , CellSize(..)
  , DecisionKind(..)
  , Value
  , Var
  , Op
  , Index
  , Array
  , Decision
  , CellBlock
  , CellSlots
  , InsertionBranch
  , InnerLoopStatus
  , OuterLoopStatus
  , IndexNegative
  , IndexZero
  , VarNode
  , ArrayNode
  , ArrayRead(..)
  , ArrayWrite(..)
  , Choice(..)
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
  , int
  , double
  , bool
  , idx
  , literal
  , index
  , declare
  , readVar
  , writeVar
  , discardVar
  , discardValue
  , array
  , intArray
  , doubleArray
  , readArrayAt
  , readArrayAtNode
  , writeArrayAt
  , writeArrayAtNode
  , discardArray
  , incIndex
  , decIndex
  , classifyInsertionBranch
  , decideInsertionBranch
  , classifyInnerLoopStatus
  , decideInnerLoopStatus
  , classifyOuterLoopStatus
  , decideOuterLoopStatus
  , classifyIndexNegative
  , decideIndexNegative
  , classifyIndexZero
  , decideIndexZero
  , operator
  , apply
  , (.+.)
  , (.*.)
  , (.>.)
  , insertionSort
  , run
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

data CellSize
  = One
  | Many

data DecisionKind
  = KInsertionBranch
  | KInnerLoopStatus
  | KOuterLoopStatus
  | KIndexNegative
  | KIndexZero

data Value (ty :: PrimitiveType)

data Var tag

data Op (op :: BinaryOp) (lhs :: PrimitiveType) (rhs :: PrimitiveType) (out :: PrimitiveType)

data Index

data Array (ty :: PrimitiveType)

data Decision (kind :: DecisionKind)

type InsertionBranch = Decision 'KInsertionBranch

type InnerLoopStatus = Decision 'KInnerLoopStatus

type OuterLoopStatus = Decision 'KOuterLoopStatus

type IndexNegative = Decision 'KIndexNegative

type IndexZero = Decision 'KIndexZero

type instance Payload (Value 'TInt) = LInt (Value 'TInt)

type instance Payload (Value 'TDouble) = LDouble (Value 'TDouble)

type instance Payload (Value 'TBool) = LBool (Value 'TBool)

type instance Payload (Var tag) = LString (Var tag)

type instance Payload (Op op lhs rhs out) = LUnit (Op op lhs rhs out)

type instance Payload Index = LInt Index

type instance Payload (Array ty) = LString (Array ty)

type instance Payload (Decision kind) = LBool (Decision kind)

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

--------------------------------------------------------------------------------
-- Cells
--------------------------------------------------------------------------------
data CellSlots owner elem where
  NoCells :: CellSlots owner elem
  CellCons
    :: Slot owner elem %1 -> CellSlots owner elem %1 -> CellSlots owner elem

data CellBlock size owner elem where
  SingleCell :: Node owner %1 -> Slot owner elem %1 -> CellBlock 'One owner elem
  ManyCells
    :: Node owner %1 -> CellSlots owner elem %1 -> CellBlock 'Many owner elem

type VarNode tag = CellBlock 'One (Var tag) tag

type ArrayNode ty = CellBlock 'Many (Array ty) (Value ty)

type IntVar = VarNode (Value 'TInt)

type DoubleVar = VarNode (Value 'TDouble)

type BoolVar = VarNode (Value 'TBool)

type IndexVar = VarNode Index

type IntArray = ArrayNode 'TInt

type DoubleArray = ArrayNode 'TDouble

data ArrayRead ty where
  ArrayRead :: ArrayNode ty %1 -> Node (Value ty) %1 -> ArrayRead ty
  ArrayReadOutOfBounds :: ArrayNode ty %1 -> ArrayRead ty

data ArrayWrite ty where
  ArrayWrite :: ArrayNode ty %1 -> ArrayWrite ty
  ArrayWriteOutOfBounds
    :: ArrayNode ty %1 -> Node (Value ty) %1 -> ArrayWrite ty

data Choice tag
  = ChooseTrue
  | ChooseFalse

--------------------------------------------------------------------------------
-- Event vocabulary
--------------------------------------------------------------------------------
data Event acts where
  Literal :: Event '[ Create (Value ty)]
  IndexLiteral :: Event '[ Create Index]
  Operator :: Event '[ Create (Op op lhs rhs out)]
  CreateCellBlock :: Event '[ Create owner]
  InitCell :: Event '[ Create elem, Seal owner elem]
  ReadCell :: Event '[ Unseal owner elem, Copy elem, Seal owner elem]
  WriteCell :: Event '[ Unseal owner elem, Replace elem, Seal owner elem]
  ReadCellAt
    :: Event '[ Destroy Index, Unseal owner elem, Copy elem, Seal owner elem]
  ReadCellOutOfBounds :: Event '[ Destroy Index]
  WriteCellAt
    :: Event '[ Destroy Index, Unseal owner elem, Replace elem, Seal owner elem]
  WriteCellOutOfBounds :: Event '[ Destroy Index]
  DiscardCell :: Event '[ Unseal owner elem, Destroy elem]
  DiscardCellBlock :: Event '[ Destroy owner]
  Eval
    :: Event
         '[ Use (Value lhs)
          , Use (Op op lhs rhs out)
          , Use (Value rhs)
          , Compute (Value out)
          ]
  DiscardValue :: Event '[ Destroy (Value ty)]
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

--------------------------------------------------------------------------------
-- Generic traced helpers
--------------------------------------------------------------------------------
createNode ::
     TracePayload tag
  => Event '[ Create tag]
  -> Payload tag
     %1 -> Builder (Node tag)
createNode event payload = do
  Created node createEvidence <- create payload
  event `explain` (createEvidence :~ Done)
  return node

destroyNode ::
     TracePayload tag => Event '[ Destroy tag] -> Node tag %1 -> Builder ()
destroyNode event node = do
  Destroyed destroyEvidence <- destroy node
  event `explain` (destroyEvidence :~ Done)

computeFromUse ::
     (TracePayload input, TracePayload output)
  => Event '[ Use input, Compute output]
  -> (Payload input %1 -> Payload output)
  -> Node input
     %1 -> Builder (Node output)
computeFromUse event f node = do
  Used payload useEvidence <- use node
  Computed output computeEvidence <- compute (f <$> payload)
  event `explain` (useEvidence :~ computeEvidence :~ Done)
  return output

computeFromUse2 ::
     (TracePayload input1, TracePayload input2, TracePayload output)
  => Event '[ Use input1, Use input2, Compute output]
  -> (Payload input1 %1 -> Payload input2 %1 -> Payload output)
  -> Node input1
     %1 -> Node input2
     %1 -> Builder (Node output)
computeFromUse2 event f first second = do
  Used firstPayload useFirst <- use first
  Used secondPayload useSecond <- use second
  Computed output computeOutput <-
    compute (f <$> firstPayload <*> secondPayload)
  event `explain` (useFirst :~ useSecond :~ computeOutput :~ Done)
  return output

computeFromInspect ::
     (TracePayload input, TracePayload output)
  => Event '[ Inspect input, Compute output]
  -> (Payload input %1 -> Payload output)
  -> Node input
     %1 -> Builder (Node input, Node output)
computeFromInspect event f node = do
  Inspected node' payload inspectEvidence <- inspect node
  Computed output computeEvidence <- compute (f <$> payload)
  event `explain` (inspectEvidence :~ computeEvidence :~ Done)
  return (node', output)

decideChoice ::
     TracePayload tag
  => (Payload tag %1 -> Bool)
  -> Event '[ Decide tag]
  -> Event '[ Decide tag]
  -> Node tag
     %1 -> Builder (Choice tag)
decideChoice predicate trueEvent falseEvent node = do
  decision <- decide predicate node
  case decision of
    DecidedTrue decideEvidence -> do
      trueEvent `explain` (decideEvidence :~ Done)
      return ChooseTrue
    DecidedFalse decideEvidence -> do
      falseEvent `explain` (decideEvidence :~ Done)
      return ChooseFalse

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
literal = createNode Literal

index :: Int -> Builder IndexNode
index value = createNode IndexLiteral (idx value)

--------------------------------------------------------------------------------
-- Cell blocks
--------------------------------------------------------------------------------
singleCellBlock ::
     (TracePayload owner, TracePayload elem)
  => Payload owner
     %1 -> Payload elem
     %1 -> Builder (CellBlock 'One owner elem)
singleCellBlock ownerPayload elemPayload = do
  Created owner createOwner <- create ownerPayload
  CreateCellBlock `explain` (createOwner :~ Done)
  Created elem createElem <- create elemPayload
  Sealed owner' slot sealElem <- seal owner elem
  InitCell `explain` (createElem :~ sealElem :~ Done)
  return (SingleCell owner' slot)

manyCellBlock ::
     (TracePayload owner, TracePayload elem)
  => Payload owner
     %1 -> [Payload elem]
  -> Builder (CellBlock 'Many owner elem)
manyCellBlock ownerPayload elemPayloads = do
  Created owner createOwner <- create ownerPayload
  CreateCellBlock `explain` (createOwner :~ Done)
  (owner', slots) <- initCells owner elemPayloads
  return (ManyCells owner' slots)

initCells ::
     (TracePayload owner, TracePayload elem)
  => Node owner
     %1 -> [Payload elem]
  -> Builder (Node owner, CellSlots owner elem)
initCells owner [] = return (owner, NoCells)
initCells owner (payload:payloads) = do
  Created elem createElem <- create payload
  Sealed owner' slot sealElem <- seal owner elem
  InitCell `explain` (createElem :~ sealElem :~ Done)
  (owner'', slots) <- initCells owner' payloads
  return (owner'', CellCons slot slots)

readOnlyCell ::
     (TracePayload owner, TracePayload elem)
  => CellBlock 'One owner elem
     %1 -> Builder (CellBlock 'One owner elem, Node elem)
readOnlyCell (SingleCell owner slot) = do
  Unsealed owner1 held unsealElem <- unseal owner slot
  Copied held' copyNode copyElem <- copy held
  Sealed owner2 slot' sealElem <- seal owner1 held'
  ReadCell `explain` (unsealElem :~ copyElem :~ sealElem :~ Done)
  return (SingleCell owner2 slot', copyNode)

writeOnlyCell ::
     (TracePayload owner, TracePayload elem)
  => CellBlock 'One owner elem
     %1 -> Node elem
     %1 -> Builder (CellBlock 'One owner elem)
writeOnlyCell (SingleCell owner slot) value = do
  Unsealed owner1 oldValue unsealElem <- unseal owner slot
  Replaced currentValue replaceElem <- replace oldValue value
  Sealed owner2 slot' sealElem <- seal owner1 currentValue
  WriteCell `explain` (unsealElem :~ replaceElem :~ sealElem :~ Done)
  return (SingleCell owner2 slot')

discardOnlyCell ::
     (TracePayload owner, TracePayload elem)
  => CellBlock 'One owner elem
     %1 -> Builder ()
discardOnlyCell (SingleCell owner slot) = do
  Unsealed owner1 held unsealElem <- unseal owner slot
  Destroyed destroyElem <- destroy held
  DiscardCell `explain` (unsealElem :~ destroyElem :~ Done)
  Destroyed destroyOwner <- destroy owner1
  DiscardCellBlock `explain` (destroyOwner :~ Done)

discardManyCellBlock ::
     (TracePayload owner, TracePayload elem)
  => CellBlock 'Many owner elem
     %1 -> Builder ()
discardManyCellBlock (ManyCells owner slots) = do
  owner' <- discardCellSlots owner slots
  Destroyed destroyOwner <- destroy owner'
  DiscardCellBlock `explain` (destroyOwner :~ Done)

discardCellSlots ::
     (TracePayload owner, TracePayload elem)
  => Node owner
     %1 -> CellSlots owner elem
     %1 -> Builder (Node owner)
discardCellSlots owner NoCells = return owner
discardCellSlots owner (CellCons slot rest) = do
  Unsealed owner1 held unsealElem <- unseal owner slot
  Destroyed destroyElem <- destroy held
  DiscardCell `explain` (unsealElem :~ destroyElem :~ Done)
  discardCellSlots owner1 rest

--------------------------------------------------------------------------------
-- Variables
--------------------------------------------------------------------------------
declare ::
     forall tag. TracePayload tag
  => String
  -> Payload tag
     %1 -> Builder (VarNode tag)
declare name initial =
  singleCellBlock (LString name :: Payload (Var tag)) initial

readVar :: TracePayload tag => VarNode tag %1 -> Builder (VarNode tag, Node tag)
readVar = readOnlyCell

writeVar ::
     TracePayload tag => VarNode tag %1 -> Node tag %1 -> Builder (VarNode tag)
writeVar = writeOnlyCell

discardVar :: TracePayload tag => VarNode tag %1 -> Builder ()
discardVar = discardOnlyCell

--------------------------------------------------------------------------------
-- Values
--------------------------------------------------------------------------------
discardValue :: TracePayload (Value ty) => Node (Value ty) %1 -> Builder ()
discardValue = destroyNode DiscardValue

--------------------------------------------------------------------------------
-- Arrays
--------------------------------------------------------------------------------
array ::
     forall ty. TracePayload (Value ty)
  => String
  -> [Payload (Value ty)]
  -> Builder (ArrayNode ty)
array name values = manyCellBlock (LString name :: Payload (Array ty)) values

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

readArrayAt ::
     TracePayload (Value ty) => Int -> ArrayNode ty %1 -> Builder (ArrayRead ty)
readArrayAt position values = do
  indexNode <- index position
  readArrayAtNode values indexNode

readArrayAtNode ::
     TracePayload (Value ty)
  => ArrayNode ty
     %1 -> IndexNode
     %1 -> Builder (ArrayRead ty)
readArrayAtNode (ManyCells owner slots) indexNode =
  readCellAtNode owner slots indexNode

writeArrayAt ::
     TracePayload (Value ty)
  => Int
  -> ArrayNode ty
     %1 -> Node (Value ty)
     %1 -> Builder (ArrayWrite ty)
writeArrayAt position values value = do
  indexNode <- index position
  writeArrayAtNode values indexNode value

writeArrayAtNode ::
     TracePayload (Value ty)
  => ArrayNode ty
     %1 -> IndexNode
     %1 -> Node (Value ty)
     %1 -> Builder (ArrayWrite ty)
writeArrayAtNode (ManyCells owner slots) indexNode value =
  writeCellAtNode owner slots indexNode value

discardArray :: TracePayload (Value ty) => ArrayNode ty %1 -> Builder ()
discardArray = discardManyCellBlock

--------------------------------------------------------------------------------
-- Array traversal
--------------------------------------------------------------------------------
readOutOfBounds ::
     TracePayload (Value ty)
  => Node (Array ty)
     %1 -> CellSlots (Array ty) (Value ty)
     %1 -> IndexNode
     %1 -> Builder (ArrayRead ty)
readOutOfBounds owner slots indexNode = do
  Destroyed destroyIndex <- destroy indexNode
  ReadCellOutOfBounds `explain` (destroyIndex :~ Done)
  return (ArrayReadOutOfBounds (ManyCells owner slots))

writeOutOfBounds ::
     TracePayload (Value ty)
  => Node (Array ty)
     %1 -> CellSlots (Array ty) (Value ty)
     %1 -> IndexNode
     %1 -> Node (Value ty)
     %1 -> Builder (ArrayWrite ty)
writeOutOfBounds owner slots indexNode value = do
  Destroyed destroyIndex <- destroy indexNode
  WriteCellOutOfBounds `explain` (destroyIndex :~ Done)
  return (ArrayWriteOutOfBounds (ManyCells owner slots) value)

readCellAtNode ::
     TracePayload (Value ty)
  => Node (Array ty)
     %1 -> CellSlots (Array ty) (Value ty)
     %1 -> IndexNode
     %1 -> Builder (ArrayRead ty)
readCellAtNode owner NoCells indexNode = readOutOfBounds owner NoCells indexNode
readCellAtNode owner slots indexNode = do
  (indexNode1, negativeNode) <- classifyIndexNegative indexNode
  negative <- decideIndexNegative negativeNode
  case negative of
    ChooseTrue  -> readOutOfBounds owner slots indexNode1
    ChooseFalse -> readCellAtNonNegative owner slots indexNode1

readCellAtNonNegative ::
     TracePayload (Value ty)
  => Node (Array ty)
     %1 -> CellSlots (Array ty) (Value ty)
     %1 -> IndexNode
     %1 -> Builder (ArrayRead ty)
readCellAtNonNegative owner slots indexNode = do
  (indexNode1, zeroNode) <- classifyIndexZero indexNode
  zero1 <- decideIndexZero zeroNode
  case zero1 of
    ChooseTrue  -> readCellAtZero owner slots indexNode1
    ChooseFalse -> readCellAtNonZero owner slots indexNode1

readCellAtZero ::
     TracePayload (Value ty)
  => Node (Array ty)
     %1 -> CellSlots (Array ty) (Value ty)
     %1 -> IndexNode
     %1 -> Builder (ArrayRead ty)
readCellAtZero owner NoCells indexNode = readOutOfBounds owner NoCells indexNode
readCellAtZero owner (CellCons slot rest) indexNode = do
  Destroyed destroyIndex <- destroy indexNode
  Unsealed owner1 held unsealElem <- unseal owner slot
  Copied held' copyNode copyElem <- copy held
  Sealed owner2 slot' sealElem <- seal owner1 held'
  ReadCellAt
    `explain` (destroyIndex :~ unsealElem :~ copyElem :~ sealElem :~ Done)
  return (ArrayRead (ManyCells owner2 (CellCons slot' rest)) copyNode)

readCellAtNonZero ::
     TracePayload (Value ty)
  => Node (Array ty)
     %1 -> CellSlots (Array ty) (Value ty)
     %1 -> IndexNode
     %1 -> Builder (ArrayRead ty)
readCellAtNonZero owner NoCells indexNode =
  readOutOfBounds owner NoCells indexNode
readCellAtNonZero owner (CellCons slot rest) indexNode = do
  nextIndex <- decIndex indexNode
  result <- readCellAtNode owner rest nextIndex
  case result of
    ArrayRead (ManyCells owner' rest') value ->
      return (ArrayRead (ManyCells owner' (CellCons slot rest')) value)
    ArrayReadOutOfBounds (ManyCells owner' rest') ->
      return (ArrayReadOutOfBounds (ManyCells owner' (CellCons slot rest')))

writeCellAtNode ::
     TracePayload (Value ty)
  => Node (Array ty)
     %1 -> CellSlots (Array ty) (Value ty)
     %1 -> IndexNode
     %1 -> Node (Value ty)
     %1 -> Builder (ArrayWrite ty)
writeCellAtNode owner NoCells indexNode value =
  writeOutOfBounds owner NoCells indexNode value
writeCellAtNode owner slots indexNode value = do
  (indexNode1, negativeNode) <- classifyIndexNegative indexNode
  negative <- decideIndexNegative negativeNode
  case negative of
    ChooseTrue  -> writeOutOfBounds owner slots indexNode1 value
    ChooseFalse -> writeCellAtNonNegative owner slots indexNode1 value

writeCellAtNonNegative ::
     TracePayload (Value ty)
  => Node (Array ty)
     %1 -> CellSlots (Array ty) (Value ty)
     %1 -> IndexNode
     %1 -> Node (Value ty)
     %1 -> Builder (ArrayWrite ty)
writeCellAtNonNegative owner slots indexNode value = do
  (indexNode1, zeroNode) <- classifyIndexZero indexNode
  zero1 <- decideIndexZero zeroNode
  case zero1 of
    ChooseTrue  -> writeCellAtZero owner slots indexNode1 value
    ChooseFalse -> writeCellAtNonZero owner slots indexNode1 value

writeCellAtZero ::
     TracePayload (Value ty)
  => Node (Array ty)
     %1 -> CellSlots (Array ty) (Value ty)
     %1 -> IndexNode
     %1 -> Node (Value ty)
     %1 -> Builder (ArrayWrite ty)
writeCellAtZero owner NoCells indexNode value =
  writeOutOfBounds owner NoCells indexNode value
writeCellAtZero owner (CellCons slot rest) indexNode value = do
  Destroyed destroyIndex <- destroy indexNode
  Unsealed owner1 oldValue unsealElem <- unseal owner slot
  Replaced currentValue replaceElem <- replace oldValue value
  Sealed owner2 slot' sealElem <- seal owner1 currentValue
  WriteCellAt
    `explain` (destroyIndex :~ unsealElem :~ replaceElem :~ sealElem :~ Done)
  return (ArrayWrite (ManyCells owner2 (CellCons slot' rest)))

writeCellAtNonZero ::
     TracePayload (Value ty)
  => Node (Array ty)
     %1 -> CellSlots (Array ty) (Value ty)
     %1 -> IndexNode
     %1 -> Node (Value ty)
     %1 -> Builder (ArrayWrite ty)
writeCellAtNonZero owner NoCells indexNode value =
  writeOutOfBounds owner NoCells indexNode value
writeCellAtNonZero owner (CellCons slot rest) indexNode value = do
  nextIndex <- decIndex indexNode
  result <- writeCellAtNode owner rest nextIndex value
  case result of
    ArrayWrite (ManyCells owner' rest') ->
      return (ArrayWrite (ManyCells owner' (CellCons slot rest')))
    ArrayWriteOutOfBounds (ManyCells owner' rest') value' ->
      return
        (ArrayWriteOutOfBounds (ManyCells owner' (CellCons slot rest')) value')

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
incIndex = computeFromUse IncIndex incIndexPayload

decIndex :: IndexNode %1 -> Builder IndexNode
decIndex = computeFromUse DecIndex decIndexPayload

--------------------------------------------------------------------------------
-- Semantic decisions
--------------------------------------------------------------------------------
toDecision :: Bool %1 -> Payload (Decision kind)
toDecision True  = LBool True
toDecision False = LBool False

decisionToBool :: Payload (Decision kind) %1 -> Bool
decisionToBool (LBool value) = value

boolToInsertionBranch :: Payload (Value 'TBool) %1 -> Payload InsertionBranch
boolToInsertionBranch (LBool value) = toDecision value

indexToInnerLoopStatus :: Payload Index %1 -> Payload InnerLoopStatus
indexToInnerLoopStatus (LInt value) = toDecision (value >= 0)

indicesToOuterLoopStatus ::
     Payload Index %1 -> Payload Index %1 -> Payload OuterLoopStatus
indicesToOuterLoopStatus (LInt i) (LInt n) = toDecision (i < n)

indexToNegative :: Payload Index %1 -> Payload IndexNegative
indexToNegative (LInt value) = toDecision (value < 0)

indexToZero :: Payload Index %1 -> Payload IndexZero
indexToZero (LInt value) = toDecision (value == 0)

classifyInsertionBranch :: BoolNode %1 -> Builder InsertionBranchNode
classifyInsertionBranch =
  computeFromUse ClassifyInsertionBranch boolToInsertionBranch

decideInsertionBranch ::
     InsertionBranchNode %1 -> Builder (Choice InsertionBranch)
decideInsertionBranch =
  decideChoice decisionToBool TakeShiftBranch TakeStopBranch

classifyInnerLoopStatus :: IndexNode %1 -> Builder InnerLoopStatusNode
classifyInnerLoopStatus =
  computeFromUse ClassifyInnerLoopStatus indexToInnerLoopStatus

decideInnerLoopStatus ::
     InnerLoopStatusNode %1 -> Builder (Choice InnerLoopStatus)
decideInnerLoopStatus =
  decideChoice decisionToBool TakeInnerLoopContinue TakeInnerLoopDone

classifyOuterLoopStatus ::
     IndexNode %1 -> IndexNode %1 -> Builder OuterLoopStatusNode
classifyOuterLoopStatus =
  computeFromUse2 ClassifyOuterLoopStatus indicesToOuterLoopStatus

decideOuterLoopStatus ::
     OuterLoopStatusNode %1 -> Builder (Choice OuterLoopStatus)
decideOuterLoopStatus =
  decideChoice decisionToBool TakeOuterLoopContinue TakeOuterLoopDone

classifyIndexNegative :: IndexNode %1 -> Builder (IndexNode, IndexNegativeNode)
classifyIndexNegative = computeFromInspect ClassifyIndexNegative indexToNegative

decideIndexNegative :: IndexNegativeNode %1 -> Builder (Choice IndexNegative)
decideIndexNegative =
  decideChoice decisionToBool TakeIndexNegative TakeIndexNonNegative

classifyIndexZero :: IndexNode %1 -> Builder (IndexNode, IndexZeroNode)
classifyIndexZero = computeFromInspect ClassifyIndexZero indexToZero

decideIndexZero :: IndexZeroNode %1 -> Builder (Choice IndexZero)
decideIndexZero = decideChoice decisionToBool TakeIndexZero TakeIndexNonZero

--------------------------------------------------------------------------------
-- Operators
--------------------------------------------------------------------------------
operator ::
     TracePayload (Op op lhs rhs out)
  => Payload (Op op lhs rhs out)
     %1 -> Builder (Node (Op op lhs rhs out))
operator = createNode Operator

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

insertionSort :: IntArray %1 -> Int -> Builder IntArray
insertionSort values len = do
  i <- declare "i" (idx 1)
  j <- declare "j" (idx 0)
  n <- declare "n" (idx len)
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
  status <- decideOuterLoopStatus statusNode
  case status of
    ChooseFalse -> return (OuterResult values i1 j n1 key)
    ChooseTrue  -> insertionSortOuterStep i1 j n1 key values

insertionSortOuterStep ::
     IndexVar
     %1 -> IndexVar
     %1 -> IndexVar
     %1 -> IntVar
     %1 -> IntArray
     %1 -> Builder OuterResult
insertionSortOuterStep i j n key values = do
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
  status <- decideInnerLoopStatus statusNode
  case status of
    ChooseFalse -> return (InnerResult values j1 key)
    ChooseTrue  -> insertionSortInnerCompare j1 key values

insertionSortInnerCompare ::
     IndexVar %1 -> IntVar %1 -> IntArray %1 -> Builder InnerResult
insertionSortInnerCompare j key values = do
  (j1, jIndexForCompare) <- readVar j
  (values1, currentForCompare) <-
    readIntArrayAtNodeChecked values jIndexForCompare
  (key1, keyForCompare) <- readVar key
  isGreaterNode <- currentForCompare .>. keyForCompare
  branchNode <- classifyInsertionBranch isGreaterNode
  branch <- decideInsertionBranch branchNode
  case branch of
    ChooseFalse -> return (InnerResult values1 j1 key1)
    ChooseTrue  -> insertionSortInnerShift j1 key1 values1

insertionSortInnerShift ::
     IndexVar %1 -> IntVar %1 -> IntArray %1 -> Builder InnerResult
insertionSortInnerShift j key values = do
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
  sorted <- insertionSort values 6
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

class DecisionLabel kind where
  decisionLabel :: Proxy kind -> String
  decisionTrueLabel :: Proxy kind -> String
  decisionFalseLabel :: Proxy kind -> String

instance DecisionLabel 'KInsertionBranch where
  decisionLabel _ = "Branch"
  decisionTrueLabel _ = "shift"
  decisionFalseLabel _ = "stop"

instance DecisionLabel 'KInnerLoopStatus where
  decisionLabel _ = "Inner"
  decisionTrueLabel _ = "continue"
  decisionFalseLabel _ = "done"

instance DecisionLabel 'KOuterLoopStatus where
  decisionLabel _ = "Outer"
  decisionTrueLabel _ = "continue"
  decisionFalseLabel _ = "done"

instance DecisionLabel 'KIndexNegative where
  decisionLabel _ = "IdxNeg"
  decisionTrueLabel _ = "true"
  decisionFalseLabel _ = "false"

instance DecisionLabel 'KIndexZero where
  decisionLabel _ = "IdxZero"
  decisionTrueLabel _ = "true"
  decisionFalseLabel _ = "false"

instance TracePayload (Value 'TInt) where
  payloadView _ (LInt i) = PayloadView (padRightF "Val" P.++ P.show i)

instance TracePayload (Value 'TDouble) where
  payloadView _ (LDouble f) = PayloadView (padRightF "Val" P.++ P.show f)

instance TracePayload (Value 'TBool) where
  payloadView _ (LBool True)  = PayloadView (padRightF "Bool" P.++ "True")
  payloadView _ (LBool False) = PayloadView (padRightF "Bool" P.++ "False")

instance TracePayload Index where
  payloadView _ (LInt i) = PayloadView (padRightF "Idx" P.++ P.show i)

instance DecisionLabel kind => TracePayload (Decision kind) where
  payloadView _ (LBool True) =
    PayloadView
      (padRightF (decisionLabel (Proxy :: Proxy kind))
         P.++ decisionTrueLabel (Proxy :: Proxy kind))
  payloadView _ (LBool False) =
    PayloadView
      (padRightF (decisionLabel (Proxy :: Proxy kind))
         P.++ decisionFalseLabel (Proxy :: Proxy kind))

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
  printEvent CreateCellBlock         = "CreateCellBlock"
  printEvent InitCell                = "InitCell"
  printEvent ReadCell                = "ReadCell"
  printEvent WriteCell               = "WriteCell"
  printEvent ReadCellAt              = "ReadCellAt"
  printEvent ReadCellOutOfBounds     = "ReadCellOutOfBounds"
  printEvent WriteCellAt             = "WriteCellAt"
  printEvent WriteCellOutOfBounds    = "WriteCellOutOfBounds"
  printEvent DiscardCell             = "DiscardCell"
  printEvent DiscardCellBlock        = "DiscardCellBlock"
  printEvent Eval                    = "Eval"
  printEvent DiscardValue            = "DiscardValue"
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
