{-# LANGUAGE RankNTypes #-}

module Solver.Backend
  ( InternalVar(..)
  , EnergyExpr
  , TermKind(..)
  , OptimizerConfig(..)
  , defaultOptimizerConfig
  , NativeBounds
  , CSP
  , BuildCSP
  , newInternalVar
  , addHardTerm
  , addSoftTerm
  , compileReturning
  , solveCSP
  , cspHardEnergy
  , valueOf
  , sq
  , maxE
  , minE
  , clipNegative
  , circularEnergy
  ) where

import           Control.Monad.State.Strict
import           Data.Array                 (Array, listArray, (!))
import           Data.List                  (foldl')
import qualified Numeric.Optimization.AD    as Opt
import           Prelude

-- Solver-facing compiled expressions
--------------------------------------------------------------------------------
newtype InternalVar =
  InternalVar Int
  deriving (Eq, Ord, Show)

newtype EnergyExpr a = EnergyExpr
  { runEnergyExpr :: EnergyEnv a -> a
  }

newtype EnergyEnv a =
  EnergyEnv (Array Int a)

valueOf :: InternalVar -> EnergyExpr a
valueOf (InternalVar i) = EnergyExpr (valueAt i)

valueAt :: Int -> EnergyEnv a -> a
valueAt i env =
  case env of
    EnergyEnv values -> values ! i

sq :: Num a => a -> a
sq x = x * x

maxE :: Floating a => EnergyExpr a -> EnergyExpr a -> EnergyExpr a
maxE x y = (x + y + abs (x - y)) / 2

minE :: Floating a => EnergyExpr a -> EnergyExpr a -> EnergyExpr a
minE x y = (x + y - abs (x - y)) / 2

clipNegative :: Floating a => EnergyExpr a -> EnergyExpr a
clipNegative = maxE 0

circularEnergy :: Floating a => Double -> EnergyExpr a -> EnergyExpr a
circularEnergy period delta = 2 - 2 * cos (scale * delta)
  where
    scale = realToFrac (2 * pi / period)

instance Num a => Num (EnergyExpr a) where
  EnergyExpr f + EnergyExpr g = EnergyExpr (\xs -> f xs + g xs)
  EnergyExpr f - EnergyExpr g = EnergyExpr (\xs -> f xs - g xs)
  EnergyExpr f * EnergyExpr g = EnergyExpr (\xs -> f xs * g xs)
  negate (EnergyExpr f) = EnergyExpr (negate . f)
  fromInteger n = EnergyExpr (const (fromInteger n))
  abs (EnergyExpr f) = EnergyExpr (abs . f)
  signum (EnergyExpr f) = EnergyExpr (signum . f)

instance Fractional a => Fractional (EnergyExpr a) where
  EnergyExpr f / EnergyExpr g = EnergyExpr (\xs -> f xs / g xs)
  recip (EnergyExpr f) = EnergyExpr (recip . f)
  fromRational r = EnergyExpr (const (fromRational r))

instance Floating a => Floating (EnergyExpr a) where
  pi = EnergyExpr (const pi)
  exp (EnergyExpr f) = EnergyExpr (exp . f)
  log (EnergyExpr f) = EnergyExpr (log . f)
  sin (EnergyExpr f) = EnergyExpr (sin . f)
  cos (EnergyExpr f) = EnergyExpr (cos . f)
  asin (EnergyExpr f) = EnergyExpr (asin . f)
  acos (EnergyExpr f) = EnergyExpr (acos . f)
  atan (EnergyExpr f) = EnergyExpr (atan . f)
  sinh (EnergyExpr f) = EnergyExpr (sinh . f)
  cosh (EnergyExpr f) = EnergyExpr (cosh . f)
  asinh (EnergyExpr f) = EnergyExpr (asinh . f)
  acosh (EnergyExpr f) = EnergyExpr (acosh . f)
  atanh (EnergyExpr f) = EnergyExpr (atanh . f)

--------------------------------------------------------------------------------
-- Problem builder
--------------------------------------------------------------------------------
data TermKind
  = HardTerm
  | SoftTerm
  deriving (Eq)

data OptimizerConfig = OptimizerConfig
  { optimizerFTolerance     :: Maybe Double
  , optimizerGTolerance     :: Maybe Double
  , optimizerMaxIterations  :: Maybe Int
  , optimizerMaxCorrections :: Maybe Int
  } deriving (Eq, Show)

defaultOptimizerConfig :: OptimizerConfig
defaultOptimizerConfig =
  OptimizerConfig
    { optimizerFTolerance = Nothing
    , optimizerGTolerance = Nothing
    , optimizerMaxIterations = Nothing
    , optimizerMaxCorrections = Nothing
    }

data Term =
  Term TermKind Rational (forall a. Floating a => EnergyExpr a)

data CSPState = CSPState
  { nextVarId       :: Int
  , initialValueRev :: [Double]
  , nativeBoundsRev :: [NativeBounds]
  , energyTermsRev  :: [Term]
  }

type BuildCSP = State CSPState

emptyCSP :: CSPState
emptyCSP =
  CSPState
    { nextVarId = 0
    , initialValueRev = []
    , nativeBoundsRev = []
    , energyTermsRev = []
    }

newInternalVar :: Double -> NativeBounds -> BuildCSP InternalVar
newInternalVar initial nativeBounds = do
  st <- get
  let i = nextVarId st
  put
    st
      { nextVarId = i + 1
      , initialValueRev = initial : initialValueRev st
      , nativeBoundsRev = nativeBounds : nativeBoundsRev st
      }
  pure (InternalVar i)

addHardTerm :: Rational -> (forall a. Floating a => EnergyExpr a) -> BuildCSP ()
addHardTerm = addTerm HardTerm

addSoftTerm :: Rational -> (forall a. Floating a => EnergyExpr a) -> BuildCSP ()
addSoftTerm = addTerm SoftTerm

addTerm ::
     TermKind
  -> Rational
  -> (forall a. Floating a => EnergyExpr a)
  -> BuildCSP ()
addTerm kind weight expr = do
  st <- get
  put st {energyTermsRev = Term kind weight expr : energyTermsRev st}

--------------------------------------------------------------------------------
-- Compilation
--------------------------------------------------------------------------------
type NativeBounds = (Double, Double)

data CSP =
  CSP
    [Double]
    [NativeBounds]
    (forall a. Floating a => [a] -> a)
    (forall a. Floating a => [a] -> a)

compileReturning :: BuildCSP a -> (a, CSP)
compileReturning build =
  (result, CSP initials nativeBounds totalEnergy hardEnergy)
  where
    (result, st) = runState build emptyCSP
    initials = reverse (initialValueRev st)
    nativeBounds = reverse (nativeBoundsRev st)
    terms = reverse (energyTermsRev st)
    totalEnergy :: Floating a => [a] -> a
    totalEnergy xs = evalTerms terms (energyEnv xs)
    hardEnergy :: Floating a => [a] -> a
    hardEnergy xs = evalTerms hardTerms (energyEnv xs)
    hardTerms = [term | term@(Term HardTerm _ _) <- terms]

energyEnv :: [a] -> EnergyEnv a
energyEnv values = EnergyEnv (listArray (0, length values - 1) values)

evalTerms :: Floating a => [Term] -> EnergyEnv a -> a
evalTerms terms env =
  foldl' (\total term -> total + weightedTerm term env) 0 terms

solveCSP :: OptimizerConfig -> CSP -> IO (Opt.Result [Double])
solveCSP optimizerConfig (CSP initials nativeBounds totalEnergy _hardEnergy)
  | Opt.isSupportedMethod Opt.LBFGSB =
    Opt.minimize
      Opt.LBFGSB
      (optimizerParams optimizerConfig)
      totalEnergy
      (Just nativeBounds)
      []
      initials
  | otherwise =
    ioError
      (userError
         "L-BFGS-B is not supported by numeric-optimization; enable the +with-lbfgsb package flag.")

optimizerParams :: OptimizerConfig -> Opt.Params [Double]
optimizerParams config =
  Opt.def
    { Opt.paramsFTol = optimizerFTolerance config
    , Opt.paramsGTol = optimizerGTolerance config
    , Opt.paramsMaxIters = optimizerMaxIterations config
    , Opt.paramsMaxCorrections = optimizerMaxCorrections config
    }

cspHardEnergy :: CSP -> [Double] -> Double
cspHardEnergy (CSP _ _ _ hardEnergy) = hardEnergy

weightedTerm :: Floating a => Term -> EnergyEnv a -> a
weightedTerm term env =
  case term of
    Term _ weight expr -> fromRational weight * runEnergyExpr expr env
--------------------------------------------------------------------------------
