{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LinearTypes #-}
{-# LANGUAGE MultiParamTypeClasses #-}
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
    NRef,
    ParentRecord (..),
    ParentLink (..),
    Observation (..),
    Observed (Observed),
    ToParentRecord (..),
    (<<<),
    (>>>),
    NSnapshot (..),
    freeze,
    discard,
    buildGraph,
  )
where

import Control.Functor.Linear
import Prelude.Linear
import Prelude qualified as P

-- Generic node layer

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
  show (Continued nid) = "continue N" P.++ P.show nid
  show (Copied nid) = "    copy N" P.++ P.show nid

data NRecord content = NRecord
  { nodeId :: NId,
    nodeParent :: ParentRecord,
    nodeContent :: Some content
  }

instance (forall tag. P.Show (content tag)) => P.Show (NRecord content) where
  show (NRecord nid parentRecord nodeContent') =
    padRight 10 ("[N" P.++ P.show nid P.++ "]")
      P.++ padRight 24 (P.show parentRecord)
      P.++ padRight 20 (P.show nodeContent')
    where
      padRight :: Int -> String -> String
      padRight n s = s P.++ P.replicate (n P.- P.length s) ' '

data N content tag where
  N :: Ur NId %1 -> Ur (content tag) %1 -> N content tag

instance Consumable (N content tag) where
  consume (N nid nodeContent') =
    consume nid `lseq` consume nodeContent'

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

-- Domain-specific Ur-like wrapper.
--
-- Pattern matching:
--
--   Observed obs <- ...
--
-- gives an unrestricted Observation value.

data Observed content tag where
  Observed :: Observation content tag -> Observed content tag

data NSnapshot content tag where
  NSnapshot ::
    NRef content ->
    content tag ->
    NSnapshot content tag

snapshotRef :: NSnapshot content tag -> NRef content
snapshotRef (NSnapshot r _) = r

instance (P.Show (content tag)) => P.Show (NSnapshot content tag) where
  show (NSnapshot (NRef nid) _) =
    "$[N" P.++ P.show nid P.++ "]"

class ToParentRecord p where
  toParentRecord :: p -> ParentRecord

instance ToParentRecord () where
  toParentRecord () = NoParent

instance ToParentRecord (NRef content) where
  toParentRecord r =
    Continued (refId r)

instance ToParentRecord (Observation content tag) where
  toParentRecord obs =
    Continued (refId (ref obs))

instance ToParentRecord (NSnapshot content tag) where
  toParentRecord snapshot =
    Copied (refId (snapshotRef snapshot))

instance ToParentRecord (ParentLink content) where
  toParentRecord =
    parentLinkToRecord

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

freeze :: N content tag %1 -> Ur (NSnapshot content tag)
freeze (N (Ur nid) (Ur nodeContent')) =
  Ur (NSnapshot (NRef nid) nodeContent')

makeNRecord ::
  content tag ->
  ParentRecord ->
  GBuilder content (Ur NId)
makeNRecord nodeContent' parentRecord = do
  GBuilderState (Ur oldNextId) (Ur oldNodes) <- get

  let newId = oldNextId
      newNode = NRecord newId parentRecord (Some nodeContent')

  put (GBuilderState (Ur (newId + 1)) (Ur (oldNodes P.++ [newNode])))
  return (Ur newId)

makeN ::
  content tag ->
  ParentRecord ->
  GBuilder content (N content tag)
makeN nodeContent' parentRecord = do
  Ur nid <- makeNRecord nodeContent' parentRecord
  return (N (Ur nid) (Ur nodeContent'))

(>>>) ::
  (ToParentRecord parent) =>
  parent ->
  content tag ->
  GBuilder content (N content tag)
parent >>> nodeContent' = makeN nodeContent' (toParentRecord parent)

discard :: N content tag %1 -> GBuilder content ()
discard node =
  consume node `lseq` return ()

buildGraph :: GBuilder content tag -> G content
buildGraph builder =
  let (_, finalState) = runState builder (GBuilderState (Ur 0) (Ur []))
      GBuilderState (Ur _) (Ur finalNodes) = finalState
   in G finalNodes
