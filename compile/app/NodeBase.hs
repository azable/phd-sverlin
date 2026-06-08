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
    Observation (..),
    Observed (Observed),
    HasParent (..),
    ToParents (..),
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

data Parent content where
  Parent :: NId -> Parent content

parentId :: Parent content -> NId
parentId (Parent nid) = nid

data Observation content tag = Observation
  { parent :: Parent content,
    content :: content tag
  }

data Observed content tag where
  Observed :: Observation content tag -> Observed content tag

data NSnapshot content tag where
  NSnapshot ::
    Parent content ->
    content tag ->
    NSnapshot content tag

instance (P.Show (content tag)) => P.Show (NSnapshot content tag) where
  show (NSnapshot (Parent nid) _) =
    "$[N" P.++ P.show nid P.++ "]"

-- Anything that can be used as a parent reference.
--
-- This deliberately includes Observed and NSnapshot, so the DSL layer does not
-- need to manually unpack parents everywhere.

class HasParent x content where
  toParent :: x -> Parent content

instance HasParent (Parent content) content where
  toParent = id

instance HasParent (Observation content tag) content where
  toParent = parent

instance HasParent (NSnapshot content tag) content where
  toParent (NSnapshot p _) = p

class ToParents ps content where
  toParents :: ps -> [Parent content]

instance ToParents () content where
  toParents () = []

instance ToParents [Parent content] content where
  toParents = id

instance ToParents (Parent content) content where
  toParents p = [p]

instance ToParents (Observation content tag) content where
  toParents obs = [toParent obs]

instance ToParents (NSnapshot content tag) content where
  toParents snapshot = [toParent snapshot]

instance
  ( HasParent a content,
    HasParent b content
  ) =>
  ToParents (a, b) content
  where
  toParents (a, b) =
    [toParent a, toParent b]

instance
  ( HasParent a content,
    HasParent b content,
    HasParent c content
  ) =>
  ToParents (a, b, c) content
  where
  toParents (a, b, c) =
    [toParent a, toParent b, toParent c]

instance
  ( HasParent a content,
    HasParent b content,
    HasParent c content,
    HasParent d content
  ) =>
  ToParents (a, b, c, d) content
  where
  toParents (a, b, c, d) =
    [toParent a, toParent b, toParent c, toParent d]

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
  return (Observed (Observation (Parent nid) nodeContent'))

freeze :: N content tag %1 -> Ur (NSnapshot content tag)
freeze (N (Ur nid) (Ur nodeContent')) =
  Ur (NSnapshot (Parent nid) nodeContent')

makeNRecord :: content tag -> [Parent content] -> GBuilder content (Ur NId)
makeNRecord nodeContent' parents = do
  GBuilderState (Ur oldNextId) (Ur oldNodes) <- get

  let newId = oldNextId
      parentIds = P.map parentId parents
      newNode = NRecord newId parentIds (Some nodeContent')

  put (GBuilderState (Ur (newId + 1)) (Ur (oldNodes P.++ [newNode])))
  return (Ur newId)

makeN :: content tag -> [Parent content] -> GBuilder content (N content tag)
makeN nodeContent' parents = do
  Ur nid <- makeNRecord nodeContent' parents
  return (N (Ur nid) (Ur nodeContent'))

(>>>) ::
  (ToParents ps content) =>
  ps ->
  content tag ->
  GBuilder content (N content tag)
parents >>> nodeContent' =
  makeN nodeContent' (toParents parents)

discard :: N content tag %1 -> GBuilder content ()
discard node =
  consume node `lseq` return ()

buildGraph :: GBuilder content tag -> G content
buildGraph builder =
  let (_, finalState) = runState builder (GBuilderState (Ur 0) (Ur []))
      GBuilderState (Ur _) (Ur finalNodes) = finalState
   in G finalNodes
