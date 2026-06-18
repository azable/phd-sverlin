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
  , Layout
  , Unit
  , Angle
  , -- * Symbolic scalar expressions
    Var(..)
  , InitialVar(..)
  , initialRangeFor
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
  , -- * Constraints
    Constraint(..)
  , ConstrainEq(..)
  , ConstrainOrd(..)
  , (@==@)
  , (@<=@)
  , (@>=@)
  , minimize
  , flattenConstraint
  , -- * Symbolic vector containers
    Vec2(..)
  , Vec3(..)
  , Vec4(..)
  , vec2
  , vec3
  , vec4
  , -- * Internal energy helpers
    maxE
  , minE
  , clipNegative
  , -- * Seeded initial value generation
    RandomSeed(..)
  , RandomSample(..)
  , defaultRandomSeed
  , randomSamplesFromSeed
  , randomUnitsFromSeed
  , -- * Solving
    SolveConfig(..)
  , defaultSolveConfig
  , Solution(..)
  , solve
  , solveWithInitialVars
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
import           System.Random              (mkStdGen, randomRs)

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

data Layout

data Unit

data Angle

instance SymbolicType Free where
  symbolicType _ =
    ScalarType
      {typeName = "free", typeRange = Nothing, typeCircularPeriod = Nothing}

instance SymbolicType Layout where
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
-- Symbolic scalar expressions
--------------------------------------------------------------------------------
newtype Var =
  Var String
  deriving (Eq, Ord, Show)

varName :: Var -> String
varName (Var name) = name

data InitialVar = InitialVar
  { initialVarName   :: String
  , initialVarType   :: ScalarType
  , initialVarBounds :: InitialBounds
  } deriving (Eq, Show)

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

initialRangeFor :: Expr ty -> Range -> Maybe InitialVar
initialRangeFor (Expr _ raw) range =
  case raw of
    EVar ty variable ->
      Just
        InitialVar
          { initialVarName = varName variable
          , initialVarType = ty
          , initialVarBounds = rangeToInitialBounds range
          }
    _ -> Nothing

num ::
     forall ty. SymbolicType ty
  => Double
  -> Expr ty
num value = Expr ty (ELit value)
  where
    ty = symbolicType (Proxy :: Proxy ty)

binaryExpr :: (RawExpr -> RawExpr -> RawExpr) -> Expr ty -> Expr ty -> Expr ty
binaryExpr f (Expr ty lhs) (Expr _ rhs) = Expr ty (f lhs rhs)

unaryExpr :: (RawExpr -> RawExpr) -> Expr ty -> Expr ty
unaryExpr f (Expr ty inner) = Expr ty (f inner)

infixl 6 @+@
infixl 6 @-@
infixl 7 @*@
infixl 7 @/@
infixr 8 @^@
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
  recip x = num 1 @/@ x
  fromRational = num . fromRational

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

instance Num a => Num (Vec2 a) where
  Vec2 ax ay + Vec2 bx by = Vec2 (ax + bx) (ay + by)
  Vec2 ax ay - Vec2 bx by = Vec2 (ax - bx) (ay - by)
  Vec2 ax ay * Vec2 bx by = Vec2 (ax * bx) (ay * by)
  negate (Vec2 ax ay) = Vec2 (negate ax) (negate ay)
  abs (Vec2 ax ay) = Vec2 (abs ax) (abs ay)
  signum (Vec2 ax ay) = Vec2 (signum ax) (signum ay)
  fromInteger n = Vec2 (fromInteger n) (fromInteger n)

instance Fractional a => Fractional (Vec2 a) where
  Vec2 ax ay / Vec2 bx by = Vec2 (ax / bx) (ay / by)
  recip (Vec2 ax ay) = Vec2 (recip ax) (recip ay)
  fromRational x = Vec2 (fromRational x) (fromRational x)

instance Num a => Num (Vec3 a) where
  Vec3 ax ay az + Vec3 bx by bz = Vec3 (ax + bx) (ay + by) (az + bz)
  Vec3 ax ay az - Vec3 bx by bz = Vec3 (ax - bx) (ay - by) (az - bz)
  Vec3 ax ay az * Vec3 bx by bz = Vec3 (ax * bx) (ay * by) (az * bz)
  negate (Vec3 ax ay az) = Vec3 (negate ax) (negate ay) (negate az)
  abs (Vec3 ax ay az) = Vec3 (abs ax) (abs ay) (abs az)
  signum (Vec3 ax ay az) = Vec3 (signum ax) (signum ay) (signum az)
  fromInteger n = Vec3 (fromInteger n) (fromInteger n) (fromInteger n)

instance Fractional a => Fractional (Vec3 a) where
  Vec3 ax ay az / Vec3 bx by bz = Vec3 (ax / bx) (ay / by) (az / bz)
  recip (Vec3 ax ay az) = Vec3 (recip ax) (recip ay) (recip az)
  fromRational x = Vec3 (fromRational x) (fromRational x) (fromRational x)

instance Num a => Num (Vec4 a) where
  Vec4 ax ay az aw + Vec4 bx by bz bw =
    Vec4 (ax + bx) (ay + by) (az + bz) (aw + bw)
  Vec4 ax ay az aw - Vec4 bx by bz bw =
    Vec4 (ax - bx) (ay - by) (az - bz) (aw - bw)
  Vec4 ax ay az aw * Vec4 bx by bz bw =
    Vec4 (ax * bx) (ay * by) (az * bz) (aw * bw)
  negate (Vec4 ax ay az aw) =
    Vec4 (negate ax) (negate ay) (negate az) (negate aw)
  abs (Vec4 ax ay az aw) = Vec4 (abs ax) (abs ay) (abs az) (abs aw)
  signum (Vec4 ax ay az aw) =
    Vec4 (signum ax) (signum ay) (signum az) (signum aw)
  fromInteger n =
    Vec4 (fromInteger n) (fromInteger n) (fromInteger n) (fromInteger n)

instance Fractional a => Fractional (Vec4 a) where
  Vec4 ax ay az aw / Vec4 bx by bz bw =
    Vec4 (ax / bx) (ay / by) (az / bz) (aw / bw)
  recip (Vec4 ax ay az aw) = Vec4 (recip ax) (recip ay) (recip az) (recip aw)
  fromRational x =
    Vec4 (fromRational x) (fromRational x) (fromRational x) (fromRational x)

--------------------------------------------------------------------------------
-- Constraints
--------------------------------------------------------------------------------
data Constraint
  = Equals ScalarType RawExpr RawExpr
  | LessOrEqual RawExpr RawExpr
  | Minimize RawExpr
  | All [Constraint]
  deriving (Eq, Show)

instance Semigroup Constraint where
  lhs <> rhs = All (flattenConstraint lhs ++ flattenConstraint rhs)

instance Monoid Constraint where
  mempty = All []

class ConstrainEq a where
  constrainEqual :: a -> a -> Constraint

class ConstrainOrd a where
  constrainLessOrEqual :: a -> a -> Constraint

infix 4 @==@
infix 4 @<=@
infix 4 @>=@
(@==@) :: ConstrainEq a => a -> a -> Constraint
(@==@) = constrainEqual

-- The solver lowers inequalities to a non-strict hinge penalty.
(@<=@) :: ConstrainOrd a => a -> a -> Constraint
(@<=@) = constrainLessOrEqual

(@>=@) :: ConstrainOrd a => a -> a -> Constraint
lhs @>=@ rhs = rhs @<=@ lhs

instance ConstrainEq (Expr ty) where
  constrainEqual (Expr ty lhs) (Expr _ rhs) = Equals ty lhs rhs

instance ConstrainOrd (Expr ty) where
  constrainLessOrEqual (Expr _ lhs) (Expr _ rhs) = LessOrEqual lhs rhs

instance ConstrainEq a => ConstrainEq (Vec2 a) where
  constrainEqual lhs rhs =
    case (lhs, rhs) of
      (Vec2 ax ay, Vec2 bx by) -> All [ax @==@ bx, ay @==@ by]

instance ConstrainEq a => ConstrainEq (Vec3 a) where
  constrainEqual lhs rhs =
    case (lhs, rhs) of
      (Vec3 ax ay az, Vec3 bx by bz) -> All [ax @==@ bx, ay @==@ by, az @==@ bz]

instance ConstrainEq a => ConstrainEq (Vec4 a) where
  constrainEqual lhs rhs =
    case (lhs, rhs) of
      (Vec4 ax ay az aw, Vec4 bx by bz bw) ->
        All [ax @==@ bx, ay @==@ by, az @==@ bz, aw @==@ bw]

flattenConstraint :: Constraint -> [Constraint]
flattenConstraint constraint =
  case constraint of
    All constraints -> concatMap flattenConstraint constraints
    _               -> [constraint]

minimize :: Expr ty -> Constraint
minimize (Expr _ objective) = Minimize objective

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
-- Seeded initial value generation
--------------------------------------------------------------------------------
newtype RandomSeed =
  RandomSeed Int
  deriving (Eq, Ord, Show)

data RandomSample = RandomSample
  { randomSampleIndex :: Int
  , randomSampleUnit  :: Double
  } deriving (Eq, Show)

defaultRandomSeed :: RandomSeed
defaultRandomSeed = RandomSeed 0

randomSamplesFromSeed :: RandomSeed -> [RandomSample]
randomSamplesFromSeed seed =
  zipWith RandomSample [0 ..] (randomUnitsFromSeed seed)

randomUnitsFromSeed :: RandomSeed -> [Double]
randomUnitsFromSeed (RandomSeed seed) = randomRs (0.0, 1.0) (mkStdGen seed)

--------------------------------------------------------------------------------
-- Named constraint solving
--------------------------------------------------------------------------------
data SolveConfig = SolveConfig
  { initialSeed :: RandomSeed
  , initialValueFor :: RandomSample -> String -> ScalarType -> InitialBounds -> Double
  , ensureWeight :: Rational
  , encourageWeight :: Rational
  , rangeWeight :: Rational
  }

defaultSolveConfig :: SolveConfig
defaultSolveConfig =
  SolveConfig
    { initialSeed = defaultRandomSeed
    , initialValueFor = defaultInitialValue
    , ensureWeight = 100
    , encourageWeight = 1
    , rangeWeight = 100
    }

defaultInitialValue ::
     RandomSample -> String -> ScalarType -> InitialBounds -> Double
defaultInitialValue sample _name _ty bounds =
  chooseInitialValue bounds (randomSampleUnit sample)

chooseInitialValue :: InitialBounds -> Double -> Double
chooseInitialValue bounds t =
  case (initialLower bounds, initialUpper bounds) of
    (Just lo, Just hi)
      | lo < hi -> lo + interior t * (hi - lo)
      | otherwise -> lo
    (Just lo, Nothing) -> lo + 1 + 999 * t
    (Nothing, Just hi) -> hi - 1 - 999 * t
    (Nothing, Nothing) -> (t - 0.5) * 2000

interior :: Double -> Double
interior t = 0.05 + 0.9 * t

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
solve config = solveWithInitialVars config []

solveWithInitialVars ::
     SolveConfig -> [InitialVar] -> [Constraint] -> IO Solution
solveWithInitialVars config initialVars constraints = do
  let named = compileConstraintsWithInitialVars config initialVars constraints
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
compileConstraints config = compileConstraintsWithInitialVars config []

compileConstraintsWithInitialVars ::
     SolveConfig -> [InitialVar] -> [Constraint] -> NamedCSP
compileConstraintsWithInitialVars config initialVars constraints =
  NamedCSP {namedVars = vars, namedCSP = csp}
  where
    flatConstraints = concatMap flattenConstraint constraints
    varTypes =
      mergeVarTypeMaps
        (collectInitialVarTypes initialVars)
        (collectConstraintVarTypes flatConstraints)
    inferredBounds =
      Map.unionWith
        mergeInitialBounds
        (collectInitialVarBounds initialVars)
        (inferInitialBounds flatConstraints)
    variableInputs =
      zip (randomSamplesFromSeed (initialSeed config)) (Map.toAscList varTypes)
    build = do
      pairs <-
        traverse
          (\(sample, (name, ty)) -> do
             let bounds =
                   typeInitialBounds ty
                     `mergeInitialBounds` Map.findWithDefault
                                            unboundedInitialBounds
                                            name
                                            inferredBounds
                 initial = initialValueFor config sample name ty bounds
             internal <- newInternalVar initial
             pure (name, ty, internal))
          variableInputs
      let vars' =
            Map.fromList [(name, internal) | (name, _ty, internal) <- pairs]
      traverse_
        (\(_name, ty, internal) ->
           case typeRange ty of
             Nothing    -> pure ()
             Just range -> addRangeTerms (rangeWeight config) internal range)
        pairs
      traverse_ (lowerConstraint config vars') flatConstraints
      pure vars'
    (vars, csp) = compileReturning build

--------------------------------------------------------------------------------
-- Symbol collection and inferred initial ranges
--------------------------------------------------------------------------------
collectInitialVarTypes :: [InitialVar] -> Map String ScalarType
collectInitialVarTypes = foldMap collectOne
  where
    collectOne initial =
      Map.singleton (initialVarName initial) (initialVarType initial)

collectInitialVarBounds :: [InitialVar] -> Map String InitialBounds
collectInitialVarBounds = foldl' addOne Map.empty
  where
    addOne bounds initial =
      Map.alter
        (Just
           . mergeInitialBounds (initialVarBounds initial)
           . maybe unboundedInitialBounds id)
        (initialVarName initial)
        bounds

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
        LessOrEqual lhs rhs ->
          mergeVarTypeMaps
            (collectRawExprVarTypes lhs)
            (collectRawExprVarTypes rhs)
        Minimize objective -> collectRawExprVarTypes objective
        All constraints -> collectConstraintVarTypes constraints

inferInitialBounds :: [Constraint] -> Map String InitialBounds
inferInitialBounds = foldl' addConstraint Map.empty

addConstraint ::
     Map String InitialBounds -> Constraint -> Map String InitialBounds
addConstraint bounds constraint =
  case constraint of
    LessOrEqual (ELit lo) (EVar _ v) ->
      Map.alter
        (Just . addInitialLower lo . maybe unboundedInitialBounds id)
        (varName v)
        bounds
    LessOrEqual (EVar _ v) (ELit hi) ->
      Map.alter
        (Just . addInitialUpper hi . maybe unboundedInitialBounds id)
        (varName v)
        bounds
    All constraints -> foldl' addConstraint bounds constraints
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
    LessOrEqual lhs rhs ->
      addTerm
        (ensureWeight config)
        (sq (clipNegative (lowerExpr vars lhs - lowerExpr vars rhs)))
    Minimize objective ->
      addTerm (encourageWeight config) (lowerExpr vars objective)
    All constraints -> traverse_ (lowerConstraint config vars) constraints

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
