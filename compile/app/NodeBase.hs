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
    NSnapshot (..),
    freeze,
    makeNode,
    dropNode,
    dropNodeM,
    withNode,
    splitNode,
    cloneNode,
    cloneNodeWith,
    cloneNodeFromSnapshot,
    mapNode,
    zipNode2,
    zipNode2WithId,
    zipNode3,
    buildGraph,
  )
where

import Control.Functor.Linear
import Prelude.Linear
import Prelude qualified as P

-- Generic createNode layer

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

data N content tag where
  N :: Ur NId %1 -> Ur (content tag) %1 -> N content tag

instance Consumable (N content tag) where
  consume (N nid content) =
    consume nid `lseq` consume content

data NSnapshot content tag where
  NSnapshot :: NId -> content tag -> NSnapshot content tag

instance (P.Show (content tag)) => P.Show (NSnapshot content tag) where
  show (NSnapshot nid _) =
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

freeze :: N content tag %1 -> Ur (NSnapshot content tag)
freeze node =
  withNode
    node
    ( \nid content ->
        Ur (NSnapshot nid content)
    )

makeNRecord :: content tag -> [NId] -> GBuilder content (Ur NId)
makeNRecord content parentsIds = do
  (GBuilderState (Ur oldNextId) (Ur oldNodes)) <- get
  let newId = oldNextId
      newNode = NRecord newId parentsIds (Some content)
  put (GBuilderState (Ur (newId + 1)) (Ur (oldNodes ++ [newNode])))
  return (Ur newId)

makeN :: content tag -> [NId] -> GBuilder content (N content tag)
makeN content parentsIds = do
  Ur nid <- makeNRecord content parentsIds
  return (N (Ur nid) (Ur content))

withNode :: N content tag %1 -> (NId -> content tag -> r) %1 -> r
withNode (N (Ur nid) (Ur content)) k = k nid content

makeNode :: content tag -> GBuilder content (N content tag)
makeNode content = makeN content []

dropNode :: N content tag %1 -> ()
dropNode = consume

dropNodeM :: N content tag %1 -> GBuilder content ()
dropNodeM node =
  consume node `lseq` return ()

splitNode ::
  N content a %1 ->
  (content a -> (content b, content c)) ->
  GBuilder content (N content b, N content c)
splitNode node f =
  withNode node $ \nid content -> do
    let (outB, outC) = f content
    nodeB <- makeN outB [nid]
    nodeC <- makeN outC [nid]
    return (nodeB, nodeC)

cloneNode ::
  N content a %1 ->
  (content a -> content b) ->
  GBuilder content (N content a, N content b)
cloneNode node f = splitNode node $ \content ->
  let outB = f content
   in (content, outB)

cloneNodeWith ::
  N content a %1 ->
  (content a -> GBuilder content (N content b)) ->
  GBuilder content (N content a, N content b)
cloneNodeWith node f =
  withNode
    node
    ( \nid content -> do
        next <- makeN content [nid]
        out <- f content
        return (next, out)
    )

cloneNodeFromSnapshot :: NSnapshot content tag -> GBuilder content (N content tag)
cloneNodeFromSnapshot (NSnapshot nid content) = makeN content [nid]

mapNode ::
  N content a %1 ->
  (content a -> content b) ->
  GBuilder content (N content b)
mapNode node f =
  withNode node $ \nid content -> do
    makeN (f content) [nid]

zipNode2 ::
  N content a %1 ->
  N content b %1 ->
  (content a -> content b -> content tag) ->
  GBuilder content (N content tag)
zipNode2 nodeA nodeB makeContent =
  withNode nodeA $ \aId contentA ->
    withNode nodeB $ \bId contentB -> do
      let nodes = [aId, bId]
      makeN
        (makeContent contentA contentB)
        nodes

zipNode2WithId ::
  N content a %1 ->
  N content b %1 ->
  (NId -> content a -> NId -> content b -> content tag) ->
  GBuilder content (N content tag)
zipNode2WithId nodeA nodeB makeContent =
  withNode nodeA $ \aId contentA ->
    withNode nodeB $ \bId contentB -> do
      let nodes = [aId, bId]
      makeN
        (makeContent aId contentA bId contentB)
        nodes

zipNode3 ::
  N content a %1 ->
  N content b %1 ->
  N content c %1 ->
  (content a -> content b -> content c -> content tag) ->
  GBuilder content (N content tag)
zipNode3 nodeA nodeB nodeC makeContent =
  withNode nodeA $ \aId contentA ->
    withNode nodeB $ \bId contentB ->
      withNode nodeC $ \cId contentC -> do
        let nodes = [aId, bId, cId]
        makeN
          (makeContent contentA contentB contentC)
          nodes

buildGraph :: GBuilder content tag -> G content
buildGraph builder =
  let (_, finalState) = runState builder (GBuilderState (Ur 0) (Ur []))
      (GBuilderState (Ur _) (Ur nodes)) = finalState
   in G nodes
