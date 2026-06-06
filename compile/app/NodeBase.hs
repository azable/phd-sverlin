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

    -- * Graph-building DSL
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

data SomeNContent where
  SomeNContent :: NContent tag -> SomeNContent

instance P.Show SomeNContent where
  show (SomeNContent content) = show content

class KnownNTag tag where
  matchContent :: SomeNContent -> Maybe (NContent tag)

data N where
  N :: NId -> SomeNContent -> [NId] -> N

instance P.Show N where
  show (N nid content refs) =
    padRight 10 ("[N" P.++ P.show nid P.++ "]")
      P.++ padRight 10 (P.show refs)
      P.++ padRight 20 (P.show content)
    where
      padRight :: Int -> String -> String
      padRight n s = s P.++ P.replicate (n P.- P.length s) ' '

data NRef tag where
  NRef :: Ur NId %1 -> NRef tag

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

makeN :: NContent tag -> [NId] -> NBuilder (Ur NId)
makeN content refs = do
  (BuilderState (Ur oldNextId) (Ur oldNodes)) <- get
  let newId = oldNextId
      newNode = N newId (SomeNContent content) refs
  put (BuilderState (Ur (newId + 1)) (Ur (oldNodes ++ [newNode])))
  return (Ur newId)

lookupRefContent :: (KnownNTag tag) => NRef tag %1 -> NBuilder (Ur (NId, NContent tag))
lookupRefContent ref =
  withNRef ref $ \rid -> do
    BuilderState (Ur _) (Ur ns) <- get
    case find (\(N nid _ _) -> nid == rid) ns of
      Just (N _ someContent _) ->
        case matchContent someContent of
          Just content -> return (Ur (rid, content))
          Nothing -> error "Internal type mismatch: ref tag does not match stored node content"
      Nothing ->
        error $ "Node not found: " P.++ P.show rid

makeNRef :: NContent tag -> [NId] -> NBuilder (NRef tag)
makeNRef content refs = do
  Ur nid <- makeN content refs
  return (NRef (Ur nid))

withNRef :: NRef tag %1 -> (NId -> r) %1 -> r
withNRef (NRef (Ur nid)) k =
  k nid

make1 :: NContent tag -> NBuilder (NRef tag)
make1 content = makeNRef content []

combine3 ::
  (KnownNTag a, KnownNTag b, KnownNTag c) =>
  NRef a %1 ->
  NRef b %1 ->
  NRef c %1 ->
  (NContent a -> NContent b -> NContent c -> NContent tag) ->
  NBuilder (NRef tag)
combine3 refA refB refC makeContent = do
  Ur (aId, contentA) <- lookupRefContent refA
  Ur (bId, contentB) <- lookupRefContent refB
  Ur (cId, contentC) <- lookupRefContent refC

  makeNRef
    (makeContent contentA contentB contentC)
    [aId, bId, cId]

-- DSL layer

data KValue

data KOp

type VRef = NRef KValue

type ORef = NRef KOp

data NContent tag where
  V :: Value -> NContent KValue
  O :: Op -> NContent KOp

instance P.Show (NContent tag) where
  show (V val) = "V " P.++ P.show val
  show (O op) = "O " P.++ P.show op

instance KnownNTag KValue where
  matchContent (SomeNContent c@(V _)) = Just c
  matchContent _ = Nothing

instance KnownNTag KOp where
  matchContent (SomeNContent c@(O _)) = Just c
  matchContent _ = Nothing

data Value
  = I32 Int
  | F64 Double
  deriving stock (P.Show)

data Op
  = Add
  | Mul
  deriving stock (P.Show)

eval :: NContent KValue -> NContent KOp -> NContent KValue -> NContent KValue
eval (V (I32 x)) (O Add) (V (I32 y)) = V (I32 (x + y))
eval (V (I32 x)) (O Mul) (V (I32 y)) = V (I32 (x * y))
eval (V (F64 x)) (O Add) (V (F64 y)) = V (F64 (x + y))
eval (V (F64 x)) (O Mul) (V (F64 y)) = V (F64 (x * y))
eval lhs op rhs = error $ "Type mismatch" ++ displayContents
  where
    displayContents = "\n  LHS: " ++ P.show lhs ++ "\n  OP: " ++ P.show op ++ "\n  RHS: " ++ P.show rhs

v :: Value -> NBuilder VRef
v val = make1 (V val)

o :: Op -> NBuilder ORef
o op = make1 (O op)

e :: VRef %1 -> ORef %1 -> VRef %1 -> NBuilder VRef
e refA refOp refB = combine3 refA refOp refB eval

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

  n3 <- n1 .*. n2
  n4 <- v (I32 10)

  n3 .+. n4
