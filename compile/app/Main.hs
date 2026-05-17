{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
-- {-# LANGUAGE Arrows #-}
{-# LANGUAGE GADTs #-}

module Main where

import Control.Arrow
import Control.Monad (unless, when)
import Control.Monad.State
import Data.MonadicStreamFunction
import Data.Dynamic


-- -- Each input is an Int.
-- -- The hidden State Int stores the running total.
-- runningSum :: MSF (State Int) Int Int
-- runningSum =
--   arrM $ \x -> do
--     total <- get
--     let total' = total + x
--     put total'
--     pure total'

-- example :: Monad m => MSF m Int (Int, Int)
-- example = proc x -> do
--   total   <- arr (+2) -< x
--   doubled <- arr (*2) -< x
--   returnA -< (total, doubled)

-- main :: IO ()
-- main = do
--   let inputs = [1, 2, 3, 4]

--       -- embed runs the MSF over a list of inputs.
--       -- Since the MSF lives in State Int, the result is also in State Int.
--       stateComputation :: State Int [(Int, Int)]
--       stateComputation = embed example inputs

--       -- Run the state computation with initial state 0.
--       (outputs, finalState) = runState stateComputation 0

--   print outputs
--   print finalState

type UniqId = Int

-- data DSLType
--   = CTypeInt Int
--   | CTypeArray [Int]

data Node id a where
  Node :: (DSLType a) => UniqId -> a -> Node UniqId a

makeNode :: (DSLType a) => a -> State Model (Node UniqId a)
makeNode value = do
  _id <- freshId
  return (Node _id value)

class DSLType a where
  view :: a -> String

data CType a where
  CInt    :: Int    -> CType Int
  CDouble :: Double -> CType Double

instance DSLType (CType a) where
  view (CInt x)    = show x
  view (CDouble x) = show x


-- class (Compound a) => Collection a where
--   size     ::                   Node a -> Integer
--   add      :: (Collection b) => Node a -> Node b -> Node b
--   remove   :: (Collection b) => Node a -> Node b -> Node b

-- class (Collection a) => Sequential a where
--   head     ::           Maybe (Node a)
--   next     :: Node a -> Maybe (Node a)
--   previous :: Node a -> Maybe (Node a)

-- class (Collection a) => Indexable a where
--   getAt    :: a -> Integer -> Maybe a

-- class (DataObject a) => 

data Model = Model
  { nextId :: Int
  , stdout :: [String]
  } 

freshId :: State Model Int
freshId = do
  model <- get
  let _id = nextId model
  put model { nextId = _id + 1 }
  return _id

-- array :: State Model (Node [Node Int])
-- array = do
--   n1 <- makeValue (6 :: Int)
--   n2 <- makeValue (7 :: Int)
--   n3 <- makeValue (3 :: Int)
--   makeValue [n1, n2, n3]

main :: IO ()
main = do
  print "Hello"
  -- let (a, _) = runState array Model
  --               { nextId = 0,
  --                 stdout = []
  --               }

  -- print $ a
