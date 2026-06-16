{-# LANGUAGE RankNTypes #-}

module LinearTrace.Solver
  ( -- * Symbolic layout language
    Var(..)
  , varName
  , Expr(..)
  , Constraint(..)
  , var
  , num
  , plus
  , minus
  , times
  , dividedBy
  , squared
  , (@=@)
  , (@<@)
  , minimize
  , maxE
  , minE
  , clipNegative
  , -- * Solving
    SolveConfig(..)
  , defaultSolveConfig
  , Solution(..)
  , solve
  , evalExpr
  ) where

import           Control.Monad.State.Strict
import           Data.Foldable              (traverse_)
import           Data.Map.Strict            (Map)
import qualified Data.Map.Strict            as Map
import           Data.Set                   (Set)
import qualified Data.Set                   as Set
import qualified Numeric.Optimization.AD    as Opt
import           Prelude

--------------------------------------------------------------------------------
-- Symbolic layout language
--------------------------------------------------------------------------------
newtype Var =
  Var String
  deriving (Eq, Ord, Show)

varName :: Var -> String
varName (Var name) = name

data Expr
  = EVar Var
  | ELit Double
  | EAdd Expr Expr
  | ESub Expr Expr
  | EMul Expr Expr
  | EDiv Expr Expr
  | ENeg Expr
  | ESquare Expr
  deriving (Eq, Show)

data Constraint
  = Equals Expr Expr
  | LessThan Expr Expr
  | Minimize Expr

var :: String -> Expr
var = EVar . Var

num :: Double -> Expr
num = ELit

plus :: Expr -> Expr -> Expr
plus = EAdd

minus :: Expr -> Expr -> Expr
minus = ESub

times :: Expr -> Expr -> Expr
times = EMul

dividedBy :: Expr -> Expr -> Expr
dividedBy = EDiv

squared :: Expr -> Expr
squared = ESquare

(@=@) :: Expr -> Expr -> Constraint
(@=@) = Equals

(@<@) :: Expr -> Expr -> Constraint
(@<@) = LessThan

minimize :: Expr -> Constraint
minimize = Minimize

maxE :: Floating a => EnergyExpr a -> EnergyExpr a -> EnergyExpr a
maxE x y = (x + y + abs (x - y)) / 2

minE :: Floating a => EnergyExpr a -> EnergyExpr a -> EnergyExpr a
minE x y = (x + y - abs (x - y)) / 2

clipNegative :: Floating a => EnergyExpr a -> EnergyExpr a
clipNegative = maxE 0

--------------------------------------------------------------------------------
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
data Term =
  Term Rational (forall a. Floating a => EnergyExpr a)

data CSPState = CSPState
  { nextVarId     :: Int
  , initialValues :: [Double]
  , energyTerms   :: [Term]
  }

type BuildCSP = State CSPState

emptyCSP :: CSPState
emptyCSP = CSPState {nextVarId = 0, initialValues = [], energyTerms = []}

newInternalVar :: Double -> BuildCSP InternalVar
newInternalVar initial = do
  st <- get
  let i = nextVarId st
  put st {nextVarId = i + 1, initialValues = initialValues st ++ [initial]}
  pure (InternalVar i)

addTerm :: Rational -> (forall a. Floating a => EnergyExpr a) -> BuildCSP ()
addTerm weight expr = do
  st <- get
  put st {energyTerms = energyTerms st ++ [Term weight expr]}

--------------------------------------------------------------------------------
-- Compilation
--------------------------------------------------------------------------------
data CSP =
  CSP [Double] (forall a. Floating a => [a] -> a)

compileReturning :: BuildCSP a -> (a, CSP)
compileReturning build = (result, CSP initials energy)
  where
    (result, st) = runState build emptyCSP
    initials = initialValues st
    terms = energyTerms st
    energy xs =
      sum
        [ fromRational weight * runEnergyExpr expr xs
        | Term weight expr <- terms
        ]

solveCSP :: CSP -> IO (Opt.Result [Double])
solveCSP (CSP initials energy) =
  Opt.minimize Opt.LBFGS Opt.def energy Nothing [] initials

--------------------------------------------------------------------------------
-- Named constraint solving
--------------------------------------------------------------------------------
data SolveConfig = SolveConfig
  { initialValueFor :: String -> Double
  , ensureWeight    :: Rational
  , encourageWeight :: Rational
  }

defaultSolveConfig :: SolveConfig
defaultSolveConfig =
  SolveConfig
    { initialValueFor = defaultInitialValue
    , ensureWeight = 100
    , encourageWeight = 1
    }

defaultInitialValue :: String -> Double
defaultInitialValue name
  | otherwise = 0

data NamedCSP = NamedCSP
  { namedVars :: Map String InternalVar
  , namedCSP  :: CSP
  }

data Solution = Solution
  { solutionSuccess :: Bool
  , solutionEnergy  :: Double
  , solutionValues  :: Map String Double
  , solutionVector  :: [Double]
  } deriving (Eq, Show)

solve :: SolveConfig -> [Constraint] -> IO Solution
solve config constraints = do
  let named = compileConstraints config constraints
  result <- solveCSP (namedCSP named)
  let vector = Opt.resultSolution result
      lookupValue (InternalVar i)
        | i < length vector = Just (vector !! i)
        | otherwise = Nothing
      values = Map.mapMaybe lookupValue (namedVars named)
  pure
    Solution
      { solutionSuccess = Opt.resultSuccess result
      , solutionEnergy = Opt.resultValue result
      , solutionValues = values
      , solutionVector = vector
      }

compileConstraints :: SolveConfig -> [Constraint] -> NamedCSP
compileConstraints config constraints =
  NamedCSP {namedVars = vars, namedCSP = csp}
  where
    names = Set.toAscList (foldMap collectConstraintVars constraints)
    build = do
      pairs <-
        traverse
          (\name -> do
             internal <- newInternalVar (initialValueFor config name)
             pure (name, internal))
          names
      let vars' = Map.fromList pairs
      traverse_ (lowerConstraint config vars') constraints
      pure vars'
    (vars, csp) = compileReturning build

--------------------------------------------------------------------------------
-- Symbol collection
--------------------------------------------------------------------------------
collectExprVars :: Expr -> Set String
collectExprVars expr =
  case expr of
    EVar v        -> Set.singleton (varName v)
    ELit _        -> Set.empty
    EAdd lhs rhs  -> collectExprVars lhs <> collectExprVars rhs
    ESub lhs rhs  -> collectExprVars lhs <> collectExprVars rhs
    EMul lhs rhs  -> collectExprVars lhs <> collectExprVars rhs
    EDiv lhs rhs  -> collectExprVars lhs <> collectExprVars rhs
    ENeg inner    -> collectExprVars inner
    ESquare inner -> collectExprVars inner

collectConstraintVars :: Constraint -> Set String
collectConstraintVars constraint =
  case constraint of
    Equals lhs rhs     -> collectExprVars lhs <> collectExprVars rhs
    LessThan lhs rhs   -> collectExprVars lhs <> collectExprVars rhs
    Minimize objective -> collectExprVars objective

--------------------------------------------------------------------------------
-- Lowering symbolic expressions to AD-friendly energy expressions
--------------------------------------------------------------------------------
lowerConstraint ::
     SolveConfig -> Map String InternalVar -> Constraint -> BuildCSP ()
lowerConstraint config vars constraint =
  case constraint of
    Equals lhs rhs ->
      addTerm
        (ensureWeight config)
        (sq (lowerExpr vars lhs - lowerExpr vars rhs))
    LessThan lhs rhs ->
      addTerm
        (ensureWeight config)
        (sq (clipNegative (lowerExpr vars lhs - lowerExpr vars rhs)))
    Minimize objective ->
      addTerm (encourageWeight config) (lowerExpr vars objective)

lowerExpr :: Floating a => Map String InternalVar -> Expr -> EnergyExpr a
lowerExpr vars expr =
  case expr of
    EVar symbolic ->
      case Map.lookup (varName symbolic) vars of
        Just internal -> valueOf internal
        Nothing       -> error ("unknown solver variable: " ++ varName symbolic)
    ELit x -> realToFrac x
    EAdd lhs rhs -> lowerExpr vars lhs + lowerExpr vars rhs
    ESub lhs rhs -> lowerExpr vars lhs - lowerExpr vars rhs
    EMul lhs rhs -> lowerExpr vars lhs * lowerExpr vars rhs
    EDiv lhs rhs -> lowerExpr vars lhs / lowerExpr vars rhs
    ENeg inner -> negate (lowerExpr vars inner)
    ESquare inner -> sq (lowerExpr vars inner)

--------------------------------------------------------------------------------
-- Evaluating symbolic expressions against a solution
--------------------------------------------------------------------------------
evalExpr :: Solution -> Expr -> Maybe Double
evalExpr solution expr =
  case expr of
    EVar symbolic -> Map.lookup (varName symbolic) (solutionValues solution)
    ELit x -> Just x
    EAdd lhs rhs -> (+) <$> evalExpr solution lhs <*> evalExpr solution rhs
    ESub lhs rhs -> (-) <$> evalExpr solution lhs <*> evalExpr solution rhs
    EMul lhs rhs -> (*) <$> evalExpr solution lhs <*> evalExpr solution rhs
    EDiv lhs rhs -> do
      lhs' <- evalExpr solution lhs
      rhs' <- evalExpr solution rhs
      pure (lhs' / rhs')
    ENeg inner -> negate <$> evalExpr solution inner
    ESquare inner -> sq <$> evalExpr solution inner
