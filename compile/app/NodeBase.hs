{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LinearTypes #-}
{-# LANGUAGE QuantifiedConstraints #-}
{-# LANGUAGE RebindableSyntax #-}

module NodeBase
  ( G (..),
    GBuilder,
    GBuilderState (..),
    NRecord (..),
    Some (..),
    NId,
    N,
    CN,
    NRef,
    ParentRecord (..),
    ParentLink (..),
    HeldRecord (..),
    Observation (..),
    Observed (Observed),
    ObservedContainer (ObservedContainer),
    ToParentRecord (..),
    (<<<),
    (>>>),
    container,
    observeC,
    discard,
    discardC,
    copyOut,
    readC,
    writeC,
    buildGraph,
  )
where

import Control.Functor.Linear
import Prelude.Linear
import Prelude qualified as P

type NId = Int

data Some content where
  Some :: content tag -> Some content

instance (forall tag. P.Show (content tag)) => P.Show (Some content) where
  show (Some content) = P.show content

data ParentRecord
  = NoParent
  | Continued NId
  | Copied NId

instance P.Show ParentRecord where
  show NoParent = ""
  show (Continued nid) = "continue [N" P.++ P.show nid P.++ "]"
  show (Copied nid) = "    copy [N" P.++ P.show nid P.++ "]"

data HeldRecord
  = HoldsNone
  | Holds NId

instance P.Show HeldRecord where
  show HoldsNone = ""
  show (Holds nid) = "holds N" P.++ P.show nid

data NRecord content = NRecord
  { nodeId :: NId,
    nodeParent :: ParentRecord,
    nodeHeld :: HeldRecord,
    nodeContent :: Some content
  }

instance (forall tag. P.Show (content tag)) => P.Show (NRecord content) where
  show (NRecord nid parentRecord heldRecord nodeContent') =
    padRight 10 ("[N" P.++ P.show nid P.++ "]")
      P.++ padRight 18 (P.show parentRecord)
      P.++ padRight 14 (P.show heldRecord)
      P.++ padRight 20 (P.show nodeContent')
    where
      padRight :: Int -> String -> String
      padRight n s = s P.++ P.replicate (n P.- P.length s) ' '

data N content tag where
  N :: Ur NId %1 -> Ur (content tag) %1 -> N content tag

instance Consumable (N content tag) where
  consume (N nid nodeContent') =
    consume nid `lseq` consume nodeContent'

data CN content tag heldTag where
  CN ::
    Ur NId %1 ->
    Ur (content tag) %1 ->
    N content heldTag %1 ->
    CN content tag heldTag

instance Consumable (CN content tag heldTag) where
  consume (CN nid nodeContent' held) =
    consume nid `lseq` consume nodeContent' `lseq` consume held

data NRef content where
  NRef :: NId -> NRef content

refId :: NRef content -> NId
refId (NRef nid) = nid

data ParentLink content
  = Continue (NRef content)
  | Copy (NRef content)

parentLinkToRecord :: ParentLink content -> ParentRecord
parentLinkToRecord (Continue r) = Continued (refId r)
parentLinkToRecord (Copy r) = Copied (refId r)

data Observation content tag = Observation
  { ref :: NRef content,
    content :: content tag
  }

data Observed content tag where
  Observed :: Observation content tag -> Observed content tag

data ObservedContainer content tag heldTag where
  ObservedContainer ::
    Observation content tag ->
    N content heldTag %1 ->
    ObservedContainer content tag heldTag

class ToParentRecord p where
  toParentRecord :: p -> ParentRecord

instance ToParentRecord () where
  toParentRecord () = NoParent

instance ToParentRecord (NRef content) where
  toParentRecord r = Continued (refId r)

instance ToParentRecord (Observation content tag) where
  toParentRecord obs = Continued (refId (ref obs))

instance ToParentRecord (ParentLink content) where
  toParentRecord = parentLinkToRecord

newtype G content = G
  { graphNodes :: [NRecord content]
  }

data GBuilderState content = GBuilderState
  { nextId :: Ur NId,
    nodes :: Ur [NRecord content]
  }

instance Consumable (GBuilderState content) where
  consume (GBuilderState next ns) =
    consume next `lseq` consume ns

instance Dupable (GBuilderState content) where
  dup2 (GBuilderState next ns) =
    case dup2 next of
      (next1, next2) ->
        case dup2 ns of
          (ns1, ns2) ->
            (GBuilderState next1 ns1, GBuilderState next2 ns2)

type GBuilder content = State (GBuilderState content)

(<<<) :: N content tag %1 -> GBuilder content (Observed content tag)
(<<<) (N (Ur nid) (Ur nodeContent')) =
  return (Observed (Observation (NRef nid) nodeContent'))

observeC ::
  CN content tag heldTag %1 ->
  GBuilder content (ObservedContainer content tag heldTag)
observeC (CN (Ur nid) (Ur nodeContent') held) =
  return (ObservedContainer (Observation (NRef nid) nodeContent') held)

makeNRecord ::
  content tag ->
  ParentRecord ->
  HeldRecord ->
  GBuilder content (Ur NId)
makeNRecord nodeContent' parentRecord heldRecord = do
  GBuilderState (Ur oldNextId) (Ur oldNodes) <- get

  let newId = oldNextId
      newNode = NRecord newId parentRecord heldRecord (Some nodeContent')

  put (GBuilderState (Ur (newId + 1)) (Ur (oldNodes P.++ [newNode])))
  return (Ur newId)

makeN ::
  content tag ->
  ParentRecord ->
  GBuilder content (N content tag)
makeN nodeContent' parentRecord = do
  Ur nid <- makeNRecord nodeContent' parentRecord HoldsNone
  return (N (Ur nid) (Ur nodeContent'))

makeCN ::
  content tag ->
  ParentRecord ->
  N content heldTag %1 ->
  GBuilder content (CN content tag heldTag)
makeCN nodeContent' parentRecord (N (Ur heldId) heldContent) = do
  Ur nid <- makeNRecord nodeContent' parentRecord (Holds heldId)
  return (CN (Ur nid) (Ur nodeContent') (N (Ur heldId) heldContent))

(>>>) ::
  (ToParentRecord parent) =>
  parent ->
  content tag ->
  GBuilder content (N content tag)
parent >>> nodeContent' =
  makeN nodeContent' (toParentRecord parent)

container ::
  (ToParentRecord parent) =>
  parent ->
  content tag ->
  N content heldTag %1 ->
  GBuilder content (CN content tag heldTag)
container parent nodeContent' held =
  makeCN nodeContent' (toParentRecord parent) held

discard :: N content tag %1 -> GBuilder content ()
discard node =
  consume node `lseq` return ()

discardC :: CN content tag heldTag %1 -> GBuilder content ()
discardC cn = do
  ObservedContainer _ held <- observeC cn
  discard held

copyOut ::
  N content tag %1 ->
  GBuilder content (N content tag, N content tag)
copyOut node = do
  Observed obs <- (<<<) node

  copy <- Copy (ref obs) >>> content obs
  source <- obs >>> content obs

  return (source, copy)

readC ::
  CN content tag heldTag %1 ->
  GBuilder content (CN content tag heldTag, N content heldTag)
readC cn = do
  ObservedContainer obs held <- observeC cn

  (held', copy) <- copyOut held
  cn' <- container obs (content obs) held'

  return (cn', copy)

writeC ::
  CN content tag oldHeldTag %1 ->
  N content newHeldTag %1 ->
  GBuilder content (CN content tag newHeldTag)
writeC cn newHeld = do
  ObservedContainer obs oldHeld <- observeC cn

  discard oldHeld
  container obs (content obs) newHeld

buildGraph :: GBuilder content tag -> G content
buildGraph builder =
  let (_, finalState) = runState builder (GBuilderState (Ur 0) (Ur []))
      GBuilderState (Ur _) (Ur finalNodes) = finalState
   in G finalNodes
