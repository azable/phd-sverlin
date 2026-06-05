{-# LANGUAGE GADTs #-}

import Control.Monad.State

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

data NContent
  = NValue Value
  | NOp Op
  deriving (Show, Eq)

data Value
  = TInt Int
  | TDouble Double
  deriving (Show, Eq)

data Op
  = OAdd
  | OMul
  deriving (Show, Eq)

eval :: [NContent] -> NContent
eval [NValue (TInt x), NOp OAdd, NValue (TInt y)] = NValue (TInt (x + y))
eval [NValue (TInt x), NOp OMul, NValue (TInt y)] = NValue (TInt (x * y))
eval [NValue (TDouble x), NOp OAdd, NValue (TDouble y)] = NValue (TDouble (x + y))
eval [NValue (TDouble x), NOp OMul, NValue (TDouble y)] = NValue (TDouble (x * y))
eval contents = error $ "Type mismatch: " ++ displayContents
  where
    displayContents = unwords $ map show contents

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

example :: NBuilder
example = do
  n1 <- makeN (NValue (TInt 42)) []
  (.+.) <- makeN (NOp OAdd) []
  (.*.) <- makeN (NOp OMul) []
  n2 <- makeN (NValue (TInt 100)) []
  added <- e [n1, (.+.), n2]
  multiplied <- e [n1, (.*.), n2]
  e [added, (.+.), multiplied]

main :: IO ()
main = do
  let (_, nodes) = runState example []
  mapM_ print nodes

-- Printing helper instances
instance Show N where
  show (N nid content refs) = "[N" ++ show nid ++ "] " ++ show content ++ " " ++ show refs
