{-# LANGUAGE FlexibleContexts #-}

module Solver where

import           Numeric.Optimization.AD

newtype Expr a = Expr
  { runExpr :: [a] -> a
  }

var :: Int -> Expr a
var i = Expr (!! i)

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

x :: Expr a
x = var 0

samplePolynomial :: Floating a => Expr a
samplePolynomial = x ^ (2 :: Int) + 3 * x + 5

energy :: Floating a => [a] -> a
energy = runExpr samplePolynomial

test :: IO ()
test = do
  result <- minimize LBFGS def energy Nothing [] ([0] :: [Double])
  putStrLn "success:"
  print (resultSuccess result)
  putStrLn "solution:"
  print (resultSolution result)
  putStrLn "energy:"
  print (resultValue result)
