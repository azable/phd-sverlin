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
    NHandle (..),
    NSnapshot (..),
    freeze,
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
  show (N nid content handles) =
    padRight 10 ("[N" P.++ P.show nid P.++ "]")
      P.++ padRight 14 (P.show handles)
      P.++ padRight 20 (P.show content)
    where
      padRight :: Int -> String -> String
      padRight n s = s P.++ P.replicate (n P.- P.length s) ' '

data NHandle content tag where
  NHandle :: Ur NId %1 -> Ur (content tag) %1 -> NHandle content tag

instance Consumable (NHandle content tag) where
  consume (NHandle nid content) =
    consume nid `lseq` consume content

data NSnapshot content tag where
  NPtr :: NId -> content tag -> NSnapshot content tag

instance (P.Show (content tag)) => P.Show (NSnapshot content tag) where
  show (NPtr nid _) =
    "$[N" P.++ P.show nid P.++ "]"

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

freeze :: NHandle content tag %1 -> Ur (NSnapshot content tag)
freeze handle =
  withNHandle
    handle
    ( \nid content ->
        Ur (NPtr nid content)
    )

copyPtr :: NSnapshot content tag -> GBuilder content (NHandle content tag)
copyPtr (NPtr nid content) = makeNHandle content [nid]

makeN :: content tag -> [NId] -> GBuilder content (Ur NId)
makeN content handles = do
  (GBuilderState (Ur oldNextId) (Ur oldNodes)) <- get
  let newId = oldNextId
      newNode = N newId (Some content) handles
  put (GBuilderState (Ur (newId + 1)) (Ur (oldNodes ++ [newNode])))
  return (Ur newId)

makeNHandle :: content tag -> [NId] -> GBuilder content (NHandle content tag)
makeNHandle content handles = do
  Ur nid <- makeN content handles
  return (NHandle (Ur nid) (Ur content))

withNHandle :: NHandle content tag %1 -> (NId -> content tag -> r) %1 -> r
withNHandle (NHandle (Ur nid) (Ur content)) k = k nid content

node :: content tag -> GBuilder content (NHandle content tag)
node content = makeNHandle content []

dropNode :: NHandle content tag %1 -> ()
dropNode = consume

dropNodeM :: NHandle content tag %1 -> GBuilder content ()
dropNodeM handle =
  consume handle `lseq` return ()

inspectNode :: NHandle content tag %1 -> (NId -> content tag -> r) %1 -> r
inspectNode (NHandle (Ur nid) (Ur content)) k = k nid content

splitNode ::
  NHandle content a %1 ->
  (content a -> (content b, content c)) ->
  GBuilder content (NHandle content b, NHandle content c)
splitNode handle f =
  inspectNode handle $ \nid content -> do
    let (outB, outC) = f content
    handleB <- makeNHandle outB [nid]
    handleC <- makeNHandle outC [nid]
    return (handleB, handleC)

cloneNode ::
  NHandle content a %1 ->
  (content a -> content b) ->
  GBuilder content (NHandle content a, NHandle content b)
cloneNode handle f = splitNode handle $ \content ->
  let outB = f content
   in (content, outB)

cloneNodeWith ::
  NHandle content a %1 ->
  (content a -> GBuilder content (NHandle content b)) ->
  GBuilder content (NHandle content a, NHandle content b)
cloneNodeWith handle f =
  withNHandle
    handle
    ( \nid content -> do
        nextHandle <- makeNHandle content [nid]
        outHandle <- f content
        return (nextHandle, outHandle)
    )

mapNode ::
  NHandle content a %1 ->
  (content a -> content b) ->
  GBuilder content (NHandle content b)
mapNode handle f =
  withNHandle handle $ \nid content -> do
    makeNHandle (f content) [nid]

zipNode2 ::
  NHandle content a %1 ->
  NHandle content b %1 ->
  (content a -> content b -> content tag) ->
  GBuilder content (NHandle content tag)
zipNode2 handleA handleB makeContent =
  withNHandle handleA $ \aId contentA ->
    withNHandle handleB $ \bId contentB -> do
      let handles = [aId, bId]
      makeNHandle
        (makeContent contentA contentB)
        handles

zipNode2WithId ::
  NHandle content a %1 ->
  NHandle content b %1 ->
  (NId -> content a -> NId -> content b -> content tag) ->
  GBuilder content (NHandle content tag)
zipNode2WithId handleA handleB makeContent =
  withNHandle handleA $ \aId contentA ->
    withNHandle handleB $ \bId contentB -> do
      let handles = [aId, bId]
      makeNHandle
        (makeContent aId contentA bId contentB)
        handles

zipNode3 ::
  NHandle content a %1 ->
  NHandle content b %1 ->
  NHandle content c %1 ->
  (content a -> content b -> content c -> content tag) ->
  GBuilder content (NHandle content tag)
zipNode3 handleA handleB handleC makeContent =
  withNHandle handleA $ \aId contentA ->
    withNHandle handleB $ \bId contentB ->
      withNHandle handleC $ \cId contentC -> do
        let handles = [aId, bId, cId]
        makeNHandle
          (makeContent contentA contentB contentC)
          handles

buildGraph :: GBuilder content tag -> G content
buildGraph builder =
  let (_, finalState) = runState builder (GBuilderState (Ur 0) (Ur []))
      (GBuilderState (Ur _) (Ur nodes)) = finalState
   in G nodes
