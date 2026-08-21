{-# LANGUAGE ConstraintKinds         #-}
{-# LANGUAGE FlexibleContexts        #-}
{-# LANGUAGE FlexibleInstances       #-}
{-# LANGUAGE FunctionalDependencies  #-}
{-# LANGUAGE GADTs                   #-}
{-# LANGUAGE LinearTypes             #-}
{-# LANGUAGE RebindableSyntax        #-}
{-# LANGUAGE ScopedTypeVariables     #-}
{-# LANGUAGE TypeFamilyDependencies  #-}
{-# LANGUAGE UndecidableInstances    #-}
{-# LANGUAGE UndecidableSuperClasses #-}

-- | Implementation surface for the linear trace core. This module is package
-- internal in Cabal; it is imported by the stable 'LinearTrace.Core' facade,
-- the event projection layer where the full graph state is required.
module LinearTrace.Core.Internal
  ( -- * Core public API data
    -- | Trace graph, builder, payload, fact, and traceable definitions. The
    -- public 'LinearTrace.Core' module re-exports the stable subset of these.
    TraceGraph
  , TraceBuilder
  , Block
  , Slot
  , Payload
  , FactValue(..)
  , Fact(..)
  , Facts(..)
  , emptyFacts
  , factAtom
  , factSymbol
  , factInt
  , factsUnion
  , factsToList
  , PayloadView(..)
  , payloadText
  , Traceable
  , -- * Trusted linear payloads
    -- | Built-in linearly tracked payload wrappers shared by core,
    -- choreography, examples, and tests.
    LUnit(..)
  , LBool(..)
  , LInt(..)
  , LDouble(..)
  , LString(..)
  , LOperator(..)
  , CoreOperator(..)
  , LinearPayload(..)
  , applyLinear1
  , applyLinear1Into
  , applyLinear2
  , applyLinear2Into
  , Applicable1(..)
  , Applicable2(..)
  , -- * Primitive operations
    -- | Primitive linear operations that update core builder state and produce
    -- pending block obligations. Higher layers call these through the public
    -- core facade.
    Pending
  , create
  , observe
  , use
  , copy
  , replace
  , apply1
  , apply2
  , materialize
  , materializeTagged
  , materializeTaggedWith
  , commit
  , destroy
  , seal
  , unseal
  , -- * Operation results
    -- | Result wrappers and linear one-use payload helpers.
    OneUse(..)
  , Create(..)
  , Observe(..)
  , Use(..)
  , Copy(..)
  , Replace(..)
  , Apply1(..)
  , Apply2(..)
  , Destroy(..)
  , Seal(..)
  , Unseal(..)
  , (<$>)
  , (<*>)
  , -- * Public graph/step data
    -- | Full graph state and step records needed by event projection. These
    -- remain internal to the package-level public API.
    BlockId
  , BlockRef(..)
  , blockRefId
  , BlockSnapshot(..)
  , blockSnapshotRef
  , blockSnapshotPayload
  , blockSnapshotPayloadView
  , blockSnapshotFacts
  , withBlockSnapshot
  , TraceStep
  , TraceEvents(..)
  , emptyTraceEvents
  , foldTraceEvents
  , PendingEvents(..)
  , emptyPendingEvents
  , traceGraphPendingEvents
  , traceGraphSteps
  , traceStepEvents
  , foldTraceStep
  , -- * Public trace event data
    -- | Trace event data consumed by event projection and choreography.
    TraceEvent(..)
  , -- * Runner
    -- | Core runners and graph builders. The choreography layer uses related
    -- stateful machinery to build core and view output together.
    checkpoint
  , buildGraph
  ) where

import           Control.Functor.Linear hiding (ask, (<$>), (<*>))
import           Data.Kind              (Type)
import           Data.Proxy             (Proxy (..))
import           Data.Typeable          (Typeable, typeRep)
import qualified Prelude                as P
import           Prelude.Linear

infixl 4 <$>
infixl 4 <*>
type BlockId = Int

type family Payload tag = payload | payload -> tag

newtype PayloadView = PayloadView
  { payloadKind :: P.String
  }

data FactValue
  = FactAtom
  | FactSymbol P.String
  | FactInt Int
  deriving (P.Eq, P.Ord, P.Show)

data Fact =
  Fact P.String FactValue
  deriving (P.Eq, P.Ord, P.Show)

newtype Facts =
  Facts [Fact]
  deriving (P.Eq, P.Ord, P.Show)

emptyFacts :: Facts
emptyFacts = Facts []

factAtom :: P.String -> Fact
factAtom name = Fact name FactAtom

factSymbol :: P.String -> P.String -> Fact
factSymbol name value = Fact name (FactSymbol value)

factInt :: P.String -> Int -> Fact
factInt name value = Fact name (FactInt value)

factsUnion :: Facts -> Facts -> Facts
factsUnion (Facts leftFacts) (Facts rightFacts) =
  Facts (dedupeFacts (leftFacts P.++ rightFacts))

factsToList :: Facts -> [Fact]
factsToList (Facts values) = values

dedupeFacts :: [Fact] -> [Fact]
dedupeFacts [] = []
dedupeFacts (fact:rest) =
  case fact `P.elem` rest of
    True  -> dedupeFacts rest
    False -> fact : dedupeFacts rest

-- Deliberately not exported.
--
-- Downstream DSLs can use LinearTrace-approved payload wrappers, but cannot
-- define new approved payload classes of their own. Core payloads are trusted
-- value payloads that may be persisted into blocks and audit snapshots.
class CorePayload payload where
  corePayloadText :: payload -> P.String
  persistCorePayload :: payload %1 -> Ur payload

data LUnit tag where
  LUnit :: LUnit tag

data LInt tag where
  LInt :: Int %1 -> LInt tag

data LBool tag where
  LBool :: Bool %1 -> LBool tag

data LDouble tag where
  LDouble :: Double %1 -> LDouble tag

data LString tag where
  LString :: P.String %1 -> LString tag

data LOperator operator tag where
  LOperator :: operator %1 -> LOperator operator tag

class CoreOperator operator where
  operatorPayloadText :: operator -> P.String
  persistOperatorPayload :: operator %1 -> Ur operator

class LinearPayload payload value | payload -> value where
  withPayload :: payload %1 -> (value %1 -> result) %1 -> result
  buildPayload :: value %1 -> payload

applyLinear1 ::
     LinearPayload payload value => (value %1 -> output) -> payload %1 -> output
applyLinear1 f payload = withPayload payload f

applyLinear1Into ::
     (LinearPayload input inputValue, LinearPayload output outputValue)
  => (inputValue %1 -> outputValue)
  -> input
     %1 -> output
applyLinear1Into f = applyLinear1 (linearBuild1 f)

linearBuild1 ::
     LinearPayload output outputValue
  => (inputValue %1 -> outputValue)
  -> inputValue
     %1 -> output
linearBuild1 f value = buildPayload (f value)

applyLinear2 ::
     (LinearPayload lhs lhsValue, LinearPayload rhs rhsValue)
  => (lhsValue %1 -> rhsValue %1 -> output)
  -> lhs
     %1 -> rhs
     %1 -> output
applyLinear2 f lhs rhs = withPayload lhs (applyLinear2Right f rhs)

applyLinear2Right ::
     LinearPayload rhs rhsValue
  => (lhsValue %1 -> rhsValue %1 -> output)
  -> rhs
     %1 -> lhsValue
     %1 -> output
applyLinear2Right f rhs lhsValue = withPayload rhs (f lhsValue)

applyLinear2Into ::
     ( LinearPayload lhs lhsValue
     , LinearPayload rhs rhsValue
     , LinearPayload output outputValue
     )
  => (lhsValue %1 -> rhsValue %1 -> outputValue)
  -> lhs
     %1 -> rhs
     %1 -> output
applyLinear2Into f = applyLinear2 (linearBuild2 f)

linearBuild2 ::
     LinearPayload output outputValue
  => (lhsValue %1 -> rhsValue %1 -> outputValue)
  -> lhsValue
     %1 -> rhsValue
     %1 -> output
linearBuild2 f lhsValue rhsValue = buildPayload (f lhsValue rhsValue)

instance CorePayload (LUnit tag) where
  corePayloadText LUnit = "()"
  persistCorePayload LUnit = Ur LUnit

instance CorePayload (LBool tag) where
  corePayloadText (LBool value) = P.show value
  persistCorePayload (LBool value) =
    case move value of
      Ur moved -> Ur (LBool moved)

instance CorePayload (LInt tag) where
  corePayloadText (LInt value) = P.show value
  persistCorePayload (LInt value) =
    case move value of
      Ur moved -> Ur (LInt moved)

instance CorePayload (LDouble tag) where
  corePayloadText (LDouble value) = P.show value
  persistCorePayload (LDouble value) =
    case move value of
      Ur moved -> Ur (LDouble moved)

instance CorePayload (LString tag) where
  corePayloadText (LString value) = value
  persistCorePayload (LString value) =
    case move value of
      Ur moved -> Ur (LString moved)

instance CoreOperator operator => CorePayload (LOperator operator tag) where
  corePayloadText (LOperator operator) = operatorPayloadText operator
  persistCorePayload (LOperator operator) =
    case persistOperatorPayload operator of
      Ur moved -> Ur (LOperator moved)

instance LinearPayload (LUnit tag) () where
  withPayload LUnit k = k ()
  buildPayload () = LUnit

instance LinearPayload (LBool tag) Bool where
  withPayload (LBool value) k = k value
  buildPayload = LBool

instance LinearPayload (LInt tag) Int where
  withPayload (LInt value) k = k value
  buildPayload = LInt

instance LinearPayload (LDouble tag) Double where
  withPayload (LDouble value) k = k value
  buildPayload = LDouble

instance LinearPayload (LString tag) P.String where
  withPayload (LString value) k = k value
  buildPayload = LString

instance LinearPayload (LOperator operator tag) operator where
  withPayload (LOperator operator) k = k operator
  buildPayload = LOperator

class (CorePayload (Payload tag), Typeable tag) =>
      Traceable tag

instance (CorePayload (Payload tag), Typeable tag) => Traceable tag

payloadView :: Traceable tag => Proxy tag -> PayloadView
payloadView tagProxy = PayloadView {payloadKind = P.show (typeRep tagProxy)}

payloadText :: Traceable tag => Payload tag -> P.String
payloadText = corePayloadText

class Applicable1 op arg where
  type Apply1Result op arg :: Type
  applyPayload1 ::
       Payload op %1 -> Payload arg %1 -> Payload (Apply1Result op arg)

class Applicable2 op lhs rhs where
  type Apply2Result op lhs rhs :: Type
  applyPayload2 ::
       Payload op
       %1 -> Payload lhs
       %1 -> Payload rhs
       %1 -> Payload (Apply2Result op lhs rhs)

data OneUse a where
  OneUse :: a %1 -> OneUse a

(<$>) :: (a %1 -> b) %1 -> OneUse a %1 -> OneUse b
f <$> OneUse x = OneUse (f x)

(<*>) :: OneUse (a %1 -> b) %1 -> OneUse a %1 -> OneUse b
OneUse f <*> OneUse x = OneUse (f x)

data BlockRef tag where
  BlockRef :: BlockId -> BlockRef tag

data Block tag where
  Block :: Ur BlockId %1 -> Ur (Payload tag) %1 -> Ur Facts %1 -> Block tag

-- | A sealed block of type @tag@ owned by an owner type @owner@.
--
-- The constructor is intentionally not exported. Users can hold slots, but
-- cannot extract the hidden block except through 'unseal'.
data Slot owner tag where
  Slot :: Block tag %1 -> Slot owner tag

data BlockSnapshot tag where
  BlockSnapshot
    :: Traceable tag=> BlockRef tag
    -> Payload tag
    -> PayloadView
    -> Facts
    -> BlockSnapshot tag

--------------------------------------------------------------------------------
-- Primitive operation result types
--------------------------------------------------------------------------------
data Pending tag where
  Pending
    :: Payload tag %1 -> Ur (BlockSnapshot tag -> TraceEvent) %1 -> Pending tag

data Create tag where
  Create :: Pending tag %1 -> Create tag

data Observe tag where
  Observe :: Block tag %1 -> Observe tag

data Use tag where
  Use :: OneUse (Payload tag) %1 -> Use tag

data Copy tag where
  Copy :: Block tag %1 -> Pending tag %1 -> Copy tag

data Replace tag where
  Replace :: Pending tag %1 -> Replace tag

data Apply1 op arg where
  Apply1 :: Pending (Apply1Result op arg) %1 -> Apply1 op arg

data Apply2 op lhs rhs where
  Apply2 :: Pending (Apply2Result op lhs rhs) %1 -> Apply2 op lhs rhs

data Destroy tag where
  Destroy :: Destroy tag

data Seal owner tag where
  Seal :: Block owner %1 -> Slot owner tag %1 -> Seal owner tag

data Unseal owner tag where
  Unseal :: Block owner %1 -> Block tag %1 -> Unseal owner tag

--------------------------------------------------------------------------------
-- Trace event data
--------------------------------------------------------------------------------
data TraceEvent where
  TraceCreate :: BlockSnapshot tag -> TraceEvent
  TraceObserve :: BlockSnapshot tag -> TraceEvent
  TraceUse :: BlockSnapshot tag -> TraceEvent
  TraceCopy :: BlockSnapshot tag -> BlockSnapshot tag -> TraceEvent
  TraceReplace :: BlockSnapshot tag -> BlockSnapshot tag -> TraceEvent
  TraceApply1
    :: BlockSnapshot op -> BlockSnapshot arg -> BlockSnapshot out -> TraceEvent
  TraceApply2
    :: BlockSnapshot op
    -> BlockSnapshot lhs
    -> BlockSnapshot rhs
    -> BlockSnapshot out
    -> TraceEvent
  TraceDestroy :: BlockSnapshot tag -> TraceEvent
  TraceSeal :: BlockSnapshot owner -> BlockSnapshot tag -> TraceEvent
  TraceUnseal :: BlockSnapshot owner -> BlockSnapshot tag -> TraceEvent

--------------------------------------------------------------------------------
-- Trace step layer
--------------------------------------------------------------------------------
newtype TraceEvents =
  TraceEvents [TraceEvent]

emptyTraceEvents :: TraceEvents
emptyTraceEvents = TraceEvents []

data TraceStep where
  CheckpointStep :: P.String -> TraceEvents -> TraceStep

data TraceGraph =
  TraceGraph [TraceStep] PendingEvents

newtype PendingEvents =
  PendingEvents TraceEvents

emptyPendingEvents :: PendingEvents
emptyPendingEvents = PendingEvents emptyTraceEvents

foldTraceEvents ::
     (accumulator -> TraceEvent -> accumulator)
  -> accumulator
  -> TraceEvents
  -> accumulator
foldTraceEvents foldEvent initial (TraceEvents traceEvents) =
  P.foldl foldEvent initial traceEvents

traceEventsFromPendingEvents :: PendingEvents -> TraceEvents
traceEventsFromPendingEvents (PendingEvents events) = events

traceGraphPendingEvents :: TraceGraph -> TraceEvents
traceGraphPendingEvents (TraceGraph _steps pending) =
  traceEventsFromPendingEvents pending

traceGraphSteps :: TraceGraph -> [TraceStep]
traceGraphSteps (TraceGraph steps _pending) = steps

traceStepEvents :: TraceStep -> TraceEvents
traceStepEvents = foldTraceStep (\_label events -> events)

foldTraceStep ::
     (P.String -> TraceEvents -> result)
  -> TraceStep
  -> result
foldTraceStep onCheckpoint (CheckpointStep label events) =
  onCheckpoint label events

data TraceBuilderState = TraceBuilderState
  { _nextBlockId :: Ur BlockId
  , _pending     :: Ur PendingEvents
  , _steps       :: Ur [TraceStep]
  }

type TraceBuilder a = State TraceBuilderState a

instance Consumable TraceBuilderState where
  consume (TraceBuilderState next pending steps) =
    consume next
      `lseq` consume pending
      `lseq` consume steps

instance Dupable TraceBuilderState where
  dup2 (TraceBuilderState next pending steps) =
    case dup2 next of
      (next1, next2) ->
        case dup2 pending of
          (pending1, pending2) ->
            case dup2 steps of
              (steps1, steps2) ->
                ( TraceBuilderState next1 pending1 steps1
                , TraceBuilderState next2 pending2 steps2)

--------------------------------------------------------------------------------
-- Internal helpers
--------------------------------------------------------------------------------
makeBlockRef :: Proxy tag -> BlockId -> BlockRef tag
makeBlockRef _ = BlockRef

makeSnapshot ::
     forall tag. Traceable tag
  => Proxy tag
  -> BlockRef tag
  -> Payload tag
  -> Facts
  -> BlockSnapshot tag
makeSnapshot tagProxy ref payload =
  BlockSnapshot ref payload (payloadView tagProxy)

makeTraceEvent1 ::
     Traceable tag
  => (BlockSnapshot tag -> TraceEvent)
  -> Proxy tag
  -> BlockRef tag
  -> Payload tag
  -> Facts
  -> TraceEvent
makeTraceEvent1 ctor tagProxy ref payload facts =
  ctor (makeSnapshot tagProxy ref payload facts)

makeTraceEvent2Hetero ::
     (Traceable left, Traceable right)
  => (BlockSnapshot left -> BlockSnapshot right -> TraceEvent)
  -> Proxy left
  -> BlockRef left
  -> Payload left
  -> Facts
  -> Proxy right
  -> BlockRef right
  -> Payload right
  -> Facts
  -> TraceEvent
makeTraceEvent2Hetero ctor leftProxy leftRef leftPayload leftFacts rightProxy rightRef rightPayload rightFacts =
  ctor
    (makeSnapshot leftProxy leftRef leftPayload leftFacts)
    (makeSnapshot rightProxy rightRef rightPayload rightFacts)

blockRefId :: BlockRef tag -> BlockId
blockRefId (BlockRef blockId) = blockId

blockSnapshotRef :: BlockSnapshot tag -> BlockRef tag
blockSnapshotRef (BlockSnapshot ref _payload _payloadView _facts) = ref

blockSnapshotPayload :: BlockSnapshot tag -> Payload tag
blockSnapshotPayload (BlockSnapshot _ref payload _payloadView _facts) = payload

blockSnapshotPayloadView :: BlockSnapshot tag -> PayloadView
blockSnapshotPayloadView (BlockSnapshot _ref _payload snapshotPayloadView _facts) =
  snapshotPayloadView

blockSnapshotFacts :: BlockSnapshot tag -> Facts
blockSnapshotFacts (BlockSnapshot _ref _payload _payloadView facts) = facts

withBlockSnapshot :: BlockSnapshot tag -> (Traceable tag => result) -> result
withBlockSnapshot BlockSnapshot {} result = result

allocatePersistedBlock ::
     Payload tag
  -> TraceBuilder (Ur BlockId, Ur (Payload tag))
allocatePersistedBlock payload = do
  TraceBuilderState (Ur oldNextBlockId) oldPending oldSteps <- get
  let blockId = oldNextBlockId
  put
    (TraceBuilderState
       (Ur (blockId + 1))
       oldPending
       oldSteps)
  return (Ur blockId, Ur payload)

appendPendingTraceEvent :: TraceEvent -> TraceBuilder ()
appendPendingTraceEvent event = do
  TraceBuilderState oldNext (Ur oldPending) oldSteps <- get
  put
    (TraceBuilderState
       oldNext
       (Ur (appendPendingEvents oldPending event))
       oldSteps)

appendPendingEvents :: PendingEvents -> TraceEvent -> PendingEvents
appendPendingEvents (PendingEvents (TraceEvents events)) event =
  PendingEvents (TraceEvents (events P.++ [event]))

checkpoint :: P.String -> TraceBuilder ()
checkpoint label = do
  TraceBuilderState oldNext (Ur pending) (Ur oldSteps) <- get
  let PendingEvents events = pending
      updatedSteps = oldSteps P.++ [CheckpointStep label events]
  put
    (TraceBuilderState
       oldNext
       (Ur emptyPendingEvents)
       (Ur updatedSteps))

--------------------------------------------------------------------------------
-- Primitive operations
--------------------------------------------------------------------------------
data SnapshottedBlock tag where
  SnapshottedBlock :: Block tag %1 -> BlockSnapshot tag -> SnapshottedBlock tag

snapshotBlock ::
     forall tag. Traceable tag
  => Block tag
     %1 -> SnapshottedBlock tag
snapshotBlock (Block (Ur blockId) (Ur payload) (Ur facts)) =
  let ref' = makeBlockRef (Proxy :: Proxy tag) blockId
      snapshot = makeSnapshot (Proxy :: Proxy tag) ref' payload facts
   in SnapshottedBlock (Block (Ur blockId) (Ur payload) (Ur facts)) snapshot

materializationFactsFrom ::
     Facts -> (Payload tag -> Facts) -> Payload tag -> Facts
materializationFactsFrom baseFacts selectFacts payload =
  factsUnion baseFacts (selectFacts payload)

materializeOutput ::
     forall tag. Traceable tag
  => Facts
  -> (Payload tag -> Facts)
  -> Payload tag
     %1 -> (BlockSnapshot tag -> TraceEvent)
  -> TraceBuilder (Block tag)
materializeOutput baseFacts selectFacts payload0 makeEvent =
  case persistCorePayload payload0 of
    Ur outputPayload -> do
      let outputFacts =
            materializationFactsFrom baseFacts selectFacts outputPayload
      (Ur outputId, Ur persistedOutput) <-
        allocatePersistedBlock outputPayload
      let outputRef = makeBlockRef (Proxy :: Proxy tag) outputId
      let outputSnapshot =
            makeSnapshot
              (Proxy :: Proxy tag)
              outputRef
              persistedOutput
              outputFacts
      appendPendingTraceEvent (makeEvent outputSnapshot)
      return (Block (Ur outputId) (Ur persistedOutput) (Ur outputFacts))

materializeTaggedWith ::
     forall tag. Traceable tag
  => Facts
  -> (Payload tag -> Facts)
  -> Pending tag
     %1 -> TraceBuilder (Block tag)
materializeTaggedWith baseFacts selectFacts (Pending payload (Ur buildEvent)) =
  materializeOutput baseFacts selectFacts payload buildEvent

materialize ::
     forall tag. Traceable tag
  => Pending tag
     %1 -> TraceBuilder (Block tag)
materialize = materializeTaggedWith emptyFacts (P.const emptyFacts)

commit ::
     forall tag. Traceable tag
  => Pending tag
     %1 -> TraceBuilder (Block tag)
commit = materialize

materializeTagged ::
     forall tag. Traceable tag
  => Facts
  -> Pending tag
     %1 -> TraceBuilder (Block tag)
materializeTagged facts = materializeTaggedWith facts (P.const emptyFacts)

create ::
     forall tag. Traceable tag
  => Payload tag
     %1 -> TraceBuilder (Create tag)
create payload0 = return (Create (Pending payload0 (Ur TraceCreate)))

observe ::
     forall tag. Traceable tag
  => Block tag
     %1 -> TraceBuilder (Observe tag)
observe block =
  case snapshotBlock block of
    SnapshottedBlock nextBlock snapshot -> do
      appendPendingTraceEvent (TraceObserve snapshot)
      return (Observe nextBlock)

use ::
     forall tag. Traceable tag
  => Block tag
     %1 -> TraceBuilder (Use tag)
use (Block (Ur blockId) (Ur payload) (Ur facts)) = do
  let ref' = makeBlockRef (Proxy :: Proxy tag) blockId
  appendPendingTraceEvent
    (makeTraceEvent1 TraceUse (Proxy :: Proxy tag) ref' payload facts)
  return (Use (OneUse payload))

copy ::
     forall tag. Traceable tag
  => Block tag
     %1 -> TraceBuilder (Copy tag)
copy block =
  case snapshotBlock block of
    SnapshottedBlock (Block (Ur originalId) (Ur payload) (Ur sourceFacts)) snapshot ->
      return
        (Copy
           (Block (Ur originalId) (Ur payload) (Ur sourceFacts))
           (Pending payload (Ur (TraceCopy snapshot))))

replace ::
     forall tag. Traceable tag
  => Block tag
     %1 -> Pending tag
     %1 -> TraceBuilder (Replace tag)
replace (Block (Ur oldId) (Ur oldPayload) (Ur oldFacts)) (Pending payload (Ur _)) =
  let oldRef = makeBlockRef (Proxy :: Proxy tag) oldId
      oldSnapshot = makeSnapshot (Proxy :: Proxy tag) oldRef oldPayload oldFacts
   in return (Replace (Pending payload (Ur (TraceReplace oldSnapshot))))

apply1 ::
     forall op arg.
     ( Applicable1 op arg
     , Traceable op
     , Traceable arg
     , Traceable (Apply1Result op arg)
     )
  => Block op
     %1 -> Block arg
     %1 -> TraceBuilder (Apply1 op arg)
apply1 (Block (Ur opId) (Ur opPayload) (Ur opFacts)) (Block (Ur argId) (Ur argPayload) (Ur argFacts)) =
  let opRef = makeBlockRef (Proxy :: Proxy op) opId
      argRef = makeBlockRef (Proxy :: Proxy arg) argId
      opSnapshot = makeSnapshot (Proxy :: Proxy op) opRef opPayload opFacts
      argSnapshot = makeSnapshot (Proxy :: Proxy arg) argRef argPayload argFacts
      outputPayload = applyPayload1 opPayload argPayload
   in return
        (Apply1
           (Pending outputPayload (Ur (TraceApply1 opSnapshot argSnapshot))))

apply2 ::
     forall op lhs rhs.
     ( Applicable2 op lhs rhs
     , Traceable op
     , Traceable lhs
     , Traceable rhs
     , Traceable (Apply2Result op lhs rhs)
     )
  => Block op
     %1 -> Block lhs
     %1 -> Block rhs
     %1 -> TraceBuilder (Apply2 op lhs rhs)
apply2 (Block (Ur opId) (Ur opPayload) (Ur opFacts)) (Block (Ur lhsId) (Ur lhsPayload) (Ur lhsFacts)) (Block (Ur rhsId) (Ur rhsPayload) (Ur rhsFacts)) =
  let opRef = makeBlockRef (Proxy :: Proxy op) opId
      lhsRef = makeBlockRef (Proxy :: Proxy lhs) lhsId
      rhsRef = makeBlockRef (Proxy :: Proxy rhs) rhsId
      opSnapshot = makeSnapshot (Proxy :: Proxy op) opRef opPayload opFacts
      lhsSnapshot = makeSnapshot (Proxy :: Proxy lhs) lhsRef lhsPayload lhsFacts
      rhsSnapshot = makeSnapshot (Proxy :: Proxy rhs) rhsRef rhsPayload rhsFacts
      outputPayload = applyPayload2 opPayload lhsPayload rhsPayload
   in return
        (Apply2
           (Pending
              outputPayload
              (Ur (TraceApply2 opSnapshot lhsSnapshot rhsSnapshot))))

destroy ::
     forall tag. Traceable tag
  => Block tag
     %1 -> TraceBuilder (Destroy tag)
destroy (Block (Ur blockId) (Ur payload) (Ur facts)) = do
  let ref' = makeBlockRef (Proxy :: Proxy tag) blockId
  appendPendingTraceEvent
    (makeTraceEvent1 TraceDestroy (Proxy :: Proxy tag) ref' payload facts)
  return Destroy

seal ::
     forall owner tag. (Traceable owner, Traceable tag)
  => Block owner
     %1 -> Block tag
     %1 -> TraceBuilder (Seal owner tag)
seal (Block (Ur ownerId) (Ur ownerPayload) (Ur ownerFacts)) (Block (Ur childId) (Ur childPayload) (Ur childFacts)) = do
  let ownerRef = makeBlockRef (Proxy :: Proxy owner) ownerId
  let childRef = makeBlockRef (Proxy :: Proxy tag) childId
  appendPendingTraceEvent
    (makeTraceEvent2Hetero
       TraceSeal
       (Proxy :: Proxy owner)
       ownerRef
       ownerPayload
       ownerFacts
       (Proxy :: Proxy tag)
       childRef
       childPayload
       childFacts)
  return
    (Seal
       (Block (Ur ownerId) (Ur ownerPayload) (Ur ownerFacts))
       (Slot (Block (Ur childId) (Ur childPayload) (Ur childFacts))))

unseal ::
     forall owner tag. (Traceable owner, Traceable tag)
  => Block owner
     %1 -> Slot owner tag
     %1 -> TraceBuilder (Unseal owner tag)
unseal (Block (Ur ownerId) (Ur ownerPayload) (Ur ownerFacts)) (Slot (Block (Ur childId) (Ur childPayload) (Ur childFacts))) = do
  let ownerRef = makeBlockRef (Proxy :: Proxy owner) ownerId
  let childRef = makeBlockRef (Proxy :: Proxy tag) childId
  appendPendingTraceEvent
    (makeTraceEvent2Hetero
       TraceUnseal
       (Proxy :: Proxy owner)
       ownerRef
       ownerPayload
       ownerFacts
       (Proxy :: Proxy tag)
       childRef
       childPayload
       childFacts)
  return
    (Unseal
       (Block (Ur ownerId) (Ur ownerPayload) (Ur ownerFacts))
       (Block (Ur childId) (Ur childPayload) (Ur childFacts)))

--------------------------------------------------------------------------------
-- Runner
--------------------------------------------------------------------------------
buildGraph :: TraceBuilder () -> TraceGraph
buildGraph builder =
  let (_, finalState) =
        runState
          builder
          (TraceBuilderState (Ur 0) (Ur emptyPendingEvents) (Ur []))
      TraceBuilderState (Ur _) (Ur finalPending) (Ur finalSteps) =
        finalState
   in TraceGraph finalSteps finalPending
