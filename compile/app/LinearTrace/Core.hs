{-# LANGUAGE ConstraintKinds         #-}
{-# LANGUAGE DataKinds               #-}
{-# LANGUAGE FlexibleContexts        #-}
{-# LANGUAGE FlexibleInstances       #-}
{-# LANGUAGE GADTs                   #-}
{-# LANGUAGE LinearTypes             #-}
{-# LANGUAGE MultiParamTypeClasses   #-}
{-# LANGUAGE RebindableSyntax        #-}
{-# LANGUAGE ScopedTypeVariables     #-}
{-# LANGUAGE TypeFamilyDependencies  #-}
{-# LANGUAGE TypeOperators           #-}
{-# LANGUAGE UndecidableInstances    #-}
{-# LANGUAGE UndecidableSuperClasses #-}

module LinearTrace.Core
  ( -- * Core public API data
    TraceGraph(..)
  , TraceBuilder
  , Block
  , Slot
  , Payload
  , PayloadView(..)
  , Traceable(..)
  , -- * Trusted linear payloads
    LUnit(..)
  , LBool(..)
  , LInt(..)
  , LDouble(..)
  , LString(..)
  , -- * Action vocabulary
    ActionKind(..)
  , Action
  , type Create
  , type Observe
  , type Inspect
  , type Use
  , type Copy
  , type Replace
  , type Compute
  , type Destroy
  , type Seal
  , type Unseal
  , type Decide
  , -- * Primitive operations
    create
  , observe
  , inspect
  , use
  , copy
  , replace
  , compute
  , destroy
  , seal
  , unseal
  , decide
  , -- * Auditing operations
    OneUse(..)
  , Evidence(..)
  , EvidenceList(..)
  , Created(..)
  , Observed(..)
  , Inspected(..)
  , Used(..)
  , Copied(..)
  , Replaced(..)
  , Computed(..)
  , Destroyed(..)
  , Sealed(..)
  , Unsealed(..)
  , Decided(..)
  , explain
  , (<$>)
  , (<*>)
  , -- * Public graph/event data
    BlockId
  , BlockRef(..)
  , BlockSnapshot(..)
  , BlockRecord(..)
  , TraceEventSpec(..)
  , EventUnion(..)
  , Member(..)
  , TraceEvent(..)
  , -- * Public audit data
    AuditStep(..)
  , Audit(..)
  , -- * Runner
    buildGraph
  ) where

import           Control.Functor.Linear hiding (ask, (<$>), (<*>))
import           Data.Kind              (Type)
import           Data.Proxy             (Proxy (..))
import           Data.Typeable          (Typeable, typeRep)
import qualified Prelude                as P
import           Prelude.Linear
import qualified Unsafe.Coerce          as Unsafe

infixl 4 <$>
infixl 4 <*>
infixr 5 :~
infixr 5 :>
type BlockId = Int

type family Payload tag = payload | payload -> tag

data PayloadView = PayloadView
  { payloadKind    :: P.String
  , payloadContent :: P.String
  }

-- Deliberately not exported.
--
-- Downstream DSLs can use LinearTrace-approved payload wrappers, but cannot
-- define new approved payload classes of their own.
class LinearPayload payload where
  payloadDebugContent :: payload -> P.String

data LUnit tag =
  LUnit

newtype LInt tag =
  LInt Int

newtype LBool tag =
  LBool Bool

newtype LDouble tag =
  LDouble Double

newtype LString tag =
  LString P.String

instance LinearPayload (LUnit tag) where
  payloadDebugContent LUnit = "()"

instance LinearPayload (LBool tag) where
  payloadDebugContent (LBool value) = P.show value

instance LinearPayload (LInt tag) where
  payloadDebugContent (LInt value) = P.show value

instance LinearPayload (LDouble tag) where
  payloadDebugContent (LDouble value) = P.show value

instance LinearPayload (LString tag) where
  payloadDebugContent (LString value) = value

class (LinearPayload (Payload tag), Typeable tag) =>
      Traceable tag
  where
  payloadView :: Proxy tag -> Payload tag -> PayloadView
  payloadView tagProxy payload =
    PayloadView
      { payloadKind = P.show (typeRep tagProxy)
      , payloadContent = payloadDebugContent payload
      }

data OneUse a where
  OneUse :: a %1 -> OneUse a

(<$>) :: (a %1 -> b) %1 -> OneUse a %1 -> OneUse b
f <$> OneUse x = OneUse (f x)

(<*>) :: OneUse (a %1 -> b) %1 -> OneUse a %1 -> OneUse b
OneUse f <*> OneUse x = OneUse (f x)

data BlockRef tag where
  BlockRef :: BlockId -> BlockRef tag

data Block tag where
  Block :: Ur BlockId %1 -> Ur (Payload tag) %1 -> Block tag

-- | A sealed block of type @tag@ owned by an owner type @owner@.
--
-- The constructor is intentionally not exported. Users can hold slots, but
-- cannot extract the hidden block except through 'unseal'.
data Slot owner tag where
  Slot :: Block tag %1 -> Slot owner tag

data BlockSnapshot tag where
  BlockSnapshot
    :: BlockRef tag -> Payload tag -> PayloadView -> BlockSnapshot tag

data BlockRecord where
  BlockRecord :: BlockSnapshot tag -> BlockRecord

--------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------
data ActionKind
  = ActionCreate
  | ActionObserve
  | ActionInspect
  | ActionUse
  | ActionCopy
  | ActionReplace
  | ActionCompute
  | ActionDestroy
  | ActionSeal
  | ActionUnseal
  | ActionDecide

data Action (kind :: ActionKind) tag

data SealTag owner tag

data UnsealTag owner tag

type Create tag = Action 'ActionCreate tag

type Observe tag = Action 'ActionObserve tag

type Inspect tag = Action 'ActionInspect tag

type Use tag = Action 'ActionUse tag

type Copy tag = Action 'ActionCopy tag

type Replace tag = Action 'ActionReplace tag

type Compute tag = Action 'ActionCompute tag

type Destroy tag = Action 'ActionDestroy tag

type Seal owner tag = Action 'ActionSeal (SealTag owner tag)

type Unseal owner tag = Action 'ActionUnseal (UnsealTag owner tag)

type Decide tag = Action 'ActionDecide tag

--------------------------------------------------------------------------------
-- Primitive operation result types
--------------------------------------------------------------------------------
data Created tag where
  Created :: Block tag %1 -> Evidence (Create tag) %1 -> Created tag

data Observed tag where
  Observed :: Block tag %1 -> Evidence (Observe tag) %1 -> Observed tag

data Inspected tag where
  Inspected
    :: Block tag
       %1 -> OneUse (Payload tag)
       %1 -> Evidence (Inspect tag)
       %1 -> Inspected tag

data Used tag where
  Used :: OneUse (Payload tag) %1 -> Evidence (Use tag) %1 -> Used tag

data Copied tag where
  Copied :: Block tag %1 -> Block tag %1 -> Evidence (Copy tag) %1 -> Copied tag

data Replaced tag where
  Replaced :: Block tag %1 -> Evidence (Replace tag) %1 -> Replaced tag

data Computed tag where
  Computed :: Block tag %1 -> Evidence (Compute tag) %1 -> Computed tag

data Destroyed tag where
  Destroyed :: Evidence (Destroy tag) %1 -> Destroyed tag

data Sealed owner tag where
  Sealed
    :: Block owner
       %1 -> Slot owner tag
       %1 -> Evidence (Seal owner tag)
       %1 -> Sealed owner tag

data Unsealed owner tag where
  Unsealed
    :: Block owner
       %1 -> Block tag
       %1 -> Evidence (Unseal owner tag)
       %1 -> Unsealed owner tag

data Decided tag where
  DecidedTrue :: Evidence (Decide tag) %1 -> Decided tag
  DecidedFalse :: Evidence (Decide tag) %1 -> Decided tag

--------------------------------------------------------------------------------
-- Audit data
--------------------------------------------------------------------------------
data AuditStep act where
  CreateStep :: BlockSnapshot tag -> AuditStep (Create tag)
  ObserveStep :: BlockSnapshot tag -> AuditStep (Observe tag)
  InspectStep :: BlockSnapshot tag -> AuditStep (Inspect tag)
  UseStep :: BlockSnapshot tag -> AuditStep (Use tag)
  CopyStep :: BlockSnapshot tag -> BlockSnapshot tag -> AuditStep (Copy tag)
  ReplaceStep
    :: BlockSnapshot tag
    -> BlockSnapshot tag
    -> BlockSnapshot tag
    -> AuditStep (Replace tag)
  ComputeStep :: BlockSnapshot tag -> AuditStep (Compute tag)
  DestroyStep :: BlockSnapshot tag -> AuditStep (Destroy tag)
  SealStep
    :: BlockSnapshot owner -> BlockSnapshot tag -> AuditStep (Seal owner tag)
  UnsealStep
    :: BlockSnapshot owner -> BlockSnapshot tag -> AuditStep (Unseal owner tag)
  DecideStep :: BlockSnapshot tag -> AuditStep (Decide tag)

data Audit acts where
  EmptyAudit :: Audit '[]
  (:>) :: AuditStep act -> Audit acts -> Audit (act : acts)

data Evidence act where
  Evidence :: Ur (AuditStep act) %1 -> Evidence act

data EvidenceList acts where
  Done :: EvidenceList '[]
  (:~) :: Evidence act %1 -> EvidenceList acts %1 -> EvidenceList (act : acts)

--------------------------------------------------------------------------------
-- Event layer
--------------------------------------------------------------------------------
class TraceEventSpec event where
  type EventActs event :: [Type]

data EventUnion (events :: [Type]) (acts :: [Type]) where
  Here
    :: TraceEventSpec event=> event
    -> EventUnion (event : events) (EventActs event)
  There :: EventUnion events acts -> EventUnion (other : events) acts

class Member event events where
  injectEvent ::
       TraceEventSpec event => event -> EventUnion events (EventActs event)

instance {-# OVERLAPPING #-} Member event (event : events) where
  injectEvent = Here

instance {-# OVERLAPPABLE #-} Member event events =>
         Member event (other : events) where
  injectEvent event = There (injectEvent event)

data TraceEvent (events :: [Type]) where
  TraceEvent :: EventUnion events acts -> Audit acts -> TraceEvent events

data TraceGraph (events :: [Type]) =
  TraceGraph [BlockRecord] [TraceEvent events]

data TraceBuilderState (events :: [Type]) = TraceBuilderState
  { _nextBlockId :: Ur BlockId
  , _blocks      :: Ur [BlockRecord]
  , _events      :: Ur [TraceEvent events]
  }

type TraceBuilder events a = State (TraceBuilderState events) a

instance Consumable (TraceBuilderState events) where
  consume (TraceBuilderState next blocks events) =
    consume next `lseq` consume blocks `lseq` consume events

instance Dupable (TraceBuilderState events) where
  dup2 (TraceBuilderState next blocks events) =
    case dup2 next of
      (next1, next2) ->
        case dup2 blocks of
          (blocks1, blocks2) ->
            case dup2 events of
              (events1, events2) ->
                ( TraceBuilderState next1 blocks1 events1
                , TraceBuilderState next2 blocks2 events2)

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
  -> BlockSnapshot tag
makeSnapshot tagProxy ref payload =
  BlockSnapshot ref payload (payloadView tagProxy payload)

makeAuditStep1 ::
     Traceable tag
  => (BlockSnapshot tag -> AuditStep act)
  -> Proxy tag
  -> BlockRef tag
  -> Payload tag
  -> Evidence act
makeAuditStep1 ctor tagProxy ref payload =
  Evidence (Ur (ctor (makeSnapshot tagProxy ref payload)))

makeAuditStep2 ::
     Traceable tag
  => (BlockSnapshot tag -> BlockSnapshot tag -> AuditStep act)
  -> Proxy tag
  -> BlockRef tag
  -> Payload tag
  -> BlockRef tag
  -> Payload tag
  -> Evidence act
makeAuditStep2 ctor tagProxy ref1 payload1 ref2 payload2 =
  Evidence
    (Ur
       (ctor
          (makeSnapshot tagProxy ref1 payload1)
          (makeSnapshot tagProxy ref2 payload2)))

makeAuditStep3 ::
     Traceable tag
  => (BlockSnapshot tag -> BlockSnapshot tag -> BlockSnapshot tag -> AuditStep
                                                                       act)
  -> Proxy tag
  -> BlockRef tag
  -> Payload tag
  -> BlockRef tag
  -> Payload tag
  -> BlockRef tag
  -> Payload tag
  -> Evidence act
makeAuditStep3 ctor tagProxy ref1 payload1 ref2 payload2 ref3 payload3 =
  Evidence
    (Ur
       (ctor
          (makeSnapshot tagProxy ref1 payload1)
          (makeSnapshot tagProxy ref2 payload2)
          (makeSnapshot tagProxy ref3 payload3)))

makeAuditStep2Hetero ::
     (Traceable left, Traceable right)
  => (BlockSnapshot left -> BlockSnapshot right -> AuditStep act)
  -> Proxy left
  -> BlockRef left
  -> Payload left
  -> Proxy right
  -> BlockRef right
  -> Payload right
  -> Evidence act
makeAuditStep2Hetero ctor leftProxy leftRef leftPayload rightProxy rightRef rightPayload =
  Evidence
    (Ur
       (ctor
          (makeSnapshot leftProxy leftRef leftPayload)
          (makeSnapshot rightProxy rightRef rightPayload)))

evidenceToAuditStep :: Evidence act %1 -> Ur (AuditStep act)
evidenceToAuditStep (Evidence step) = step

evidenceListToAudit :: EvidenceList acts %1 -> Ur (Audit acts)
evidenceListToAudit Done = Ur EmptyAudit
evidenceListToAudit (evidence :~ rest) =
  case evidenceToAuditStep evidence of
    Ur step ->
      case evidenceListToAudit rest of
        Ur audit -> Ur (step :> audit)

unsafeUr :: forall a. a %1 -> Ur a
unsafeUr = Unsafe.unsafeCoerce (Ur :: a -> Ur a)

allocateBlock ::
     forall events tag. Traceable tag
  => Proxy tag
  -> Payload tag
     %1 -> TraceBuilder events (Ur BlockId, Ur (Payload tag))
allocateBlock tagProxy payload0 =
  case unsafeUr payload0 of
    Ur payload -> do
      TraceBuilderState (Ur oldNextBlockId) (Ur oldBlocks) oldEvents <- get
      let blockId = oldNextBlockId
      let ref' = makeBlockRef tagProxy blockId
      let snapshot = makeSnapshot tagProxy ref' payload
      let blockRecord = BlockRecord snapshot
      put
        (TraceBuilderState
           (Ur (blockId + 1))
           (Ur (oldBlocks P.++ [blockRecord]))
           oldEvents)
      return (Ur blockId, Ur payload)

emitEvent :: TraceEvent events -> TraceBuilder events ()
emitEvent event = do
  TraceBuilderState oldNext oldBlocks (Ur oldEvents) <- get
  put (TraceBuilderState oldNext oldBlocks (Ur (oldEvents P.++ [event])))

explain ::
     (TraceEventSpec event, Member event events)
  => event
  -> EvidenceList (EventActs event)
     %1 -> TraceBuilder events ()
explain event evidenceList =
  case evidenceListToAudit evidenceList of
    Ur audit -> emitEvent (TraceEvent (injectEvent event) audit)

--------------------------------------------------------------------------------
-- Primitive operations
--------------------------------------------------------------------------------
create ::
     forall events tag. Traceable tag
  => Payload tag
     %1 -> TraceBuilder events (Created tag)
create payload0 = do
  (Ur blockId, Ur payload) <- allocateBlock (Proxy :: Proxy tag) payload0
  let ref' = makeBlockRef (Proxy :: Proxy tag) blockId
  return
    (Created
       (Block (Ur blockId) (Ur payload))
       (makeAuditStep1 CreateStep (Proxy :: Proxy tag) ref' payload))

observe ::
     forall events tag. Traceable tag
  => Block tag
     %1 -> TraceBuilder events (Observed tag)
observe (Block (Ur blockId) (Ur payload)) = do
  let ref' = makeBlockRef (Proxy :: Proxy tag) blockId
  return
    (Observed
       (Block (Ur blockId) (Ur payload))
       (makeAuditStep1 ObserveStep (Proxy :: Proxy tag) ref' payload))

inspect ::
     forall events tag. Traceable tag
  => Block tag
     %1 -> TraceBuilder events (Inspected tag)
inspect (Block (Ur blockId) (Ur payload)) = do
  let ref' = makeBlockRef (Proxy :: Proxy tag) blockId
  return
    (Inspected
       (Block (Ur blockId) (Ur payload))
       (OneUse payload)
       (makeAuditStep1 InspectStep (Proxy :: Proxy tag) ref' payload))

use ::
     forall events tag. Traceable tag
  => Block tag
     %1 -> TraceBuilder events (Used tag)
use (Block (Ur blockId) (Ur payload)) = do
  let ref' = makeBlockRef (Proxy :: Proxy tag) blockId
  return
    (Used
       (OneUse payload)
       (makeAuditStep1 UseStep (Proxy :: Proxy tag) ref' payload))

copy ::
     forall events tag. Traceable tag
  => Block tag
     %1 -> TraceBuilder events (Copied tag)
copy (Block (Ur originalId) (Ur payload)) = do
  (Ur copyId, Ur copiedPayload) <- allocateBlock (Proxy :: Proxy tag) payload
  let originalRef = makeBlockRef (Proxy :: Proxy tag) originalId
  let copyRef = makeBlockRef (Proxy :: Proxy tag) copyId
  return
    (Copied
       (Block (Ur originalId) (Ur payload))
       (Block (Ur copyId) (Ur copiedPayload))
       (makeAuditStep2
          CopyStep
          (Proxy :: Proxy tag)
          originalRef
          payload
          copyRef
          copiedPayload))

replace ::
     forall events tag. Traceable tag
  => Block tag
     %1 -> Block tag
     %1 -> TraceBuilder events (Replaced tag)
replace oldBlock incomingBlock =
  case oldBlock of
    Block (Ur oldId) (Ur oldPayload) ->
      case incomingBlock of
        Block (Ur incomingId) (Ur incomingPayload) -> do
          (Ur outputId, Ur outputPayload) <-
            allocateBlock (Proxy :: Proxy tag) incomingPayload
          let oldRef = makeBlockRef (Proxy :: Proxy tag) oldId
          let incomingRef = makeBlockRef (Proxy :: Proxy tag) incomingId
          let outputRef = makeBlockRef (Proxy :: Proxy tag) outputId
          return
            (Replaced
               (Block (Ur outputId) (Ur outputPayload))
               (makeAuditStep3
                  ReplaceStep
                  (Proxy :: Proxy tag)
                  oldRef
                  oldPayload
                  incomingRef
                  incomingPayload
                  outputRef
                  outputPayload))

compute ::
     forall events tag. Traceable tag
  => OneUse (Payload tag)
     %1 -> TraceBuilder events (Computed tag)
compute (OneUse payload0) = do
  (Ur blockId, Ur payload) <- allocateBlock (Proxy :: Proxy tag) payload0
  let ref' = makeBlockRef (Proxy :: Proxy tag) blockId
  return
    (Computed
       (Block (Ur blockId) (Ur payload))
       (makeAuditStep1 ComputeStep (Proxy :: Proxy tag) ref' payload))

destroy ::
     forall events tag. Traceable tag
  => Block tag
     %1 -> TraceBuilder events (Destroyed tag)
destroy (Block (Ur blockId) (Ur payload)) = do
  let ref' = makeBlockRef (Proxy :: Proxy tag) blockId
  return
    (Destroyed (makeAuditStep1 DestroyStep (Proxy :: Proxy tag) ref' payload))

seal ::
     forall events owner tag. (Traceable owner, Traceable tag)
  => Block owner
     %1 -> Block tag
     %1 -> TraceBuilder events (Sealed owner tag)
seal ownerBlock childBlock =
  case ownerBlock of
    Block (Ur ownerId) (Ur ownerPayload) ->
      case childBlock of
        Block (Ur childId) (Ur childPayload) -> do
          let ownerRef = makeBlockRef (Proxy :: Proxy owner) ownerId
          let childRef = makeBlockRef (Proxy :: Proxy tag) childId
          return
            (Sealed
               (Block (Ur ownerId) (Ur ownerPayload))
               (Slot (Block (Ur childId) (Ur childPayload)))
               (makeAuditStep2Hetero
                  SealStep
                  (Proxy :: Proxy owner)
                  ownerRef
                  ownerPayload
                  (Proxy :: Proxy tag)
                  childRef
                  childPayload))

unseal ::
     forall events owner tag. (Traceable owner, Traceable tag)
  => Block owner
     %1 -> Slot owner tag
     %1 -> TraceBuilder events (Unsealed owner tag)
unseal ownerBlock slot =
  case ownerBlock of
    Block (Ur ownerId) (Ur ownerPayload) ->
      case slot of
        Slot childBlock ->
          case childBlock of
            Block (Ur childId) (Ur childPayload) -> do
              let ownerRef = makeBlockRef (Proxy :: Proxy owner) ownerId
              let childRef = makeBlockRef (Proxy :: Proxy tag) childId
              return
                (Unsealed
                   (Block (Ur ownerId) (Ur ownerPayload))
                   (Block (Ur childId) (Ur childPayload))
                   (makeAuditStep2Hetero
                      UnsealStep
                      (Proxy :: Proxy owner)
                      ownerRef
                      ownerPayload
                      (Proxy :: Proxy tag)
                      childRef
                      childPayload))

decide ::
     forall events tag. Traceable tag
  => (Payload tag %1 -> Bool)
  -> Block tag
     %1 -> TraceBuilder events (Decided tag)
decide predicate (Block (Ur blockId) (Ur payload)) = do
  let ref' = makeBlockRef (Proxy :: Proxy tag) blockId
  let evidence = makeAuditStep1 DecideStep (Proxy :: Proxy tag) ref' payload
  case predicate payload of
    True  -> return (DecidedTrue evidence)
    False -> return (DecidedFalse evidence)

--------------------------------------------------------------------------------
-- Runner
--------------------------------------------------------------------------------
buildGraph :: TraceBuilder events () -> TraceGraph events
buildGraph builder =
  let (_, finalState) =
        runState builder (TraceBuilderState (Ur 0) (Ur []) (Ur []))
      TraceBuilderState (Ur _) (Ur finalBlocks) (Ur finalEvents) = finalState
   in TraceGraph finalBlocks finalEvents
