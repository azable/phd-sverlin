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
    N (..),
    Some (..),
    NId,
    NLive (..),
    NPtr (..),
    freezeRef,
    copyPtr,
    node,
    dropNode,
    dropNodeM,
    inspectNode,
    splitNode,
    cloneNode,
    cloneNodeWith,
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

-- Generic node layer

type NId = Int

data Some content where
  Some :: content tag -> Some content

instance (forall tag. P.Show (content tag)) => P.Show (Some content) where
  show (Some content) = P.show content

data N content where
  N :: NId -> Some content -> [NId] -> N content

instance (forall tag. P.Show (content tag)) => P.Show (N content) where
  show (N nid content refs) =
    padRight 10 ("[N" P.++ P.show nid P.++ "]")
      P.++ padRight 14 (P.show refs)
      P.++ padRight 20 (P.show content)
    where
      padRight :: Int -> String -> String
      padRight n s = s P.++ P.replicate (n P.- P.length s) ' '

data NLive content tag where
  NLive :: Ur NId %1 -> Ur (content tag) %1 -> NLive content tag

instance Consumable (NLive content tag) where
  consume (NLive nid content) =
    consume nid `lseq` consume content

data NPtr content tag where
  NPtr :: NId -> content tag -> NPtr content tag

instance (P.Show (content tag)) => P.Show (NPtr content tag) where
  show (NPtr nid _) =
    "[NLive" P.++ P.show nid P.++ "]"

newtype G content = G
  { graphNodes :: [N content]
  }

data GBuilderState content = GBuilderState
  { nextId :: Ur NId,
    nodes :: Ur [N content]
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

freezeRef :: NLive content tag %1 -> Ur (NPtr content tag)
freezeRef ref =
  withNRef
    ref
    ( \nid content ->
        Ur (NPtr nid content)
    )

copyPtr :: NPtr content tag -> GBuilder content (NLive content tag)
copyPtr (NPtr nid content) = makeNRef content [nid]

makeN :: content tag -> [NId] -> GBuilder content (Ur NId)
makeN content refs = do
  (GBuilderState (Ur oldNextId) (Ur oldNodes)) <- get
  let newId = oldNextId
      newNode = N newId (Some content) refs
  put (GBuilderState (Ur (newId + 1)) (Ur (oldNodes ++ [newNode])))
  return (Ur newId)

makeNRef :: content tag -> [NId] -> GBuilder content (NLive content tag)
makeNRef content refs = do
  Ur nid <- makeN content refs
  return (NLive (Ur nid) (Ur content))

withNRef :: NLive content tag %1 -> (NId -> content tag -> r) %1 -> r
withNRef (NLive (Ur nid) (Ur content)) k = k nid content

node :: content tag -> GBuilder content (NLive content tag)
node content = makeNRef content []

dropNode :: NLive content tag %1 -> ()
dropNode = consume

dropNodeM :: NLive content tag %1 -> GBuilder content ()
dropNodeM ref =
  consume ref `lseq` return ()

inspectNode :: NLive content tag %1 -> (NId -> content tag -> r) %1 -> r
inspectNode (NLive (Ur nid) (Ur content)) k = k nid content

splitNode ::
  NLive content a %1 ->
  (content a -> (content b, content c)) ->
  GBuilder content (NLive content b, NLive content c)
splitNode ref f =
  inspectNode ref $ \nid content -> do
    let (outB, outC) = f content
    refB <- makeNRef outB [nid]
    refC <- makeNRef outC [nid]
    return (refB, refC)

cloneNode ::
  NLive content a %1 ->
  (content a -> content b) ->
  GBuilder content (NLive content a, NLive content b)
cloneNode ref f = splitNode ref $ \content ->
  let outB = f content
   in (content, outB)

cloneNodeWith ::
  NLive content a %1 ->
  (content a -> GBuilder content (NLive content b)) ->
  GBuilder content (NLive content a, NLive content b)
cloneNodeWith ref f =
  withNRef
    ref
    ( \nid content -> do
        nextRef <- makeNRef content [nid]
        outRef <- f content
        return (nextRef, outRef)
    )

mapNode ::
  NLive content a %1 ->
  (content a -> content b) ->
  GBuilder content (NLive content b)
mapNode ref f =
  withNRef ref $ \nid content -> do
    makeNRef (f content) [nid]

zipNode2 ::
  NLive content a %1 ->
  NLive content b %1 ->
  (content a -> content b -> content tag) ->
  GBuilder content (NLive content tag)
zipNode2 refA refB makeContent =
  withNRef refA $ \aId contentA ->
    withNRef refB $ \bId contentB -> do
      let refs = [aId, bId]
      makeNRef
        (makeContent contentA contentB)
        refs

zipNode2WithId ::
  NLive content a %1 ->
  NLive content b %1 ->
  (NId -> content a -> NId -> content b -> content tag) ->
  GBuilder content (NLive content tag)
zipNode2WithId refA refB makeContent =
  withNRef refA $ \aId contentA ->
    withNRef refB $ \bId contentB -> do
      let refs = [aId, bId]
      makeNRef
        (makeContent aId contentA bId contentB)
        refs

zipNode3 ::
  NLive content a %1 ->
  NLive content b %1 ->
  NLive content c %1 ->
  (content a -> content b -> content c -> content tag) ->
  GBuilder content (NLive content tag)
zipNode3 refA refB refC makeContent =
  withNRef refA $ \aId contentA ->
    withNRef refB $ \bId contentB ->
      withNRef refC $ \cId contentC -> do
        let refs = [aId, bId, cId]
        makeNRef
          (makeContent contentA contentB contentC)
          refs

buildGraph :: GBuilder content tag -> G content
buildGraph builder =
  let (_, finalState) = runState builder (GBuilderState (Ur 0) (Ur []))
      (GBuilderState (Ur _) (Ur nodes)) = finalState
   in G nodes
