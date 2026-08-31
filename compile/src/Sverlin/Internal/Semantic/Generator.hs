{-# LANGUAGE DataKinds #-}

-- | Deterministic, finite-choice scenario generation for the managed DSL.
--
-- This module is compiler support.  The authored facade re-exports only the
-- generator type and its constructors, while the semantic runner uses
-- 'runGenerator' to retain a replay transcript.
module Sverlin.Internal.Semantic.Generator
  ( Generator
  , GeneratorDecision(..)
  , GeneratorFailure(..)
  , between
  , elementOf
  , weighted
  , listOf
  , shuffle
  , runGenerator
  ) where

import           GHC.Exts       (Multiplicity (Many))
import           Prelude
import qualified Prelude        as P
import           Sverlin.Syntax (Rebind (..))
import           System.Random  (StdGen, mkStdGen, randomR)

-- | One replayable random decision, numbered in evaluation order within one
-- Domain variable.
data GeneratorDecision
  = BetweenDecision
      { generatorDecisionIndex    :: Int
      , generatorBetweenLow       :: Int
      , generatorBetweenHigh      :: Int
      , generatorBetweenSelection :: Int
      }
  | ElementDecision
      { generatorDecisionIndex    :: Int
      , generatorElementCount     :: Int
      , generatorElementSelection :: Int
      }
  | WeightedDecision
      { generatorDecisionIndex     :: Int
      , generatorWeights           :: [Int]
      , generatorWeightedSelection :: Int
      }
  | LengthDecision
      { generatorDecisionIndex   :: Int
      , generatorLengthMinimum   :: Int
      , generatorLengthMaximum   :: Int
      , generatorLengthSelection :: Int
      }
  | ShuffleDecision
      { generatorDecisionIndex    :: Int
      , generatorShuffleRemaining :: Int
      , generatorShuffleSelection :: Int
      }
  deriving (Eq, Show)

-- | A generator definition was invalid before it could produce a scenario.
newtype GeneratorFailure = GeneratorFailure
  { generatorFailureMessage :: String
  } deriving (Eq, Show)

data GeneratorState = GeneratorState
  { generatorRandom     :: StdGen
  , generatorNextIndex  :: Int
  , generatorTranscript :: [GeneratorDecision]
  }

newtype Generator value = Generator
  { evaluateGenerator :: GeneratorState -> Either
                                             GeneratorFailure
                                             (value, GeneratorState)
  }

instance Functor Generator where
  fmap transform (Generator generate) =
    Generator $ \state -> do
      (value, next) <- generate state
      pure (transform value, next)

instance Applicative Generator where
  pure value = Generator (\state -> Right (value, state))
  Generator generateFunction <*> Generator generateValue =
    Generator $ \state -> do
      (function, afterFunction) <- generateFunction state
      (value, afterValue) <- generateValue afterFunction
      pure (function value, afterValue)

instance Monad Generator where
  Generator generate >>= continue =
    Generator $ \state -> do
      (value, next) <- generate state
      evaluateGenerator (continue value) next

instance Rebind 'Many Generator where
  rebind = (P.>>=)
  repure = P.pure
  refail = P.error

-- | Sample an inclusive integral range uniformly.
between :: Int -> Int -> Generator Int
between low high =
  Generator $ \state ->
    if low > high
      then failure
             "between requires its lower bound to be no greater than its upper bound"
      else let (selected, random') = randomR (low, high) (generatorRandom state)
               decision =
                 BetweenDecision
                   { generatorDecisionIndex = generatorNextIndex state
                   , generatorBetweenLow = low
                   , generatorBetweenHigh = high
                   , generatorBetweenSelection = selected
                   }
            in Right (selected, recordDecision random' decision state)

-- | Select one position uniformly.  The leading value makes the domain
-- non-empty without a partial list operation in authored code.
elementOf :: value -> [value] -> Generator value
elementOf first rest =
  Generator $ \state ->
    let values = first : rest
        count = length values
        (selectedIndex, random') =
          randomR (0, count - 1) (generatorRandom state)
        decision =
          ElementDecision
            { generatorDecisionIndex = generatorNextIndex state
            , generatorElementCount = count
            , generatorElementSelection = selectedIndex
            }
     in Right (values !! selectedIndex, recordDecision random' decision state)

-- | Select one generator using positive integer weights, then evaluate only
-- the selected branch.
weighted ::
     (Int, Generator value) -> [(Int, Generator value)] -> Generator value
weighted first rest =
  Generator $ \state -> do
    let branches = first : rest
        weights = map fst branches
    if any (<= 0) weights
      then failure "weighted requires every branch weight to be positive"
      else do
        let total = sum (map toInteger weights)
            (point, random') = randomR (1, total) (generatorRandom state)
            selectedIndex = weightedIndex point weights
            decision =
              WeightedDecision
                { generatorDecisionIndex = generatorNextIndex state
                , generatorWeights = weights
                , generatorWeightedSelection = selectedIndex
                }
            next = recordDecision random' decision state
        evaluateGenerator (snd (branches !! selectedIndex)) next

-- | Select a length uniformly, then evaluate the item generator independently
-- for every position.
listOf :: Int -> Int -> Generator value -> Generator [value]
listOf minimumLength maximumLength item =
  Generator $ \state ->
    if minimumLength < 0
      then failure "listOf requires a non-negative minimum length"
      else if minimumLength > maximumLength
             then failure
                    "listOf requires its minimum length to be no greater than its maximum"
             else do
               let (selectedLength, random') =
                     randomR
                       (minimumLength, maximumLength)
                       (generatorRandom state)
                   decision =
                     LengthDecision
                       { generatorDecisionIndex = generatorNextIndex state
                       , generatorLengthMinimum = minimumLength
                       , generatorLengthMaximum = maximumLength
                       , generatorLengthSelection = selectedLength
                       }
                   next = recordDecision random' decision state
               evaluateGenerator (repeatGenerator selectedLength item) next

-- | Produce a uniform permutation of the supplied positions.
shuffle :: [value] -> Generator [value]
shuffle values = Generator (shuffleFrom values [])

-- | Run one generator with its isolated variable sub-seed.
runGenerator ::
     Int
  -> Generator value
  -> Either GeneratorFailure (value, [GeneratorDecision])
runGenerator seed (Generator generate) = do
  (value, final) <-
    generate
      GeneratorState
        { generatorRandom = mkStdGen seed
        , generatorNextIndex = 0
        , generatorTranscript = []
        }
  pure (value, reverse (generatorTranscript final))

failure :: String -> Either GeneratorFailure value
failure = Left . GeneratorFailure

recordDecision ::
     StdGen -> GeneratorDecision -> GeneratorState -> GeneratorState
recordDecision random' decision state =
  state
    { generatorRandom = random'
    , generatorNextIndex = generatorNextIndex state + 1
    , generatorTranscript = decision : generatorTranscript state
    }

weightedIndex :: Integer -> [Int] -> Int
weightedIndex = go 0
  where
    go index remaining weights =
      case weights of
        [] -> error "internal error: a non-empty weighted domain became empty"
        weight:more
          | remaining <= toInteger weight -> index
          | otherwise -> go (index + 1) (remaining - toInteger weight) more

repeatGenerator :: Int -> Generator value -> Generator [value]
repeatGenerator count generator
  | count <= 0 = pure []
  | otherwise = (:) <$> generator <*> repeatGenerator (count - 1) generator

shuffleFrom ::
     [value]
  -> [value]
  -> GeneratorState
  -> Either GeneratorFailure ([value], GeneratorState)
shuffleFrom remaining selected state =
  case remaining of
    [] -> Right (reverse selected, state)
    _ ->
      let count = length remaining
          (selectedIndex, random') =
            randomR (0, count - 1) (generatorRandom state)
          (value, rest) = removeAt selectedIndex remaining
          decision =
            ShuffleDecision
              { generatorDecisionIndex = generatorNextIndex state
              , generatorShuffleRemaining = count
              , generatorShuffleSelection = selectedIndex
              }
          next = recordDecision random' decision state
       in shuffleFrom rest (value : selected) next

removeAt :: Int -> [value] -> (value, [value])
removeAt selectedIndex values =
  case splitAt selectedIndex values of
    (before, selected:after) -> (selected, before ++ after)
    _ -> error "internal error: shuffle selected an out-of-range position"
