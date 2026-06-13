{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE LinearTypes           #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RebindableSyntax      #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}

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
    TraceOp(..)
  , TraceOps(..)
  , -- * Internal builder state
    GBuilderState(..)
  , buildGraph
  , mkNRef
  , mkSnapshot
  , makeOp1
  , makeOp2
  , descToTraceOp
  , descListToTraceOps
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

class TracePayload model tag where
  payloadView :: Proxy model -> Proxy tag -> Payload tag -> PayloadView
  payloadModel :: Proxy model -> Proxy tag -> Payload tag -> model

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

data NodeSnapshot model tag where
  NodeSnapshot :: NRef tag -> PayloadView -> model -> NodeSnapshot model tag

data SomeNodeSnapshot model where
  SomeNodeSnapshot :: NodeSnapshot model tag -> SomeNodeSnapshot model

data NRecord model =
  NRecord NId (SomeNodeSnapshot model)

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

data Created model tag where
  Created :: N tag %1 -> Owed model (Create tag) %1 -> Created model tag

data Observed model tag where
  Observed :: N tag %1 -> Owed model (Observe tag) %1 -> Observed model tag

data Used model tag where
  Used :: OneUse (Payload tag) %1 -> Owed model (Use tag) %1 -> Used model tag

data Copied model tag where
  Copied :: N tag %1 -> N tag %1 -> Owed model (Copy tag) %1 -> Copied model tag

data Replaced model tag where
  Replaced :: N tag %1 -> Owed model (Replace tag) %1 -> Replaced model tag

data Computed model tag where
  Computed :: N tag %1 -> Owed model (Compute tag) %1 -> Computed model tag

data Destroyed model tag where
  Destroyed :: Owed model (Destroy tag) %1 -> Destroyed model tag

data TraceOp model act where
  TraceCreate :: NodeSnapshot model tag -> TraceOp model (Create tag)
  TraceObserve :: NodeSnapshot model tag -> TraceOp model (Observe tag)
  TraceUse :: NodeSnapshot model tag -> TraceOp model (Use tag)
  TraceCopy
    :: NodeSnapshot model tag
    -> NodeSnapshot model tag
    -> TraceOp model (Copy tag)
  TraceReplace
    :: NodeSnapshot model tag
    -> NodeSnapshot model tag
    -> TraceOp model (Replace tag)
  TraceCompute :: NodeSnapshot model tag -> TraceOp model (Compute tag)
  TraceDestroy :: NodeSnapshot model tag -> TraceOp model (Destroy tag)

data TraceOps model acts where
  TraceNil :: TraceOps model '[]
  (:>)
    :: TraceOp model act -> TraceOps model acts -> TraceOps model (act : acts)

data Owed model act where
  Owed :: Ur (TraceOp model act) %1 -> Owed model act

data OwedList model acts where
  PaidDebt :: OwedList model '[]
  (:~)
    :: Owed model act
       %1 -> OwedList model acts
       %1 -> OwedList model (act : acts)

data Event model (desc :: [Type] -> Type) where
  Event :: desc acts -> TraceOps model acts -> Event model desc

data G model (desc :: [Type] -> Type) =
  G [NRecord model] [Event model desc]

data GBuilderState model (desc :: [Type] -> Type) = GBuilderState
  { _nextId :: Ur NId
  , _nodes  :: Ur [NRecord model]
  , _events :: Ur [Event model desc]
  }

instance Consumable (GBuilderState model desc) where
  consume (GBuilderState next ns es) =
    consume next `lseq` consume ns `lseq` consume es

instance Dupable (GBuilderState model desc) where
  dup2 (GBuilderState next ns es) =
    case dup2 next of
      (next1, next2) ->
        case dup2 ns of
          (ns1, ns2) ->
            case dup2 es of
              (es1, es2) ->
                (GBuilderState next1 ns1 es1, GBuilderState next2 ns2 es2)

type GBuilder model desc a = State (GBuilderState model desc) a

mkNRef :: Proxy tag -> NId -> NRef tag
mkNRef _ = NRef

mkSnapshot ::
     forall model tag. TracePayload model tag
  => Proxy model
  -> Proxy tag
  -> NRef tag
  -> Payload tag
  -> NodeSnapshot model tag
mkSnapshot modelProxy tagProxy ref payload =
  NodeSnapshot
    ref
    (payloadView modelProxy tagProxy payload)
    (payloadModel modelProxy tagProxy payload)

makeOp1 ::
     TracePayload model tag
  => (NodeSnapshot model tag -> TraceOp model act)
  -> Proxy model
  -> Proxy tag
  -> NRef tag
  -> Payload tag
  -> Owed model act
makeOp1 ctor modelProxy tagProxy ref payload =
  Owed (Ur (ctor (mkSnapshot modelProxy tagProxy ref payload)))

makeOp2 ::
     TracePayload model tag
  => (NodeSnapshot model tag -> NodeSnapshot model tag -> TraceOp model act)
  -> Proxy model
  -> Proxy tag
  -> NRef tag
  -> Payload tag
  -> NRef tag
  -> Payload tag
  -> Owed model act
makeOp2 ctor modelProxy tagProxy ref1 payload1 ref2 payload2 =
  Owed
    (Ur
       (ctor
          (mkSnapshot modelProxy tagProxy ref1 payload1)
          (mkSnapshot modelProxy tagProxy ref2 payload2)))

descToTraceOp :: Owed model act %1 -> Ur (TraceOp model act)
descToTraceOp (Owed op) = op

descListToTraceOps :: OwedList model acts %1 -> Ur (TraceOps model acts)
descListToTraceOps PaidDebt = Ur TraceNil
descListToTraceOps (owed :~ rest) =
  case descToTraceOp owed of
    Ur op ->
      case descListToTraceOps rest of
        Ur restOps -> Ur (op :> restOps)

unsafeUr :: forall a. a %1 -> Ur a
unsafeUr = Unsafe.unsafeCoerce (Ur :: a -> Ur a)

storeNRecord ::
     forall model desc tag. TracePayload model tag
  => Proxy model
  -> Proxy tag
  -> Payload tag
     %1 -> GBuilder model desc (Ur NId, Ur (Payload tag))
storeNRecord modelProxy tagProxy payload0 =
  case unsafeUr payload0 of
    Ur payload -> do
      GBuilderState (Ur oldNextId) (Ur oldNodes) oldEvents <- get
      let newId = oldNextId
      let ref' = mkNRef tagProxy newId
      let snapshot = mkSnapshot modelProxy tagProxy ref' payload
      let newNode = NRecord newId (SomeNodeSnapshot snapshot)
      put
        (GBuilderState (Ur (newId + 1)) (Ur (oldNodes P.++ [newNode])) oldEvents)
      return (Ur newId, Ur payload)

emitEvent :: Event model desc -> GBuilder model desc ()
emitEvent event = do
  GBuilderState oldNext oldNodes (Ur oldEvents) <- get
  put (GBuilderState oldNext oldNodes (Ur (oldEvents P.++ [event])))

explain :: desc acts -> OwedList model acts %1 -> GBuilder model desc ()
explain desc owedList =
  case descListToTraceOps owedList of
    Ur ops -> emitEvent (Event desc ops)

create ::
     forall model desc tag. TracePayload model tag
  => Payload tag
     %1 -> GBuilder model desc (Created model tag)
create payload0 = do
  (Ur nid, Ur payload) <-
    storeNRecord (Proxy :: Proxy model) (Proxy :: Proxy tag) payload0
  let ref' = mkNRef (Proxy :: Proxy tag) nid
  return
    (Created
       (N (Ur nid) (Ur payload))
       (makeOp1
          TraceCreate
          (Proxy :: Proxy model)
          (Proxy :: Proxy tag)
          ref'
          payload))

observe ::
     forall model desc tag. TracePayload model tag
  => N tag
     %1 -> GBuilder model desc (Observed model tag)
observe (N (Ur nid) (Ur payload)) = do
  let ref' = mkNRef (Proxy :: Proxy tag) nid
  return
    (Observed
       (N (Ur nid) (Ur payload))
       (makeOp1
          TraceObserve
          (Proxy :: Proxy model)
          (Proxy :: Proxy tag)
          ref'
          payload))

use ::
     forall model desc tag. TracePayload model tag
  => N tag
     %1 -> GBuilder model desc (Used model tag)
use (N (Ur nid) (Ur payload)) = do
  let ref' = mkNRef (Proxy :: Proxy tag) nid
  return
    (Used
       (OneUse payload)
       (makeOp1
          TraceUse
          (Proxy :: Proxy model)
          (Proxy :: Proxy tag)
          ref'
          payload))

copy ::
     forall model desc tag. TracePayload model tag
  => N tag
     %1 -> GBuilder model desc (Copied model tag)
copy (N (Ur originalId) (Ur payload)) = do
  (Ur copyId, Ur copiedPayload) <-
    storeNRecord (Proxy :: Proxy model) (Proxy :: Proxy tag) payload
  let originalRef = mkNRef (Proxy :: Proxy tag) originalId
  let copyRef = mkNRef (Proxy :: Proxy tag) copyId
  return
    (Copied
       (N (Ur originalId) (Ur payload))
       (N (Ur copyId) (Ur copiedPayload))
       (makeOp2
          TraceCopy
          (Proxy :: Proxy model)
          (Proxy :: Proxy tag)
          originalRef
          payload
          copyRef
          copiedPayload))

replace ::
     forall model desc tag. TracePayload model tag
  => N tag
     %1 -> N tag
     %1 -> GBuilder model desc (Replaced model tag)
replace oldNode newNode =
  case oldNode of
    N (Ur oldId) (Ur oldPayload) ->
      case newNode of
        N (Ur newId) (Ur newPayload) -> do
          let oldRef = mkNRef (Proxy :: Proxy tag) oldId
          let newRef = mkNRef (Proxy :: Proxy tag) newId
          return
            (Replaced
               (N (Ur newId) (Ur newPayload))
               (makeOp2
                  TraceReplace
                  (Proxy :: Proxy model)
                  (Proxy :: Proxy tag)
                  oldRef
                  oldPayload
                  newRef
                  newPayload))

compute ::
     forall model desc tag. TracePayload model tag
  => OneUse (Payload tag)
     %1 -> GBuilder model desc (Computed model tag)
compute (OneUse payload0) = do
  (Ur nid, Ur payload) <-
    storeNRecord (Proxy :: Proxy model) (Proxy :: Proxy tag) payload0
  let ref' = mkNRef (Proxy :: Proxy tag) nid
  return
    (Computed
       (N (Ur nid) (Ur payload))
       (makeOp1
          TraceCompute
          (Proxy :: Proxy model)
          (Proxy :: Proxy tag)
          ref'
          payload))

destroy ::
     forall model desc tag. TracePayload model tag
  => N tag
     %1 -> GBuilder model desc (Destroyed model tag)
destroy (N (Ur nid) (Ur payload)) = do
  let ref' = mkNRef (Proxy :: Proxy tag) nid
  return
    (Destroyed
       (makeOp1
          TraceDestroy
          (Proxy :: Proxy model)
          (Proxy :: Proxy tag)
          ref'
          payload))

buildGraph :: GBuilder model desc () -> G model desc
buildGraph builder =
  let (_, finalState) = runState builder (GBuilderState (Ur 0) (Ur []) (Ur []))
      GBuilderState (Ur _) (Ur finalNodes) (Ur finalEvents) = finalState
   in G finalNodes finalEvents
