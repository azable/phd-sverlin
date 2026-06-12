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
  , create
  , observe
  , use
  , copy
  , replace
  , compute
  , destroy
  , explain
  , buildGraph
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

data Owed act where
  Owed :: Ur [SomeObservation] %1 -> Owed act

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
  Event :: desc acts -> [SomeObservation] -> Event desc

data G (desc :: [Type] -> Type) = G
  { graphNodes  :: [NRecord]
  , graphEvents :: [Event desc]
  }

class ShowDesc desc where
  showDesc :: desc acts -> String

instance (ShowDesc desc) => P.Show (Event desc) where
  show (Event desc observations) =
    padRight 14 (showDesc desc) P.++ joinWith ", " (P.map P.show observations)

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

makeDesc1 ::
     (P.Show (Payload tag)) => Proxy tag -> NRef tag -> Payload tag -> Owed act
makeDesc1 proxy r payload = Owed (Ur [makeObservation proxy r payload])

makeDesc2 ::
     (P.Show (Payload tag1), P.Show (Payload tag2))
  => Proxy tag1
  -> NRef tag1
  -> Payload tag1
  -> Proxy tag2
  -> NRef tag2
  -> Payload tag2
  -> Owed act
makeDesc2 proxy1 r1 payload1 proxy2 r2 payload2 =
  Owed
    (Ur [makeObservation proxy1 r1 payload1, makeObservation proxy2 r2 payload2])

descToObservations :: Owed act %1 -> Ur [SomeObservation]
descToObservations (Owed observations) = observations

descListToObservations :: OwedList acts %1 -> Ur [SomeObservation]
descListToObservations PaidDebt = Ur []
descListToObservations (desc :~ rest) =
  case descToObservations desc of
    Ur observations ->
      case descListToObservations rest of
        Ur restObservations -> Ur (observations P.++ restObservations)

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
  case descListToObservations descList of
    Ur observations -> emitEvent (Event desc observations)

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
       (makeDesc1 (Proxy :: Proxy tag) ref' payload))

observe ::
     forall desc tag. (P.Show (Payload tag))
  => N tag
     %1 -> GBuilder desc (Observed tag)
observe (N (Ur nid) (Ur payload)) =
  return
    (Observed
       (N (Ur nid) (Ur payload))
       (makeDesc1 (Proxy :: Proxy tag) (NRef nid) payload))

use ::
     forall desc tag. (P.Show (Payload tag))
  => N tag
     %1 -> GBuilder desc (Used tag)
use (N (Ur nid) (Ur payload)) =
  return
    (Used (OneUse payload) (makeDesc1 (Proxy :: Proxy tag) (NRef nid) payload))

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
       (makeDesc2
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
               (makeDesc2
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
       (makeDesc1 (Proxy :: Proxy tag) ref' payload))

destroy ::
     forall desc tag. (P.Show (Payload tag))
  => N tag
     %1 -> GBuilder desc (Destroyed tag)
destroy (N (Ur nid) (Ur payload)) =
  return (Destroyed (makeDesc1 (Proxy :: Proxy tag) (NRef nid) payload))

buildGraph :: GBuilder desc () -> G desc
buildGraph builder =
  let (_, finalState) = runState builder (GBuilderState (Ur 0) (Ur []) (Ur []))
      GBuilderState (Ur _) (Ur finalNodes) (Ur finalEvents) = finalState
   in G finalNodes finalEvents

padRight :: Int -> String -> String
padRight n s = s P.++ P.replicate (n P.- P.length s) ' '

joinWith :: String -> [String] -> String
joinWith _ []       = ""
joinWith _ [x]      = x
joinWith sep (x:xs) = x P.++ sep P.++ joinWith sep xs
