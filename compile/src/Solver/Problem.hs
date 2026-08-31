-- | High-level solver problem compilation and solving. This module connects
-- expression/constraint/choice definitions to numeric backends; the public
-- 'Solver' facade re-exports the stable problem and solution API.
module Solver.Problem
  ( -- * Seeded randomness
    -- | Deterministic initial sampling used by tests, benchmarks, and
    -- visualization regeneration.
    RandomSeed(..)
  , -- * Solve configuration
    -- | User-facing seeds, initial values, and categorical conditioning limit.
    SolveConfig(..)
  , NumericBackend(..)
  , defaultSolveConfig
  , withInitialSeed
  , withInitialOverrides
  , withMaxCategoricalBranches
  , -- * Problem model
    -- | Numeric constraints, categorical choices, and optional initial
    -- overrides before backend lowering.
    SolverProblem(..)
  , solverProblem
  , solverProblemWithChoices
  , withChoiceConstraints
  , pinProblemChoices
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
  , BackendStatistics(..)
  , SamplingStatistics(..)
  , VolumeBudget(..)
  , defaultVolumeBudget
  , VolumeEstimate(..)
  , SamplingStrategy(..)
  , DecisionCoverage(..)
  , SamplingProvenance(..)
  , solve
  , solveProblem
  , solveCompiledProblem
  , compileProblem
  , inspectConstraints
  , evalExpr
  , evalChoice
  ) where

import           Data.List          (isPrefixOf)
import           Data.Map.Strict    (Map)
import qualified Data.Map.Strict    as Map
import           Data.Maybe         (fromMaybe)
import           Prelude
import           Solver.Affine
import           Solver.Categorical
import           Solver.Choice
import           Solver.Constraint
import           Solver.Expr
import           Solver.Random
import           Solver.Sample

-- Named constraint solving
--------------------------------------------------------------------------------
-- | Numeric backend selected after inspecting the hard constraints.
data NumericBackend =
  AffineSampler
  deriving (Eq, Show)

data SolveConfig = SolveConfig
  { initialSeed       :: RandomSeed
  , initialOverrides  :: Map String Double
  , maxChoiceBranches :: Int
  }

defaultSolveConfig :: SolveConfig
defaultSolveConfig =
  SolveConfig
    { initialSeed = RandomSeed 0
    , initialOverrides = Map.empty
    , maxChoiceBranches = 256
    }

withInitialSeed :: RandomSeed -> SolveConfig -> SolveConfig
withInitialSeed seed config = config {initialSeed = seed}

withInitialOverrides :: Map String Double -> SolveConfig -> SolveConfig
withInitialOverrides overrides config = config {initialOverrides = overrides}

withMaxCategoricalBranches :: Int -> SolveConfig -> SolveConfig
withMaxCategoricalBranches branchLimit config =
  config {maxChoiceBranches = max 1 branchLimit}

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

-- | Pin an already-resolved finite assignment without exposing internal
-- categorical or decision constructors. Domains are recovered from the
-- problem and checked before the pins are added.
pinProblemChoices ::
     Map String String -> SolverProblem -> Either String SolverProblem
pinProblemChoices assignment problem = do
  domains <- problemChoiceDomains problem
  pins <- traverse (pinOne domains) (Map.toAscList assignment)
  pure (withChoiceConstraints pins problem)
  where
    pinOne domains (name, token) =
      case Map.lookup name domains of
        Nothing -> Left ("cannot pin unknown finite choice " ++ show name)
        Just categories
          | token `elem` categories ->
            Right (ChoiceIs (ChoiceSpec name categories) token)
          | otherwise ->
            Left
              ("cannot pin token "
                 ++ show token
                 ++ " for finite choice "
                 ++ show name)

problemChoiceDomains :: SolverProblem -> Either String (Map String [String])
problemChoiceDomains problem = foldl addSpec (Right Map.empty) allSpecs
  where
    allSpecs =
      [ (decisionSpecName spec, map fst (decisionSpecAlternatives spec))
      | spec <- constraintDecisionSpecs (solverConstraints problem)
      ]
        ++ concatMap choiceConstraintSpecs (solverChoiceConstraints problem)
    addSpec result (name, categories) = do
      domains <- result
      case Map.lookup name domains of
        Nothing -> Right (Map.insert name categories domains)
        Just previous
          | previous == categories -> Right domains
          | otherwise ->
            Left ("finite choice has incompatible domains: " ++ show name)

withProblemInitialOverrides ::
     Map String Double -> SolverProblem -> SolverProblem
withProblemInitialOverrides overrides problem =
  problem {solverInitialOverrides = overrides}

data CompiledProblem = CompiledProblem
  { compiledSeed            :: RandomSeed
  , compiledNumericProblem  :: CompiledNumericProblem
  , compiledInitialValues   :: Map String Double
  , compiledHardConstraints :: [Constraint]
  , compiledChoices         :: Map String String
  , compiledInspection      :: ProblemInspection
  }

newtype CompiledNumericProblem =
  SampleAffineProblem AffineProblem

data ProblemInspection = ProblemInspection
  { inspectedVariableCount                  :: Int
  , inspectedNativeBoundCount               :: Int
  , inspectedFlattenedCount                 :: Int
  , inspectedRawCount                       :: Int
  , inspectedCanonicalCount                 :: Int
  , inspectedEliminatedCount                :: Int
  , inspectedChoiceCount                    :: Int
  , inspectedChoiceBranchCount              :: Int
  , inspectedChoiceComponentCount           :: Int
  , inspectedLargestChoiceComponentBranches :: Int
  , inspectedNativeBoundNames               :: [String]
  , inspectedBackend                        :: NumericBackend
  , inspectedAffineEqualityCount            :: Int
  , inspectedAffineInequalityCount          :: Int
  } deriving (Eq, Show)

-- | Work performed while sampling the prepared affine region.
newtype BackendStatistics =
  AffineSamplingStatistics SamplingStatistics
  deriving (Eq, Show)

data Solution = Solution
  { solutionSuccess           :: Bool
  , solutionSeed              :: RandomSeed
  , solutionEnergy            :: Double
  , solutionValues            :: Map String Double
  , solutionChoices           :: Map String String
  , solutionInspection        :: ProblemInspection
  , solutionBackend           :: NumericBackend
  , solutionBackendStatistics :: BackendStatistics
  , solutionSampling          :: SamplingProvenance
  , solutionVector            :: [Double]
  } deriving (Eq, Show)

solve :: SolveConfig -> [Constraint] -> IO Solution
solve config constraints = solveProblem config (solverProblem constraints)

solveProblem :: SolveConfig -> SolverProblem -> IO Solution
solveProblem config = solveCompiledProblem . compileProblem config

solveCompiledProblem :: CompiledProblem -> IO Solution
solveCompiledProblem compiled = do
  let choiceValues = compiledChoices compiled
  choiceValues `seq` pure ()
  case compiledNumericProblem compiled of
    SampleAffineProblem affine ->
      solveAffineCompiled compiled affine choiceValues

solveAffineCompiled ::
     CompiledProblem -> AffineProblem -> Map String String -> IO Solution
solveAffineCompiled compiled affine choiceValues = do
  (values, statistics) <-
    case sampleAffineProblem
           (compiledSeed compiled)
           (compiledInitialValues compiled)
           affine of
      Left (FeasibilityFailure message) -> ioError (userError message)
      Right sampled                     -> pure sampled
  let variableNames = affineVariableNames affine
      vector =
        [ Map.findWithDefault
          (error ("missing sampled solver variable: " ++ name))
          name
          values
        | name <- variableNames
        ]
      hardEnergy =
        hardConstraintEnergy values (compiledHardConstraints compiled)
  pure
    Solution
      { solutionSuccess = hardEnergy <= 1.0e-8
      , solutionSeed = compiledSeed compiled
      , solutionEnergy = hardEnergy
      , solutionValues = values
      , solutionChoices = choiceValues
      , solutionInspection = compiledInspection compiled
      , solutionBackend = AffineSampler
      , solutionBackendStatistics = AffineSamplingStatistics statistics
      , solutionSampling = SampledWith BalancedDesignChoices EnumeratedDecisions
      , solutionVector = vector
      }

compileProblem :: SolveConfig -> SolverProblem -> CompiledProblem
compileProblem config problem =
  CompiledProblem
    { compiledSeed = initialSeed config
    , compiledNumericProblem = numericProblem
    , compiledInitialValues = configuredInitialValues
    , compiledHardConstraints = flatConstraints
    , compiledChoices = choiceValues
    , compiledInspection =
        choiceValues
          `seq` validatedAffine
          `seq` boundsValidation
          `seq` ProblemInspection
                  { inspectedVariableCount = Map.size varTypes
                  , inspectedNativeBoundCount = length nativeBoundNames
                  , inspectedFlattenedCount = length flatConstraints
                  , inspectedRawCount = length rawConstraints
                  , inspectedCanonicalCount = length flatConstraints
                  , inspectedEliminatedCount =
                      max 0 (length rawConstraints - length flatConstraints)
                  , inspectedChoiceCount = Map.size choiceValues
                  , inspectedChoiceBranchCount =
                      choiceCandidateCount choiceStatistics
                  , inspectedChoiceComponentCount =
                      choiceComponentCount choiceStatistics
                  , inspectedLargestChoiceComponentBranches =
                      choiceLargestComponentCandidates choiceStatistics
                  , inspectedNativeBoundNames = nativeBoundNames
                  , inspectedBackend = AffineSampler
                  , inspectedAffineEqualityCount =
                      length (affineEqualities validatedAffine)
                  , inspectedAffineInequalityCount =
                      length (affineInequalities validatedAffine)
                  }
    }
  where
    constraints = solverConstraints problem
    rawConstraints = concatMap flattenConstraint constraints
    flatConstraints = flattenConstraints constraints
    (choiceValues, choiceStatistics) =
      solveChoiceConstraints
        (initialSeed config)
        (maxChoiceBranches config)
        (solverChoiceConstraints problem)
    classification = classifyAffineProblem constraints
    validatedAffine =
      case classification of
        AffineReady affine -> affine
        AffineUnsupported reason ->
          error ("unsupported solver problem: " ++ reason)
        AffineInvalid message -> error message
    varTypes = collectConstraintVarTypes flatConstraints
    inferredBounds = inferDomainBounds flatConstraints
    finalBounds =
      Map.mapWithKey
        (\name ty -> validateDomainBounds name (finalDomainBounds name ty))
        varTypes
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
        (randomUnitsFromSeed (initialSeed config))
        (Map.toAscList varTypes)
    rangeInitialValues =
      seedRangeInitialValues flatConstraints initialSpecs Map.empty
    configuredInitialValues =
      Map.union
        (solverInitialOverrides problem)
        (Map.union
           (initialOverrides config)
           (seedDerivedInitialValues flatConstraints rangeInitialValues))
    numericProblem = SampleAffineProblem validatedAffine
    makeInitialSpec unit (name, ty) =
      InitialSpec
        { initialSpecUnit = unit
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

data InitialSpec = InitialSpec
  { initialSpecUnit   :: Double
  , initialSpecName   :: String
  , initialSpecType   :: Domain
  , initialSpecBounds :: DomainBounds
  } deriving (Eq, Show)

type NativeBounds = (Double, Double)

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
              sampled = sampleInitialWithinBounds bounds (initialSpecUnit spec)
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

--------------------------------------------------------------------------------
-- Evaluating symbolic expressions against a solution
--------------------------------------------------------------------------------
hardConstraintEnergy :: Map String Double -> [Constraint] -> Double
hardConstraintEnergy values = sum . map energy
  where
    energy constraint =
      case constraint of
        Equals ty lhs rhs ->
          let difference = evalRawValues values lhs - evalRawValues values rhs
           in case domainCircularPeriod ty of
                Just period
                  | period > 0 -> 2 - 2 * cos (2 * pi * difference / period)
                _ -> difference * difference
        LessOrEqual lhs rhs ->
          let violation =
                max 0 (evalRawValues values lhs - evalRawValues values rhs)
           in violation * violation
        Minimize _ ->
          error "numeric objective reached affine solution validation"
        Soft _ -> error "soft constraint reached affine solution validation"
        All constraints -> hardConstraintEnergy values constraints
        Cases _ ->
          error "unresolved finite disjunction reached solution validation"

evalRawValues :: Map String Double -> RawExpr -> Double
evalRawValues values expr =
  case expr of
    EVar _ symbolic ->
      Map.findWithDefault
        (error ("unknown solver variable: " ++ varName symbolic))
        (varName symbolic)
        values
    ELit value -> value
    EAdd lhs rhs -> evalRawValues values lhs + evalRawValues values rhs
    ESub lhs rhs -> evalRawValues values lhs - evalRawValues values rhs
    EMul lhs rhs -> evalRawValues values lhs * evalRawValues values rhs
    EDiv lhs rhs -> evalRawValues values lhs / evalRawValues values rhs
    ENeg inner -> negate (evalRawValues values inner)
    EAbs inner -> abs (evalRawValues values inner)
    ESignum inner -> signum (evalRawValues values inner)
    EPow base to -> evalRawValues values base ** evalRawValues values to
    EMin lhs rhs -> min (evalRawValues values lhs) (evalRawValues values rhs)
    EMax lhs rhs -> max (evalRawValues values lhs) (evalRawValues values rhs)

evalExpr :: Solution -> Expr ty -> Maybe Double
evalExpr solution (Expr ty expr) =
  normalizeByType ty <$> evalRawExpr solution expr

evalChoice :: ChoiceDomain ty => Solution -> Choice ty -> Maybe ty
evalChoice solution selected =
  Map.lookup (choiceName selected) (solutionChoices solution)
    >>= choiceValueFromToken

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
