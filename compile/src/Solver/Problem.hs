{-# LANGUAGE RankNTypes #-}

module Solver.Problem
  ( RandomSeed(..)
  , RandomSample(..)
  , randomSamplesFromSeed
  , randomUnitsFromSeed
  , SolveConfig(..)
  , defaultSolveConfig
  , SolverProblem(..)
  , CompiledProblem
  , compiledInspection
  , ProblemInspection(..)
  , Solution(..)
  , solve
  , solveProblem
  , compileProblem
  , inspectConstraints
  , evalExpr
  ) where

import           Data.Foldable           (traverse_)
import           Data.List               (foldl', isPrefixOf)
import           Data.Map.Strict         (Map)
import qualified Data.Map.Strict         as Map
import           Data.Maybe              (fromMaybe)
import qualified Numeric.Optimization.AD as Opt
import           Prelude
import           Solver.Backend
import           Solver.Constraint
import           Solver.Expr
import           System.Random           (mkStdGen, randomRs)

-- Seeded initial value generation
--------------------------------------------------------------------------------
newtype RandomSeed =
  RandomSeed Int
  deriving (Eq, Ord, Show)

data RandomSample = RandomSample
  { randomSampleIndex :: Int
  , randomSampleUnit  :: Double
  } deriving (Eq, Show)

randomSamplesFromSeed :: RandomSeed -> [RandomSample]
randomSamplesFromSeed seed =
  zipWith RandomSample [0 ..] (randomUnitsFromSeed seed)

randomUnitsFromSeed :: RandomSeed -> [Double]
randomUnitsFromSeed (RandomSeed seed) = randomRs (0.0, 1.0) (mkStdGen seed)

--------------------------------------------------------------------------------
-- Named constraint solving
--------------------------------------------------------------------------------
data SolveConfig = SolveConfig
  { initialSeed      :: RandomSeed
  , initialOverrides :: Map String Double
  , ensureWeight     :: Rational
  , encourageWeight  :: Rational
  }

defaultSolveConfig :: SolveConfig
defaultSolveConfig =
  SolveConfig
    { initialSeed = RandomSeed 0
    , initialOverrides = Map.empty
    , ensureWeight = 100
    , encourageWeight = 1
    }

sampleInitialWithinBounds :: InitialBounds -> Double -> Double
sampleInitialWithinBounds bounds t =
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

data SolverProblem = SolverProblem
  { solverConstraints      :: [Constraint]
  , solverInitialOverrides :: Map String Double
  } deriving (Eq, Show)

data CompiledProblem = CompiledProblem
  { compiledVars       :: Map String InternalVar
  , compiledCSP        :: CSP
  , compiledInspection :: ProblemInspection
  }

data ProblemInspection = ProblemInspection
  { inspectedVariableCount    :: Int
  , inspectedNativeBoundCount :: Int
  , inspectedEnergyTermCount  :: Int
  , inspectedFlattenedCount   :: Int
  , inspectedNativeBoundNames :: [String]
  } deriving (Eq, Show)

data Solution = Solution
  { solutionSuccess :: Bool
  , solutionSeed    :: RandomSeed
  , solutionEnergy  :: Double
  , solutionValues  :: Map String Double
  , solutionVector  :: [Double]
  } deriving (Eq, Show)

solve :: SolveConfig -> [Constraint] -> IO Solution
solve config constraints =
  solveProblem
    config
    SolverProblem
      {solverConstraints = constraints, solverInitialOverrides = Map.empty}

solveProblem :: SolveConfig -> SolverProblem -> IO Solution
solveProblem config problem = do
  let compiled = compileProblem config problem
      named =
        NamedCSP
          {namedVars = compiledVars compiled, namedCSP = compiledCSP compiled}
  result <- solveCSP (compiledCSP compiled)
  let vector = Opt.resultSolution result
      hardEnergy = cspHardEnergy (compiledCSP compiled) vector
      lookupValue (InternalVar i)
        | i < length vector = Just (vector !! i)
        | otherwise = Nothing
      values = Map.mapMaybe lookupValue (namedVars named)
  pure
    Solution
      { solutionSuccess = Opt.resultSuccess result
      , solutionSeed = initialSeed config
      , solutionEnergy = hardEnergy
      , solutionValues = values
      , solutionVector = vector
      }

compileProblem :: SolveConfig -> SolverProblem -> CompiledProblem
compileProblem config problem =
  CompiledProblem
    { compiledVars = vars
    , compiledCSP = csp
    , compiledInspection =
        ProblemInspection
          { inspectedVariableCount = Map.size vars
          , inspectedNativeBoundCount = length nativeBoundNames
          , inspectedEnergyTermCount = length energyConstraints
          , inspectedFlattenedCount = length flatConstraints
          , inspectedNativeBoundNames = nativeBoundNames
          }
    }
  where
    constraints = solverConstraints problem
    flatConstraints = flattenConstraints constraints
    varTypes = collectConstraintVarTypes flatConstraints
    inferredBounds = inferInitialBounds flatConstraints
    energyConstraints = filter (not . nativeBoundConstraint) flatConstraints
    nativeBoundNames =
      Map.keys
        (Map.filter
           finiteInitialBounds
           (Map.mapWithKey finalInitialBounds varTypes))
    initialSpecs =
      zipWith
        makeInitialSpec
        (randomSamplesFromSeed (initialSeed config))
        (Map.toAscList varTypes)
    rangeInitialValues =
      seedRangeInitialValues flatConstraints initialSpecs Map.empty
    configuredInitialValues =
      Map.union
        (solverInitialOverrides problem)
        (Map.union
           (initialOverrides config)
           (seedDerivedInitialValues flatConstraints rangeInitialValues))
    build = do
      pairs <-
        traverse
          (\spec -> do
             let name = initialSpecName spec
                 ty = initialSpecType spec
                 nativeBounds = nativeBoundsFor name (initialSpecBounds spec)
                 initial =
                   clampInitialValue
                     nativeBounds
                     (Map.findWithDefault
                        (sampleInitialWithinBounds
                           (initialSpecBounds spec)
                           (randomSampleUnit (initialSpecSample spec)))
                        name
                        configuredInitialValues)
             internal <- newInternalVar initial nativeBounds
             pure (name, ty, internal))
          initialSpecs
      let vars' =
            Map.fromList [(name, internal) | (name, _ty, internal) <- pairs]
      traverse_ (lowerConstraint config vars') energyConstraints
      pure vars'
    (vars, csp) = compileReturning build
    makeInitialSpec sample (name, ty) =
      InitialSpec
        { initialSpecSample = sample
        , initialSpecName = name
        , initialSpecType = ty
        , initialSpecBounds = finalInitialBounds name ty
        }
    finalInitialBounds name ty =
      typeInitialBounds ty
        `mergeInitialBounds` Map.findWithDefault
                               unboundedInitialBounds
                               name
                               inferredBounds

data InitialSpec = InitialSpec
  { initialSpecSample :: RandomSample
  , initialSpecName   :: String
  , initialSpecType   :: ScalarType
  , initialSpecBounds :: InitialBounds
  } deriving (Eq, Show)

finiteInitialBounds :: InitialBounds -> Bool
finiteInitialBounds bounds =
  case (initialLower bounds, initialUpper bounds) of
    (Nothing, Nothing) -> False
    _                  -> True

inspectConstraints :: SolveConfig -> [Constraint] -> ProblemInspection
inspectConstraints config constraints =
  compiledInspection
    (compileProblem
       config
       SolverProblem
         {solverConstraints = constraints, solverInitialOverrides = Map.empty})

nativeBoundsFor :: String -> InitialBounds -> NativeBounds
nativeBoundsFor name bounds
  | lower <= upper = (lower, upper)
  | otherwise =
    error
      ("inconsistent native bounds for solver variable "
         ++ show name
         ++ ": lower "
         ++ show lower
         ++ " is greater than upper "
         ++ show upper)
  where
    lower = fromMaybe negativeInfinity (initialLower bounds)
    upper = fromMaybe positiveInfinity (initialUpper bounds)

positiveInfinity :: Double
positiveInfinity = 1 / 0

negativeInfinity :: Double
negativeInfinity = -positiveInfinity

clampInitialValue :: NativeBounds -> Double -> Double
clampInitialValue (lower, upper) = min upper . max lower

nativeBoundConstraint :: Constraint -> Bool
nativeBoundConstraint constraint =
  case constraint of
    LessOrEqual (ELit _) (EVar _ _) -> True
    LessOrEqual (EVar _ _) (ELit _) -> True
    _                               -> False

seedRangeInitialValues ::
     [Constraint] -> [InitialSpec] -> Map String Double -> Map String Double
seedRangeInitialValues constraints specs values =
  foldl' seedRangeInitialValue values specs
  where
    ranges = dynamicInitialBounds constraints values
    seedRangeInitialValue seeded spec =
      case Map.lookup (initialSpecName spec) ranges of
        Nothing -> seeded
        Just rangeBounds ->
          let bounds = initialSpecBounds spec `mergeInitialBounds` rangeBounds
              nativeBounds = nativeBoundsFor (initialSpecName spec) bounds
              sampled =
                sampleInitialWithinBounds
                  bounds
                  (randomSampleUnit (initialSpecSample spec))
           in Map.insert
                (initialSpecName spec)
                (clampInitialValue nativeBounds sampled)
                seeded

dynamicInitialBounds ::
     [Constraint] -> Map String Double -> Map String InitialBounds
dynamicInitialBounds constraints values =
  foldl' (addDynamicInitialBound values) Map.empty constraints

addDynamicInitialBound ::
     Map String Double
  -> Map String InitialBounds
  -> Constraint
  -> Map String InitialBounds
addDynamicInitialBound values bounds constraint =
  case constraint of
    LessOrEqual lhs rhs ->
      addDynamicUpper values lhs rhs (addDynamicLower values lhs rhs bounds)
    Soft _ -> bounds
    All constraints -> foldl' (addDynamicInitialBound values) bounds constraints
    _ -> bounds

addDynamicLower ::
     Map String Double
  -> RawExpr
  -> RawExpr
  -> Map String InitialBounds
  -> Map String InitialBounds
addDynamicLower values lowerBoundExpr target =
  addDynamicBound values addInitialLower target lowerBoundExpr

addDynamicUpper ::
     Map String Double
  -> RawExpr
  -> RawExpr
  -> Map String InitialBounds
  -> Map String InitialBounds
addDynamicUpper values = addDynamicBound values addInitialUpper

addDynamicBound ::
     Map String Double
  -> (Double -> InitialBounds -> InitialBounds)
  -> RawExpr
  -> RawExpr
  -> Map String InitialBounds
  -> Map String InitialBounds
addDynamicBound values addBound target expr bounds =
  case target of
    EVar _ variable
      | not (rawExprMentions name expr) ->
        case evalInitialRawExpr values expr of
          Just value
            | finiteInitialValue value ->
              Map.alter
                (Just . addBound value . fromMaybe unboundedInitialBounds)
                name
                bounds
          _ -> bounds
      where
        name = varName variable
    _ -> bounds

seedDerivedInitialValues ::
     [Constraint] -> Map String Double -> Map String Double
seedDerivedInitialValues constraints values =
  foldl' seedDerivedInitialValue values constraints

seedDerivedInitialValue :: Map String Double -> Constraint -> Map String Double
seedDerivedInitialValue values constraint =
  case constraint of
    Equals _ lhs rhs -> seedEqualityInitialValue values lhs rhs
    _                -> values

seedEqualityInitialValue ::
     Map String Double -> RawExpr -> RawExpr -> Map String Double
seedEqualityInitialValue values lhs rhs =
  seedDerivedValueFromExpr (seedDerivedValueFromExpr values lhs rhs) rhs lhs

seedDerivedValueFromExpr ::
     Map String Double -> RawExpr -> RawExpr -> Map String Double
seedDerivedValueFromExpr values target expr =
  case target of
    EVar _ variable
      | derivedValueName name
      , independentInitialExpr expr
      , not (rawExprMentions name expr) ->
        case evalInitialRawExpr values expr of
          Just value
            | finiteInitialValue value -> Map.insert name value values
          _ -> values
      where
        name = varName variable
    _ -> values

derivedValueName :: String -> Bool
derivedValueName = not . independentValueName

independentValueName :: String -> Bool
independentValueName = isPrefixOf "global."

independentInitialExpr :: RawExpr -> Bool
independentInitialExpr expr =
  all independentValueName (Map.keys (collectRawExprVarTypes expr))

rawExprMentions :: String -> RawExpr -> Bool
rawExprMentions name expr = Map.member name (collectRawExprVarTypes expr)

finiteInitialValue :: Double -> Bool
finiteInitialValue value = not (isNaN value) && not (isInfinite value)

evalInitialRawExpr :: Map String Double -> RawExpr -> Maybe Double
evalInitialRawExpr values expr =
  case expr of
    EVar _ variable -> Map.lookup (varName variable) values
    ELit value -> Just value
    EAdd lhs rhs ->
      (+) <$> evalInitialRawExpr values lhs <*> evalInitialRawExpr values rhs
    ESub lhs rhs ->
      (-) <$> evalInitialRawExpr values lhs <*> evalInitialRawExpr values rhs
    EMul lhs rhs ->
      (*) <$> evalInitialRawExpr values lhs <*> evalInitialRawExpr values rhs
    EDiv lhs rhs ->
      (/) <$> evalInitialRawExpr values lhs <*> evalInitialRawExpr values rhs
    ENeg inner -> negate <$> evalInitialRawExpr values inner
    EAbs inner -> abs <$> evalInitialRawExpr values inner
    ESignum inner -> signum <$> evalInitialRawExpr values inner
    EPow base to ->
      (**) <$> evalInitialRawExpr values base <*> evalInitialRawExpr values to
    EMin lhs rhs ->
      min <$> evalInitialRawExpr values lhs <*> evalInitialRawExpr values rhs
    EMax lhs rhs ->
      max <$> evalInitialRawExpr values lhs <*> evalInitialRawExpr values rhs

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
    EMin lhs rhs ->
      mergeVarTypeMaps (collectRawExprVarTypes lhs) (collectRawExprVarTypes rhs)
    EMax lhs rhs ->
      mergeVarTypeMaps (collectRawExprVarTypes lhs) (collectRawExprVarTypes rhs)

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
        Soft inner -> collectConstraintVarTypes [inner]
        All constraints -> collectConstraintVarTypes constraints

inferInitialBounds :: [Constraint] -> Map String InitialBounds
inferInitialBounds constraints =
  foldl' (addAffineConstraint directBounds) directBounds constraints
  where
    directBounds = foldl' addDirectConstraint Map.empty constraints

addDirectConstraint ::
     Map String InitialBounds -> Constraint -> Map String InitialBounds
addDirectConstraint bounds constraint =
  case constraint of
    LessOrEqual (ELit lo) (EVar _ v) ->
      Map.alter
        (Just . addInitialLower lo . fromMaybe unboundedInitialBounds)
        (varName v)
        bounds
    LessOrEqual (EVar _ v) (ELit hi) ->
      Map.alter
        (Just . addInitialUpper hi . fromMaybe unboundedInitialBounds)
        (varName v)
        bounds
    Soft _ -> bounds
    All constraints -> foldl' addDirectConstraint bounds constraints
    _ -> bounds

addAffineConstraint ::
     Map String InitialBounds
  -> Map String InitialBounds
  -> Constraint
  -> Map String InitialBounds
addAffineConstraint known bounds constraint =
  case constraint of
    LessOrEqual lhs rhs -> addLinearUpperBounds known (rawSub lhs rhs) bounds
    Soft _              -> bounds
    All constraints     -> foldl' (addAffineConstraint known) bounds constraints
    _                   -> bounds

rawSub :: RawExpr -> RawExpr -> RawExpr
rawSub = ESub

addLinearUpperBounds ::
     Map String InitialBounds
  -> RawExpr
  -> Map String InitialBounds
  -> Map String InitialBounds
addLinearUpperBounds known expr bounds =
  case linearRawExpr expr of
    Nothing -> bounds
    Just (coefficients, constant) ->
      foldl'
        (addLinearBound known coefficients constant)
        bounds
        (Map.toAscList coefficients)

addLinearBound ::
     Map String InitialBounds
  -> Map String Double
  -> Double
  -> Map String InitialBounds
  -> (String, Double)
  -> Map String InitialBounds
addLinearBound known coefficients constant bounds (target, coeff)
  | abs coeff <= equalityEpsilon = bounds
  | otherwise =
    case boundFromOtherTerms known target coeff coefficients constant of
      Nothing -> bounds
      Just value
        | coeff > 0 ->
          Map.alter
            (Just . addInitialUpper value . fromMaybe unboundedInitialBounds)
            target
            bounds
        | otherwise ->
          Map.alter
            (Just . addInitialLower value . fromMaybe unboundedInitialBounds)
            target
            bounds

boundFromOtherTerms ::
     Map String InitialBounds
  -> String
  -> Double
  -> Map String Double
  -> Double
  -> Maybe Double
boundFromOtherTerms known target coeff coefficients constant = do
  otherValue <- minOtherTerms known target coefficients
  let bound = (-constant - otherValue) / coeff
  pure bound

minOtherTerms ::
     Map String InitialBounds -> String -> Map String Double -> Maybe Double
minOtherTerms known target coefficients =
  sum
    <$> traverse
          termMinimum
          [ (name, coeff)
          | (name, coeff) <- Map.toAscList coefficients
          , name /= target
          ]
  where
    termMinimum (name, coeff)
      | coeff >= 0 = do
        bounds <- Map.lookup name known
        lower <- initialLower bounds
        pure (coeff * lower)
      | otherwise = do
        bounds <- Map.lookup name known
        upper <- initialUpper bounds
        pure (coeff * upper)

linearRawExpr :: RawExpr -> Maybe (Map String Double, Double)
linearRawExpr expr =
  case expr of
    EVar _ variable -> Just (Map.singleton (varName variable) 1, 0)
    ELit value -> Just (Map.empty, value)
    EAdd lhs rhs -> addLinear lhs rhs
    ESub lhs rhs -> subtractLinear lhs rhs
    ENeg inner -> scaleLinear (-1) <$> linearRawExpr inner
    EMul (ELit scalar) rhs -> scaleLinear scalar <$> linearRawExpr rhs
    EMul lhs (ELit scalar) -> scaleLinear scalar <$> linearRawExpr lhs
    EDiv lhs (ELit scalar)
      | abs scalar > equalityEpsilon ->
        scaleLinear (1 / scalar) <$> linearRawExpr lhs
    _ -> Nothing

addLinear :: RawExpr -> RawExpr -> Maybe (Map String Double, Double)
addLinear lhs rhs = do
  (lhsCoefficients, lhsConstant) <- linearRawExpr lhs
  (rhsCoefficients, rhsConstant) <- linearRawExpr rhs
  pure
    ( Map.unionWith (+) lhsCoefficients rhsCoefficients
    , lhsConstant + rhsConstant)

subtractLinear :: RawExpr -> RawExpr -> Maybe (Map String Double, Double)
subtractLinear lhs rhs = do
  lhsLinear <- linearRawExpr lhs
  rhsLinear <- linearRawExpr rhs
  pure (addLinearValues lhsLinear (scaleLinear (-1) rhsLinear))

addLinearValues ::
     (Map String Double, Double)
  -> (Map String Double, Double)
  -> (Map String Double, Double)
addLinearValues (lhsCoefficients, lhsConstant) (rhsCoefficients, rhsConstant) =
  (Map.unionWith (+) lhsCoefficients rhsCoefficients, lhsConstant + rhsConstant)

scaleLinear ::
     Double -> (Map String Double, Double) -> (Map String Double, Double)
scaleLinear scalar (coefficients, constant) =
  (Map.map (* scalar) coefficients, scalar * constant)

--------------------------------------------------------------------------------
-- Lowering symbolic expressions to AD-friendly energy expressions
--------------------------------------------------------------------------------
lowerConstraint ::
     SolveConfig -> Map String InternalVar -> Constraint -> BuildCSP ()
lowerConstraint = lowerConstraintWith HardTerm

lowerConstraintWith ::
     TermKind
  -> SolveConfig
  -> Map String InternalVar
  -> Constraint
  -> BuildCSP ()
lowerConstraintWith kind config vars constraint =
  case constraint of
    Equals ty lhs rhs ->
      case typeCircularPeriod ty of
        Just period
          | period > 0 ->
            addWeightedTerm
              kind
              config
              (circularEnergy period (lowerExpr vars lhs - lowerExpr vars rhs))
        _ ->
          addWeightedTerm
            kind
            config
            (sq (lowerExpr vars lhs - lowerExpr vars rhs))
    LessOrEqual lhs rhs ->
      addWeightedTerm
        kind
        config
        (sq (clipNegative (lowerExpr vars lhs - lowerExpr vars rhs)))
    Minimize objective ->
      addSoftTerm (encourageWeight config) (lowerExpr vars objective)
    Soft inner -> lowerConstraintWith SoftTerm config vars inner
    All constraints ->
      traverse_ (lowerConstraintWith kind config vars) constraints

addWeightedTerm ::
     TermKind
  -> SolveConfig
  -> (forall a. Floating a => EnergyExpr a)
  -> BuildCSP ()
addWeightedTerm kind config =
  case kind of
    HardTerm -> addHardTerm (ensureWeight config)
    SoftTerm -> addSoftTerm (encourageWeight config)

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
    EMin lhs rhs -> minE (lowerExpr vars lhs) (lowerExpr vars rhs)
    EMax lhs rhs -> maxE (lowerExpr vars lhs) (lowerExpr vars rhs)

--------------------------------------------------------------------------------
-- Evaluating symbolic expressions against a solution
--------------------------------------------------------------------------------
evalExpr :: Solution -> Expr ty -> Maybe Double
evalExpr solution (Expr ty expr) =
  normalizeByType ty <$> evalRawExpr solution expr

normalizeByType :: ScalarType -> Double -> Double
normalizeByType ty value =
  case typeCircularPeriod ty of
    Just period
      | period > 0 -> positiveModulo period value
    _ -> value

positiveModulo :: Double -> Double -> Double
positiveModulo period value =
  value - period * fromInteger (floor (value / period) :: Integer)

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
    EMin lhs rhs ->
      min <$> evalRawExpr solution lhs <*> evalRawExpr solution rhs
    EMax lhs rhs ->
      max <$> evalRawExpr solution lhs <*> evalRawExpr solution rhs
