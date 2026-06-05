{-# LANGUAGE GADTs #-}
{-# LANGUAGE LinearTypes #-}

import Control.Monad.State

-- Generic node layer

type NId = Int

data N where
  N :: NId -> NContent -> [NRef] -> N

newtype NRef = NRef NId deriving (Show, Eq, Ord)

type NBuilder = State [N] NRef

makeN :: NContent -> [NRef] -> NBuilder
makeN content refs = do
  ns <- get
  let newId = length ns
      newNode = N newId content refs
  put (ns ++ [newNode])
  pure (NRef newId)

e :: [NRef] -> NBuilder
e refs = do
  ns <- get
  let contents =
        map
          ( \(NRef rid) -> case filter (\(N nid _ _) -> nid == rid) ns of
              [N _ c _] -> c
              _ -> error "Node not found"
          )
          refs
  makeN (eval contents) refs

v :: Value -> NBuilder
v val = makeN (V val) []

o :: Op -> NBuilder
o op = makeN (O op) []

-- DSL layer

data NContent
  = V Value
  | O Op
  deriving (Show, Eq)

data Value
  = I32 Int
  | F64 Double
  deriving (Show, Eq)

data Op
  = Add
  | Mul
  deriving (Show, Eq)

eval :: [NContent] -> NContent
eval [V (I32 x), O Add, V (I32 y)] = V (I32 (x + y))
eval [V (I32 x), O Mul, V (I32 y)] = V (I32 (x * y))
eval [V (F64 x), O Add, V (F64 y)] = V (F64 (x + y))
eval [V (F64 x), O Mul, V (F64 y)] = V (F64 (x * y))
eval contents = error $ "Type mismatch: " ++ displayContents
  where
    displayContents = unwords $ map show contents

(.+.) :: NRef -> NRef -> NBuilder
(.+.) a b = do
  add <- o Add
  e [a, add, b]

(.*.) :: NRef -> NRef -> NBuilder
(.*.) a b = do
  mul <- o Mul
  e [a, mul, b]

example :: NBuilder
example = do
  n1 <- v (I32 42)
  n2 <- v (I32 100)
  added <- n1 .+. n2
  multiplied <- n1 .*. n2
  added .+. multiplied

main :: IO ()
main = do
  let (_, nodes) = runState example []
  mapM_ print nodes

-- Printing helper instances
instance Show N where
  show (N nid content refs) = "[N" ++ show nid ++ "] " ++ show content ++ " " ++ show refs
