{-# LANGUAGE FlexibleContexts #-}

module Solver where

import           Control.Monad.State.Strict
import           Numeric.Optimization.AD

--------------------------------------------------------------------------------
-- Variables and expressions
--------------------------------------------------------------------------------
newtype Var =
  Var Int
  deriving (Eq, Ord, Show)

newtype Expr a = Expr
  { runExpr :: [a] -> a
  }

valueOf :: Var -> Expr a
valueOf (Var i) = Expr (!! i)

sq :: Num a => a -> a
sq x = x * x

instance Num a => Num (Expr a) where
  Expr f + Expr g = Expr (\xs -> f xs + g xs)
  Expr f - Expr g = Expr (\xs -> f xs - g xs)
  Expr f * Expr g = Expr (\xs -> f xs * g xs)
  negate (Expr f) = Expr $ negate . f
  fromInteger n = Expr $ const (fromInteger n)
  abs (Expr f) = Expr $ abs . f
  signum (Expr f) = Expr $ signum . f

instance Fractional a => Fractional (Expr a) where
  Expr f / Expr g = Expr $ \xs -> f xs / g xs
  recip (Expr f) = Expr $ recip . f
  fromRational r = Expr $ const (fromRational r)

instance Floating a => Floating (Expr a) where
  pi = Expr $ const pi
  exp (Expr f) = Expr $ exp . f
  log (Expr f) = Expr $ log . f
  sin (Expr f) = Expr $ sin . f
  cos (Expr f) = Expr $ cos . f
  asin (Expr f) = Expr $ asin . f
  acos (Expr f) = Expr $ acos . f
  atan (Expr f) = Expr $ atan . f
  sinh (Expr f) = Expr $ sinh . f
  cosh (Expr f) = Expr $ cosh . f
  asinh (Expr f) = Expr $ asinh . f
  acosh (Expr f) = Expr $ acosh . f
  atanh (Expr f) = Expr $ atanh . f

--------------------------------------------------------------------------------
-- Problem builder
--------------------------------------------------------------------------------
data Term =
  Term Rational (forall a. Floating a => Expr a)

data CSPState = CSPState
  { nextVarId     :: Int
  , initialValues :: [Double]
  , energyTerms   :: [Term]
  }

type BuildCSP = State CSPState

emptyCSP :: CSPState
emptyCSP = CSPState {nextVarId = 0, initialValues = [], energyTerms = []}

newVar :: Double -> BuildCSP Var
newVar initial = do
  st <- get
  let i = nextVarId st
  put st {nextVarId = i + 1, initialValues = initialValues st ++ [initial]}
  pure (Var i)

addTerm :: Rational -> (forall a. Floating a => Expr a) -> BuildCSP ()
addTerm weight expr = do
  st <- get
  put st {energyTerms = energyTerms st ++ [Term weight expr]}

encourage :: (forall a. Floating a => Expr a) -> BuildCSP ()
encourage = addTerm 1

ensure :: (forall a. Floating a => Expr a) -> BuildCSP ()
ensure = addTerm 100

--------------------------------------------------------------------------------
-- Compilation
--------------------------------------------------------------------------------
data CSP =
  CSP [Double] (forall a. Floating a => [a] -> a)

compile :: BuildCSP () -> CSP
compile build = CSP initials energy
  where
    st = execState build emptyCSP
    initials = initialValues st
    terms = energyTerms st
    energy xs =
      sum [fromRational weight * runExpr expr xs | Term weight expr <- terms]

solve :: CSP -> IO (Result [Double])
solve (CSP initials energy) = minimize LBFGS def energy Nothing [] initials

--------------------------------------------------------------------------------
-- Constraint/objective helpers
--------------------------------------------------------------------------------
target :: Floating a => Var -> Rational -> Expr a
target v wanted = sq (valueOf v - fromRational wanted)

equal :: Floating a => Var -> Var -> Expr a
equal a b = sq (valueOf a - valueOf b)

sumEquals :: Floating a => Var -> Var -> Rational -> Expr a
sumEquals a b wanted = sq (valueOf a + valueOf b - fromRational wanted)

--------------------------------------------------------------------------------
-- Example
--------------------------------------------------------------------------------
example :: BuildCSP ()
example = do
  x <- newVar 0
  y <- newVar 0
  encourage (target x 3)
  encourage (target y 2)
  ensure (sumEquals x y 6)

test :: IO ()
test = do
  let csp = compile example
  result <- solve csp
  putStrLn "success:"
  print (resultSuccess result)
  putStrLn "solution:"
  print (resultSolution result)
  putStrLn "energy:"
  print (resultValue result)
