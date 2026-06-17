{-# LANGUAGE DeriveTraversable   #-}
{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}

module LinearTrace.Solver
  ( -- * Symbolic scalar domains
    Range(..)
  , ScalarType(..)
  , InitialBounds(..)
  , SymbolicType(..)
  , Free
  , Length
  , Unit
  , Angle
  , -- * Symbolic scalar language
    Var(..)
  , varName
  , Expr
  , RawExpr(..)
  , exprType
  , exprRaw
  , var
  , num
  , (@+@)
  , (@-@)
  , (@*@)
  , (@/@)
  , (@^@)
  , plus
  , minus
  , times
  , dividedBy
  , squared
  , Constraint(..)
  , (@=@)
  , (@<@)
  , minimize
  , -- * Symbolic vector containers
    Vec2(..)
  , Vec3(..)
  , Vec4(..)
  , vec2
  , vec3
  , vec4
  , evalVec2
  , evalVec3
  , evalVec4
  , -- * Internal energy helpers
    maxE
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
import           Data.List                  (foldl')
import           Data.Map.Strict            (Map)
import qualified Data.Map.Strict            as Map
import           Data.Proxy                 (Proxy (..))
import qualified Numeric.Optimization.AD    as Opt
import           Prelude

--------------------------------------------------------------------------------
-- Symbolic scalar domains
--------------------------------------------------------------------------------
data Range = Range
  { rangeLower :: Double
  , rangeUpper :: Double
  } deriving (Eq, Ord, Show)

data ScalarType = ScalarType
  { typeName           :: String
  , typeRange          :: Maybe Range
  , typeCircularPeriod :: Maybe Double
  } deriving (Eq, Ord, Show)

data InitialBounds = InitialBounds
  { initialLower :: Maybe Double
  , initialUpper :: Maybe Double
  } deriving (Eq, Show)

class SymbolicType ty where
  symbolicType :: Proxy ty -> ScalarType

data Free

data Length

data Unit

data Angle

instance SymbolicType Free where
  symbolicType _ =
    ScalarType
      {typeName = "free", typeRange = Nothing, typeCircularPeriod = Nothing}

instance SymbolicType Length where
  symbolicType _ =
    ScalarType
      {typeName = "length", typeRange = Nothing, typeCircularPeriod = Nothing}

instance SymbolicType Unit where
  symbolicType _ =
    ScalarType
      { typeName = "unit"
      , typeRange = Just (Range 0 1)
      , typeCircularPeriod = Nothing
      }

instance SymbolicType Angle where
  symbolicType _ =
    ScalarType
      { typeName = "angle"
      , typeRange = Just (Range 0 360)
      , typeCircularPeriod = Just 360
      }

unboundedInitialBounds :: InitialBounds
unboundedInitialBounds =
  InitialBounds {initialLower = Nothing, initialUpper = Nothing}

rangeToInitialBounds :: Range -> InitialBounds
rangeToInitialBounds range =
  InitialBounds
    { initialLower = Just (rangeLower range)
    , initialUpper = Just (rangeUpper range)
    }

typeInitialBounds :: ScalarType -> InitialBounds
typeInitialBounds ty =
  case typeRange ty of
    Nothing    -> unboundedInitialBounds
    Just range -> rangeToInitialBounds range

mergeInitialBounds :: InitialBounds -> InitialBounds -> InitialBounds
mergeInitialBounds a b =
  InitialBounds
    { initialLower = mergeLower (initialLower a) (initialLower b)
    , initialUpper = mergeUpper (initialUpper a) (initialUpper b)
    }

mergeLower :: Maybe Double -> Maybe Double -> Maybe Double
mergeLower a b =
  case (a, b) of
    (Nothing, x)     -> x
    (x, Nothing)     -> x
    (Just x, Just y) -> Just (max x y)

mergeUpper :: Maybe Double -> Maybe Double -> Maybe Double
mergeUpper a b =
  case (a, b) of
    (Nothing, x)     -> x
    (x, Nothing)     -> x
    (Just x, Just y) -> Just (min x y)

addInitialLower :: Double -> InitialBounds -> InitialBounds
addInitialLower lo bounds =
  bounds
    { initialLower =
        case initialLower bounds of
          Nothing  -> Just lo
          Just old -> Just (max old lo)
    }

addInitialUpper :: Double -> InitialBounds -> InitialBounds
addInitialUpper hi bounds =
  bounds
    { initialUpper =
        case initialUpper bounds of
          Nothing  -> Just hi
          Just old -> Just (min old hi)
    }

--------------------------------------------------------------------------------
-- Symbolic scalar language
--------------------------------------------------------------------------------
newtype Var =
  Var String
  deriving (Eq, Ord, Show)

varName :: Var -> String
varName (Var name) = name

data RawExpr
  = EVar ScalarType Var
  | ELit Double
  | EAdd RawExpr RawExpr
  | ESub RawExpr RawExpr
  | EMul RawExpr RawExpr
  | EDiv RawExpr RawExpr
  | ENeg RawExpr
  | EAbs RawExpr
  | ESignum RawExpr
  | EPow RawExpr RawExpr
  deriving (Eq, Show)

data Expr ty = Expr
  { exprType :: ScalarType
  , exprRaw  :: RawExpr
  } deriving (Eq, Show)

var ::
     forall ty. SymbolicType ty
  => String
  -> Expr ty
var name = Expr ty (EVar ty (Var name))
  where
    ty = symbolicType (Proxy :: Proxy ty)

num ::
     forall ty. SymbolicType ty
  => Double
  -> Expr ty
num value = Expr (symbolicType (Proxy :: Proxy ty)) (ELit value)

binaryExpr :: (RawExpr -> RawExpr -> RawExpr) -> Expr ty -> Expr ty -> Expr ty
binaryExpr f (Expr ty lhs) (Expr _ rhs) = Expr ty (f lhs rhs)

unaryExpr :: (RawExpr -> RawExpr) -> Expr ty -> Expr ty
unaryExpr f (Expr ty inner) = Expr ty (f inner)

(@+@) :: Expr ty -> Expr ty -> Expr ty
(@+@) = binaryExpr EAdd

(@-@) :: Expr ty -> Expr ty -> Expr ty
(@-@) = binaryExpr ESub

(@*@) :: Expr ty -> Expr ty -> Expr ty
(@*@) = binaryExpr EMul

(@/@) :: Expr ty -> Expr ty -> Expr ty
(@/@) = binaryExpr EDiv

(@^@) :: Expr ty -> Expr ty -> Expr ty
(@^@) = binaryExpr EPow

plus :: Expr ty -> Expr ty -> Expr ty
plus = (@+@)

minus :: Expr ty -> Expr ty -> Expr ty
minus = (@-@)

times :: Expr ty -> Expr ty -> Expr ty
times = (@*@)

dividedBy :: Expr ty -> Expr ty -> Expr ty
dividedBy = (@/@)

squared :: Expr ty -> Expr ty
squared x = x @*@ x

instance SymbolicType ty => Num (Expr ty) where
  (+) = (@+@)
  (-) = (@-@)
  (*) = (@*@)
  negate = unaryExpr ENeg
  abs = unaryExpr EAbs
  signum = unaryExpr ESignum
  fromInteger = num . fromInteger

instance SymbolicType ty => Fractional (Expr ty) where
  (/) = (@/@)
  recip x = num 1 / x
  fromRational = num . fromRational

data Constraint
  = Equals ScalarType RawExpr RawExpr
  | LessThan RawExpr RawExpr
  | Minimize RawExpr
  deriving (Eq, Show)

(@=@) :: Expr ty -> Expr ty -> Constraint
Expr ty lhs @=@ Expr _ rhs = Equals ty lhs rhs

(@<@) :: Expr ty -> Expr ty -> Constraint
Expr _ lhs @<@ Expr _ rhs = LessThan lhs rhs

minimize :: Expr ty -> Constraint
minimize (Expr _ objective) = Minimize objective

--------------------------------------------------------------------------------
-- Symbolic vector containers
--------------------------------------------------------------------------------
data Vec2 a =
  Vec2 a a
  deriving (Eq, Show, Functor, Foldable, Traversable)

data Vec3 a =
  Vec3 a a a
  deriving (Eq, Show, Functor, Foldable, Traversable)

data Vec4 a =
  Vec4 a a a a
  deriving (Eq, Show, Functor, Foldable, Traversable)

vec2 :: a -> a -> Vec2 a
vec2 = Vec2

vec3 :: a -> a -> a -> Vec3 a
vec3 = Vec3

vec4 :: a -> a -> a -> a -> Vec4 a
vec4 = Vec4

evalVec2 :: Solution -> Vec2 (Expr ty) -> Maybe (Vec2 Double)
evalVec2 solution = traverse (evalExpr solution)

evalVec3 :: Solution -> Vec3 (Expr ty) -> Maybe (Vec3 Double)
evalVec3 solution = traverse (evalExpr solution)

evalVec4 :: Solution -> Vec4 (Expr ty) -> Maybe (Vec4 Double)
evalVec4 solution = traverse (evalExpr solution)

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

constant :: Floating a => Double -> EnergyExpr a
constant x = EnergyExpr (const (realToFrac x))

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

addRangeTerms :: Rational -> InternalVar -> Range -> BuildCSP ()
addRangeTerms weight internal range = do
  addTerm
    weight
    (sq (clipNegative (constant (rangeLower range) - valueOf internal)))
  addTerm
    weight
    (sq (clipNegative (valueOf internal - constant (rangeUpper range))))

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
  { initialValueFor :: String -> ScalarType -> InitialBounds -> Double
  , ensureWeight    :: Rational
  , encourageWeight :: Rational
  , rangeWeight     :: Rational
  }

defaultSolveConfig :: SolveConfig
defaultSolveConfig =
  SolveConfig
    { initialValueFor = defaultInitialValue
    , ensureWeight = 100
    , encourageWeight = 1
    , rangeWeight = 100
    }

defaultInitialValue :: String -> ScalarType -> InitialBounds -> Double
defaultInitialValue name _ bounds = chooseInitialValue bounds (hashUnit name)

chooseInitialValue :: InitialBounds -> Double -> Double
chooseInitialValue bounds t =
  case (initialLower bounds, initialUpper bounds) of
    (Just lo, Just hi)
      | lo < hi -> lo + interior t * (hi - lo)
      | otherwise -> lo
    (Just lo, Nothing) -> lo + 1 + 99 * t
    (Nothing, Just hi) -> hi - 1 - 99 * t
    (Nothing, Nothing) -> (t - 0.5) * 200

interior :: Double -> Double
interior t = 0.05 + 0.9 * t

hashUnit :: String -> Double
hashUnit text = fromIntegral bucket / fromIntegral modulus
  where
    modulus = 1000000 :: Int
    bucket = abs hash `mod` modulus
    hash = foldl' (\acc ch -> acc * 33 + fromEnum ch) (5381 :: Int) text

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
    varTypes = collectConstraintVarTypes constraints
    inferredBounds = inferInitialBounds constraints
    build = do
      pairs <-
        traverse
          (\(name, ty) -> do
             let bounds =
                   typeInitialBounds ty
                     `mergeInitialBounds` Map.findWithDefault
                                            unboundedInitialBounds
                                            name
                                            inferredBounds
             internal <- newInternalVar (initialValueFor config name ty bounds)
             pure (name, ty, internal))
          (Map.toAscList varTypes)
      let vars' =
            Map.fromList [(name, internal) | (name, _ty, internal) <- pairs]
      traverse_
        (\(_name, ty, internal) ->
           case typeRange ty of
             Nothing    -> pure ()
             Just range -> addRangeTerms (rangeWeight config) internal range)
        pairs
      traverse_ (lowerConstraint config vars') constraints
      pure vars'
    (vars, csp) = compileReturning build

--------------------------------------------------------------------------------
-- Symbol collection and inferred initial ranges
--------------------------------------------------------------------------------
collectRawExprVarTypes :: RawExpr -> Map String ScalarType
collectRawExprVarTypes expr =
  case expr of
    EVar ty v -> Map.singleton (varName v) ty
    ELit _ -> Map.empty
    EAdd lhs rhs ->
      mergeVarTypeMaps (collectRawExprVarTypes lhs) (collectRawExprVarTypes rhs)
    ESub lhs rhs ->
      mergeVarTypeMaps (collectRawExprVarTypes lhs) (collectRawExprVarTypes rhs)
    EMul lhs rhs ->
      mergeVarTypeMaps (collectRawExprVarTypes lhs) (collectRawExprVarTypes rhs)
    EDiv lhs rhs ->
      mergeVarTypeMaps (collectRawExprVarTypes lhs) (collectRawExprVarTypes rhs)
    ENeg inner -> collectRawExprVarTypes inner
    EAbs inner -> collectRawExprVarTypes inner
    ESignum inner -> collectRawExprVarTypes inner
    EPow base to ->
      mergeVarTypeMaps (collectRawExprVarTypes base) (collectRawExprVarTypes to)

mergeVarTypeMaps ::
     Map String ScalarType -> Map String ScalarType -> Map String ScalarType
mergeVarTypeMaps = Map.unionWith mergeVarTypes

mergeVarTypes :: ScalarType -> ScalarType -> ScalarType
mergeVarTypes a b
  | a == b = a
  | otherwise =
    error
      ("solver variable used with incompatible symbolic types: "
         ++ show a
         ++ " and "
         ++ show b)

collectConstraintVarTypes :: [Constraint] -> Map String ScalarType
collectConstraintVarTypes = foldMap collectOne
  where
    collectOne constraint =
      case constraint of
        Equals _ lhs rhs ->
          mergeVarTypeMaps
            (collectRawExprVarTypes lhs)
            (collectRawExprVarTypes rhs)
        LessThan lhs rhs ->
          mergeVarTypeMaps
            (collectRawExprVarTypes lhs)
            (collectRawExprVarTypes rhs)
        Minimize objective -> collectRawExprVarTypes objective

inferInitialBounds :: [Constraint] -> Map String InitialBounds
inferInitialBounds = foldl' addConstraint Map.empty

addConstraint ::
     Map String InitialBounds -> Constraint -> Map String InitialBounds
addConstraint bounds constraint =
  case constraint of
    LessThan (ELit lo) (EVar _ v) ->
      Map.alter
        (Just . addInitialLower lo . maybe unboundedInitialBounds id)
        (varName v)
        bounds
    LessThan (EVar _ v) (ELit hi) ->
      Map.alter
        (Just . addInitialUpper hi . maybe unboundedInitialBounds id)
        (varName v)
        bounds
    _ -> bounds

--------------------------------------------------------------------------------
-- Lowering symbolic expressions to AD-friendly energy expressions
--------------------------------------------------------------------------------
lowerConstraint ::
     SolveConfig -> Map String InternalVar -> Constraint -> BuildCSP ()
lowerConstraint config vars constraint =
  case constraint of
    Equals ty lhs rhs ->
      case typeCircularPeriod ty of
        Just period
          | period > 0 ->
            addTerm
              (ensureWeight config)
              (circularEnergy period (lowerExpr vars lhs - lowerExpr vars rhs))
        _ ->
          addTerm
            (ensureWeight config)
            (sq (lowerExpr vars lhs - lowerExpr vars rhs))
    LessThan lhs rhs ->
      addTerm
        (ensureWeight config)
        (sq (clipNegative (lowerExpr vars lhs - lowerExpr vars rhs)))
    Minimize objective ->
      addTerm (encourageWeight config) (lowerExpr vars objective)

lowerExpr :: Floating a => Map String InternalVar -> RawExpr -> EnergyExpr a
lowerExpr vars expr =
  case expr of
    EVar _ symbolic ->
      case Map.lookup (varName symbolic) vars of
        Just internal -> valueOf internal
        Nothing       -> error ("unknown solver variable: " ++ varName symbolic)
    ELit x -> realToFrac x
    EAdd lhs rhs -> lowerExpr vars lhs + lowerExpr vars rhs
    ESub lhs rhs -> lowerExpr vars lhs - lowerExpr vars rhs
    EMul lhs rhs -> lowerExpr vars lhs * lowerExpr vars rhs
    EDiv lhs rhs -> lowerExpr vars lhs / lowerExpr vars rhs
    ENeg inner -> negate (lowerExpr vars inner)
    EAbs inner -> abs (lowerExpr vars inner)
    ESignum inner -> signum (lowerExpr vars inner)
    EPow base to -> lowerExpr vars base ** lowerExpr vars to

--------------------------------------------------------------------------------
-- Evaluating symbolic expressions against a solution
--------------------------------------------------------------------------------
evalExpr :: Solution -> Expr ty -> Maybe Double
evalExpr solution (Expr _ expr) = evalRawExpr solution expr

evalRawExpr :: Solution -> RawExpr -> Maybe Double
evalRawExpr solution expr =
  case expr of
    EVar _ symbolic -> Map.lookup (varName symbolic) (solutionValues solution)
    ELit x -> Just x
    EAdd lhs rhs ->
      (+) <$> evalRawExpr solution lhs <*> evalRawExpr solution rhs
    ESub lhs rhs ->
      (-) <$> evalRawExpr solution lhs <*> evalRawExpr solution rhs
    EMul lhs rhs ->
      (*) <$> evalRawExpr solution lhs <*> evalRawExpr solution rhs
    EDiv lhs rhs -> do
      lhs' <- evalRawExpr solution lhs
      rhs' <- evalRawExpr solution rhs
      pure (lhs' / rhs')
    ENeg inner -> negate <$> evalRawExpr solution inner
    EAbs inner -> abs <$> evalRawExpr solution inner
    ESignum inner -> signum <$> evalRawExpr solution inner
    EPow base to ->
      (**) <$> evalRawExpr solution base <*> evalRawExpr solution to
