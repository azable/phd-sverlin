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
  , type Use
  , type Copy
  , type Replace
  , type Compute
  , type Destroy
  , -- * Primitive operations
    create
  , observe
  , use
  , copy
  , replace
  , compute
  , destroy
  , -- * Auditing operations
    OneUse(..)
  , Owed(..)
  , OwedList(..)
  , Created(..)
  , Observed(..)
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
  , Event(..)
  , -- * Internal trace data
    TraceAction(..)
  , ActionTrace(..)
  , -- * Internal builder state
    TraceBuilderState(..)
  , buildGraph
  , makeNodeRef
  , makeSnapshot
  , makeTraceAction1
  , makeTraceAction2
  , owedToTraceAction
  , owedListToActionTrace
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
  | ActionUse
  | ActionCopy
  | ActionReplace
  | ActionCompute
  | ActionDestroy

data Action (kind :: ActionKind) tag

type Create tag = Action 'ActionCreate tag

type Observe tag = Action 'ActionObserve tag

type Use tag = Action 'ActionUse tag

type Copy tag = Action 'ActionCopy tag

type Replace tag = Action 'ActionReplace tag

type Compute tag = Action 'ActionCompute tag

type Destroy tag = Action 'ActionDestroy tag

data Created tag where
  Created :: Node tag %1 -> Owed (Create tag) %1 -> Created tag

data Observed tag where
  Observed :: Node tag %1 -> Owed (Observe tag) %1 -> Observed tag

data Used tag where
  Used :: OneUse (Payload tag) %1 -> Owed (Use tag) %1 -> Used tag

data Copied tag where
  Copied :: Node tag %1 -> Node tag %1 -> Owed (Copy tag) %1 -> Copied tag

data Replaced tag where
  Replaced :: Node tag %1 -> Owed (Replace tag) %1 -> Replaced tag

data Computed tag where
  Computed :: Node tag %1 -> Owed (Compute tag) %1 -> Computed tag

data Destroyed tag where
  Destroyed :: Owed (Destroy tag) %1 -> Destroyed tag

data TraceAction act where
  TraceCreate :: NodeSnapshot tag -> TraceAction (Create tag)
  TraceObserve :: NodeSnapshot tag -> TraceAction (Observe tag)
  TraceUse :: NodeSnapshot tag -> TraceAction (Use tag)
  TraceCopy :: NodeSnapshot tag -> NodeSnapshot tag -> TraceAction (Copy tag)
  TraceReplace
    :: NodeSnapshot tag -> NodeSnapshot tag -> TraceAction (Replace tag)
  TraceCompute :: NodeSnapshot tag -> TraceAction (Compute tag)
  TraceDestroy :: NodeSnapshot tag -> TraceAction (Destroy tag)

data ActionTrace acts where
  TraceNil :: ActionTrace '[]
  (:>) :: TraceAction act -> ActionTrace acts -> ActionTrace (act : acts)

data Owed act where
  Owed :: Ur (TraceAction act) %1 -> Owed act

data OwedList acts where
  PaidDebt :: OwedList '[]
  (:~) :: Owed act %1 -> OwedList acts %1 -> OwedList (act : acts)

data Event (desc :: [Type] -> Type) where
  Event :: desc acts -> ActionTrace acts -> Event desc

data TraceGraph (desc :: [Type] -> Type) =
  TraceGraph [NodeRecord] [Event desc]

data TraceBuilderState (desc :: [Type] -> Type) = TraceBuilderState
  { _nextId :: Ur NodeId
  , _nodes  :: Ur [NodeRecord]
  , _events :: Ur [Event desc]
  }

instance Consumable (TraceBuilderState desc) where
  consume (TraceBuilderState next ns es) =
    consume next `lseq` consume ns `lseq` consume es

instance Dupable (TraceBuilderState desc) where
  dup2 (TraceBuilderState next ns es) =
    case dup2 next of
      (next1, next2) ->
        case dup2 ns of
          (ns1, ns2) ->
            case dup2 es of
              (es1, es2) ->
                ( TraceBuilderState next1 ns1 es1
                , TraceBuilderState next2 ns2 es2)

type TraceBuilder desc a = State (TraceBuilderState desc) a

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

makeTraceAction1 ::
     TracePayload tag
  => (NodeSnapshot tag -> TraceAction act)
  -> Proxy tag
  -> NodeRef tag
  -> Payload tag
  -> Owed act
makeTraceAction1 ctor tagProxy ref payload =
  Owed (Ur (ctor (makeSnapshot tagProxy ref payload)))

makeTraceAction2 ::
     TracePayload tag
  => (NodeSnapshot tag -> NodeSnapshot tag -> TraceAction act)
  -> Proxy tag
  -> NodeRef tag
  -> Payload tag
  -> NodeRef tag
  -> Payload tag
  -> Owed act
makeTraceAction2 ctor tagProxy ref1 payload1 ref2 payload2 =
  Owed
    (Ur
       (ctor
          (makeSnapshot tagProxy ref1 payload1)
          (makeSnapshot tagProxy ref2 payload2)))

owedToTraceAction :: Owed act %1 -> Ur (TraceAction act)
owedToTraceAction (Owed action) = action

owedListToActionTrace :: OwedList acts %1 -> Ur (ActionTrace acts)
owedListToActionTrace PaidDebt = Ur TraceNil
owedListToActionTrace (owed :~ rest) =
  case owedToTraceAction owed of
    Ur action ->
      case owedListToActionTrace rest of
        Ur restActions -> Ur (action :> restActions)

unsafeUr :: forall a. a %1 -> Ur a
unsafeUr = Unsafe.unsafeCoerce (Ur :: a -> Ur a)

allocateNode ::
     forall desc tag. TracePayload tag
  => Proxy tag
  -> Payload tag
     %1 -> TraceBuilder desc (Ur NodeId, Ur (Payload tag))
allocateNode tagProxy payload0 =
  case unsafeUr payload0 of
    Ur payload -> do
      TraceBuilderState (Ur oldNextId) (Ur oldNodes) oldEvents <- get
      let newId = oldNextId
      let ref' = makeNodeRef tagProxy newId
      let snapshot = makeSnapshot tagProxy ref' payload
      let newNode = NodeRecord snapshot
      put
        (TraceBuilderState
           (Ur (newId + 1))
           (Ur (oldNodes P.++ [newNode]))
           oldEvents)
      return (Ur newId, Ur payload)

emitEvent :: Event desc -> TraceBuilder desc ()
emitEvent event = do
  TraceBuilderState oldNext oldNodes (Ur oldEvents) <- get
  put (TraceBuilderState oldNext oldNodes (Ur (oldEvents P.++ [event])))

explain :: desc acts -> OwedList acts %1 -> TraceBuilder desc ()
explain desc owedList =
  case owedListToActionTrace owedList of
    Ur actions -> emitEvent (Event desc actions)

create ::
     forall desc tag. TracePayload tag
  => Payload tag
     %1 -> TraceBuilder desc (Created tag)
create payload0 = do
  (Ur nodeId, Ur payload) <- allocateNode (Proxy :: Proxy tag) payload0
  let ref' = makeNodeRef (Proxy :: Proxy tag) nodeId
  return
    (Created
       (Node (Ur nodeId) (Ur payload))
       (makeTraceAction1 TraceCreate (Proxy :: Proxy tag) ref' payload))

observe ::
     forall desc tag. TracePayload tag
  => Node tag
     %1 -> TraceBuilder desc (Observed tag)
observe (Node (Ur nodeId) (Ur payload)) = do
  let ref' = makeNodeRef (Proxy :: Proxy tag) nodeId
  return
    (Observed
       (Node (Ur nodeId) (Ur payload))
       (makeTraceAction1 TraceObserve (Proxy :: Proxy tag) ref' payload))

use ::
     forall desc tag. TracePayload tag
  => Node tag
     %1 -> TraceBuilder desc (Used tag)
use (Node (Ur nodeId) (Ur payload)) = do
  let ref' = makeNodeRef (Proxy :: Proxy tag) nodeId
  return
    (Used
       (OneUse payload)
       (makeTraceAction1 TraceUse (Proxy :: Proxy tag) ref' payload))

copy ::
     forall desc tag. TracePayload tag
  => Node tag
     %1 -> TraceBuilder desc (Copied tag)
copy (Node (Ur originalId) (Ur payload)) = do
  (Ur copyId, Ur copiedPayload) <- allocateNode (Proxy :: Proxy tag) payload
  let originalRef = makeNodeRef (Proxy :: Proxy tag) originalId
  let copyRef = makeNodeRef (Proxy :: Proxy tag) copyId
  return
    (Copied
       (Node (Ur originalId) (Ur payload))
       (Node (Ur copyId) (Ur copiedPayload))
       (makeTraceAction2
          TraceCopy
          (Proxy :: Proxy tag)
          originalRef
          payload
          copyRef
          copiedPayload))

replace ::
     forall desc tag. TracePayload tag
  => Node tag
     %1 -> Node tag
     %1 -> TraceBuilder desc (Replaced tag)
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
               (makeTraceAction2
                  TraceReplace
                  (Proxy :: Proxy tag)
                  oldRef
                  oldPayload
                  newRef
                  newPayload))

compute ::
     forall desc tag. TracePayload tag
  => OneUse (Payload tag)
     %1 -> TraceBuilder desc (Computed tag)
compute (OneUse payload0) = do
  (Ur nodeId, Ur payload) <- allocateNode (Proxy :: Proxy tag) payload0
  let ref' = makeNodeRef (Proxy :: Proxy tag) nodeId
  return
    (Computed
       (Node (Ur nodeId) (Ur payload))
       (makeTraceAction1 TraceCompute (Proxy :: Proxy tag) ref' payload))

destroy ::
     forall desc tag. TracePayload tag
  => Node tag
     %1 -> TraceBuilder desc (Destroyed tag)
destroy (Node (Ur nodeId) (Ur payload)) = do
  let ref' = makeNodeRef (Proxy :: Proxy tag) nodeId
  return
    (Destroyed (makeTraceAction1 TraceDestroy (Proxy :: Proxy tag) ref' payload))

buildGraph :: TraceBuilder desc () -> TraceGraph desc
buildGraph builder =
  let (_, finalState) =
        runState builder (TraceBuilderState (Ur 0) (Ur []) (Ur []))
      TraceBuilderState (Ur _) (Ur finalNodes) (Ur finalEvents) = finalState
   in TraceGraph finalNodes finalEvents
