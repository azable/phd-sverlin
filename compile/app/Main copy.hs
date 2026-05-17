{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE ScopedTypeVariables #-}
-- {-# LANGUAGE Arrows #-}

module Main where

-- import Control.Arrow
import Control.Monad (unless, when)
import Control.Monad.State
import qualified Data.Map as Map
import Data.List (intercalate)
import Data.Typeable (Typeable, cast)
-- import Data.MonadicStreamFunction

--------------------------------------------------------------------------------
-- Virtual C language types

newtype CTypeInt = CTypeInt Int
  deriving (Eq, Ord, Num, Real, Typeable)

newtype CTypeDouble = CTypeDouble Double
  deriving (Eq, Ord, Num, Real, Typeable)

newtype CTypeArray a = CTypeArray
  { ctypeArrayValues :: [a]
  }
  deriving (Eq, Typeable)

instance Show CTypeInt where
  show (CTypeInt a) = show a

instance Show CTypeDouble where
  show (CTypeDouble a) = show a

instance Show a => Show (CTypeArray a) where
  show (CTypeArray xs) =
    "[" ++ intercalate ", " (map show xs) ++ "]"

--------------------------------------------------------------------------------
-- Runtime value universe

data CValue =
  forall a. CType a => CValue a

instance Show CValue where
  show (CValue x) = show x

--------------------------------------------------------------------------------
-- Typed C value classes

class (Show a, Typeable a) => CType a where
  toCValue :: a -> CValue
  toCValue = CValue

  fromCValue :: CValue -> Maybe a
  fromCValue (CValue x) = cast x

class CType a => CTypeAssignable a

class (CTypeAssignable a, Real a) => CTypePrimitive a

instance CType CTypeInt
instance CType CTypeDouble

instance CTypePrimitive CTypeInt
instance CTypePrimitive CTypeDouble

instance CTypeAssignable CTypeInt
instance CTypeAssignable CTypeDouble

-- Generic arrayays:

instance CTypePrimitive a => CType (CTypeArray a)

instance CTypePrimitive a => CTypeAssignable (CTypeArray a)

--------------------------------------------------------------------------------
-- Typed variables

type CIdentifier = String

newtype CVar a = CVar CIdentifier
  deriving Show

--------------------------------------------------------------------------------
-- Runtime model

data Model = Model
  { store  :: Map.Map CIdentifier CValue
  , stdout :: [String]
  }
  deriving Show

type CStatement    = State Model ()
type CExpression a = State Model a

--------------------------------------------------------------------------------
-- Runtime helpers

printf :: Show a => CExpression a -> CStatement
printf eStr = do
  str <- eStr
  modify $ \m ->
    m { stdout = stdout m ++ [show str] }

runtimeError :: String -> State Model a
runtimeError msg = do
  outs <- gets stdout
  error $
    msg
      ++ "\n=== STDOUT ===\n"
      ++ unlines outs
      ++ "\n==============\n"

lookupVar :: forall a. CType a => CVar a -> CExpression a
lookupVar (CVar name) = do
  st <- gets store
  case Map.lookup name st of
    Nothing ->
      runtimeError $ "Unknown variable: " ++ name

    Just value ->
      case fromCValue value :: Maybe a of
        Just x -> pure x
        Nothing -> runtimeError $ "Variable has wrong type: " ++ name

assignVar :: forall a. CTypeAssignable a => CVar a -> a -> CExpression a
assignVar (CVar name) value = do
  st <- gets store

  case Map.lookup name st of
    Nothing ->
      runtimeError $ "Assignment to undeclared variable: " ++ name

    Just oldValue ->
      case fromCValue oldValue :: Maybe a of
        Nothing ->
          runtimeError $ "Assignment has wrong type: " ++ name

        Just _ -> do
          modify $ \m ->
            m { store = Map.insert name (toCValue value) (store m) }

          pure value

--------------------------------------------------------------------------------
-- Expression helpers

_r :: CType a => CVar a -> CExpression a
_r = lookupVar

_l :: CType a => a -> CExpression a
_l = pure

(@@=) :: CTypeAssignable a => CVar a -> CExpression a -> CExpression a
(@@=) var eRight = do
  right <- eRight
  assignVar var right

(@@+=) :: CTypePrimitive a => CVar a -> CExpression a -> CExpression a
(@@+=) var eRight = do
  right <- eRight
  left  <- _r var
  assignVar var (left + right)

(@@-=) :: CTypePrimitive a => CVar a -> CExpression a -> CExpression a
(@@-=) var eRight = do
  right <- eRight
  left  <- _r var
  assignVar var (left - right)

(@@-) :: CTypePrimitive a => CExpression a -> CExpression a -> CExpression a
(@@-) eLeft eRight = do
  left  <- eLeft
  right <- eRight
  pure (left - right)

(@@>) :: CTypePrimitive a => CExpression a -> CExpression a -> CExpression CTypeInt
(@@>) eLeft eRight = do
  left  <- eLeft
  right <- eRight
  pure $ if left > right then 1 else 0

(@@<) :: CTypePrimitive a => CExpression a -> CExpression a -> CExpression CTypeInt
(@@<) eLeft eRight = do
  left  <- eLeft
  right <- eRight
  pure $ if left < right then 1 else 0

(@@&&) :: CExpression CTypeInt -> CExpression CTypeInt -> CExpression CTypeInt
(@@&&) eLeft eRight = do
  left <- eLeft
  if left /= 0
    then eRight
    else pure 0

--------------------------------------------------------------------------------
-- Generic arrayay access/update

(||.) :: CTypePrimitive a => CVar (CTypeArray a) -> CExpression CTypeInt -> CExpression a
(||.) arrayayVar eIdx = do
  CTypeArray xs <- _r arrayayVar
  CTypeInt idx  <- eIdx

  case safeIndex idx xs of
    Just value -> pure value
    Nothing -> runtimeError $ "Out of bounds access at: " ++ show idx

(||.=) :: CTypePrimitive a => CVar (CTypeArray a) -> CExpression CTypeInt -> CExpression a -> CStatement
(||.=) arrayayVar eIdx eValue = do
  CTypeArray xs <- _r arrayayVar
  CTypeInt idx  <- eIdx
  value         <- eValue

  case updateAt idx value xs of
    Just xs' -> do
      _ <- assignVar arrayayVar (CTypeArray xs')
      pure ()

    Nothing ->
      runtimeError $ "Out of bounds assignment at: " ++ show idx

safeIndex :: Int -> [a] -> Maybe a
safeIndex idx xs
  | idx < 0 = Nothing
  | otherwise =
      case drop idx xs of
        x : _ -> Just x
        []    -> Nothing

updateAt :: Int -> a -> [a] -> Maybe [a]
updateAt idx value xs
  | idx < 0          = Nothing
  | idx >= length xs = Nothing
  | otherwise        = Just $ take idx xs ++ [value] ++ drop (idx + 1) xs

--------------------------------------------------------------------------------
-- Control structures

cWhile :: CExpression CTypeInt -> CStatement -> CStatement
cWhile eGuard sBody = do
  guardValue <- eGuard
  when (guardValue /= 0) $ do
    sBody
    cWhile eGuard sBody

cFor :: CExpression a -> CExpression CTypeInt -> CExpression b -> CStatement -> CStatement
cFor sInit eGuard sIter sBody = do
  _ <- sInit
  cWhile eGuard $ do
    sBody
    _ <- sIter
    pure ()

--------------------------------------------------------------------------------
-- Fixities

infixl 6 @@-
infixl 5 ||.
infix  4 @@<, @@>
infixr 3 @@&&
infixr 1 @@=, @@+=, @@-=
infixr 1 ||.=

--------------------------------------------------------------------------------
-- Program state

i :: CVar CTypeInt
i = CVar "i"

j :: CVar CTypeInt
j = CVar "j"

n :: CVar CTypeInt
n = CVar "n"

tmp :: CVar CTypeInt
tmp = CVar "tmp"

array :: CVar (CTypeArray CTypeInt)
array = CVar "array"

--------------------------------------------------------------------------------
-- Program

-- void insertion_sort(int array[], int n) {
--     for (int i = 1; i < n; i += 1) {
--         for (int j = i; j > 0 && array[j - 1] > array[j]; j -= 1) {
--             int tmp = array[j];
--             array[j] = array[j - 1];
--             array[j - 1] = tmp;
--         }
--     }
-- }

insertionSort :: CStatement
insertionSort = do
  cFor (i @@= _l 1) (_r i @@< _r n) (i @@+= _l 1) $ do
      cFor (j @@= _r i) ((_r j @@> _l 0) @@&& ((array ||. _r j @@- _l 1) @@> (array ||. _r j))) (j @@-= _l 1) $ do
          _ <- tmp @@= (array ||. _r j)
          array ||.= _r j          $ array ||. _r j @@- _l 1
          array ||.= _r j @@- _l 1 $ _r tmp

insertionSort' :: CStatement
insertionSort' = do
  loopOverEachItem $ do
    printf $ pure "Next item to insert"
    loopBackwardThroughSortedPrefix $ do
      swapAdjacentOutOfOrderItems

  where
    startAtSecondItem           = i @@= _l 1
    itemIsWithinBounds          = _r i @@< _r n
    selectNextItemToInsert      = i @@+= _l 1

    loopOverEachItem =
      cFor startAtSecondItem itemIsWithinBounds selectNextItemToInsert

    startAtCurrentItemToInsert  = j @@= _r i
      
    currentItemNotAtStart       = _r j @@> _l 0
    previousItem                = array ||. _r j @@- _l 1
    currentItem                 = array ||. _r j
    adjacentItemsOutOfOrder     = previousItem @@> currentItem
    shouldKeepMovingLeft        = currentItemNotAtStart @@&& adjacentItemsOutOfOrder
    moveToPreviousItem          = j @@-= _l 1

    loopBackwardThroughSortedPrefix =
      cFor startAtCurrentItemToInsert shouldKeepMovingLeft moveToPreviousItem

    saveCurrentItem             = tmp @@= currentItem
    movePreviousItemRight       = array ||.= _r j          $ previousItem
    moveCurrentItemLeft         = array ||.= _r j @@- _l 1 $ _r tmp

    swapAdjacentOutOfOrderItems = do 
      _ <- saveCurrentItem
      movePreviousItemRight
      moveCurrentItemLeft

--------------------------------------------------------------------------------
-- Initial model


initialModel :: Model
initialModel =
  Model
    { store =
        Map.fromList
          [ ("array", toCValue $ CTypeArray $ map CTypeInt [5, 4, 7, 1, 3, 2])
          , ("n",   toCValue $ CTypeInt 6)
          , ("i",   toCValue $ CTypeInt (-1))
          , ("j",   toCValue $ CTypeInt (-1))
          , ("tmp", toCValue $ CTypeInt (-1))
          ]
    , stdout = []
    }

main :: IO ()
main = do
  let finalModel =
        execState insertionSort' initialModel

      sortedArr =
        evalState (_r array) finalModel :: CTypeArray CTypeInt

      outs =
        stdout finalModel
  
  print sortedArr

  unless (null outs) $ do
    putStrLn "\n=== STDOUT ===\n"
    putStrLn $ concat outs


---------

-- example :: Monad m => MSF m Int (Int, Int)
-- example = proc x -> do
--   total   <- arr (+2) -< x
--   doubled <- arr (*2) -< x
--   returnA -< (total, doubled)

-- -- Each input is an Int.
-- -- The hidden State Int stores the running total.
-- runningSum :: MSF (State Int) Int Int
-- runningSum =
--   arrM $ \x -> do
--     total <- get
--     let total' = total + x
--     put total'
--     pure total'

-- main :: IO ()
-- main = do
--   let inputs = [1, 2, 3, 4]

--       -- embed runs the MSF over a list of inputs.
--       -- Since the MSF lives in State Int, the result is also in State Int.
--       stateComputation :: State Int [Int]
--       stateComputation = embed runningSum inputs

--       -- Run the state computation with initial state 0.
--       (outputs, finalState) = runState stateComputation 0

--   print outputs
--   print finalState

-- type Id = Int

-- data MemObject a = MemObject Id a

-- makeMemObject a = MemObject 

-- insSort = do
--   let n1 = MemObject 6
--   let n2 = MemObject 7
--   let n3 = MemObject 3
--   let n4 = MemObject 1
--   let n5 = MemObject 8
--   let n6 = MemObject 4



--   print "test"
