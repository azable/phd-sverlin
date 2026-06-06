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
  NRef :: Ur NId %1 -> Ur (NContent tag) %1 -> NRef tag

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

makeNRef :: NContent tag -> [NId] -> NBuilder (NRef tag)
makeNRef content refs = do
  Ur nid <- makeN content refs
  return (NRef (Ur nid) (Ur content))

withNRef :: NRef tag %1 -> (NId -> NContent tag -> r) %1 -> r
withNRef (NRef (Ur nid) (Ur content)) k =
  k nid content

make :: NContent tag -> NBuilder (NRef tag)
make content = makeNRef content []

combine3 ::
  NRef a %1 ->
  NRef b %1 ->
  NRef c %1 ->
  (NContent a -> NContent b -> NContent c -> NContent tag) ->
  NBuilder (NRef tag)
combine3 refA refB refC makeContent =
  withNRef refA $ \aId contentA ->
    withNRef refB $ \bId contentB ->
      withNRef refC $ \cId contentC -> do
        let refs = [aId, bId, cId]
        makeNRef
          (makeContent contentA contentB contentC)
          refs

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
v val = make (V val)

o :: Op -> NBuilder ORef
o op = make (O op)

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
