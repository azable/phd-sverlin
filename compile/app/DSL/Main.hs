{-# LANGUAGE ConstraintKinds         #-}
{-# LANGUAGE DataKinds               #-}
{-# LANGUAGE EmptyCase               #-}
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
  , Value
  , Cell
  , Decision
  , CellBlock(..)
  , IntBlock
  , DecisionBlock
  , CompareDecision(..)
  , -- * Event types
    CreateCell(..)
  , SelectKey(..)
  , ReadCell(..)
  , CopyForCompare(..)
  , CompareGreater(..)
  , ShiftRight(..)
  , InsertKey(..)
  , DiscardCell(..)
  , -- * Action-list aliases
    CreateCellActions
  , SelectKeyActions
  , ReadCellActions
  , CopyForCompareActions
  , CompareGreaterActions
  , ShiftRightActions
  , InsertKeyActions
  , DiscardCellActions
  , -- * Constructors / operations
    int
  , createCell
  , selectKey
  , readCell
  , copyForCompare
  , compareGreater
  , shiftRight
  , insertKey
  , discardCell
  , -- * Example
    ExampleEvents
  , insertionSort
  , example
  ) where

import           Control.Functor.Linear hiding ((<$>), (<*>))
import           Data.Kind              (Type)
import           LinearTrace
import           LinearTrace.View

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
data PrimitiveType =
  TInt

data Value (ty :: PrimitiveType)

data Cell

data Decision

type instance Payload (Value 'TInt) = LInt (Value 'TInt)

type instance Payload Cell = LString Cell

type instance Payload Decision = LBool Decision

instance Traceable (Value 'TInt) where
  payloadView _ (LInt value) =
    PayloadView {payloadKind = "Int", payloadContent = P.show value}

instance Traceable Cell where
  payloadView _ (LString name) =
    PayloadView {payloadKind = "Cell", payloadContent = name}

instance Traceable Decision where
  payloadView _ (LBool value) =
    PayloadView
      { payloadKind = "Decision"
      , payloadContent =
          case value of
            True  -> ">"
            False -> "<="
      }

type IntBlock = Block (Value 'TInt)

type DecisionBlock = Block Decision

data CellBlock where
  CellBlock :: Block Cell %1 -> Slot Cell (Value 'TInt) %1 -> CellBlock

data CompareDecision
  = IsGreater
  | IsNotGreater

int :: Int -> Payload (Value 'TInt)
int = LInt

--------------------------------------------------------------------------------
-- Create cell
--------------------------------------------------------------------------------
type CreateCellActions
  = '[ Create (Value 'TInt), Create Cell, Seal Cell (Value 'TInt)]

data CreateCell =
  CreateCell Int String

type instance Actions CreateCell = CreateCellActions

instance Step CreateCell where
  type Input CreateCell = Payload (Value 'TInt)
  type Output CreateCell = CellBlock
  perform (CreateCell _ name) initial = do
    Created valueBlock createValue <- create initial
    Created cellBlock createCellBlock <- create (LString name :: Payload Cell)
    Sealed sealedCell valueSlot sealValue <- seal cellBlock valueBlock
    return
      (Performed
         (CellBlock sealedCell valueSlot)
         (createValue :~ createCellBlock :~ sealValue :~ Done))

createCell ::
     Member CreateCell events
  => Int
  -> String
  -> Payload (Value 'TInt)
     %1 -> Builder events CellBlock
createCell index name = step (CreateCell index name)

instance PrintEvent CreateCell where
  printEvent (CreateCell _ name) = "Create " P.++ name

--------------------------------------------------------------------------------
-- Select key
--------------------------------------------------------------------------------
type SelectKeyActions
  = '[ Unseal Cell (Value 'TInt)
     , Copy (Value 'TInt)
     , Copy (Value 'TInt)
     , Destroy (Value 'TInt)
     , Seal Cell (Value 'TInt)
     ]

data SelectKey =
  SelectKey Int String

type instance Actions SelectKey = SelectKeyActions

instance Step SelectKey where
  type Input SelectKey = CellBlock
  type Output SelectKey = CellBlock :* IntBlock
  perform (SelectKey _ _) (CellBlock cellBlock valueSlot) = do
    Unsealed openedCell heldValue unsealValue <- unseal cellBlock valueSlot
    Copied heldForCell keyForProgram copyKey <- copy heldValue
    Copied keyForProgram' keyPreview copyPreview <- copy keyForProgram
    Destroyed destroyPreview <- destroy keyPreview
    Sealed sealedCell valueSlot' sealValue <- seal openedCell heldForCell
    return
      (Performed
         (CellBlock sealedCell valueSlot' :* keyForProgram')
         (unsealValue
            :~ copyKey
            :~ copyPreview
            :~ destroyPreview
            :~ sealValue
            :~ Done))

selectKey ::
     Member SelectKey events
  => Int
  -> String
  -> CellBlock
     %1 -> Builder events (CellBlock :* IntBlock)
selectKey index label = step (SelectKey index label)

instance PrintEvent SelectKey where
  printEvent (SelectKey _ label) = "Select key " P.++ label

--------------------------------------------------------------------------------
-- Read cell
--------------------------------------------------------------------------------
type ReadCellActions
  = '[ Unseal Cell (Value 'TInt)
     , Copy (Value 'TInt)
     , Copy (Value 'TInt)
     , Destroy (Value 'TInt)
     , Seal Cell (Value 'TInt)
     ]

data ReadCell =
  ReadCell Int String

type instance Actions ReadCell = ReadCellActions

instance Step ReadCell where
  type Input ReadCell = CellBlock
  type Output ReadCell = CellBlock :* IntBlock
  perform (ReadCell _ _) (CellBlock cellBlock valueSlot) = do
    Unsealed openedCell heldValue unsealValue <- unseal cellBlock valueSlot
    Copied heldForCell readForProgram copyRead <- copy heldValue
    Copied readForProgram' readPreview copyPreview <- copy readForProgram
    Destroyed destroyPreview <- destroy readPreview
    Sealed sealedCell valueSlot' sealValue <- seal openedCell heldForCell
    return
      (Performed
         (CellBlock sealedCell valueSlot' :* readForProgram')
         (unsealValue
            :~ copyRead
            :~ copyPreview
            :~ destroyPreview
            :~ sealValue
            :~ Done))

readCell ::
     Member ReadCell events
  => Int
  -> String
  -> CellBlock
     %1 -> Builder events (CellBlock :* IntBlock)
readCell index label = step (ReadCell index label)

instance PrintEvent ReadCell where
  printEvent (ReadCell _ label) = "Read " P.++ label

--------------------------------------------------------------------------------
-- Copy key for comparison
--------------------------------------------------------------------------------
type CopyForCompareActions = '[ Copy (Value 'TInt)]

data CopyForCompare =
  CopyForCompare String

type instance Actions CopyForCompare = CopyForCompareActions

instance Step CopyForCompare where
  type Input CopyForCompare = IntBlock
  type Output CopyForCompare = IntBlock :* IntBlock
  perform (CopyForCompare _) key = do
    Copied key' comparisonKey copyKey <- copy key
    return (Performed (key' :* comparisonKey) (copyKey :~ Done))

copyForCompare ::
     Member CopyForCompare events
  => String
  -> IntBlock
     %1 -> Builder events (IntBlock :* IntBlock)
copyForCompare label = step (CopyForCompare label)

instance PrintEvent CopyForCompare where
  printEvent (CopyForCompare label) = "Copy key for " P.++ label

--------------------------------------------------------------------------------
-- Compare greater-than + decision
--------------------------------------------------------------------------------
type CompareGreaterActions
  = '[ Use (Value 'TInt)
     , Use (Value 'TInt)
     , Compute Decision
     , Decide Decision
     ]

data CompareGreater =
  CompareGreater String

type instance Actions CompareGreater = CompareGreaterActions

instance Step CompareGreater where
  type Input CompareGreater = IntBlock :* IntBlock
  type Output CompareGreater = CompareDecision
  perform (CompareGreater _) (lhsBlock :* rhsBlock) = do
    Used lhsPayload useLhs <- use lhsBlock
    Used rhsPayload useRhs <- use rhsBlock
    Computed decisionBlock computeDecision <-
      compute (greaterThan <$> lhsPayload <*> rhsPayload)
    decision <- decide decisionPayload decisionBlock
    case decision of
      DecidedTrue decideResult ->
        return
          (Performed
             IsGreater
             (useLhs :~ useRhs :~ computeDecision :~ decideResult :~ Done))
      DecidedFalse decideResult ->
        return
          (Performed
             IsNotGreater
             (useLhs :~ useRhs :~ computeDecision :~ decideResult :~ Done))

greaterThan ::
     Payload (Value 'TInt)
     %1 -> Payload (Value 'TInt)
     %1 -> Payload Decision
greaterThan (LInt lhs) (LInt rhs) = LBool (lhs > rhs)

decisionPayload :: Payload Decision %1 -> Bool
decisionPayload (LBool value) = value

compareGreater ::
     Member CompareGreater events
  => String
  -> IntBlock
     %1 -> IntBlock
     %1 -> Builder events CompareDecision
compareGreater label lhs rhs = step (CompareGreater label) (lhs :* rhs)

instance PrintEvent CompareGreater where
  printEvent (CompareGreater label) = "Compare " P.++ label

--------------------------------------------------------------------------------
-- Shift one cell right
--------------------------------------------------------------------------------
type ShiftRightActions
  = '[ Unseal Cell (Value 'TInt)
     , Copy (Value 'TInt)
     , Seal Cell (Value 'TInt)
     , Unseal Cell (Value 'TInt)
     , Replace (Value 'TInt)
     , Seal Cell (Value 'TInt)
     ]

data ShiftRight =
  ShiftRight Int Int String

type instance Actions ShiftRight = ShiftRightActions

instance Step ShiftRight where
  type Input ShiftRight = CellBlock :* CellBlock
  type Output ShiftRight = CellBlock :* CellBlock
  perform (ShiftRight _ _ _) (sourceCell :* targetCell) =
    case sourceCell of
      CellBlock sourceBlock sourceSlot ->
        case targetCell of
          CellBlock targetBlock targetSlot -> do
            Unsealed sourceOpened sourceValue unsealSource <-
              unseal sourceBlock sourceSlot
            Copied sourceStored movingValue copyMoving <- copy sourceValue
            Sealed sourceSealed sourceSlot' sealSource <-
              seal sourceOpened sourceStored
            Unsealed targetOpened targetOldValue unsealTarget <-
              unseal targetBlock targetSlot
            Replaced targetStored replaceTarget <-
              replace targetOldValue movingValue
            Sealed targetSealed targetSlot' sealTarget <-
              seal targetOpened targetStored
            return
              (Performed
                 (CellBlock sourceSealed sourceSlot' :* CellBlock targetSealed targetSlot')
                 (unsealSource
                    :~ copyMoving
                    :~ sealSource
                    :~ unsealTarget
                    :~ replaceTarget
                    :~ sealTarget
                    :~ Done))

shiftRight ::
     Member ShiftRight events
  => Int
  -> Int
  -> String
  -> CellBlock
     %1 -> CellBlock
     %1 -> Builder events (CellBlock :* CellBlock)
shiftRight sourceIndex targetIndex label source target =
  step (ShiftRight sourceIndex targetIndex label) (source :* target)

instance PrintEvent ShiftRight where
  printEvent (ShiftRight _ _ label) = "Shift " P.++ label

--------------------------------------------------------------------------------
-- Insert key
--------------------------------------------------------------------------------
type InsertKeyActions
  = '[ Unseal Cell (Value 'TInt)
     , Replace (Value 'TInt)
     , Seal Cell (Value 'TInt)
     ]

data InsertKey =
  InsertKey Int String

type instance Actions InsertKey = InsertKeyActions

instance Step InsertKey where
  type Input InsertKey = CellBlock :* IntBlock
  type Output InsertKey = CellBlock
  perform (InsertKey _ _) (CellBlock cellBlock valueSlot :* keyValue) = do
    Unsealed openedCell oldValue unsealValue <- unseal cellBlock valueSlot
    Replaced storedValue replaceValue <- replace oldValue keyValue
    Sealed sealedCell valueSlot' sealValue <- seal openedCell storedValue
    return
      (Performed
         (CellBlock sealedCell valueSlot')
         (unsealValue :~ replaceValue :~ sealValue :~ Done))

insertKey ::
     Member InsertKey events
  => Int
  -> String
  -> CellBlock
     %1 -> IntBlock
     %1 -> Builder events CellBlock
insertKey index label cell key = step (InsertKey index label) (cell :* key)

instance PrintEvent InsertKey where
  printEvent (InsertKey _ label) = "Insert " P.++ label

--------------------------------------------------------------------------------
-- Discard cell
--------------------------------------------------------------------------------
type DiscardCellActions
  = '[ Unseal Cell (Value 'TInt), Destroy Cell, Destroy (Value 'TInt)]

data DiscardCell =
  DiscardCell Int String

type instance Actions DiscardCell = DiscardCellActions

instance Step DiscardCell where
  type Input DiscardCell = CellBlock
  type Output DiscardCell = ()
  perform (DiscardCell _ _) (CellBlock cellBlock valueSlot) = do
    Unsealed openedCell heldValue unsealValue <- unseal cellBlock valueSlot
    Destroyed destroyCell <- destroy openedCell
    Destroyed destroyValue <- destroy heldValue
    return (Performed () (unsealValue :~ destroyCell :~ destroyValue :~ Done))

discardCell ::
     Member DiscardCell events
  => Int
  -> String
  -> CellBlock
     %1 -> Builder events ()
discardCell index label = step (DiscardCell index label)

instance PrintEvent DiscardCell where
  printEvent (DiscardCell _ label) = "Discard " P.++ label

--------------------------------------------------------------------------------
-- Fixed-size insertion sort program
--------------------------------------------------------------------------------
type SortEvents events
  = ( Member CreateCell events
    , Member SelectKey events
    , Member ReadCell events
    , Member CopyForCompare events
    , Member CompareGreater events
    , Member ShiftRight events
    , Member InsertKey events
    , Member DiscardCell events)

type ExampleEvents
  = '[ CreateCell
     , SelectKey
     , ReadCell
     , CopyForCompare
     , CompareGreater
     , ShiftRight
     , InsertKey
     , DiscardCell
     ]

example :: Builder ExampleEvents ()
example = insertionSort 5 2 4 6 1 3

insertionSort ::
     SortEvents events
  => Int
  -> Int
  -> Int
  -> Int
  -> Int
  -> Int
  -> Builder events ()
insertionSort v0 v1 v2 v3 v4 v5 = do
  cell0a <- createCell 0 "a[0]" (int v0)
  cell1a <- createCell 1 "a[1]" (int v1)
  cell2a <- createCell 2 "a[2]" (int v2)
  cell3a <- createCell 3 "a[3]" (int v3)
  cell4a <- createCell 4 "a[4]" (int v4)
  cell5a <- createCell 5 "a[5]" (int v5)
  cell0b :* cell1b <- pass1 cell0a cell1a
  cell0c :* cell1c :* cell2b <- pass2 cell0b cell1b cell2a
  cell0d :* cell1d :* cell2c :* cell3b <- pass3 cell0c cell1c cell2b cell3a
  cell0e :* cell1e :* cell2d :* cell3c :* cell4b <-
    pass4 cell0d cell1d cell2c cell3b cell4a
  cell0f :* cell1f :* cell2e :* cell3d :* cell4c :* cell5b <-
    pass5 cell0e cell1e cell2d cell3c cell4b cell5a
  discardCell 0 "a[0]" cell0f
  discardCell 1 "a[1]" cell1f
  discardCell 2 "a[2]" cell2e
  discardCell 3 "a[3]" cell3d
  discardCell 4 "a[4]" cell4c
  discardCell 5 "a[5]" cell5b

compareCellWithKey ::
     ( Member ReadCell events
     , Member CopyForCompare events
     , Member CompareGreater events
     )
  => Int
  -> String
  -> String
  -> CellBlock
     %1 -> IntBlock
     %1 -> Builder events (CompareDecision :* CellBlock :* IntBlock)
compareCellWithKey index cellLabel comparisonLabel cell0 key0 = do
  key1 :* keyForCompare <- copyForCompare comparisonLabel key0
  cell1 :* cellValue <- readCell index cellLabel cell0
  decision <- compareGreater comparisonLabel cellValue keyForCompare
  return (decision :* cell1 :* key1)

pass1 ::
     SortEvents events
  => CellBlock
     %1 -> CellBlock
     %1 -> Builder events (CellBlock :* CellBlock)
pass1 cell0a cell1a = do
  cell1b :* key0 <- selectKey 1 "i=1, key=a[1]" cell1a
  decision0 :* cell0b :* key1 <-
    compareCellWithKey 0 "a[0]" "a[0] > key" cell0a key0
  case decision0 of
    IsGreater -> do
      cell0c :* cell1c <- shiftRight 0 1 "a[1] <- a[0]" cell0b cell1b
      cell0d <- insertKey 0 "a[0] <- key" cell0c key1
      return (cell0d :* cell1c)
    IsNotGreater -> do
      cell1c <- insertKey 1 "a[1] <- key" cell1b key1
      return (cell0b :* cell1c)

pass2 ::
     SortEvents events
  => CellBlock
     %1 -> CellBlock
     %1 -> CellBlock
     %1 -> Builder events (CellBlock :* CellBlock :* CellBlock)
pass2 cell0a cell1a cell2a = do
  cell2b :* key0 <- selectKey 2 "i=2, key=a[2]" cell2a
  decision0 :* cell1b :* key1 <-
    compareCellWithKey 1 "a[1]" "a[1] > key" cell1a key0
  case decision0 of
    IsNotGreater -> do
      cell2c <- insertKey 2 "a[2] <- key" cell2b key1
      return (cell0a :* cell1b :* cell2c)
    IsGreater -> do
      cell1c :* cell2c <- shiftRight 1 2 "a[2] <- a[1]" cell1b cell2b
      decision1 :* cell0b :* key2 <-
        compareCellWithKey 0 "a[0]" "a[0] > key" cell0a key1
      case decision1 of
        IsGreater -> do
          cell0c :* cell1d <- shiftRight 0 1 "a[1] <- a[0]" cell0b cell1c
          cell0d <- insertKey 0 "a[0] <- key" cell0c key2
          return (cell0d :* cell1d :* cell2c)
        IsNotGreater -> do
          cell1d <- insertKey 1 "a[1] <- key" cell1c key2
          return (cell0b :* cell1d :* cell2c)

pass3 ::
     SortEvents events
  => CellBlock
     %1 -> CellBlock
     %1 -> CellBlock
     %1 -> CellBlock
     %1 -> Builder events (CellBlock :* CellBlock :* CellBlock :* CellBlock)
pass3 cell0a cell1a cell2a cell3a = do
  cell3b :* key0 <- selectKey 3 "i=3, key=a[3]" cell3a
  decision0 :* cell2b :* key1 <-
    compareCellWithKey 2 "a[2]" "a[2] > key" cell2a key0
  case decision0 of
    IsNotGreater -> do
      cell3c <- insertKey 3 "a[3] <- key" cell3b key1
      return (cell0a :* cell1a :* cell2b :* cell3c)
    IsGreater -> do
      cell2c :* cell3c <- shiftRight 2 3 "a[3] <- a[2]" cell2b cell3b
      decision1 :* cell1b :* key2 <-
        compareCellWithKey 1 "a[1]" "a[1] > key" cell1a key1
      case decision1 of
        IsNotGreater -> do
          cell2d <- insertKey 2 "a[2] <- key" cell2c key2
          return (cell0a :* cell1b :* cell2d :* cell3c)
        IsGreater -> do
          cell1c :* cell2d <- shiftRight 1 2 "a[2] <- a[1]" cell1b cell2c
          decision2 :* cell0b :* key3 <-
            compareCellWithKey 0 "a[0]" "a[0] > key" cell0a key2
          case decision2 of
            IsGreater -> do
              cell0c :* cell1d <- shiftRight 0 1 "a[1] <- a[0]" cell0b cell1c
              cell0d <- insertKey 0 "a[0] <- key" cell0c key3
              return (cell0d :* cell1d :* cell2d :* cell3c)
            IsNotGreater -> do
              cell1d <- insertKey 1 "a[1] <- key" cell1c key3
              return (cell0b :* cell1d :* cell2d :* cell3c)

pass4 ::
     SortEvents events
  => CellBlock
     %1 -> CellBlock
     %1 -> CellBlock
     %1 -> CellBlock
     %1 -> CellBlock
     %1 -> Builder
       events
       (CellBlock :* CellBlock :* CellBlock :* CellBlock :* CellBlock)
pass4 cell0a cell1a cell2a cell3a cell4a = do
  cell4b :* key0 <- selectKey 4 "i=4, key=a[4]" cell4a
  decision0 :* cell3b :* key1 <-
    compareCellWithKey 3 "a[3]" "a[3] > key" cell3a key0
  case decision0 of
    IsNotGreater -> do
      cell4c <- insertKey 4 "a[4] <- key" cell4b key1
      return (cell0a :* cell1a :* cell2a :* cell3b :* cell4c)
    IsGreater -> do
      cell3c :* cell4c <- shiftRight 3 4 "a[4] <- a[3]" cell3b cell4b
      decision1 :* cell2b :* key2 <-
        compareCellWithKey 2 "a[2]" "a[2] > key" cell2a key1
      case decision1 of
        IsNotGreater -> do
          cell3d <- insertKey 3 "a[3] <- key" cell3c key2
          return (cell0a :* cell1a :* cell2b :* cell3d :* cell4c)
        IsGreater -> do
          cell2c :* cell3d <- shiftRight 2 3 "a[3] <- a[2]" cell2b cell3c
          decision2 :* cell1b :* key3 <-
            compareCellWithKey 1 "a[1]" "a[1] > key" cell1a key2
          case decision2 of
            IsNotGreater -> do
              cell2d <- insertKey 2 "a[2] <- key" cell2c key3
              return (cell0a :* cell1b :* cell2d :* cell3d :* cell4c)
            IsGreater -> do
              cell1c :* cell2d <- shiftRight 1 2 "a[2] <- a[1]" cell1b cell2c
              decision3 :* cell0b :* key4 <-
                compareCellWithKey 0 "a[0]" "a[0] > key" cell0a key3
              case decision3 of
                IsGreater -> do
                  cell0c :* cell1d <-
                    shiftRight 0 1 "a[1] <- a[0]" cell0b cell1c
                  cell0d <- insertKey 0 "a[0] <- key" cell0c key4
                  return (cell0d :* cell1d :* cell2d :* cell3d :* cell4c)
                IsNotGreater -> do
                  cell1d <- insertKey 1 "a[1] <- key" cell1c key4
                  return (cell0b :* cell1d :* cell2d :* cell3d :* cell4c)

pass5 ::
     SortEvents events
  => CellBlock
     %1 -> CellBlock
     %1 -> CellBlock
     %1 -> CellBlock
     %1 -> CellBlock
     %1 -> CellBlock
     %1 -> Builder
       events
       (CellBlock :* CellBlock :* CellBlock :* CellBlock :* CellBlock :* CellBlock)
pass5 cell0a cell1a cell2a cell3a cell4a cell5a = do
  cell5b :* key0 <- selectKey 5 "i=5, key=a[5]" cell5a
  decision0 :* cell4b :* key1 <-
    compareCellWithKey 4 "a[4]" "a[4] > key" cell4a key0
  case decision0 of
    IsNotGreater -> do
      cell5c <- insertKey 5 "a[5] <- key" cell5b key1
      return (cell0a :* cell1a :* cell2a :* cell3a :* cell4b :* cell5c)
    IsGreater -> do
      cell4c :* cell5c <- shiftRight 4 5 "a[5] <- a[4]" cell4b cell5b
      decision1 :* cell3b :* key2 <-
        compareCellWithKey 3 "a[3]" "a[3] > key" cell3a key1
      case decision1 of
        IsNotGreater -> do
          cell4d <- insertKey 4 "a[4] <- key" cell4c key2
          return (cell0a :* cell1a :* cell2a :* cell3b :* cell4d :* cell5c)
        IsGreater -> do
          cell3c :* cell4d <- shiftRight 3 4 "a[4] <- a[3]" cell3b cell4c
          decision2 :* cell2b :* key3 <-
            compareCellWithKey 2 "a[2]" "a[2] > key" cell2a key2
          case decision2 of
            IsNotGreater -> do
              cell3d <- insertKey 3 "a[3] <- key" cell3c key3
              return
                (cell0a :* cell1a :* cell2b :* cell3d :* cell4d :* cell5c)
            IsGreater -> do
              cell2c :* cell3d <-
                shiftRight 2 3 "a[3] <- a[2]" cell2b cell3c
              decision3 :* cell1b :* key4 <-
                compareCellWithKey 1 "a[1]" "a[1] > key" cell1a key3
              case decision3 of
                IsNotGreater -> do
                  cell2d <- insertKey 2 "a[2] <- key" cell2c key4
                  return
                    (cell0a :* cell1b :* cell2d :* cell3d :* cell4d :* cell5c)
                IsGreater -> do
                  cell1c :* cell2d <-
                    shiftRight 1 2 "a[2] <- a[1]" cell1b cell2c
                  decision4 :* cell0b :* key5 <-
                    compareCellWithKey 0 "a[0]" "a[0] > key" cell0a key4
                  case decision4 of
                    IsGreater -> do
                      cell0c :* cell1d <-
                        shiftRight 0 1 "a[1] <- a[0]" cell0b cell1c
                      cell0d <- insertKey 0 "a[0] <- key" cell0c key5
                      return
                        (cell0d
                           :* cell1d
                           :* cell2d
                           :* cell3d
                           :* cell4d
                           :* cell5c)
                    IsNotGreater -> do
                      cell1d <- insertKey 1 "a[1] <- key" cell1c key5
                      return
                        (cell0b
                           :* cell1d
                           :* cell2d
                           :* cell3d
                           :* cell4d
                           :* cell5c)

--------------------------------------------------------------------------------
-- Block visualisation
--------------------------------------------------------------------------------
valueSize :: LayoutExpr
valueSize = num 70

cellSize :: LayoutExpr
cellSize = num 116

decisionWidth :: LayoutExpr
decisionWidth = num 112

decisionHeight :: LayoutExpr
decisionHeight = num 58

arrayTop :: LayoutExpr
arrayTop = num 250

keyTop :: LayoutExpr
keyTop = num 112

readTop :: LayoutExpr
readTop = num 382

compareTop :: LayoutExpr
compareTop = num 458

compareLeft :: LayoutExpr
compareLeft = num 210

cellGap :: Double
cellGap = 124

arrayLeftFor :: Int -> LayoutExpr
arrayLeftFor index = num (48 P.+ P.fromIntegral index P.* cellGap)

black :: HslExpr
black = Hsl {hue = num 0, saturation = num 0, lightness = num 0}

intFill :: HslExpr
intFill =
  Hsl
    { hue = global "int.hue"
    , saturation = global "int.saturation"
    , lightness = global "int.lightness"
    }

cellFill :: HslExpr
cellFill =
  Hsl
    { hue = global "cell.hue"
    , saturation = global "cell.saturation"
    , lightness = global "cell.lightness"
    }

decisionFill :: HslExpr
decisionFill =
  Hsl
    { hue = global "decision.hue"
    , saturation = global "decision.saturation"
    , lightness = global "decision.lightness"
    }

fixedSize ::
     HasBounds block
  => LayoutExpr
  -> LayoutExpr
  -> block
  -> ViewBuilder events ()
fixedSize w h block = do
  ensure $ width block @==@ w
  ensure $ height block @==@ h

square :: HasBounds block => LayoutExpr -> block -> ViewBuilder events ()
square size' = fixedSize size' size'

fixedRadius :: HasStyle block => LayoutExpr -> block -> ViewBuilder events ()
fixedRadius value block = ensure $ radius block @==@ value

fixedFontSize :: HasStyle block => LayoutExpr -> block -> ViewBuilder events ()
fixedFontSize value block = ensure $ fontSize block @==@ value

fixedStrokeWidth :: HasStyle block => LayoutExpr -> block -> ViewBuilder events ()
fixedStrokeWidth value block = ensure $ strokeWidth block @==@ value

fixedOpacity :: HasStyle block => UnitExpr -> block -> ViewBuilder events ()
fixedOpacity value block = do
  ensure $ opacity block @==@ value
  ensure $ alpha block @==@ value

colourRange ::
     HslExpr
  -> AngleExpr
  -> AngleExpr
  -> UnitExpr
  -> UnitExpr
  -> UnitExpr
  -> UnitExpr
  -> ViewBuilder events ()
colourRange colour minHue maxHue minSaturation maxSaturation minLightness maxLightness = do
  between minHue (hue colour) maxHue
  between minSaturation (saturation colour) maxSaturation
  between minLightness (lightness colour) maxLightness

midX :: HasBounds block => block -> LayoutExpr
midX block = left block @+@ width block @/@ num 2

bottomEdge :: HasBounds block => block -> LayoutExpr
bottomEdge block = top block @+@ height block

pinCell :: HasBounds block => Int -> block -> ViewBuilder events ()
pinCell index block = do
  ensure $ left block @==@ arrayLeftFor index
  ensure $ top block @==@ arrayTop

placeInCell ::
     (HasBounds value, HasBounds cell) => value -> cell -> ViewBuilder events ()
placeInCell value cell = ensure $ center value @==@ center cell

placeKeyAboveCell ::
     (HasBounds value, HasBounds cell) => value -> cell -> ViewBuilder events ()
placeKeyAboveCell value cell = do
  ensure $ midX value @==@ midX cell
  ensure $ top value @==@ keyTop
  ensure $ bottomEdge value @<=@ top cell

placeReadBelowCell ::
     (HasBounds value, HasBounds cell) => value -> cell -> ViewBuilder events ()
placeReadBelowCell value cell = do
  ensure $ midX value @==@ midX cell
  ensure $ top value @==@ readTop
  ensure $ bottomEdge cell @<=@ top value

placeCompareStart :: HasBounds value => value -> ViewBuilder events ()
placeCompareStart value = do
  ensure $ left value @==@ compareLeft
  ensure $ top value @==@ compareTop

intStyle :: Style -> Style
intStyle =
  setFill intFill
    P.. setStroke black
    P.. setStrokeWidth (num 3)
    P.. setRadius (num 35)
    P.. setFontSize (num 34)
    P.. setFontFamily "Verdana"
    P.. setFontWeight FontWeightBold
    P.. setTextAlign TextAlignCenter
    P.. setWhiteSpace WhiteSpaceNoWrap
    P.. setBorderStyle BorderSolid
    P.. setOpacity (num 1)
    P.. setAlpha (num 1)
    P.. setZIndex (num 3)

cellStyle :: Style -> Style
cellStyle =
  setFill cellFill
    P.. setStroke black
    P.. setStrokeWidth (num 2)
    P.. setRadius (num 16)
    P.. setFontSize (num 24)
    P.. setFontFamily "Verdana"
    P.. setFontWeight FontWeightBold
    P.. setTextAlign TextAlignCenter
    P.. setWhiteSpace WhiteSpaceNoWrap
    P.. setBorderStyle BorderSolid
    P.. setOpacity (num 1)
    P.. setAlpha (num 0.78)
    P.. setZIndex (num 1)

decisionStyle :: Style -> Style
decisionStyle =
  setFill decisionFill
    P.. setStroke black
    P.. setStrokeWidth (num 3)
    P.. setRadius (num 14)
    P.. setFontSize (num 24)
    P.. setFontFamily "Verdana"
    P.. setFontWeight FontWeightBold
    P.. setTextAlign TextAlignCenter
    P.. setWhiteSpace WhiteSpaceNoWrap
    P.. setBorderStyle BorderSolid
    P.. setOpacity (num 1)
    P.. setAlpha (num 1)
    P.. setZIndex (num 4)

intBlockV :: BlockView tag -> ViewBuilder events ()
intBlockV block = do
  square valueSize block
  fixedRadius (num 35) block
  fixedFontSize (num 34) block
  fixedStrokeWidth (num 3) block
  fixedOpacity (num 1) block
  colourRange intFill (num 205) (num 320) (num 0.58) (num 0.9) (num 0.42) (num 0.64)

cellBlockV :: BlockView tag -> ViewBuilder events ()
cellBlockV block = do
  square cellSize block
  fixedRadius (num 16) block
  fixedFontSize (num 24) block
  fixedStrokeWidth (num 2) block
  ensure $ opacity block @==@ num 1
  ensure $ alpha block @==@ num 0.78
  colourRange cellFill (num 75) (num 170) (num 0.1) (num 0.36) (num 0.82) (num 0.98)

decisionBlockV :: BlockView tag -> ViewBuilder events ()
decisionBlockV block = do
  fixedSize decisionWidth decisionHeight block
  fixedRadius (num 14) block
  fixedFontSize (num 24) block
  fixedStrokeWidth (num 3) block
  fixedOpacity (num 1) block
  colourRange decisionFill (num 20) (num 58) (num 0.62) (num 0.92) (num 0.44) (num 0.68)

instance ViewBlock (Value 'TInt) where
  styleBlock _ = intStyle
  viewBlock = intBlockV

instance ViewBlock Cell where
  styleBlock _ = cellStyle
  viewBlock = cellBlockV

instance ViewBlock Decision where
  styleBlock _ = decisionStyle
  viewBlock = decisionBlockV

--------------------------------------------------------------------------------
-- Event visualisation
--------------------------------------------------------------------------------
instance ViewEvent CreateCell where
  viewEvent (CreateCell index _) tokens =
    case tokens of
      VCons createValue (VCons createCellBlock (VCons sealValue VNil)) -> do
        Ur value0 <- createVisual createValue
        Ur cell0 <- createVisual createCellBlock
        Ur value <- fresh value0
        Ur cell <- fresh cell0
        Ur (_sealedCell, _sealedValue) <- sealVisual sealValue
        pinCell index cell
        placeInCell value cell

instance ViewEvent SelectKey where
  viewEvent (SelectKey index _) tokens =
    case tokens of
      VCons unsealValue
        (VCons copyKey
          (VCons copyPreview
            (VCons destroyPreview
              (VCons sealValue VNil)))) -> do
          Ur (cell, _held) <- unsealVisual unsealValue
          Ur (heldForCell, keyForProgram0) <- copyVisual copyKey
          Ur keyForProgram <- forkFrom heldForCell keyForProgram0
          Ur (_keyForProgram', keyPreview0) <- copyVisual copyPreview
          Ur keyPreview <- forkFrom keyForProgram keyPreview0
          Ur previewToDestroy <- destroyVisual destroyPreview
          Ur (_sealedCell, _sealedValue) <- sealVisual sealValue
          pinCell index cell
          placeInCell heldForCell cell
          ensure $ width keyForProgram @==@ valueSize
          placeKeyAboveCell keyPreview cell
          remove previewToDestroy

instance ViewEvent ReadCell where
  viewEvent (ReadCell index _) tokens =
    case tokens of
      VCons unsealValue
        (VCons copyRead
          (VCons copyPreview
            (VCons destroyPreview
              (VCons sealValue VNil)))) -> do
          Ur (cell, _held) <- unsealVisual unsealValue
          Ur (heldForCell, readForProgram0) <- copyVisual copyRead
          Ur readForProgram <- forkFrom heldForCell readForProgram0
          Ur (_readForProgram', readPreview0) <- copyVisual copyPreview
          Ur readPreview <- forkFrom readForProgram readPreview0
          Ur previewToDestroy <- destroyVisual destroyPreview
          Ur (_sealedCell, _sealedValue) <- sealVisual sealValue
          pinCell index cell
          placeInCell heldForCell cell
          ensure $ width readForProgram @==@ valueSize
          placeReadBelowCell readPreview cell
          remove previewToDestroy

instance ViewEvent CopyForCompare where
  viewEvent (CopyForCompare _) tokens =
    case tokens of
      VCons copyKey VNil -> do
        Ur (key, comparisonKey0) <- copyVisual copyKey
        Ur comparisonKey <- forkFrom key comparisonKey0
        discard comparisonKey

instance ViewEvent CompareGreater where
  viewEvent (CompareGreater _) tokens =
    case tokens of
      VCons useLhs
        (VCons useRhs
          (VCons computeDecision
            (VCons decideResult VNil))) -> do
        Ur lhs <- useVisual useLhs
        Ur rhs <- useVisual useRhs
        Ur result0 <- computeVisual computeDecision
        Ur result <- fresh result0
        Ur decision <- decideVisual decideResult
        placeCompareStart lhs
        besideWithGap (num 24) lhs rhs
        besideWithGap (num 24) rhs result
        ensure $ centerY lhs @==@ centerY rhs
        ensure $ centerY rhs @==@ centerY result
        discard decision
        remove lhs
        remove rhs

instance ViewEvent ShiftRight where
  viewEvent (ShiftRight sourceIndex targetIndex _) tokens =
    case tokens of
      VCons unsealSource
        (VCons copySource
          (VCons sealSource
            (VCons unsealTarget
              (VCons replaceTarget
                (VCons sealTarget VNil))))) -> do
          Ur (sourceCell, _sourceValue) <- unsealVisual unsealSource
          Ur (sourceStored, movingValue0) <- copyVisual copySource
          Ur movingValue <- forkFrom sourceStored movingValue0
          Ur (_sealedSource, _sealedSourceValue) <- sealVisual sealSource
          Ur (targetCell, _targetOld) <- unsealVisual unsealTarget
          Ur (oldValue, incomingValue, targetStored0) <- replaceVisual replaceTarget
          Ur targetStored <- continueFrom incomingValue targetStored0
          Ur (_sealedTarget, _sealedTargetValue) <- sealVisual sealTarget
          pinCell sourceIndex sourceCell
          pinCell targetIndex targetCell
          placeInCell sourceStored sourceCell
          placeKeyAboveCell movingValue targetCell
          placeInCell targetStored targetCell
          remove oldValue

instance ViewEvent InsertKey where
  viewEvent (InsertKey index _) tokens =
    case tokens of
      VCons unsealCell
        (VCons replaceCell
          (VCons sealCell VNil)) -> do
          Ur (cell, _oldValue) <- unsealVisual unsealCell
          Ur (old, incoming, stored0) <- replaceVisual replaceCell
          Ur stored <- continueFrom incoming stored0
          Ur (_sealedCell, _sealedValue) <- sealVisual sealCell
          pinCell index cell
          placeKeyAboveCell incoming cell
          placeInCell stored cell
          remove old

instance ViewEvent DiscardCell where
  viewEvent (DiscardCell index _) tokens =
    case tokens of
      VCons unsealCell
        (VCons destroyValue
          (VCons destroyCell VNil)) -> do
        Ur (cell, value) <- unsealVisual unsealCell
        Ur valueToDestroy <- destroyVisual destroyValue
        Ur cellToDestroy <- destroyVisual destroyCell
        pinCell index cell
        placeInCell value cell
        remove valueToDestroy
        remove cellToDestroy
