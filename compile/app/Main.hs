{-# LANGUAGE TemplateHaskell #-}

module Main where
import Control.Lens
import Control.Monad.State
import Control.Monad (when, unless)
import Data.List

-- Virtual C language types - concrete definitions

newtype CTypeInt = CTypeInt Int
  deriving (Eq, Ord, Num, Real)

newtype CTypeDouble = CTypeDouble Double
  deriving (Eq, Ord, Num, Real)

newtype CTypeArray a = CTypeArray
    { _ctypeArrayValues :: [a]
    }
    deriving (Eq)

instance Show CTypeInt where
    show (CTypeInt a) = show a

instance Show CTypeDouble where
    show (CTypeDouble a) = show a

instance Show a => Show (CTypeArray a) where
    show (CTypeArray xs) = "[" ++ intercalate ", " (map show xs) ++ "]"

makeLenses ''CTypeArray


-- Define hierarchy of virtual C types
class (Show a) => CType a

instance CType          CTypeInt
instance CType          CTypeDouble
instance CType          a => CType (CTypeArray a)


-- All assignable types
class (CType a) => CTypeAssignable a

instance CTypeAssignable CTypeInt
instance CTypeAssignable CTypeDouble


-- All primitives are assignable, and can be treated as numeric
class (CTypeAssignable a, Real a) => CTypePrimitive a

instance CTypePrimitive CTypeInt
instance CTypePrimitive CTypeDouble


-- Data model

data Model = Model 
    { _arr :: CTypeArray CTypeInt
    , _n :: CTypeInt
    , _i :: CTypeInt
    , _j :: CTypeInt
    , _tmp :: CTypeInt
    , _stdout :: [String]
    } deriving (Show)

makeLenses ''Model


-- Virtual C language control structure monadic types

type CStatement       = State Model ()
type CExpression a    = State Model a

-- Virtual C language functions

printf :: (Show a) => CExpression a -> CStatement
printf eStr = do 
    str <- eStr
    stdout %= (++ [show str])

runtimeError :: String -> State Model a
runtimeError msg = do 
    stdouts <- unlines <$> use stdout
    error $ msg ++ "\n=== STDOUT ===\n" ++ stdouts ++ "\n==============\n"

(||.) :: (CType a) => Lens' Model (CTypeArray a) -> CExpression CTypeInt -> CExpression a
(||.) lArray eIdx = do
    CTypeInt idx <- eIdx 
    mValue <- preuse (lArray . ctypeArrayValues . ix idx)
    case mValue of
        Just value -> return value
        Nothing    -> runtimeError $ "Out of bounds access at: " ++ show idx

(||.=) :: (CType a) => Lens' Model (CTypeArray a) -> CExpression CTypeInt -> CExpression a -> CStatement
(||.=) lArray eIdx eValue = do
    CTypeInt idx <- eIdx
    value <- eValue
    lArray . ctypeArrayValues . ix idx .= value

(@@&&) :: CExpression CTypeInt -> CExpression CTypeInt -> CExpression CTypeInt
(@@&&) eLeft eRight = do
    left <- eLeft
    if left /= 0 then do
        eRight
    else
        return 0

(@@>) :: (CTypePrimitive a) => CExpression a -> CExpression a -> CExpression CTypeInt
(@@>) eLeft eRight = do
    left <- eLeft
    right <- eRight
    return $ if left > right then 1 else 0

(@@<) :: (CTypePrimitive a) => CExpression a -> CExpression a -> CExpression CTypeInt
(@@<) eLeft eRight = do
    left <- eLeft
    right <- eRight
    return $ if left < right then 1 else 0

_r :: (CTypePrimitive a) => Lens' Model a -> CExpression a
_r l = do
    use l

_l :: (CTypePrimitive a) => a -> CExpression a
_l value = do
    return value

cWhile :: CExpression CTypeInt -> CStatement -> CStatement
cWhile eGuard sBody = do
    guard <- eGuard
    when (guard /= 0) $ do
        sBody
        cWhile eGuard sBody

cFor :: CExpression a -> CExpression CTypeInt -> CExpression b -> CStatement -> CStatement
cFor sInit eGuard sIter sBody = do
    _ <- sInit
    cWhile eGuard $ do
        sBody
        _ <- sIter
        return ()

(@@=) :: (CTypeAssignable a) => Lens' Model a -> CExpression a -> CExpression a
(@@=) lLeft eRight = do
    right <- eRight
    lLeft .= right
    return right

(@@+=) :: (CTypePrimitive a) => Lens' Model a -> CExpression a -> CExpression a
(@@+=) lLeft eRight = do
    right <- eRight
    left <- _r lLeft
    lLeft .= (left + right)
    return (left + right)

(@@-=) :: (CTypePrimitive a) => Lens' Model a -> CExpression a -> CExpression a
(@@-=) lLeft eRight = do
    right <- eRight
    left <- _r lLeft
    lLeft .= (left - right)
    return (left - right)

(@@-) :: (CTypePrimitive a) => CExpression a -> CExpression a -> CExpression a
(@@-) eLeft eRight = do
    left <- eLeft
    right <- eRight
    return (left - right)

infixl 6 @@-
infixl 5 ||.
infix  4 @@<, @@> --, @@==
infixr 3 @@&&
infixr 1 @@=, @@+=, @@-=
infixr 1 ||.=

run :: CStatement
run = do
    cFor (i @@= _l 1) (_r i @@< _r n) (i @@+= _l 1) $ do
        cFor (j @@= _r i) ((_r j @@> _l 0) @@&& (arr||.(_r j @@- _l 1) @@> arr||._r j)) (j @@-= _l 1) $ do 
            _ <- tmp @@= (arr||._r j)
            arr||.= _r j            $ arr||.(_r j @@- _l 1)
            arr||.= (_r j @@- _l 1) $ _r tmp

run2 :: CStatement
run2 = do
    loopOverEachItem $ do
        loopBackwardThroughSortedPrefix $ do
            swapAdjacentOutOfOrderItems

    where 
        startAtSecondItem          = i @@= _l 1
        itemIsWithinBounds         = _r i @@< _r n
        selectNextItemToInsert     = i @@+= _l 1
        loopOverEachItem           = 
            cFor startAtSecondItem itemIsWithinBounds selectNextItemToInsert
        
        startAtCurrentItemToInsert = j @@= _r i
        currentItemNotAtStart      = _r j @@> _l 0
        previousItem               = arr ||. (_r j @@- _l 1)
        currentItem                = arr ||. _r j
        adjacentItemsOutOfOrder    = previousItem @@> currentItem
        shouldKeepMovingLeft       = currentItemNotAtStart @@&& adjacentItemsOutOfOrder
        moveToPreviousItem         = j @@-= _l 1

        loopBackwardThroughSortedPrefix =
            cFor startAtCurrentItemToInsert shouldKeepMovingLeft moveToPreviousItem

        saveCurrentItem =
            tmp @@= currentItem

        movePreviousItemRight =
            arr ||.= _r j $ previousItem

        moveCurrentItemLeft =
            arr ||.= (_r j @@- _l 1) $ _r tmp

        swapAdjacentOutOfOrderItems = do
            _ <- saveCurrentItem
            movePreviousItemRight
            moveCurrentItemLeft



main :: IO ()
main = do
    let (_, Model { _arr, _stdout }) = runState run2 (Model 
            { _arr = CTypeArray [5, 4, 7, 1, 3, 2]
            , _n = 6
            , _i = -1
            , _j = -1
            , _tmp = -1
            , _stdout = []
            })
    print $ _arr
    unless (null _stdout) $ do
        putStrLn "\n=== STDOUT ===\n"
        putStrLn $ unlines _stdout

-- void insertion_sort(int a[], int n) {
--     for (int i = 1; i < n; i++) {
--         for (int j = i; j > 0 && a[j - 1] > a[j]; j--) {
--             int tmp = a[j];
--             a[j] = a[j - 1];
--             a[j - 1] = tmp;
--         }
--     }
-- }