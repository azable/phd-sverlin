{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LinearTypes #-}
{-# LANGUAGE QuantifiedConstraints #-}
{-# LANGUAGE RebindableSyntax #-}

module NodeBase
  ( NBuilder,
    BuilderState (..),
    N (..),
    Some (..),
    NId,
    NRef,
    LPair (..),
    node,
    dropNode,
    dropNodeM,
    inspectNode,
    splitNode,
    cloneNode,
    mapNode,
    zipNode2,
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

data NRef content tag where
  NRef :: Ur NId %1 -> Ur (content tag) %1 -> NRef content tag

instance Consumable (NRef content tag) where
  consume (NRef nid content) =
    consume nid `lseq` consume content

data BuilderState content = BuilderState
  { nextId :: Ur NId,
    nodes :: Ur [N content]
  }

instance Consumable (BuilderState content) where
  consume (BuilderState next ns) =
    consume next `lseq` consume ns

instance Dupable (BuilderState content) where
  dup2 (BuilderState next ns) =
    case dup2 next of
      (next1, next2) ->
        case dup2 ns of
          (ns1, ns2) ->
            (BuilderState next1 ns1, BuilderState next2 ns2)

type NBuilder content = State (BuilderState content)

data LPair a b where
  LPair :: a %1 -> b %1 -> LPair a b

makeN :: content tag -> [NId] -> NBuilder content (Ur NId)
makeN content refs = do
  (BuilderState (Ur oldNextId) (Ur oldNodes)) <- get
  let newId = oldNextId
      newNode = N newId (Some content) refs
  put (BuilderState (Ur (newId + 1)) (Ur (oldNodes ++ [newNode])))
  return (Ur newId)

makeNRef :: content tag -> [NId] -> NBuilder content (NRef content tag)
makeNRef content refs = do
  Ur nid <- makeN content refs
  return (NRef (Ur nid) (Ur content))

withNRef :: NRef content tag %1 -> (NId -> content tag -> r) %1 -> r
withNRef (NRef (Ur nid) (Ur content)) k =
  k nid content

node :: content tag -> NBuilder content (NRef content tag)
node content = makeNRef content []

dropNode :: NRef content tag %1 -> ()
dropNode = consume

dropNodeM :: NRef content tag %1 -> NBuilder content ()
dropNodeM ref =
  consume ref `lseq` return ()

inspectNode :: NRef content tag %1 -> (NId -> content tag -> r) %1 -> r
inspectNode (NRef (Ur nid) (Ur content)) k = k nid content

splitNode ::
  NRef content a %1 ->
  (content a -> (content b, content c)) ->
  NBuilder content (LPair (NRef content b) (NRef content c))
splitNode ref f =
  inspectNode ref $ \nid content -> do
    let (outB, outC) = f content
    refB <- makeNRef outB [nid]
    refC <- makeNRef outC [nid]
    return (LPair refB refC)

cloneNode ::
  NRef content a %1 ->
  (content a -> content b) ->
  NBuilder content (LPair (NRef content a) (NRef content b))
cloneNode ref f = splitNode ref $ \content ->
  let outB = f content
   in (content, outB)

mapNode ::
  NRef content a %1 ->
  (content a -> content b) ->
  NBuilder content (NRef content b)
mapNode ref f =
  withNRef ref $ \nid content -> do
    makeNRef (f content) [nid]

zipNode2 ::
  NRef content a %1 ->
  NRef content b %1 ->
  (content a -> content b -> content tag) ->
  NBuilder content (NRef content tag)
zipNode2 refA refB makeContent =
  withNRef refA $ \aId contentA ->
    withNRef refB $ \bId contentB -> do
      let refs = [aId, bId]
      makeNRef
        (makeContent contentA contentB)
        refs

zipNode3 ::
  NRef content a %1 ->
  NRef content b %1 ->
  NRef content c %1 ->
  (content a -> content b -> content c -> content tag) ->
  NBuilder content (NRef content tag)
zipNode3 refA refB refC makeContent =
  withNRef refA $ \aId contentA ->
    withNRef refB $ \bId contentB ->
      withNRef refC $ \cId contentC -> do
        let refs = [aId, bId, cId]
        makeNRef
          (makeContent contentA contentB contentC)
          refs

buildGraph :: NBuilder content tag -> [N content]
buildGraph builder =
  let (_, finalState) = runState builder (BuilderState (Ur 0) (Ur []))
      (BuilderState (Ur _) (Ur nodes)) = finalState
   in nodes
