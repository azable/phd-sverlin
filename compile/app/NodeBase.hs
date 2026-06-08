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
    Observation (..),
    Observed (Observed),
    HasRef (..),
    ToRefs (..),
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

data NRecord content = NRecord
  { nodeId :: NId,
    -- These are the IDs of nodes this node depends on.
    --
    -- This is graph provenance, not the node's own identity.
    nodeParents :: [NId],
    nodeContent :: Some content
  }

instance (forall tag. P.Show (content tag)) => P.Show (NRecord content) where
  show (NRecord nid parents nodeContent') =
    padRight 10 ("[N" P.++ P.show nid P.++ "]")
      P.++ padRight 14 (P.show parents)
      P.++ padRight 20 (P.show nodeContent')
    where
      padRight :: Int -> String -> String
      padRight n s = s P.++ P.replicate (n P.- P.length s) ' '

-- Linear node handle.
--
-- The constructor is not exported, so users cannot fabricate node handles.

data N content tag where
  N :: Ur NId %1 -> Ur (content tag) %1 -> N content tag

instance Consumable (N content tag) where
  consume (N nid nodeContent') =
    consume nid `lseq` consume nodeContent'

-- A reference to a graph node.
--
-- This is the node's own identity. It can later be used as one parent/input
-- when constructing another node.
--
-- It is deliberately not called Parent, because a node can itself have many
-- parents in its NRecord.

data NRef content where
  NRef :: NId -> NRef content

refId :: NRef content -> NId
refId (NRef nid) = nid

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

instance (P.Show (content tag)) => P.Show (NSnapshot content tag) where
  show (NSnapshot (NRef nid) _) =
    "$[N" P.++ P.show nid P.++ "]"

-- Anything that has a node reference.

class HasRef x content where
  toRef :: x -> NRef content

instance HasRef (NRef content) content where
  toRef = id

instance HasRef (Observation content tag) content where
  toRef = ref

instance HasRef (NSnapshot content tag) content where
  toRef (NSnapshot r _) = r

-- Things that can be converted into a list of node references.
--
-- These references become the parents/provenance of the newly emitted node.

class ToRefs ps content where
  toRefs :: ps -> [NRef content]

instance ToRefs () content where
  toRefs () = []

instance ToRefs [NRef content] content where
  toRefs = id

instance ToRefs (NRef content) content where
  toRefs r = [r]

instance ToRefs (Observation content tag) content where
  toRefs obs = [toRef obs]

instance ToRefs (NSnapshot content tag) content where
  toRefs snapshot = [toRef snapshot]

instance
  ( HasRef a content,
    HasRef b content
  ) =>
  ToRefs (a, b) content
  where
  toRefs (a, b) =
    [toRef a, toRef b]

instance
  ( HasRef a content,
    HasRef b content,
    HasRef c content
  ) =>
  ToRefs (a, b, c) content
  where
  toRefs (a, b, c) =
    [toRef a, toRef b, toRef c]

instance
  ( HasRef a content,
    HasRef b content,
    HasRef c content,
    HasRef d content
  ) =>
  ToRefs (a, b, c, d) content
  where
  toRefs (a, b, c, d) =
    [toRef a, toRef b, toRef c, toRef d]

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

makeNRecord :: content tag -> [NRef content] -> GBuilder content (Ur NId)
makeNRecord nodeContent' refs = do
  GBuilderState (Ur oldNextId) (Ur oldNodes) <- get

  let newId = oldNextId
      parentIds = P.map refId refs
      newNode = NRecord newId parentIds (Some nodeContent')

  put (GBuilderState (Ur (newId + 1)) (Ur (oldNodes P.++ [newNode])))
  return (Ur newId)

makeN :: content tag -> [NRef content] -> GBuilder content (N content tag)
makeN nodeContent' refs = do
  Ur nid <- makeNRecord nodeContent' refs
  return (N (Ur nid) (Ur nodeContent'))

(>>>) ::
  (ToRefs ps content) =>
  ps ->
  content tag ->
  GBuilder content (N content tag)
refs >>> nodeContent' =
  makeN nodeContent' (toRefs refs)

discard :: N content tag %1 -> GBuilder content ()
discard node =
  consume node `lseq` return ()

buildGraph :: GBuilder content tag -> G content
buildGraph builder =
  let (_, finalState) = runState builder (GBuilderState (Ur 0) (Ur []))
      GBuilderState (Ur _) (Ur finalNodes) = finalState
   in G finalNodes
