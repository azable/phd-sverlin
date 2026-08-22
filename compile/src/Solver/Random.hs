-- | Stable seeded random streams shared by numeric and categorical solving.
module Solver.Random
  ( RandomSeed(..)
  , deriveSeed
  , randomUnitsFromSeed
  ) where

import           Data.Bits     (xor)
import           Data.Char     (ord)
import           Data.Word     (Word64)
import           Prelude
import           System.Random (mkStdGen, randomRs)

-- | A deterministic seed for one complete solver invocation.
newtype RandomSeed =
  RandomSeed Int
  deriving (Eq, Ord, Show)

-- | Derive an independent deterministic stream from a stable textual key.
deriveSeed :: RandomSeed -> String -> RandomSeed
deriveSeed (RandomSeed seed) key =
  RandomSeed (fromIntegral (foldl' hashByte initial key))
  where
    initial = offsetBasis `xor` fromIntegral seed
    hashByte hashValue character =
      (hashValue `xor` fromIntegral (ord character)) * fnvPrime

offsetBasis :: Word64
offsetBasis = 14695981039346656037

fnvPrime :: Word64
fnvPrime = 1099511628211

-- | Infinite uniform samples in @[0, 1]@ for a deterministic stream.
randomUnitsFromSeed :: RandomSeed -> [Double]
randomUnitsFromSeed (RandomSeed seed) = randomRs (0.0, 1.0) (mkStdGen seed)
