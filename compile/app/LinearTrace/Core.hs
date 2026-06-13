{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE LinearTypes         #-}
{-# LANGUAGE RebindableSyntax    #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies        #-}
{-# LANGUAGE TypeOperators       #-}

module LinearTrace.Core
  ( -- * Core public API data
    TraceGraph(..)
  , TraceBuilder
  , Node(..)
  , Payload
  , PayloadView(..)
  , TracePayload(..)
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
  , -- * Primitive operations
    create
  , observe
  , inspect
  , use
  , copy
  , replace
  , compute
  , destroy
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
  , explain
  , (<$>)
  , (<*>)
  , -- * Internal graph/event data
    NodeId
  , NodeRef(..)
  , NodeSnapshot(..)
  , NodeRecord(..)
  , TraceEvent(..)
  , -- * Internal audit data
    AuditStep(..)
  , Audit(..)
  , -- * Internal builder state
    TraceBuilderState(..)
  , buildGraph
  , makeNodeRef
  , makeSnapshot
  , makeAuditStep1
  , makeAuditStep2
  , evidenceToAuditStep
  , evidenceListToAudit
  , unsafeUr
  , allocateNode
  , emitEvent
  ) where

import           Control.Functor.Linear hiding ((<$>), (<*>))
import           Data.Kind              (Type)
import           Data.Proxy             (Proxy (..))
import qualified Prelude                as P
import           Prelude.Linear
import qualified Unsafe.Coerce          as Unsafe

infixl 4 <$>
infixl 4 <*>
infixr 5 :~
infixr 5 :>
type NodeId = Int

type family Payload tag :: Type

newtype PayloadView =
  PayloadView P.String

class TracePayload tag where
  payloadView :: Proxy tag -> Payload tag -> PayloadView

data OneUse a where
  OneUse :: a %1 -> OneUse a

(<$>) :: (a %1 -> b) %1 -> OneUse a %1 -> OneUse b
f <$> OneUse x = OneUse (f x)

(<*>) :: OneUse (a %1 -> b) %1 -> OneUse a %1 -> OneUse b
OneUse f <*> OneUse x = OneUse (f x)

data NodeRef tag where
  NodeRef :: NodeId -> NodeRef tag

data Node tag where
  Node :: Ur NodeId %1 -> Ur (Payload tag) %1 -> Node tag

data NodeSnapshot tag where
  NodeSnapshot :: NodeRef tag -> Payload tag -> PayloadView -> NodeSnapshot tag

data NodeRecord where
  NodeRecord :: NodeSnapshot tag -> NodeRecord

data ActionKind
  = ActionCreate
  | ActionObserve
  | ActionInspect
  | ActionUse
  | ActionCopy
  | ActionReplace
  | ActionCompute
  | ActionDestroy

data Action (kind :: ActionKind) tag

type Create tag = Action 'ActionCreate tag

type Observe tag = Action 'ActionObserve tag

type Inspect tag = Action 'ActionInspect tag

type Use tag = Action 'ActionUse tag

type Copy tag = Action 'ActionCopy tag

type Replace tag = Action 'ActionReplace tag

type Compute tag = Action 'ActionCompute tag

type Destroy tag = Action 'ActionDestroy tag

data Created tag where
  Created :: Node tag %1 -> Evidence (Create tag) %1 -> Created tag

data Observed tag where
  Observed :: Node tag %1 -> Evidence (Observe tag) %1 -> Observed tag

data Inspected tag where
  Inspected
    :: Node tag
       %1 -> OneUse (Payload tag)
       %1 -> Evidence (Inspect tag)
       %1 -> Inspected tag

data Used tag where
  Used :: OneUse (Payload tag) %1 -> Evidence (Use tag) %1 -> Used tag

data Copied tag where
  Copied :: Node tag %1 -> Node tag %1 -> Evidence (Copy tag) %1 -> Copied tag

data Replaced tag where
  Replaced :: Node tag %1 -> Evidence (Replace tag) %1 -> Replaced tag

data Computed tag where
  Computed :: Node tag %1 -> Evidence (Compute tag) %1 -> Computed tag

data Destroyed tag where
  Destroyed :: Evidence (Destroy tag) %1 -> Destroyed tag

data AuditStep act where
  CreateStep :: NodeSnapshot tag -> AuditStep (Create tag)
  ObserveStep :: NodeSnapshot tag -> AuditStep (Observe tag)
  InspectStep :: NodeSnapshot tag -> AuditStep (Inspect tag)
  UseStep :: NodeSnapshot tag -> AuditStep (Use tag)
  CopyStep :: NodeSnapshot tag -> NodeSnapshot tag -> AuditStep (Copy tag)
  ReplaceStep :: NodeSnapshot tag -> NodeSnapshot tag -> AuditStep (Replace tag)
  ComputeStep :: NodeSnapshot tag -> AuditStep (Compute tag)
  DestroyStep :: NodeSnapshot tag -> AuditStep (Destroy tag)

data Audit acts where
  EmptyAudit :: Audit '[]
  (:>) :: AuditStep act -> Audit acts -> Audit (act : acts)

data Evidence act where
  Evidence :: Ur (AuditStep act) %1 -> Evidence act

data EvidenceList acts where
  Done :: EvidenceList '[]
  (:~) :: Evidence act %1 -> EvidenceList acts %1 -> EvidenceList (act : acts)

data TraceEvent (event :: [Type] -> Type) where
  TraceEvent :: event acts -> Audit acts -> TraceEvent event

data TraceGraph (event :: [Type] -> Type) =
  TraceGraph [NodeRecord] [TraceEvent event]

data TraceBuilderState (event :: [Type] -> Type) = TraceBuilderState
  { _nextId :: Ur NodeId
  , _nodes  :: Ur [NodeRecord]
  , _events :: Ur [TraceEvent event]
  }

instance Consumable (TraceBuilderState event) where
  consume (TraceBuilderState next ns es) =
    consume next `lseq` consume ns `lseq` consume es

instance Dupable (TraceBuilderState event) where
  dup2 (TraceBuilderState next ns es) =
    case dup2 next of
      (next1, next2) ->
        case dup2 ns of
          (ns1, ns2) ->
            case dup2 es of
              (es1, es2) ->
                ( TraceBuilderState next1 ns1 es1
                , TraceBuilderState next2 ns2 es2)

type TraceBuilder event a = State (TraceBuilderState event) a

makeNodeRef :: Proxy tag -> NodeId -> NodeRef tag
makeNodeRef _ = NodeRef

makeSnapshot ::
     forall tag. TracePayload tag
  => Proxy tag
  -> NodeRef tag
  -> Payload tag
  -> NodeSnapshot tag
makeSnapshot tagProxy ref payload =
  NodeSnapshot ref payload (payloadView tagProxy payload)

makeAuditStep1 ::
     TracePayload tag
  => (NodeSnapshot tag -> AuditStep act)
  -> Proxy tag
  -> NodeRef tag
  -> Payload tag
  -> Evidence act
makeAuditStep1 ctor tagProxy ref payload =
  Evidence (Ur (ctor (makeSnapshot tagProxy ref payload)))

makeAuditStep2 ::
     TracePayload tag
  => (NodeSnapshot tag -> NodeSnapshot tag -> AuditStep act)
  -> Proxy tag
  -> NodeRef tag
  -> Payload tag
  -> NodeRef tag
  -> Payload tag
  -> Evidence act
makeAuditStep2 ctor tagProxy ref1 payload1 ref2 payload2 =
  Evidence
    (Ur
       (ctor
          (makeSnapshot tagProxy ref1 payload1)
          (makeSnapshot tagProxy ref2 payload2)))

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

allocateNode ::
     forall event tag. TracePayload tag
  => Proxy tag
  -> Payload tag
     %1 -> TraceBuilder event (Ur NodeId, Ur (Payload tag))
allocateNode tagProxy payload0 =
  case unsafeUr payload0 of
    Ur payload -> do
      TraceBuilderState (Ur oldNextId) (Ur oldNodes) oldEvents <- get
      let nodeId = oldNextId
      let ref' = makeNodeRef tagProxy nodeId
      let snapshot = makeSnapshot tagProxy ref' payload
      let nodeRecord = NodeRecord snapshot
      put
        (TraceBuilderState
           (Ur (nodeId + 1))
           (Ur (oldNodes P.++ [nodeRecord]))
           oldEvents)
      return (Ur nodeId, Ur payload)

emitEvent :: TraceEvent event -> TraceBuilder event ()
emitEvent event = do
  TraceBuilderState oldNext oldNodes (Ur oldEvents) <- get
  put (TraceBuilderState oldNext oldNodes (Ur (oldEvents P.++ [event])))

explain :: event acts -> EvidenceList acts %1 -> TraceBuilder event ()
explain event evidenceList =
  case evidenceListToAudit evidenceList of
    Ur audit -> emitEvent (TraceEvent event audit)

create ::
     forall event tag. TracePayload tag
  => Payload tag
     %1 -> TraceBuilder event (Created tag)
create payload0 = do
  (Ur nodeId, Ur payload) <- allocateNode (Proxy :: Proxy tag) payload0
  let ref' = makeNodeRef (Proxy :: Proxy tag) nodeId
  return
    (Created
       (Node (Ur nodeId) (Ur payload))
       (makeAuditStep1 CreateStep (Proxy :: Proxy tag) ref' payload))

observe ::
     forall event tag. TracePayload tag
  => Node tag
     %1 -> TraceBuilder event (Observed tag)
observe (Node (Ur nodeId) (Ur payload)) = do
  let ref' = makeNodeRef (Proxy :: Proxy tag) nodeId
  return
    (Observed
       (Node (Ur nodeId) (Ur payload))
       (makeAuditStep1 ObserveStep (Proxy :: Proxy tag) ref' payload))

inspect ::
     forall event tag. TracePayload tag
  => Node tag
     %1 -> TraceBuilder event (Inspected tag)
inspect (Node (Ur nodeId) (Ur payload)) = do
  let ref' = makeNodeRef (Proxy :: Proxy tag) nodeId
  return
    (Inspected
       (Node (Ur nodeId) (Ur payload))
       (OneUse payload)
       (makeAuditStep1 InspectStep (Proxy :: Proxy tag) ref' payload))

use ::
     forall event tag. TracePayload tag
  => Node tag
     %1 -> TraceBuilder event (Used tag)
use (Node (Ur nodeId) (Ur payload)) = do
  let ref' = makeNodeRef (Proxy :: Proxy tag) nodeId
  return
    (Used
       (OneUse payload)
       (makeAuditStep1 UseStep (Proxy :: Proxy tag) ref' payload))

copy ::
     forall event tag. TracePayload tag
  => Node tag
     %1 -> TraceBuilder event (Copied tag)
copy (Node (Ur originalId) (Ur payload)) = do
  (Ur copyId, Ur copiedPayload) <- allocateNode (Proxy :: Proxy tag) payload
  let originalRef = makeNodeRef (Proxy :: Proxy tag) originalId
  let copyRef = makeNodeRef (Proxy :: Proxy tag) copyId
  return
    (Copied
       (Node (Ur originalId) (Ur payload))
       (Node (Ur copyId) (Ur copiedPayload))
       (makeAuditStep2
          CopyStep
          (Proxy :: Proxy tag)
          originalRef
          payload
          copyRef
          copiedPayload))

replace ::
     forall event tag. TracePayload tag
  => Node tag
     %1 -> Node tag
     %1 -> TraceBuilder event (Replaced tag)
replace oldNode newNode =
  case oldNode of
    Node (Ur oldId) (Ur oldPayload) ->
      case newNode of
        Node (Ur newId) (Ur newPayload) -> do
          let oldRef = makeNodeRef (Proxy :: Proxy tag) oldId
          let newRef = makeNodeRef (Proxy :: Proxy tag) newId
          return
            (Replaced
               (Node (Ur newId) (Ur newPayload))
               (makeAuditStep2
                  ReplaceStep
                  (Proxy :: Proxy tag)
                  oldRef
                  oldPayload
                  newRef
                  newPayload))

compute ::
     forall event tag. TracePayload tag
  => OneUse (Payload tag)
     %1 -> TraceBuilder event (Computed tag)
compute (OneUse payload0) = do
  (Ur nodeId, Ur payload) <- allocateNode (Proxy :: Proxy tag) payload0
  let ref' = makeNodeRef (Proxy :: Proxy tag) nodeId
  return
    (Computed
       (Node (Ur nodeId) (Ur payload))
       (makeAuditStep1 ComputeStep (Proxy :: Proxy tag) ref' payload))

destroy ::
     forall event tag. TracePayload tag
  => Node tag
     %1 -> TraceBuilder event (Destroyed tag)
destroy (Node (Ur nodeId) (Ur payload)) = do
  let ref' = makeNodeRef (Proxy :: Proxy tag) nodeId
  return
    (Destroyed (makeAuditStep1 DestroyStep (Proxy :: Proxy tag) ref' payload))

buildGraph :: TraceBuilder event () -> TraceGraph event
buildGraph builder =
  let (_, finalState) =
        runState builder (TraceBuilderState (Ur 0) (Ur []) (Ur []))
      TraceBuilderState (Ur _) (Ur finalNodes) (Ur finalEvents) = finalState
   in TraceGraph finalNodes finalEvents
