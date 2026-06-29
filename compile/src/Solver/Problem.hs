{-# LANGUAGE RankNTypes #-}

-- | High-level solver problem compilation and solving. This module connects
-- expression/constraint/choice definitions to the optimizer backend; the public
-- 'Solver' facade re-exports the stable problem and solution API.
module Solver.Problem
  ( -- * Seeded randomness
    -- | Deterministic initial sampling used by tests, benchmarks, and
    -- visualization regeneration.
    RandomSeed(..)
  , RandomSample(..)
  , randomSamplesFromSeed
  , randomUnitsFromSeed
  , -- * Solve configuration
    -- | User-facing solver knobs plus backend optimizer tolerances. View
    -- solving supplies a tuned config through 'LinearTrace.View.Solve'.
    SolveConfig(..)
  , defaultSolveConfig
  , withInitialSeed
  , withInitialOverrides
  , withConstraintWeights
  , withMaxCategoricalBranches
  , withOptimizerTolerances
  , withMaxOptimizerIterations
  , withOptimizerMaxCorrections
  , -- * Problem model
    -- | Numeric constraints, categorical choices, and optional initial
    -- overrides before backend lowering.
    SolverProblem(..)
  , solverProblem
  , solverProblemWithChoices
  , withChoiceConstraints
  , withProblemInitialOverrides
  , -- * Compilation and inspection
    -- | Compiled backend problem plus diagnostics consumed by tests,
    -- benchmarks, and solution summaries.
    CompiledProblem
  , compiledInspection
  , ProblemInspection(..)
  , -- * Solving and evaluation
    -- | Solve entrypoints and solution evaluation used by the view layer,
    -- compile pipeline, tests, and benchmarks.
    Solution(..)
  , solve
  , solveProblem
  , solveCompiledProblem
  , compileProblem
  , inspectConstraints
  , evalExpr
  , evalChoice
  ) where

import           Data.Foldable           (traverse_)
import           Data.List               (isPrefixOf)
import           Data.Map.Strict         (Map)
import qualified Data.Map.Strict         as Map
import           Data.Maybe              (fromMaybe)
import qualified Numeric.Optimization.AD as Opt
import           Prelude
import           Solver.Backend
import           Solver.Choice
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
  { initialSeed       :: RandomSeed
  , initialOverrides  :: Map String Double
  , ensureWeight      :: Rational
  , encourageWeight   :: Rational
  , maxChoiceBranches :: Int
  , optimizerConfig   :: OptimizerConfig
  }

defaultSolveConfig :: SolveConfig
defaultSolveConfig =
  SolveConfig
    { initialSeed = RandomSeed 0
    , initialOverrides = Map.empty
    , ensureWeight = 100
    , encourageWeight = 1
    , maxChoiceBranches = 256
    , optimizerConfig = defaultOptimizerConfig
    }

withInitialSeed :: RandomSeed -> SolveConfig -> SolveConfig
withInitialSeed seed config = config {initialSeed = seed}

withInitialOverrides :: Map String Double -> SolveConfig -> SolveConfig
withInitialOverrides overrides config = config {initialOverrides = overrides}

withConstraintWeights :: Rational -> Rational -> SolveConfig -> SolveConfig
withConstraintWeights hardWeight softWeight config =
  config {ensureWeight = hardWeight, encourageWeight = softWeight}

withMaxCategoricalBranches :: Int -> SolveConfig -> SolveConfig
withMaxCategoricalBranches branchLimit config =
  config {maxChoiceBranches = max 1 branchLimit}

withOptimizerTolerances ::
     Maybe Double -> Maybe Double -> SolveConfig -> SolveConfig
withOptimizerTolerances ftol gtol config =
  config
    { optimizerConfig =
        (optimizerConfig config)
          {optimizerFTolerance = ftol, optimizerGTolerance = gtol}
    }

withMaxOptimizerIterations :: Int -> SolveConfig -> SolveConfig
withMaxOptimizerIterations iterations config =
  config
    { optimizerConfig =
        (optimizerConfig config) {optimizerMaxIterations = Just iterations}
    }

withOptimizerMaxCorrections :: Int -> SolveConfig -> SolveConfig
withOptimizerMaxCorrections corrections config =
  config
    { optimizerConfig =
        (optimizerConfig config) {optimizerMaxCorrections = Just corrections}
    }

sampleInitialWithinBounds :: DomainBounds -> Double -> Double
sampleInitialWithinBounds bounds t =
  case (domainLowerBound bounds, domainUpperBound bounds) of
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
  { solverConstraints       :: [Constraint]
  , solverChoiceConstraints :: [ChoiceConstraint]
  , solverInitialOverrides  :: Map String Double
  } deriving (Eq, Show)

solverProblem :: [Constraint] -> SolverProblem
solverProblem constraints =
  SolverProblem
    { solverConstraints = constraints
    , solverChoiceConstraints = []
    , solverInitialOverrides = Map.empty
    }

solverProblemWithChoices :: [Constraint] -> [ChoiceConstraint] -> SolverProblem
solverProblemWithChoices constraints choiceConstraints =
  SolverProblem
    { solverConstraints = constraints
    , solverChoiceConstraints = choiceConstraints
    , solverInitialOverrides = Map.empty
    }

withChoiceConstraints :: [ChoiceConstraint] -> SolverProblem -> SolverProblem
withChoiceConstraints choiceConstraints problem =
  problem
    { solverChoiceConstraints =
        solverChoiceConstraints problem ++ choiceConstraints
    }

withProblemInitialOverrides ::
     Map String Double -> SolverProblem -> SolverProblem
withProblemInitialOverrides overrides problem =
  problem {solverInitialOverrides = overrides}

data CompiledProblem = CompiledProblem
  { compiledSeed       :: RandomSeed
  , compiledVars       :: Map String InternalVar
  , compiledCSP        :: CSP
  , compiledChoices    :: Map String String
  , compiledOptimizer  :: OptimizerConfig
  , compiledInspection :: ProblemInspection
  }

data ProblemInspection = ProblemInspection
  { inspectedVariableCount     :: Int
  , inspectedNativeBoundCount  :: Int
  , inspectedEnergyTermCount   :: Int
  , inspectedFlattenedCount    :: Int
  , inspectedRawCount          :: Int
  , inspectedCanonicalCount    :: Int
  , inspectedEliminatedCount   :: Int
  , inspectedChoiceCount       :: Int
  , inspectedChoiceBranchCount :: Int
  , inspectedNativeBoundNames  :: [String]
  } deriving (Eq, Show)

data Solution = Solution
  { solutionSuccess             :: Bool
  , solutionSeed                :: RandomSeed
  , solutionEnergy              :: Double
  , solutionValues              :: Map String Double
  , solutionChoices             :: Map String String
  , solutionInspection          :: ProblemInspection
  , solutionIterations          :: Int
  , solutionFunctionEvaluations :: Int
  , solutionGradientEvaluations :: Int
  , solutionVector              :: [Double]
  } deriving (Eq, Show)

solve :: SolveConfig -> [Constraint] -> IO Solution
solve config constraints = solveProblem config (solverProblem constraints)

solveProblem :: SolveConfig -> SolverProblem -> IO Solution
solveProblem config = solveCompiledProblem . compileProblem config

solveCompiledProblem :: CompiledProblem -> IO Solution
solveCompiledProblem compiled = do
  let choiceValues = compiledChoices compiled
  choiceValues `seq` pure ()
  let named =
        NamedCSP
          {namedVars = compiledVars compiled, namedCSP = compiledCSP compiled}
  result <- solveCSP (compiledOptimizer compiled) (compiledCSP compiled)
  let vector = Opt.resultSolution result
      stats = Opt.resultStatistics result
      hardEnergy = cspHardEnergy (compiledCSP compiled) vector
      lookupValue (InternalVar i)
        | i < length vector = Just (vector !! i)
        | otherwise = Nothing
      values = Map.mapMaybe lookupValue (namedVars named)
  pure
    Solution
      { solutionSuccess = Opt.resultSuccess result
      , solutionSeed = compiledSeed compiled
      , solutionEnergy = hardEnergy
      , solutionValues = values
      , solutionChoices = choiceValues
      , solutionInspection = compiledInspection compiled
      , solutionIterations = Opt.totalIters stats
      , solutionFunctionEvaluations = Opt.funcEvals stats
      , solutionGradientEvaluations = Opt.gradEvals stats
      , solutionVector = vector
      }

compileProblem :: SolveConfig -> SolverProblem -> CompiledProblem
compileProblem config problem =
  CompiledProblem
    { compiledSeed = initialSeed config
    , compiledVars = vars
    , compiledCSP = csp
    , compiledChoices = choiceValues
    , compiledOptimizer = optimizerConfig config
    , compiledInspection =
        choiceValues
          `seq` boundsValidation
          `seq` ProblemInspection
                  { inspectedVariableCount = Map.size vars
                  , inspectedNativeBoundCount = length nativeBoundNames
                  , inspectedEnergyTermCount = length energyConstraints
                  , inspectedFlattenedCount = length flatConstraints
                  , inspectedRawCount = length rawConstraints
                  , inspectedCanonicalCount = length flatConstraints
                  , inspectedEliminatedCount =
                      max 0 (length rawConstraints - length flatConstraints)
                  , inspectedChoiceCount = Map.size choiceValues
                  , inspectedChoiceBranchCount = choiceBranchCount
                  , inspectedNativeBoundNames = nativeBoundNames
                  }
    }
  where
    constraints = solverConstraints problem
    rawConstraints = concatMap flattenConstraint constraints
    flatConstraints = flattenConstraints constraints
    (choiceValues, choiceBranchCount) =
      solveChoiceConstraints config (solverChoiceConstraints problem)
    varTypes = collectConstraintVarTypes flatConstraints
    inferredBounds = inferDomainBounds flatConstraints
    finalBounds =
      Map.mapWithKey
        (\name ty -> validateDomainBounds name (finalDomainBounds name ty))
        varTypes
    energyConstraints =
      filter (not . loweredByNativeBounds finalBounds) flatConstraints
    boundsValidation =
      foldl'
        (\checked (name, bounds) ->
           checked `seq` validateDomainBounds name bounds `seq` ())
        ()
        (Map.toAscList finalBounds)
    nativeBoundNames = Map.keys (Map.filter finiteDomainBounds finalBounds)
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
        , initialSpecBounds =
            Map.findWithDefault unboundedDomainBounds name finalBounds
        }
    finalDomainBounds name ty =
      domainDefaultBounds ty
        `mergeDomainBounds` Map.findWithDefault
                              unboundedDomainBounds
                              name
                              inferredBounds

validateDomainBounds :: String -> DomainBounds -> DomainBounds
validateDomainBounds name bounds =
  case nativeBoundsFor name bounds of
    (lower, upper) -> lower `seq` upper `seq` bounds

solveChoiceConstraints ::
     SolveConfig -> [ChoiceConstraint] -> (Map String String, Int)
solveChoiceConstraints _ [] = (Map.empty, 0)
solveChoiceConstraints config constraints =
  if branchCount > maxChoiceBranches config
    then error
           ("categorical solver branch count "
              ++ show branchCount
              ++ " exceeds configured limit "
              ++ show (maxChoiceBranches config))
    else case validAssignments of
           [] ->
             error
               "categorical solver constraints have no satisfying assignment"
           valid -> (valid !! selectedIndex valid, branchCount)
  where
    domains = choiceDomains constraints
    choices = Map.toAscList domains
    branchCount = product (map (length . snd) choices)
    assignments = enumerateChoiceAssignments choices
    validAssignments =
      filter
        (\assignment -> all (choiceConstraintSatisfied assignment) constraints)
        assignments
    selectedIndex valid =
      min (length valid - 1) (floor (seedUnit * fromIntegral (length valid)))
    seedUnit =
      case randomUnitsFromSeed (initialSeed config) of
        value:_ -> value
        []      -> 0

choiceDomains :: [ChoiceConstraint] -> Map String [String]
choiceDomains = foldl' addConstraint Map.empty
  where
    addConstraint domains constraint =
      foldl' addSpec domains (choiceConstraintSpecs constraint)
    addSpec domains (name, categories)
      | null categories =
        error ("categorical choice " ++ show name ++ " has an empty domain")
      | otherwise =
        Map.alter (Just . mergeChoiceDomain name categories) name domains

mergeChoiceDomain :: String -> [String] -> Maybe [String] -> [String]
mergeChoiceDomain _ categories Nothing = categories
mergeChoiceDomain name categories (Just old)
  | old == categories = old
  | otherwise =
    error
      ("categorical choice "
         ++ show name
         ++ " was used with incompatible domains")

enumerateChoiceAssignments :: [(String, [String])] -> [Map String String]
enumerateChoiceAssignments choices =
  case choices of
    [] -> [Map.empty]
    (name, categories):rest ->
      [ Map.insert name categoryValue assignment
      | categoryValue <- categories
      , assignment <- enumerateChoiceAssignments rest
      ]

data InitialSpec = InitialSpec
  { initialSpecSample :: RandomSample
  , initialSpecName   :: String
  , initialSpecType   :: Domain
  , initialSpecBounds :: DomainBounds
  } deriving (Eq, Show)

finiteDomainBounds :: DomainBounds -> Bool
finiteDomainBounds bounds =
  case (domainLowerBound bounds, domainUpperBound bounds) of
    (Nothing, Nothing) -> False
    _                  -> True

inspectConstraints :: SolveConfig -> [Constraint] -> ProblemInspection
inspectConstraints config constraints =
  compiledInspection (compileProblem config (solverProblem constraints))

nativeBoundsFor :: String -> DomainBounds -> NativeBounds
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
    lower = fromMaybe negativeInfinity (domainLowerBound bounds)
    upper = fromMaybe positiveInfinity (domainUpperBound bounds)

positiveInfinity :: Double
positiveInfinity = 1 / 0

negativeInfinity :: Double
negativeInfinity = -positiveInfinity

clampInitialValue :: NativeBounds -> Double -> Double
clampInitialValue (lower, upper) = min upper . max lower

nativeBoundConstraint :: Constraint -> Bool
nativeBoundConstraint constraint =
  case constraint of
    LessOrEqual lhs rhs -> singleVariableNativeBound lhs rhs
    _                   -> False

singleVariableNativeBound :: RawExpr -> RawExpr -> Bool
singleVariableNativeBound lhs rhs =
  case linearRawExpr (rawSub lhs rhs) of
    Nothing -> False
    Just (coefficients, constant) ->
      case nonZeroLinearTerms coefficients of
        [(_, coeff)] ->
          abs coeff > equalityEpsilon
            && finiteInitialValue ((-constant) / coeff)
        _ -> False

nonZeroLinearTerms :: Map String Double -> [(String, Double)]
nonZeroLinearTerms =
  filter (\(_, coeff) -> abs coeff > equalityEpsilon) . Map.toAscList

loweredByNativeBounds :: Map String DomainBounds -> Constraint -> Bool
loweredByNativeBounds bounds constraint =
  nativeBoundConstraint constraint || impliedByNativeBounds bounds constraint

impliedByNativeBounds :: Map String DomainBounds -> Constraint -> Bool
impliedByNativeBounds bounds constraint =
  case constraint of
    LessOrEqual lhs rhs ->
      case linearRawExpr (rawSub lhs rhs) of
        Nothing -> False
        Just (coefficients, constant) ->
          case maximumLinearValue bounds coefficients constant of
            Nothing    -> False
            Just value -> value <= equalityEpsilon
    _ -> False

maximumLinearValue ::
     Map String DomainBounds -> Map String Double -> Double -> Maybe Double
maximumLinearValue bounds coefficients constant =
  foldl' addTermMax (Just constant) (nonZeroLinearTerms coefficients)
  where
    addTermMax acc (name, coeff) = do
      total <- acc
      variableBounds <- Map.lookup name bounds
      bound <-
        if coeff > 0
          then domainUpperBound variableBounds
          else domainLowerBound variableBounds
      pure (total + coeff * bound)

seedRangeInitialValues ::
     [Constraint] -> [InitialSpec] -> Map String Double -> Map String Double
seedRangeInitialValues constraints specs values =
  foldl' seedRangeInitialValue values specs
  where
    ranges = dynamicDomainBounds constraints values
    seedRangeInitialValue seeded spec =
      case Map.lookup (initialSpecName spec) ranges of
        Nothing -> seeded
        Just rangeBounds ->
          let bounds = initialSpecBounds spec `mergeDomainBounds` rangeBounds
              nativeBounds = nativeBoundsFor (initialSpecName spec) bounds
              sampled =
                sampleInitialWithinBounds
                  bounds
                  (randomSampleUnit (initialSpecSample spec))
           in Map.insert
                (initialSpecName spec)
                (clampInitialValue nativeBounds sampled)
                seeded

dynamicDomainBounds ::
     [Constraint] -> Map String Double -> Map String DomainBounds
dynamicDomainBounds constraints values =
  foldl' (addDynamicInitialBound values) Map.empty constraints

addDynamicInitialBound ::
     Map String Double
  -> Map String DomainBounds
  -> Constraint
  -> Map String DomainBounds
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
  -> Map String DomainBounds
  -> Map String DomainBounds
addDynamicLower values lowerBoundExpr target =
  addDynamicBound values addDomainLower target lowerBoundExpr

addDynamicUpper ::
     Map String Double
  -> RawExpr
  -> RawExpr
  -> Map String DomainBounds
  -> Map String DomainBounds
addDynamicUpper values = addDynamicBound values addDomainUpper

addDynamicBound ::
     Map String Double
  -> (Double -> DomainBounds -> DomainBounds)
  -> RawExpr
  -> RawExpr
  -> Map String DomainBounds
  -> Map String DomainBounds
addDynamicBound values addBound target expr bounds =
  case target of
    EVar _ variable
      | not (rawExprMentions name expr) ->
        case evalInitialRawExpr values expr of
          Just value
            | finiteInitialValue value ->
              Map.alter
                (Just . addBound value . fromMaybe unboundedDomainBounds)
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

collectRawExprVarTypes :: RawExpr -> Map String Domain
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

mergeVarTypeMaps :: Map String Domain -> Map String Domain -> Map String Domain
mergeVarTypeMaps = Map.unionWith mergeVarTypes

mergeVarTypes :: Domain -> Domain -> Domain
mergeVarTypes a b
  | a == b = a
  | otherwise =
    error
      ("solver variable used with incompatible symbolic types: "
         ++ show a
         ++ " and "
         ++ show b)

collectConstraintVarTypes :: [Constraint] -> Map String Domain
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

inferDomainBounds :: [Constraint] -> Map String DomainBounds
inferDomainBounds constraints =
  foldl' (addAffineConstraint directBounds) directBounds constraints
  where
    directBounds = foldl' addDirectConstraint Map.empty constraints

addDirectConstraint ::
     Map String DomainBounds -> Constraint -> Map String DomainBounds
addDirectConstraint bounds constraint =
  case constraint of
    LessOrEqual (ELit lo) (EVar _ v) ->
      Map.alter
        (Just . addDomainLower lo . fromMaybe unboundedDomainBounds)
        (varName v)
        bounds
    LessOrEqual (EVar _ v) (ELit hi) ->
      Map.alter
        (Just . addDomainUpper hi . fromMaybe unboundedDomainBounds)
        (varName v)
        bounds
    Soft _ -> bounds
    All constraints -> foldl' addDirectConstraint bounds constraints
    _ -> bounds

addAffineConstraint ::
     Map String DomainBounds
  -> Map String DomainBounds
  -> Constraint
  -> Map String DomainBounds
addAffineConstraint known bounds constraint =
  case constraint of
    LessOrEqual lhs rhs -> addLinearUpperBounds known (rawSub lhs rhs) bounds
    Soft _              -> bounds
    All constraints     -> foldl' (addAffineConstraint known) bounds constraints
    _                   -> bounds

rawSub :: RawExpr -> RawExpr -> RawExpr
rawSub = ESub

addLinearUpperBounds ::
     Map String DomainBounds
  -> RawExpr
  -> Map String DomainBounds
  -> Map String DomainBounds
addLinearUpperBounds known expr bounds =
  case linearRawExpr expr of
    Nothing -> bounds
    Just (coefficients, constant) ->
      foldl'
        (addLinearBound known coefficients constant)
        bounds
        (Map.toAscList coefficients)

addLinearBound ::
     Map String DomainBounds
  -> Map String Double
  -> Double
  -> Map String DomainBounds
  -> (String, Double)
  -> Map String DomainBounds
addLinearBound known coefficients constant bounds (target, coeff)
  | abs coeff <= equalityEpsilon = bounds
  | otherwise =
    case boundFromOtherTerms known target coeff coefficients constant of
      Nothing -> bounds
      Just value
        | coeff > 0 ->
          Map.alter
            (Just . addDomainUpper value . fromMaybe unboundedDomainBounds)
            target
            bounds
        | otherwise ->
          Map.alter
            (Just . addDomainLower value . fromMaybe unboundedDomainBounds)
            target
            bounds

boundFromOtherTerms ::
     Map String DomainBounds
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
     Map String DomainBounds -> String -> Map String Double -> Maybe Double
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
        lower <- domainLowerBound bounds
        pure (coeff * lower)
      | otherwise = do
        bounds <- Map.lookup name known
        upper <- domainUpperBound bounds
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
      case domainCircularPeriod ty of
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

evalChoice :: Solution -> Choice ty -> Maybe (Category ty)
evalChoice solution selected =
  category <$> Map.lookup (choiceName selected) (solutionChoices solution)

normalizeByType :: Domain -> Double -> Double
normalizeByType ty value =
  case domainCircularPeriod ty of
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
