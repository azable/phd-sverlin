{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
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
    Parent,
    Observed (Observed),
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
  show (NRecord nid parents content) =
    padRight 10 ("[N" P.++ P.show nid P.++ "]")
      P.++ padRight 14 (P.show parents)
      P.++ padRight 20 (P.show content)
    where
      padRight :: Int -> String -> String
      padRight n s = s P.++ P.replicate (n P.- P.length s) ' '

-- Linear node handle.
--
-- The constructor is not exported, so users cannot fabricate node handles.

data N content tag where
  N :: Ur NId %1 -> Ur (content tag) %1 -> N content tag

instance Consumable (N content tag) where
  consume (N nid content) =
    consume nid `lseq` consume content

data Parent content where
  Parent :: NId -> Parent content

parentId :: Parent content -> NId
parentId (Parent nid) = nid

data Observed content tag where
  Observed ::
    Parent content ->
    content tag ->
    Observed content tag

data NSnapshot content tag where
  NSnapshot ::
    Parent content ->
    content tag ->
    NSnapshot content tag

instance (P.Show (content tag)) => P.Show (NSnapshot content tag) where
  show (NSnapshot (Parent nid) _) =
    "$[N" P.++ P.show nid P.++ "]"

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
(<<<) (N (Ur nid) (Ur content)) = return (Observed (Parent nid) content)

freeze :: N content tag %1 -> Ur (NSnapshot content tag)
freeze (N (Ur nid) (Ur content)) =
  Ur (NSnapshot (Parent nid) content)

makeNRecord :: content tag -> [Parent content] -> GBuilder content (Ur NId)
makeNRecord content parents = do
  GBuilderState (Ur oldNextId) (Ur oldNodes) <- get

  let newId = oldNextId
      parentIds = P.map parentId parents
      newNode = NRecord newId parentIds (Some content)

  put (GBuilderState (Ur (newId + 1)) (Ur (oldNodes P.++ [newNode])))
  return (Ur newId)

makeN :: content tag -> [Parent content] -> GBuilder content (N content tag)
makeN content parents = do
  Ur nid <- makeNRecord content parents
  return (N (Ur nid) (Ur content))

(>>>) :: [Parent content] -> content tag -> GBuilder content (N content tag)
(>>>) parents content = makeN content parents

discard :: N content tag %1 -> GBuilder content ()
discard node =
  consume node `lseq` return ()

buildGraph :: GBuilder content tag -> G content
buildGraph builder =
  let (_, finalState) = runState builder (GBuilderState (Ur 0) (Ur []))
      GBuilderState (Ur _) (Ur finalNodes) = finalState
   in G finalNodes
