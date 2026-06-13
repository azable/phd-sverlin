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
    G(..)
  , GBuilder
  , N(..)
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
    NId
  , NRef(..)
  , NodeSnapshot(..)
  , SomeNodeSnapshot(..)
  , NRecord(..)
  , Event(..)
  , -- * Internal trace data
    TraceAction(..)
  , TraceActions(..)
  , -- * Internal builder state
    GBuilderState(..)
  , buildGraph
  , makeNRef
  , makeSnapshot
  , makeTraceAction1
  , makeTraceAction2
  , owedToTraceAction
  , owedListToTraceActions
  , unsafeUr
  , storeNRecord
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
type NId = Int

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

data NRef tag where
  NRef :: NId -> NRef tag

data N tag where
  N :: Ur NId %1 -> Ur (Payload tag) %1 -> N tag

data NodeSnapshot tag where
  NodeSnapshot :: NRef tag -> Payload tag -> PayloadView -> NodeSnapshot tag

data SomeNodeSnapshot where
  SomeNodeSnapshot :: NodeSnapshot tag -> SomeNodeSnapshot

data NRecord =
  NRecord NId SomeNodeSnapshot

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
  Created :: N tag %1 -> Owed (Create tag) %1 -> Created tag

data Observed tag where
  Observed :: N tag %1 -> Owed (Observe tag) %1 -> Observed tag

data Used tag where
  Used :: OneUse (Payload tag) %1 -> Owed (Use tag) %1 -> Used tag

data Copied tag where
  Copied :: N tag %1 -> N tag %1 -> Owed (Copy tag) %1 -> Copied tag

data Replaced tag where
  Replaced :: N tag %1 -> Owed (Replace tag) %1 -> Replaced tag

data Computed tag where
  Computed :: N tag %1 -> Owed (Compute tag) %1 -> Computed tag

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

data TraceActions acts where
  TraceNil :: TraceActions '[]
  (:>) :: TraceAction act -> TraceActions acts -> TraceActions (act : acts)

data Owed act where
  Owed :: Ur (TraceAction act) %1 -> Owed act

data OwedList acts where
  PaidDebt :: OwedList '[]
  (:~) :: Owed act %1 -> OwedList acts %1 -> OwedList (act : acts)

data Event (desc :: [Type] -> Type) where
  Event :: desc acts -> TraceActions acts -> Event desc

data G (desc :: [Type] -> Type) =
  G [NRecord] [Event desc]

data GBuilderState (desc :: [Type] -> Type) = GBuilderState
  { _nextId :: Ur NId
  , _nodes  :: Ur [NRecord]
  , _events :: Ur [Event desc]
  }

instance Consumable (GBuilderState desc) where
  consume (GBuilderState next ns es) =
    consume next `lseq` consume ns `lseq` consume es

instance Dupable (GBuilderState desc) where
  dup2 (GBuilderState next ns es) =
    case dup2 next of
      (next1, next2) ->
        case dup2 ns of
          (ns1, ns2) ->
            case dup2 es of
              (es1, es2) ->
                (GBuilderState next1 ns1 es1, GBuilderState next2 ns2 es2)

type GBuilder desc a = State (GBuilderState desc) a

makeNRef :: Proxy tag -> NId -> NRef tag
makeNRef _ = NRef

makeSnapshot ::
     forall tag. TracePayload tag
  => Proxy tag
  -> NRef tag
  -> Payload tag
  -> NodeSnapshot tag
makeSnapshot tagProxy ref payload =
  NodeSnapshot ref payload (payloadView tagProxy payload)

makeTraceAction1 ::
     TracePayload tag
  => (NodeSnapshot tag -> TraceAction act)
  -> Proxy tag
  -> NRef tag
  -> Payload tag
  -> Owed act
makeTraceAction1 ctor tagProxy ref payload =
  Owed (Ur (ctor (makeSnapshot tagProxy ref payload)))

makeTraceAction2 ::
     TracePayload tag
  => (NodeSnapshot tag -> NodeSnapshot tag -> TraceAction act)
  -> Proxy tag
  -> NRef tag
  -> Payload tag
  -> NRef tag
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

owedListToTraceActions :: OwedList acts %1 -> Ur (TraceActions acts)
owedListToTraceActions PaidDebt = Ur TraceNil
owedListToTraceActions (owed :~ rest) =
  case owedToTraceAction owed of
    Ur action ->
      case owedListToTraceActions rest of
        Ur restActions -> Ur (action :> restActions)

unsafeUr :: forall a. a %1 -> Ur a
unsafeUr = Unsafe.unsafeCoerce (Ur :: a -> Ur a)

storeNRecord ::
     forall desc tag. TracePayload tag
  => Proxy tag
  -> Payload tag
     %1 -> GBuilder desc (Ur NId, Ur (Payload tag))
storeNRecord tagProxy payload0 =
  case unsafeUr payload0 of
    Ur payload -> do
      GBuilderState (Ur oldNextId) (Ur oldNodes) oldEvents <- get
      let newId = oldNextId
      let ref' = makeNRef tagProxy newId
      let snapshot = makeSnapshot tagProxy ref' payload
      let newNode = NRecord newId (SomeNodeSnapshot snapshot)
      put
        (GBuilderState (Ur (newId + 1)) (Ur (oldNodes P.++ [newNode])) oldEvents)
      return (Ur newId, Ur payload)

emitEvent :: Event desc -> GBuilder desc ()
emitEvent event = do
  GBuilderState oldNext oldNodes (Ur oldEvents) <- get
  put (GBuilderState oldNext oldNodes (Ur (oldEvents P.++ [event])))

explain :: desc acts -> OwedList acts %1 -> GBuilder desc ()
explain desc owedList =
  case owedListToTraceActions owedList of
    Ur actions -> emitEvent (Event desc actions)

create ::
     forall desc tag. TracePayload tag
  => Payload tag
     %1 -> GBuilder desc (Created tag)
create payload0 = do
  (Ur nid, Ur payload) <- storeNRecord (Proxy :: Proxy tag) payload0
  let ref' = makeNRef (Proxy :: Proxy tag) nid
  return
    (Created
       (N (Ur nid) (Ur payload))
       (makeTraceAction1 TraceCreate (Proxy :: Proxy tag) ref' payload))

observe ::
     forall desc tag. TracePayload tag
  => N tag
     %1 -> GBuilder desc (Observed tag)
observe (N (Ur nid) (Ur payload)) = do
  let ref' = makeNRef (Proxy :: Proxy tag) nid
  return
    (Observed
       (N (Ur nid) (Ur payload))
       (makeTraceAction1 TraceObserve (Proxy :: Proxy tag) ref' payload))

use ::
     forall desc tag. TracePayload tag
  => N tag
     %1 -> GBuilder desc (Used tag)
use (N (Ur nid) (Ur payload)) = do
  let ref' = makeNRef (Proxy :: Proxy tag) nid
  return
    (Used
       (OneUse payload)
       (makeTraceAction1 TraceUse (Proxy :: Proxy tag) ref' payload))

copy ::
     forall desc tag. TracePayload tag
  => N tag
     %1 -> GBuilder desc (Copied tag)
copy (N (Ur originalId) (Ur payload)) = do
  (Ur copyId, Ur copiedPayload) <- storeNRecord (Proxy :: Proxy tag) payload
  let originalRef = makeNRef (Proxy :: Proxy tag) originalId
  let copyRef = makeNRef (Proxy :: Proxy tag) copyId
  return
    (Copied
       (N (Ur originalId) (Ur payload))
       (N (Ur copyId) (Ur copiedPayload))
       (makeTraceAction2
          TraceCopy
          (Proxy :: Proxy tag)
          originalRef
          payload
          copyRef
          copiedPayload))

replace ::
     forall desc tag. TracePayload tag
  => N tag
     %1 -> N tag
     %1 -> GBuilder desc (Replaced tag)
replace oldNode newNode =
  case oldNode of
    N (Ur oldId) (Ur oldPayload) ->
      case newNode of
        N (Ur newId) (Ur newPayload) -> do
          let oldRef = makeNRef (Proxy :: Proxy tag) oldId
          let newRef = makeNRef (Proxy :: Proxy tag) newId
          return
            (Replaced
               (N (Ur newId) (Ur newPayload))
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
     %1 -> GBuilder desc (Computed tag)
compute (OneUse payload0) = do
  (Ur nid, Ur payload) <- storeNRecord (Proxy :: Proxy tag) payload0
  let ref' = makeNRef (Proxy :: Proxy tag) nid
  return
    (Computed
       (N (Ur nid) (Ur payload))
       (makeTraceAction1 TraceCompute (Proxy :: Proxy tag) ref' payload))

destroy ::
     forall desc tag. TracePayload tag
  => N tag
     %1 -> GBuilder desc (Destroyed tag)
destroy (N (Ur nid) (Ur payload)) = do
  let ref' = makeNRef (Proxy :: Proxy tag) nid
  return
    (Destroyed (makeTraceAction1 TraceDestroy (Proxy :: Proxy tag) ref' payload))

buildGraph :: GBuilder desc () -> G desc
buildGraph builder =
  let (_, finalState) = runState builder (GBuilderState (Ur 0) (Ur []) (Ur []))
      GBuilderState (Ur _) (Ur finalNodes) (Ur finalEvents) = finalState
   in G finalNodes finalEvents
