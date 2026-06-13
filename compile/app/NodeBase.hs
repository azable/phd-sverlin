{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE LinearTypes           #-}
{-# LANGUAGE QuantifiedConstraints #-}
{-# LANGUAGE RebindableSyntax      #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}

module NodeBase
  ( G(..)
  , GBuilder
  , GBuilderState(..)
  , NRecord(..)
  , TraceAction(..)
  , TraceOp(..)
  , SomeTraceOp(..)
  , Event(..)
  , Some
  , SomeObservation
  , NId
  , N
  , NRef
  , Observation
  , Payload
  , OneUse
  , (<$>)
  , (<*>)
  , Create
  , Observe
  , Use
  , Copy
  , Replace
  , Compute
  , Destroy
  , Owed
  , OwedList(..)
  , Created(..)
  , Observed(..)
  , Used(..)
  , Copied(..)
  , Replaced(..)
  , Computed(..)
  , Destroyed(..)
  , ShowDesc(..)
  , traceActionName
  , create
  , observe
  , use
  , copy
  , replace
  , compute
  , destroy
  , explain
  , -- Graph building and rendering
    buildGraph
  , renderGraph
  , printGraph
  ) where

import           Control.Functor.Linear hiding ((<$>), (<*>))
import           Data.Kind              (Type)
import           Data.Proxy             (Proxy (..))
import qualified Prelude                as P
import           Prelude.Linear
import qualified Unsafe.Coerce          as Unsafe

infixl 4 <$>
infixl 4 <*>
type NId = Int

type family Payload tag :: Type

data OneUse a where
  OneUse :: a %1 -> OneUse a

(<$>) :: (a %1 -> b) %1 -> OneUse a %1 -> OneUse b
f <$> OneUse x = OneUse (f x)

(<*>) :: OneUse (a %1 -> b) %1 -> OneUse a %1 -> OneUse b
OneUse f <*> OneUse x = OneUse (f x)

data NRef tag where
  NRef :: NId -> NRef tag

instance P.Show (NRef tag) where
  show (NRef nid) = "[N" P.++ P.show nid P.++ "]"

data Some where
  Some :: (P.Show (Payload tag)) => NRef tag -> Payload tag -> Some

instance P.Show Some where
  show (Some _ payload) = P.show payload

data NRecord = NRecord
  { nodeId      :: NId
  , nodePayload :: Some
  }

instance P.Show NRecord where
  show (NRecord nid payload) =
    padRight 10 ("[N" P.++ P.show nid P.++ "]") P.++ P.show payload

data N tag where
  N :: Ur NId %1 -> Ur (Payload tag) %1 -> N tag

data Observation tag where
  Observation
    :: (P.Show (Payload tag)) => NRef tag -> Payload tag -> Observation tag

instance P.Show (Observation tag) where
  show (Observation r payload) = P.show r P.++ " " P.++ P.show payload

data SomeObservation where
  SomeObservation :: Observation tag -> SomeObservation

instance P.Show SomeObservation where
  show (SomeObservation obs) = P.show obs

data Create tag

data Observe tag

data Use tag

data Copy tag

data Replace tag

data Compute tag

data Destroy tag

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

data TraceOp act = TraceOp
  { traceOpAction       :: TraceAction act
  , traceOpObservations :: [SomeObservation]
  }

instance P.Show (TraceOp act) where
  show (TraceOp action observations) =
    traceActionName action
      P.++ " "
      P.++ joinWith ", " (P.map P.show observations)

data SomeTraceOp where
  SomeTraceOp :: TraceOp act -> SomeTraceOp

instance P.Show SomeTraceOp where
  show (SomeTraceOp op) = P.show op

data Owed act where
  Owed :: Ur (TraceOp act) %1 -> Owed act

data OwedList acts where
  PaidDebt :: OwedList '[]
  (:~) :: Owed act %1 -> OwedList acts %1 -> OwedList (act : acts)

infixr 5 :~
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

data G (desc :: [Type] -> Type) = G
  { graphNodes  :: [NRecord]
  , graphEvents :: [Event desc]
  }

class ShowDesc desc where
  showDesc :: desc acts -> String

instance (ShowDesc desc) => P.Show (Event desc) where
  show (Event desc ops) =
    padRight 14 (showDesc desc) P.++ joinWith " | " (P.map P.show ops)

instance (ShowDesc desc) => P.Show (G desc) where
  show (G ns es) =
    "Nodes:\n"
      P.++ P.concatMap showNode ns
      P.++ "Events:\n"
      P.++ P.concatMap showEvent es
    where
      showNode n = "  " P.++ P.show n P.++ "\n"
      showEvent e = "  " P.++ P.show e P.++ "\n"

data GBuilderState (desc :: [Type] -> Type) = GBuilderState
  { nextId :: Ur NId
  , nodes  :: Ur [NRecord]
  , events :: Ur [Event desc]
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

type GBuilder desc = State (GBuilderState desc)

mkNRef :: Proxy tag -> NId -> NRef tag
mkNRef _ = NRef

makeObservation ::
     (P.Show (Payload tag))
  => Proxy tag
  -> NRef tag
  -> Payload tag
  -> SomeObservation
makeObservation _ r payload = SomeObservation (Observation r payload)

makeOp1 ::
     (P.Show (Payload tag))
  => TraceAction act
  -> Proxy tag
  -> NRef tag
  -> Payload tag
  -> Owed act
makeOp1 action proxy r payload =
  Owed (Ur (TraceOp action [makeObservation proxy r payload]))

makeOp2 ::
     (P.Show (Payload tag1), P.Show (Payload tag2))
  => TraceAction act
  -> Proxy tag1
  -> NRef tag1
  -> Payload tag1
  -> Proxy tag2
  -> NRef tag2
  -> Payload tag2
  -> Owed act
makeOp2 action proxy1 r1 payload1 proxy2 r2 payload2 =
  Owed
    (Ur
       (TraceOp
          action
          [ makeObservation proxy1 r1 payload1
          , makeObservation proxy2 r2 payload2
          ]))

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
     forall desc tag. (P.Show (Payload tag))
  => Proxy tag
  -> Payload tag
     %1 -> GBuilder desc (Ur NId, Ur (Payload tag))
storeNRecord _ payload0 =
  case unsafeUr payload0 of
    Ur payload -> do
      GBuilderState (Ur oldNextId) (Ur oldNodes) oldEvents <- get
      let newId = oldNextId
      let ref' = mkNRef (Proxy :: Proxy tag) newId
      let newNode = NRecord newId (Some ref' payload)
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
     forall desc tag. (P.Show (Payload tag))
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
     forall desc tag. (P.Show (Payload tag))
  => N tag
     %1 -> GBuilder desc (Observed tag)
observe (N (Ur nid) (Ur payload)) =
  return
    (Observed
       (N (Ur nid) (Ur payload))
       (makeOp1 TraceObserve (Proxy :: Proxy tag) (NRef nid) payload))

use ::
     forall desc tag. (P.Show (Payload tag))
  => N tag
     %1 -> GBuilder desc (Used tag)
use (N (Ur nid) (Ur payload)) =
  return
    (Used
       (OneUse payload)
       (makeOp1 TraceUse (Proxy :: Proxy tag) (NRef nid) payload))

copy ::
     forall desc tag. (P.Show (Payload tag))
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
          (Proxy :: Proxy tag)
          copyRef
          copiedPayload))

replace ::
     forall desc tag. (P.Show (Payload tag))
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
                  (Proxy :: Proxy tag)
                  (NRef newId)
                  newPayload))

compute ::
     forall desc tag. (P.Show (Payload tag))
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
     forall desc tag. (P.Show (Payload tag))
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

renderGraph :: (ShowDesc desc) => G desc -> String
renderGraph (G ns es) =
  renderHeader "Graph"
    P.++ renderSummary ns es
    P.++ "\n"
    P.++ renderNodes ns
    P.++ "\n"
    P.++ renderTrace es

printGraph :: (ShowDesc desc) => G desc -> P.IO ()
printGraph graph = P.putStr (renderGraph graph)

renderSummary :: [NRecord] -> [Event desc] -> String
renderSummary ns es =
  "Nodes:  "
    P.++ P.show (P.length ns)
    P.++ "\n"
    P.++ "Events: "
    P.++ P.show (P.length es)
    P.++ "\n"

renderNodes :: [NRecord] -> String
renderNodes ns = renderHeader "Nodes" P.++ P.concatMap renderNode ns

renderNode :: NRecord -> String
renderNode (NRecord nid payload) =
  "  " P.++ padRight 8 ("N" P.++ P.show nid) P.++ P.show payload P.++ "\n"

renderTrace :: (ShowDesc desc) => [Event desc] -> String
renderTrace es =
  renderHeader "Trace"
    P.++ P.concat (P.zipWith renderEvent (P.enumFrom (0 :: Int)) es)

renderEvent :: (ShowDesc desc) => Int -> Event desc -> String
renderEvent ix (Event desc ops) =
  padLeft 3 (P.show ix)
    P.++ " | "
    P.++ showDesc desc
    P.++ "\n"
    P.++ P.concatMap renderTraceOp ops
    P.++ "\n"

renderTraceOp :: SomeTraceOp -> String
renderTraceOp (SomeTraceOp (TraceOp action observations)) =
  case observations of
    [] -> renderTraceOpName (traceActionName action) P.++ "\n"
    first:rest ->
      renderTaggedObservation (traceActionName action) first
        P.++ P.concatMap renderUntaggedObservation rest

renderTaggedObservation :: String -> SomeObservation -> String
renderTaggedObservation name observation =
  renderTraceOpName name P.++ "  " P.++ P.show observation P.++ "\n"

renderUntaggedObservation :: SomeObservation -> String
renderUntaggedObservation observation =
  renderTraceOpName "" P.++ "  " P.++ P.show observation P.++ "\n"

renderTraceOpName :: String -> String
renderTraceOpName name = "    " P.++ padLeft 11 name

renderHeader :: String -> String
renderHeader title =
  title P.++ "\n" P.++ P.replicate (P.length title) '-' P.++ "\n"

padRight :: Int -> String -> String
padRight n s = s P.++ P.replicate (n P.- P.length s) ' '

padLeft :: Int -> String -> String
padLeft n s = P.replicate (n P.- P.length s) ' ' P.++ s

joinWith :: String -> [String] -> String
joinWith _ []       = ""
joinWith _ [x]      = x
joinWith sep (x:xs) = x P.++ sep P.++ joinWith sep xs
