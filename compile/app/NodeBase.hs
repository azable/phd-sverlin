{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LinearTypes #-}
{-# LANGUAGE RebindableSyntax #-}

module NodeBase
  ( -- * Running builders
    NBuilder,
    BuilderState (..),

    -- * Public graph data
    N (..),
    NId,
    NContent (..),
    Value (..),
    Op (..),

    -- * Linear value handles
    VRef,
    VPair (..),

    -- * Graph-building DSL
    v,
    (.+.),
    (.*.),
    buildGraph,
    example,
  )
where

import Control.Functor.Linear
import Prelude.Linear
import Prelude qualified as P

-- Generic node layer

type NId = Int

data N where
  N :: NId -> NContent -> [NId] -> N

instance P.Show N where
  show (N nid content refs) =
    padRight 10 ("[N" P.++ P.show nid P.++ "]")
      P.++ padRight 10 (P.show refs)
      P.++ padRight 20 (P.show content)
    where
      padRight :: Int -> String -> String
      padRight n s = s P.++ P.replicate (n P.- P.length s) ' '

-- Internal/plain references used only inside stored graph nodes.
newtype NRef = NRef NId
  deriving (Show, Eq, Ord)

-- Linear public handle to a value node.
-- In a real module, export VRef abstractly; do not export VRef(..).
data VRef where
  VRef :: Ur NId %1 -> VRef

-- Linear public handle to an operator node.
data ORef where
  ORef :: Ur NId %1 -> ORef

data BuilderState = BuilderState
  { nextId :: Ur NId,
    nodes :: Ur [N]
  }

instance Consumable BuilderState where
  consume (BuilderState next ns) =
    consume next `lseq` consume ns

instance Dupable BuilderState where
  dup2 (BuilderState next ns) =
    case dup2 next of
      (next1, next2) ->
        case dup2 ns of
          (ns1, ns2) ->
            (BuilderState next1 ns1, BuilderState next2 ns2)

type NBuilder = State BuilderState

makeN :: NContent -> [NId] -> NBuilder (Ur NId)
makeN content refs = do
  (BuilderState (Ur oldNextId) (Ur oldNodes)) <- get
  let newId = oldNextId
      newNode = N newId content refs
  put (BuilderState (Ur (newId + 1)) (Ur (oldNodes ++ [newNode])))
  return (Ur newId)

lookupContent :: NId -> NBuilder (Ur NContent)
lookupContent rid = do
  (BuilderState (Ur _) (Ur nodes)) <- get
  case find (\(N nid _ _) -> nid == rid) nodes of
    Just (N _ content _) -> return (Ur content)
    Nothing -> error $ "Node not found: " ++ show rid

lookupContents :: [NId] -> NBuilder (Ur [NContent])
lookupContents [] = return (Ur [])
lookupContents (rid : rids) = do
  (Ur c) <- lookupContent rid
  (Ur cs) <- lookupContents rids
  return (Ur (c : cs))

v :: Value -> NBuilder VRef
v val = do
  Ur nid <- makeN (V val) []
  return (VRef (Ur nid))

o :: Op -> NBuilder ORef
o op = do
  Ur nid <- makeN (O op) []
  return (ORef (Ur nid))

-- Consume one value ref to expose its underlying node id.
withVRef :: VRef %1 -> (NId -> NBuilder a) %1 -> NBuilder a
withVRef (VRef (Ur nid)) k =
  k nid

-- Consume one op ref to expose its underlying node id.
withORef :: ORef %1 -> (NId -> NBuilder a) %1 -> NBuilder a
withORef (ORef (Ur nid)) k =
  k nid

-- This is your old `e`, but specialised to:
--   value, operator, value
--
-- The value references are consumed linearly.
e :: VRef %1 -> ORef %1 -> VRef %1 -> NBuilder VRef
e left op right =
  withVRef left $ \leftId ->
    withORef op $ \opId ->
      withVRef right $ \rightId -> do
        let refs = [leftId, opId, rightId]
        (Ur contents) <- lookupContents refs
        (Ur newId) <- makeN (eval contents) refs
        return (VRef (Ur newId))

-- Explicit duplication / sharing.
--
-- This is the escape hatch you use when you intentionally want graph sharing.
data VPair where
  VPair :: VRef %1 -> VRef %1 -> VPair

-- DSL layer

data NContent
  = V Value
  | O Op
  deriving stock (P.Show)

data Value
  = I32 Int
  | F64 Double
  deriving stock (P.Show)

data Op
  = Add
  | Mul
  deriving stock (P.Show)

eval :: [NContent] -> NContent
eval [V (I32 x), O Add, V (I32 y)] = V (I32 (x + y))
eval [V (I32 x), O Mul, V (I32 y)] = V (I32 (x * y))
eval [V (F64 x), O Add, V (F64 y)] = V (F64 (x + y))
eval [V (F64 x), O Mul, V (F64 y)] = V (F64 (x * y))
eval contents = error $ "Type mismatch: " ++ displayContents
  where
    displayContents = unwords $ P.map show contents

(.+.) :: VRef %1 -> VRef %1 -> NBuilder VRef
(.+.) a b = do
  add <- o Add
  e a add b

(.*.) :: VRef %1 -> VRef %1 -> NBuilder VRef
(.*.) a b = do
  mul <- o Mul
  e a mul b

buildGraph :: NBuilder a -> [N]
buildGraph builder =
  let (_, finalState) = runState builder (BuilderState (Ur 0) (Ur []))
      (BuilderState (Ur _) (Ur nodes)) = finalState
   in nodes

example :: NBuilder VRef
example = do
  n1 <- v (I32 42)
  n2 <- v (I32 100)

  -- added <- n1 .+. n2
  n1 .*. n2
