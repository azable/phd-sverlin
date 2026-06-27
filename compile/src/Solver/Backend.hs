{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE RankNTypes               #-}

module Solver.Backend
  ( InternalVar(..)
  , EnergyExpr
  , TermKind(..)
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

import           Control.Exception          (bracket)
import           Control.Monad.State.Strict
import           Foreign.C.Types            (CInt (..))
import           Foreign.Ptr                (Ptr, nullPtr)
import qualified Numeric.Optimization.AD    as Opt
import           Prelude
import qualified System.IO                  as IO
import           System.Posix.IO            (OpenMode (WriteOnly), closeFd,
                                             defaultFileFlags, dup, dupTo,
                                             openFd, stdOutput)

-- Solver-facing compiled expressions
--------------------------------------------------------------------------------
newtype InternalVar =
  InternalVar Int
  deriving (Eq, Ord, Show)

newtype EnergyExpr a = EnergyExpr
  { runEnergyExpr :: [a] -> a
  }

valueOf :: InternalVar -> EnergyExpr a
valueOf (InternalVar i) = EnergyExpr (!! i)

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
    totalEnergy xs =
      sum [weightedTerm weight expr xs | Term _ weight expr <- terms]
    hardEnergy xs =
      sum [weightedTerm weight expr xs | Term HardTerm weight expr <- terms]

solveCSP :: CSP -> IO (Opt.Result [Double])
solveCSP (CSP initials nativeBounds totalEnergy _hardEnergy)
  | Opt.isSupportedMethod Opt.LBFGSB =
    suppressNativeStdout
      (Opt.minimize
         Opt.LBFGSB
         Opt.def
         totalEnergy
         (Just nativeBounds)
         []
         initials)
  | otherwise =
    ioError
      (userError
         "L-BFGS-B is not supported by numeric-optimization; enable the +with-lbfgsb package flag.")

suppressNativeStdout :: IO a -> IO a
suppressNativeStdout =
  bracket
    (do
       IO.hFlush IO.stdout
       flushNativeOutput
       savedStdout <- dup stdOutput
       nullOutput <- openFd "/dev/null" WriteOnly defaultFileFlags
       _ <- dupTo nullOutput stdOutput
       closeFd nullOutput
       pure savedStdout)
    (\savedStdout -> do
       flushNativeOutput
       IO.hFlush IO.stdout
       _ <- dupTo savedStdout stdOutput
       closeFd savedStdout)
    . const

flushNativeOutput :: IO ()
flushNativeOutput = do
  _ <- c_fflush nullPtr
  pure ()

foreign import ccall unsafe "stdio.h fflush" c_fflush :: Ptr () -> IO CInt

cspHardEnergy :: CSP -> [Double] -> Double
cspHardEnergy (CSP _ _ _ hardEnergy) = hardEnergy

weightedTerm ::
     Floating a
  => Rational
  -> (forall b. Floating b => EnergyExpr b)
  -> [a]
  -> a
weightedTerm weight expr xs = fromRational weight * runEnergyExpr expr xs
--------------------------------------------------------------------------------
