{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE EmptyDataDecls        #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE LinearTypes           #-}
{-# LANGUAGE QuantifiedConstraints #-}
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
  , NRecord(..)
  , Some(..)
  , Observation(..)
  , SomeObservation(..)
  , Event(..)
  , -- * Internal trace data
    TraceAction(..)
  , TraceOp(..)
  , SomeTraceOp(..)
  , traceActionName
  , -- * Internal builder state
    GBuilderState(..)
  , buildGraph
  , mkNRef
  , makeObservation
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
type NId = Int

type family Payload tag :: Type

data PayloadView =
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

data Some where
  Some :: NRef tag -> PayloadView -> Some

data NRecord =
  NRecord NId Some

data N tag where
  N :: Ur NId %1 -> Ur (Payload tag) %1 -> N tag

data Observation tag where
  Observation :: NRef tag -> PayloadView -> Observation tag

data SomeObservation where
  SomeObservation :: Observation tag -> SomeObservation

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

data TraceAction act where
  TraceCreate :: TraceAction (Create tag)
  TraceObserve :: TraceAction (Observe tag)
  TraceUse :: TraceAction (Use tag)
  TraceCopy :: TraceAction (Copy tag)
  TraceReplace :: TraceAction (Replace tag)
  TraceCompute :: TraceAction (Compute tag)
  TraceDestroy :: TraceAction (Destroy tag)

traceActionName :: TraceAction act -> String
traceActionName TraceCreate  = "create"
traceActionName TraceObserve = "observe"
traceActionName TraceUse     = "use"
traceActionName TraceCopy    = "copy"
traceActionName TraceReplace = "replace"
traceActionName TraceCompute = "compute"
traceActionName TraceDestroy = "destroy"

data TraceOp act where
  TraceOp :: TraceAction act -> [SomeObservation] -> TraceOp act

data SomeTraceOp where
  SomeTraceOp :: TraceOp act -> SomeTraceOp

data Owed act where
  Owed :: Ur (TraceOp act) %1 -> Owed act

data OwedList acts where
  PaidDebt :: OwedList '[]
  (:~) :: Owed act %1 -> OwedList acts %1 -> OwedList (act : acts)

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

data Event (desc :: [Type] -> Type) where
  Event :: desc acts -> [SomeTraceOp] -> Event desc

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

mkNRef :: Proxy tag -> NId -> NRef tag
mkNRef _ = NRef

makeObservation ::
     TracePayload tag => Proxy tag -> NRef tag -> Payload tag -> SomeObservation
makeObservation proxy r payload =
  SomeObservation (Observation r (payloadView proxy payload))

makeOp1 ::
     TracePayload tag
  => TraceAction (Action kind tag)
  -> Proxy tag
  -> NRef tag
  -> Payload tag
  -> Owed (Action kind tag)
makeOp1 action proxy r payload =
  Owed (Ur (TraceOp action [makeObservation proxy r payload]))

makeOp2 ::
     TracePayload tag
  => TraceAction (Action kind tag)
  -> Proxy tag
  -> NRef tag
  -> Payload tag
  -> NRef tag
  -> Payload tag
  -> Owed (Action kind tag)
makeOp2 action proxy r1 payload1 r2 payload2 =
  Owed
    (Ur
       (TraceOp
          action
          [makeObservation proxy r1 payload1, makeObservation proxy r2 payload2]))

descToTraceOp :: Owed act %1 -> Ur SomeTraceOp
descToTraceOp (Owed op) =
  case op of
    Ur traceOp -> Ur (SomeTraceOp traceOp)

descListToTraceOps :: OwedList acts %1 -> Ur [SomeTraceOp]
descListToTraceOps PaidDebt = Ur []
descListToTraceOps (desc :~ rest) =
  case descToTraceOp desc of
    Ur op ->
      case descListToTraceOps rest of
        Ur restOps -> Ur (op : restOps)

unsafeUr :: forall a. a %1 -> Ur a
unsafeUr = Unsafe.unsafeCoerce (Ur :: a -> Ur a)

storeNRecord ::
     forall desc tag. TracePayload tag
  => Proxy tag
  -> Payload tag
     %1 -> GBuilder desc (Ur NId, Ur (Payload tag))
storeNRecord proxy payload0 =
  case unsafeUr payload0 of
    Ur payload -> do
      GBuilderState (Ur oldNextId) (Ur oldNodes) oldEvents <- get
      let newId = oldNextId
      let ref' = mkNRef proxy newId
      let payloadSnapshot = payloadView proxy payload
      let newNode = NRecord newId (Some ref' payloadSnapshot)
      put
        (GBuilderState (Ur (newId + 1)) (Ur (oldNodes P.++ [newNode])) oldEvents)
      return (Ur newId, Ur payload)

emitEvent :: Event desc -> GBuilder desc ()
emitEvent event = do
  GBuilderState oldNext oldNodes (Ur oldEvents) <- get
  put (GBuilderState oldNext oldNodes (Ur (oldEvents P.++ [event])))

explain :: desc acts -> OwedList acts %1 -> GBuilder desc ()
explain desc descList =
  case descListToTraceOps descList of
    Ur ops -> emitEvent (Event desc ops)

create ::
     forall desc tag. TracePayload tag
  => Payload tag
     %1 -> GBuilder desc (Created tag)
create payload0 = do
  (Ur nid, Ur payload) <- storeNRecord (Proxy :: Proxy tag) payload0
  let ref' = NRef nid
  return
    (Created
       (N (Ur nid) (Ur payload))
       (makeOp1 TraceCreate (Proxy :: Proxy tag) ref' payload))

observe ::
     forall desc tag. TracePayload tag
  => N tag
     %1 -> GBuilder desc (Observed tag)
observe (N (Ur nid) (Ur payload)) =
  return
    (Observed
       (N (Ur nid) (Ur payload))
       (makeOp1 TraceObserve (Proxy :: Proxy tag) (NRef nid) payload))

use ::
     forall desc tag. TracePayload tag
  => N tag
     %1 -> GBuilder desc (Used tag)
use (N (Ur nid) (Ur payload)) =
  return
    (Used
       (OneUse payload)
       (makeOp1 TraceUse (Proxy :: Proxy tag) (NRef nid) payload))

copy ::
     forall desc tag. TracePayload tag
  => N tag
     %1 -> GBuilder desc (Copied tag)
copy (N (Ur originalId) (Ur payload)) = do
  (Ur copyId, Ur copiedPayload) <- storeNRecord (Proxy :: Proxy tag) payload
  let originalRef = NRef originalId
  let copyRef = NRef copyId
  return
    (Copied
       (N (Ur originalId) (Ur payload))
       (N (Ur copyId) (Ur copiedPayload))
       (makeOp2
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
        N (Ur newId) (Ur newPayload) ->
          return
            (Replaced
               (N (Ur newId) (Ur newPayload))
               (makeOp2
                  TraceReplace
                  (Proxy :: Proxy tag)
                  (NRef oldId)
                  oldPayload
                  (NRef newId)
                  newPayload))

compute ::
     forall desc tag. TracePayload tag
  => OneUse (Payload tag)
     %1 -> GBuilder desc (Computed tag)
compute (OneUse payload0) = do
  (Ur nid, Ur payload) <- storeNRecord (Proxy :: Proxy tag) payload0
  let ref' = NRef nid
  return
    (Computed
       (N (Ur nid) (Ur payload))
       (makeOp1 TraceCompute (Proxy :: Proxy tag) ref' payload))

destroy ::
     forall desc tag. TracePayload tag
  => N tag
     %1 -> GBuilder desc (Destroyed tag)
destroy (N (Ur nid) (Ur payload)) =
  return
    (Destroyed (makeOp1 TraceDestroy (Proxy :: Proxy tag) (NRef nid) payload))

buildGraph :: GBuilder desc () -> G desc
buildGraph builder =
  let (_, finalState) = runState builder (GBuilderState (Ur 0) (Ur []) (Ur []))
      GBuilderState (Ur _) (Ur finalNodes) (Ur finalEvents) = finalState
   in G finalNodes finalEvents
