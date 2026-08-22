-- | Seed-independent compilation and repeated sampling of finite affine
-- design spaces. This is the implementation behind the public 'Solver'
-- facade; callers should not depend on the branch representation.
module Solver.DesignSpace
  ( DesignSpaceError(..)
  , CompiledDesignSpace
  , compileDesignSpace
  , sampleDesignSpace
  , sampleDesignSpaceBatch
  ) where

import           Data.Map.Strict    (Map)
import qualified Data.Map.Strict    as Map
import           Data.Maybe         (catMaybes)
import           Data.Set           (Set)
import qualified Data.Set           as Set
import           Prelude
import           Solver.Affine
import           Solver.Categorical
import           Solver.Choice
import           Solver.Constraint
import           Solver.Highs
import           Solver.Problem
import           Solver.Random
import           Solver.Sample

-- | Failure modes that are useful to the DSL compiler and API boundary.
data DesignSpaceError
  = InvalidDecision String
  | UnsupportedDesignSpace String
  | InfeasibleDesignSpace String
  | DecisionSpaceTooLarge Int Int
  | SamplingFailed String
  deriving (Eq, Show)

data CompiledDesignSpace = CompiledDesignSpace
  { compiledDesignConfig       :: SolveConfig
  , compiledDesignProblem      :: SolverProblem
  , compiledEnumerationDomains :: Map String [String]
  , compiledAllChoiceDomains   :: Map String [String]
  , compiledRelevantChoices    :: [ChoiceConstraint]
  , compiledIndependentChoices :: [ChoiceConstraint]
  , compiledDesignBranches     :: CompiledBranches
  }

data CompiledBranches
  = EnumeratedBranches [CompiledBranch]
  | DeferredMipBranches

data CompiledBranch = CompiledBranch
  { branchAssignment    :: Map String String
  , branchAffineProblem :: AffineProblem
  , branchInspection    :: ProblemInspection
  }

-- | Compile all affine alternatives once. The configured categorical branch
-- limit is also the exact-enumeration threshold; larger spaces are retained
-- for bounded MIP conditioning at sample time.
compileDesignSpace ::
     SolveConfig -> SolverProblem -> Either DesignSpaceError CompiledDesignSpace
compileDesignSpace config problem = do
  case forcedBackend config of
    Just PenaltyOptimizer ->
      Left
        (UnsupportedDesignSpace
           "finite design spaces cannot use the penalty optimizer")
    _ -> Right ()
  decisionDomains <- collectDecisionDomains (solverConstraints problem)
  categoricalDomains <- collectChoiceDomains (solverChoiceConstraints problem)
  allDomains <- mergeDomainMaps decisionDomains categoricalDomains
  let decisionNames = Map.keysSet decisionDomains
      relevantNames =
        choiceClosure decisionNames (solverChoiceConstraints problem)
      relevantDomains = Map.restrictKeys allDomains relevantNames
      (relevantChoices, independentChoices) =
        splitChoiceConstraints relevantNames (solverChoiceConstraints problem)
      candidateCount = domainProduct relevantDomains
      limit = maxChoiceBranches config
  branches <-
    if candidateCount <= toInteger limit
      then EnumeratedBranches
             <$> compileEnumeratedBranches
                   config
                   problem
                   relevantDomains
                   relevantChoices
      else pure DeferredMipBranches
  pure
    CompiledDesignSpace
      { compiledDesignConfig = config
      , compiledDesignProblem = problem
      , compiledEnumerationDomains = relevantDomains
      , compiledAllChoiceDomains = allDomains
      , compiledRelevantChoices = relevantChoices
      , compiledIndependentChoices = independentChoices
      , compiledDesignBranches = branches
      }

-- | Sample one seed from a compiled design space.
sampleDesignSpace ::
     SamplingStrategy
  -> RandomSeed
  -> CompiledDesignSpace
  -> IO (Either DesignSpaceError Solution)
sampleDesignSpace strategy seed compiled = do
  results <- sampleDesignSpaceBatch strategy [seed] compiled
  pure
    (case results of
       Left err -> Left err
       Right [solution] -> Right solution
       Right _ ->
         Left (SamplingFailed "single-sample request returned no solution"))

-- | Sample multiple seeds while reusing branch compilation and, for geometric
-- weighting, one set of bounded volume estimates.
sampleDesignSpaceBatch ::
     SamplingStrategy
  -> [RandomSeed]
  -> CompiledDesignSpace
  -> IO (Either DesignSpaceError [Solution])
sampleDesignSpaceBatch strategy seeds compiled =
  case compiledDesignBranches compiled of
    EnumeratedBranches branches ->
      pure $ do
        weights <- branchWeights strategy branches
        traverse (sampleEnumerated compiled strategy branches weights) seeds
    DeferredMipBranches ->
      case strategy of
        GeometricVolume _ ->
          pure
            (Left
               (DecisionSpaceTooLarge
                  (boundedDomainProduct (compiledEnumerationDomains compiled))
                  (maxChoiceBranches (compiledDesignConfig compiled))))
        BalancedDesignChoices -> sampleMipBatch compiled seeds

compileEnumeratedBranches ::
     SolveConfig
  -> SolverProblem
  -> Map String [String]
  -> [ChoiceConstraint]
  -> Either DesignSpaceError [CompiledBranch]
compileEnumeratedBranches config problem domains relevantChoices = do
  candidates <-
    traverse
      compileAssignment
      (filter
         (\assignment ->
            all (choiceConstraintSatisfied assignment) relevantChoices)
         (enumerateChoiceAssignments (Map.toAscList domains)))
  let feasible = catMaybes candidates
  if null feasible
    then Left
           (InfeasibleDesignSpace
              "no finite decision assignment has a feasible affine region")
    else Right feasible
  where
    compileAssignment assignment = do
      resolved <- resolveAssignment problem assignment
      case classifyAffineProblem (solverConstraints resolved) of
        AffineInvalid _ -> Right Nothing
        AffineFallback reason -> Left (UnsupportedDesignSpace reason)
        AffineReady affine ->
          case sampleAffineProblem
                 (RandomSeed 0)
                 (explicitInitialValues config resolved)
                 affine of
            Left _ -> Right Nothing
            Right _ ->
              let pinned = assignmentConstraints domains assignment
                  inspectedProblem =
                    resolved
                      { solverChoiceConstraints =
                          pinned ++ solverChoiceConstraints problem
                      }
                  inspection =
                    compiledInspection (compileProblem config inspectedProblem)
               in Right
                    (Just
                       CompiledBranch
                         { branchAssignment = assignment
                         , branchAffineProblem = affine
                         , branchInspection = inspection
                         })

resolveAssignment ::
     SolverProblem -> Map String String -> Either DesignSpaceError SolverProblem
resolveAssignment problem assignment = do
  constraints <-
    either
      (Left . InvalidDecision)
      Right
      (resolveConstraintDecisions
         (Map.toAscList assignment)
         (solverConstraints problem))
  pure problem {solverConstraints = constraints}

sampleEnumerated ::
     CompiledDesignSpace
  -> SamplingStrategy
  -> [CompiledBranch]
  -> [Double]
  -> RandomSeed
  -> Either DesignSpaceError Solution
sampleEnumerated compiled strategy branches weights seed = do
  branch <- selectWeighted seed branches weights
  let domains = compiledEnumerationDomains compiled
      pins = assignmentConstraints domains (branchAssignment branch)
      allChoiceConstraints =
        pins
          ++ compiledRelevantChoices compiled
          ++ compiledIndependentChoices compiled
      (choices, _) =
        solveChoiceConstraints
          seed
          (maxChoiceBranches (compiledDesignConfig compiled))
          allChoiceConstraints
  makeAffineSolution
    (SampledWith strategy EnumeratedDecisions)
    seed
    choices
    (explicitInitialValues
       (compiledDesignConfig compiled)
       (compiledDesignProblem compiled))
    branch

sampleMipBatch ::
     CompiledDesignSpace
  -> [RandomSeed]
  -> IO (Either DesignSpaceError [Solution])
sampleMipBatch compiled = go []
  where
    go solutions remaining =
      case remaining of
        [] -> pure (Right (reverse solutions))
        seed:rest -> do
          selected <-
            selectFeasibleAssignmentWithHighs
              seed
              (compiledAllChoiceDomains compiled)
              (compiledDesignProblem compiled)
          case selected of
            Left err -> pure (Left (SamplingFailed err))
            Right assignment ->
              case compileMipBranch compiled assignment of
                Left err -> pure (Left err)
                Right branch ->
                  case makeAffineSolution
                         (SampledWith
                            BalancedDesignChoices
                            MipConditionedDecisions)
                         seed
                         assignment
                         (explicitInitialValues
                            (compiledDesignConfig compiled)
                            (compiledDesignProblem compiled))
                         branch of
                    Left err       -> pure (Left err)
                    Right solution -> go (solution : solutions) rest

compileMipBranch ::
     CompiledDesignSpace
  -> Map String String
  -> Either DesignSpaceError CompiledBranch
compileMipBranch compiled assignment = do
  resolved <- resolveAssignment (compiledDesignProblem compiled) assignment
  affine <-
    case classifyAffineProblem (solverConstraints resolved) of
      AffineReady value     -> Right value
      AffineInvalid message -> Left (InfeasibleDesignSpace message)
      AffineFallback reason -> Left (UnsupportedDesignSpace reason)
  let pins =
        assignmentConstraints (compiledAllChoiceDomains compiled) assignment
      inspectedProblem =
        resolved
          { solverChoiceConstraints =
              pins ++ solverChoiceConstraints (compiledDesignProblem compiled)
          }
      inspection =
        compiledInspection
          (compileProblem (compiledDesignConfig compiled) inspectedProblem)
  pure
    CompiledBranch
      { branchAssignment = assignment
      , branchAffineProblem = affine
      , branchInspection = inspection
      }

makeAffineSolution ::
     SamplingProvenance
  -> RandomSeed
  -> Map String String
  -> Map String Double
  -> CompiledBranch
  -> Either DesignSpaceError Solution
makeAffineSolution provenance seed choices overrides branch = do
  (values, statistics) <-
    either
      (Left . SamplingFailed . feasibilityMessage)
      Right
      (sampleAffineProblem seed overrides (branchAffineProblem branch))
  let names = affineVariableNames (branchAffineProblem branch)
      vector =
        [ Map.findWithDefault
          (error ("missing sampled solver variable: " ++ name))
          name
          values
        | name <- names
        ]
  pure
    Solution
      { solutionSuccess = True
      , solutionSeed = seed
      , solutionEnergy = 0
      , solutionValues = values
      , solutionChoices = choices
      , solutionInspection = branchInspection branch
      , solutionBackend = AffineSampler
      , solutionBackendStatistics = AffineSamplingStatistics statistics
      , solutionSampling = provenance
      , solutionVector = vector
      }

branchWeights ::
     SamplingStrategy -> [CompiledBranch] -> Either DesignSpaceError [Double]
branchWeights strategy branches =
  case strategy of
    BalancedDesignChoices -> Right (replicate (length branches) 1)
    GeometricVolume budget -> do
      estimates <-
        traverse
          (\(index, branch) ->
             either
               (Left . SamplingFailed . feasibilityMessage)
               Right
               (estimateAffineLogVolume
                  budget
                  (deriveSeed (RandomSeed 0) ("branch." ++ show index))
                  (branchAffineProblem branch)))
          (zip [0 :: Int ..] branches)
      let dimensions = Set.fromList (map volumeDimension estimates)
      if Set.size dimensions > 1
        then Left
               (UnsupportedDesignSpace
                  "geometric branch weighting requires a common intrinsic dimension")
        else let logMeasures = map volumeLogMeasure estimates
                 largest = maximum (0 : logMeasures)
              in Right [exp (measure - largest) | measure <- logMeasures]

selectWeighted :: RandomSeed -> [a] -> [Double] -> Either DesignSpaceError a
selectWeighted seed values weights =
  case values of
    [] -> Left (InfeasibleDesignSpace "the compiled design space is empty")
    _
      | length values /= length weights ->
        Left (SamplingFailed "branch weights do not match compiled branches")
      | total <= 0 || isNaN total || isInfinite total ->
        Left (SamplingFailed "branch weights are not finite and positive")
      | otherwise -> Right (pick target (zip values weights))
  where
    total = sum weights
    target = randomUnit seed "design.branch" * total
    pick _ [(value, _)] = value
    pick remaining ((value, weight):rest)
      | remaining < weight = value
      | otherwise = pick (remaining - weight) rest
    pick _ [] = error "non-empty weighted selection exhausted its values"

randomUnit :: RandomSeed -> String -> Double
randomUnit seed label =
  case randomUnitsFromSeed (deriveSeed seed label) of
    value:_ -> value
    []      -> 0

explicitInitialValues :: SolveConfig -> SolverProblem -> Map String Double
explicitInitialValues config problem =
  solverInitialOverrides problem `Map.union` initialOverrides config

assignmentConstraints ::
     Map String [String] -> Map String String -> [ChoiceConstraint]
assignmentConstraints domains assignment =
  [ ChoiceIs (ChoiceSpec name categories) token
  | (name, token) <- Map.toAscList assignment
  , let categories =
          Map.findWithDefault
            (error ("missing decision domain: " ++ name))
            name
            domains
  ]

collectDecisionDomains ::
     [Constraint] -> Either DesignSpaceError (Map String [String])
collectDecisionDomains constraints =
  foldl addSpec (Right Map.empty) (constraintDecisionSpecs constraints)
  where
    addSpec result spec = do
      domains <- result
      addDomain
        (decisionSpecName spec)
        (map fst (decisionSpecAlternatives spec))
        domains

collectChoiceDomains ::
     [ChoiceConstraint] -> Either DesignSpaceError (Map String [String])
collectChoiceDomains = foldl addConstraint (Right Map.empty)
  where
    addConstraint result constraint = do
      domains <- result
      foldl addSpec (Right domains) (choiceConstraintSpecs constraint)
    addSpec result (name, categories) = result >>= addDomain name categories

addDomain ::
     String
  -> [String]
  -> Map String [String]
  -> Either DesignSpaceError (Map String [String])
addDomain name categories domains
  | null name = Left (InvalidDecision "decision names must not be empty")
  | null categories =
    Left (InvalidDecision ("decision has an empty domain: " ++ show name))
  | Set.size (Set.fromList categories) /= length categories =
    Left
      (InvalidDecision ("decision has duplicate alternatives: " ++ show name))
  | otherwise =
    case Map.lookup name domains of
      Nothing -> Right (Map.insert name categories domains)
      Just old
        | old == categories -> Right domains
        | otherwise ->
          Left
            (InvalidDecision
               ("decision has incompatible domains: " ++ show name))

mergeDomainMaps ::
     Map String [String]
  -> Map String [String]
  -> Either DesignSpaceError (Map String [String])
mergeDomainMaps first second =
  foldl
    (\result (name, categories) -> result >>= addDomain name categories)
    (Right first)
    (Map.toAscList second)

choiceClosure :: Set String -> [ChoiceConstraint] -> Set String
choiceClosure names constraints =
  let expanded =
        foldl
          (\current constraint ->
             let touched =
                   Set.fromList (map fst (choiceConstraintSpecs constraint))
              in if Set.null (Set.intersection current touched)
                   then current
                   else Set.union current touched)
          names
          constraints
   in if expanded == names
        then names
        else choiceClosure expanded constraints

splitChoiceConstraints ::
     Set String
  -> [ChoiceConstraint]
  -> ([ChoiceConstraint], [ChoiceConstraint])
splitChoiceConstraints relevant =
  foldr
    (\constraint (related, independent) ->
       if any ((`Set.member` relevant) . fst) (choiceConstraintSpecs constraint)
         then (constraint : related, independent)
         else (related, constraint : independent))
    ([], [])

domainProduct :: Map String [String] -> Integer
domainProduct = product . map (toInteger . length) . Map.elems

boundedDomainProduct :: Map String [String] -> Int
boundedDomainProduct domains =
  fromInteger (min (toInteger (maxBound :: Int)) (domainProduct domains))

feasibilityMessage :: FeasibilityFailure -> String
feasibilityMessage (FeasibilityFailure message) = message
