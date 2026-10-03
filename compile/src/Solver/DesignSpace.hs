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

import           Data.IORef         (atomicModifyIORef', modifyIORef', newIORef,
                                     readIORef)
import           Data.List          (intercalate, nub, sortOn)
import           Data.Map.Strict    (Map)
import qualified Data.Map.Strict    as Map
import           Data.Maybe         (mapMaybe)
import           Data.Set           (Set)
import qualified Data.Set           as Set
import           Prelude
import           Solver.Affine
import           Solver.Categorical
import           Solver.Choice
import           Solver.Constraint
import           Solver.Expr        (RawExpr (ESub), domainCircularPeriod)
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
  , compiledDecisionSpecs      :: [DecisionSpec]
  , compiledDesignBranches     :: CompiledBranches
  }

data CompiledBranches
  = EnumeratedBranches [CompiledBranch]
  | DeferredConditionedChoices

data DecisionSelection = DecisionSelection
  { selectedDecisionName   :: String
  , selectedDecisionToken  :: String
  , selectedDecisionOrigin :: DecisionOrigin
  } deriving (Eq, Ord, Show)

data CompiledBranch = CompiledBranch
  { branchIndex          :: Int
  , branchAssignment     :: Map String String
  , branchDecisions      :: [DecisionSelection]
  , branchAffineProblem  :: AffineProblem
  , branchPreparedRegion :: PreparedAffineRegion
  , branchDefaultMeasure :: Either FeasibilityFailure VolumeEstimate
  , branchInspection     :: ProblemInspection
  }

-- | Compile all affine alternatives once. The configured categorical branch
-- limit is also the exact-enumeration threshold; larger spaces are retained
-- for bounded MIP conditioning at sample time.
compileDesignSpace ::
     SolveConfig -> SolverProblem -> Either DesignSpaceError CompiledDesignSpace
compileDesignSpace config problem = do
  validateAffineLanguage (solverConstraints problem)
  decisionDomains <- collectDecisionDomains (solverConstraints problem)
  validateDecisionOrigins (constraintDecisionSpecs (solverConstraints problem))
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
      decisionSpecs = decisionSpecsInOrder (solverConstraints problem)
      independentCount =
        largestChoiceComponentProduct categoricalDomains independentChoices
      conditionedCount = max candidateCount independentCount
  branches <-
    if conditionedCount <= toInteger limit
      then EnumeratedBranches
             <$> compileEnumeratedBranches
                   config
                   problem
                   relevantDomains
                   relevantChoices
      else pure DeferredConditionedChoices
  pure
    CompiledDesignSpace
      { compiledDesignConfig = config
      , compiledDesignProblem = problem
      , compiledEnumerationDomains = relevantDomains
      , compiledAllChoiceDomains = allDomains
      , compiledRelevantChoices = relevantChoices
      , compiledIndependentChoices = independentChoices
      , compiledDecisionSpecs = decisionSpecs
      , compiledDesignBranches = branches
      }

-- Reject language features that cannot belong to any affine branch before
-- choosing between enumeration and deferred MIP conditioning. Branch-specific
-- bounds and feasibility are still checked after a decision assignment is
-- resolved.
validateAffineLanguage :: [Constraint] -> Either DesignSpaceError ()
validateAffineLanguage = mapM_ validate
  where
    validate constraint =
      case constraint of
        Equals domain lhs rhs ->
          case domainCircularPeriod domain of
            Just _ -> unsupported "cyclic equality is not affine"
            Nothing ->
              case linearRawExpr (ESub lhs rhs) of
                Nothing -> unsupported "non-affine equality is unsupported"
                Just _  -> Right ()
        LessOrEqual lhs rhs ->
          case linearRawExpr (ESub lhs rhs) of
            Nothing -> unsupported "non-affine inequality is unsupported"
            Just _  -> Right ()
        Minimize _ ->
          unsupported
            "numeric objectives are unsupported in affine design spaces"
        Soft _ ->
          unsupported "soft constraints are unsupported in affine design spaces"
        All nested -> mapM_ validate nested
        Cases spec ->
          mapM_ (mapM_ validate . snd) (decisionSpecAlternatives spec)
    unsupported = Left . UnsupportedDesignSpace

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
      pure
        $ case strategy of
            BalancedDesignChoices ->
              traverse (sampleBalanced compiled branches) seeds
            GeometricVolume _ -> do
              weights <- branchWeights strategy branches
              traverse
                (sampleGeometric compiled strategy branches weights)
                seeds
    DeferredConditionedChoices ->
      case strategy of
        GeometricVolume _ ->
          pure
            (Left
               (DecisionSpaceTooLarge
                  (max
                     (boundedDomainProduct (compiledEnumerationDomains compiled))
                     (boundedInteger
                        (largestChoiceComponentProduct
                           (compiledAllChoiceDomains compiled)
                           (compiledIndependentChoices compiled))))
                  (maxChoiceBranches (compiledDesignConfig compiled))))
        BalancedDesignChoices -> sampleMipBatch compiled seeds

compileEnumeratedBranches ::
     SolveConfig
  -> SolverProblem
  -> Map String [String]
  -> [ChoiceConstraint]
  -> Either DesignSpaceError [CompiledBranch]
compileEnumeratedBranches config problem domains relevantChoices = do
  paths <-
    fmap
      (Map.elems . Map.fromList)
      (traverse
         activePath
         (filter
            (\assignment ->
               all (choiceConstraintSatisfied assignment) relevantChoices)
            (enumerateChoiceAssignments (Map.toAscList domains))))
  candidates <- traverse compileAssignment (zip [0 :: Int ..] paths)
  let feasible = mapMaybe fst candidates
      rejected = nub (mapMaybe snd candidates)
  if null feasible
    then Left
           (InfeasibleDesignSpace
              (case rejected of
                 [] ->
                   "no finite decision assignment has a feasible affine region"
                 reasons ->
                   "no finite decision assignment has a feasible affine region: "
                     ++ intercalate "; " reasons))
    else Right feasible
  where
    activePath complete = do
      decisions <- activeDecisionPath complete (solverConstraints problem)
      let assignment =
            Map.fromList
              [ (selectedDecisionName selected, selectedDecisionToken selected)
              | selected <- decisions
              ]
      pure (Map.toAscList assignment, (assignment, decisions))
    compileAssignment (index, (assignment, decisions)) = do
      resolved <- resolveAssignment problem assignment
      case classifyAffineProblem
             (boundTolerance config)
             (solverConstraints resolved) of
        AffineInvalid message -> Right (Nothing, Just message)
        AffineUnsupported reason -> Left (UnsupportedDesignSpace reason)
        AffineReady affine ->
          case prepareAffineRegion
                 (explicitInitialValues config resolved)
                 affine of
            Left failure -> Right (Nothing, Just (feasibilityMessage failure))
            Right prepared ->
              let pinned = assignmentConstraints domains assignment
                  inspectedProblem =
                    resolved
                      { solverChoiceConstraints =
                          pinned ++ solverChoiceConstraints problem
                      }
                  inspection =
                    compiledInspection (compileProblem config inspectedProblem)
               in Right
                    ( Just
                        CompiledBranch
                          { branchIndex = index
                          , branchAssignment = assignment
                          , branchDecisions = decisions
                          , branchAffineProblem = affine
                          , branchPreparedRegion = prepared
                          , branchDefaultMeasure =
                              estimatePreparedAffineLogVolume
                                defaultVolumeBudget
                                (deriveSeed
                                   (RandomSeed 0)
                                   ("algebraic.branch." ++ show index))
                                prepared
                          , branchInspection = inspection
                          }
                    , Nothing)

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

activeDecisionPath ::
     Map String String
  -> [Constraint]
  -> Either DesignSpaceError [DecisionSelection]
activeDecisionPath assignment constraints =
  uniqueSelections <$> foldMapM collect constraints
  where
    collect constraint =
      case constraint of
        Equals {} -> Right []
        LessOrEqual _ _ -> Right []
        Minimize _ -> Right []
        Soft inner -> collect inner
        All nested -> foldMapM collect nested
        Cases spec ->
          case Map.lookup (decisionSpecName spec) assignment of
            Nothing ->
              Left
                (InvalidDecision
                   ("missing decision assignment for "
                      ++ show (decisionSpecName spec)))
            Just token ->
              case lookup token (decisionSpecAlternatives spec) of
                Nothing ->
                  Left
                    (InvalidDecision
                       ("unknown alternative "
                          ++ show token
                          ++ " for decision "
                          ++ show (decisionSpecName spec)))
                Just nested -> do
                  rest <- foldMapM collect nested
                  pure
                    (DecisionSelection
                       { selectedDecisionName = decisionSpecName spec
                       , selectedDecisionToken = token
                       , selectedDecisionOrigin = decisionSpecOrigin spec
                       }
                       : rest)

uniqueSelections :: [DecisionSelection] -> [DecisionSelection]
uniqueSelections = go Set.empty
  where
    go _ [] = []
    go seen (selected:rest)
      | selectedDecisionName selected `Set.member` seen = go seen rest
      | otherwise =
        selected : go (Set.insert (selectedDecisionName selected) seen) rest

decisionSpecsInOrder :: [Constraint] -> [DecisionSpec]
decisionSpecsInOrder = uniqueSpecs . concatMap collect
  where
    collect constraint =
      case constraint of
        Equals {} -> []
        LessOrEqual _ _ -> []
        Minimize _ -> []
        Soft inner -> collect inner
        All nested -> concatMap collect nested
        Cases spec ->
          spec
            : concatMap
                (concatMap collect . snd)
                (decisionSpecAlternatives spec)
    uniqueSpecs = go Set.empty
    go _ [] = []
    go seen (spec:rest)
      | decisionSpecName spec `Set.member` seen = go seen rest
      | otherwise = spec : go (Set.insert (decisionSpecName spec) seen) rest

foldMapM :: Monad m => (a -> m [b]) -> [a] -> m [b]
foldMapM f values = concat <$> traverse f values

sampleBalanced ::
     CompiledDesignSpace
  -> [CompiledBranch]
  -> RandomSeed
  -> Either DesignSpaceError Solution
sampleBalanced compiled branches seed = do
  authored <- selectAuthoredBranches compiled seed branches
  branch <- selectAlgebraicBranch seed authored
  completeEnumeratedSolution compiled BalancedDesignChoices seed branch

sampleGeometric ::
     CompiledDesignSpace
  -> SamplingStrategy
  -> [CompiledBranch]
  -> [Double]
  -> RandomSeed
  -> Either DesignSpaceError Solution
sampleGeometric compiled strategy branches weights seed = do
  branch <- selectWeighted seed "design.geometric-branch" branches weights
  completeEnumeratedSolution compiled strategy seed branch

completeEnumeratedSolution ::
     CompiledDesignSpace
  -> SamplingStrategy
  -> RandomSeed
  -> CompiledBranch
  -> Either DesignSpaceError Solution
completeEnumeratedSolution compiled strategy seed branch = do
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
      algebraicNames =
        Set.fromList
          [ decisionSpecName spec
          | spec <- compiledDecisionSpecs compiled
          , decisionSpecOrigin spec == AlgebraicPartition
          ]
  makeAffineSolution
    (SampledWith strategy EnumeratedDecisions)
    seed
    (Map.withoutKeys choices algebraicNames)
    branch

selectAuthoredBranches ::
     CompiledDesignSpace
  -> RandomSeed
  -> [CompiledBranch]
  -> Either DesignSpaceError [CompiledBranch]
selectAuthoredBranches compiled seed = go authoredSpecs
  where
    authoredSpecs =
      [ spec
      | spec <- compiledDecisionSpecs compiled
      , decisionSpecOrigin spec == AuthoredDecision
      ]
    go specs candidates =
      case specs of
        [] -> Right candidates
        spec:rest ->
          let name = decisionSpecName spec
              active = map (branchDecisionToken name) candidates
           in if all (== Nothing) active
                then go rest candidates
                else if Nothing `elem` active
                       then Left
                              (UnsupportedDesignSpace
                                 ("authored decision "
                                    ++ show name
                                    ++ " is activated by an algebraic partition"))
                       else do
                         let feasibleTokens =
                               [ token
                               | (token, _) <- decisionSpecAlternatives spec
                               , Just token `elem` active
                               ]
                         selected <-
                           selectWeighted
                             seed
                             ("design.authored." ++ name)
                             feasibleTokens
                             (replicate (length feasibleTokens) 1)
                         go
                           rest
                           [ branch
                           | branch <- candidates
                           , branchDecisionToken name branch == Just selected
                           ]

branchDecisionToken :: String -> CompiledBranch -> Maybe String
branchDecisionToken name branch =
  case [ selectedDecisionToken selected
       | selected <- branchDecisions branch
       , selectedDecisionName selected == name
       ] of
    token:_ -> Just token
    []      -> Nothing

selectAlgebraicBranch ::
     RandomSeed -> [CompiledBranch] -> Either DesignSpaceError CompiledBranch
selectAlgebraicBranch seed branches =
  case branches of
    [] -> Left (InfeasibleDesignSpace "no authored assignment is feasible")
    [branch] -> Right branch
    _ -> do
      estimates <-
        traverse
          (either (Left . SamplingFailed . feasibilityMessage) Right
             . branchDefaultMeasure)
          branches
      let dimensions = Set.fromList (map volumeDimension estimates)
      if Set.size dimensions > 1
        then Left
               (UnsupportedDesignSpace
                  "algebraic cells for one authored assignment have different intrinsic dimensions")
        else let logMeasures = map volumeLogMeasure estimates
                 largest = maximum logMeasures
              in selectWeighted
                   seed
                   "design.algebraic-cell"
                   branches
                   [exp (measure - largest) | measure <- logMeasures]

sampleMipBatch ::
     CompiledDesignSpace
  -> [RandomSeed]
  -> IO (Either DesignSpaceError [Solution])
sampleMipBatch compiled = go Map.empty []
  where
    go cache solutions remaining =
      case remaining of
        [] -> pure (Right (reverse solutions))
        seed:rest -> do
          conditioned <- selectConditionedBranch compiled seed cache
          case conditioned of
            Left err -> pure (Left err)
            Right (nextCache, assignment, branch) ->
              case do
                     visibleAssignment <-
                       visibleConditionedChoices compiled assignment branch
                     makeAffineSolution
                       (SampledWith
                          BalancedDesignChoices
                          MipConditionedDecisions)
                       seed
                       visibleAssignment
                       branch of
                Left err       -> pure (Left err)
                Right solution -> go nextCache (solution : solutions) rest

-- Ask HiGHS for one seed-driven completion of the large finite space. If exact
-- affine preparation rejects that completion, bounded backtracking remains a
-- correctness fallback rather than work paid by every ordinary sample.
selectConditionedBranch ::
     CompiledDesignSpace
  -> RandomSeed
  -> Map (Map String String) CompiledBranch
  -> IO
       (Either
          DesignSpaceError
          ( Map (Map String String) CompiledBranch
          , Map String String
          , CompiledBranch))
selectConditionedBranch compiled seed cache = do
  attempts <- newIORef 0
  rejections <- newIORef []
  completionResult <-
    queryFeasible attempts rejections seededCompletionCosts Map.empty
  selected <-
    case completionResult of
      Left err -> pure (Left err)
      Right Nothing -> pure (Right Nothing)
      Right (Just completion) -> do
        let complete = highsChoiceAssignment completion
        prepared <-
          prepareCompletion rejections complete (highsNumericValues completion)
        case prepared of
          Left err -> pure (Left err)
          Right (Just success) -> pure (Right (Just success))
          Right Nothing ->
            chooseDeferred
              attempts
              rejections
              Map.empty
              completionDomains
              Nothing
  rejected <- readIORef rejections
  pure $ do
    result <- selected
    case result of
      Nothing ->
        Left
          (InfeasibleDesignSpace
             ("no conditioned decision assignment has a feasible affine region"
                ++ case nub rejected of
                     []      -> ""
                     reasons -> ": " ++ intercalate "; " reasons))
      Just value -> Right value
  where
    problem = compiledDesignProblem compiled
    domains = compiledAllChoiceDomains compiled
    decisionNames =
      Set.fromList (map decisionSpecName (compiledDecisionSpecs compiled))
    categoricalNames =
      [name | name <- Map.keys domains, name `Set.notMember` decisionNames]
    authoredAndCategoricalDomains =
      [ ( decisionSpecName spec
        , map fst (decisionSpecAlternatives spec)
        , "conditioned")
      | spec <- compiledDecisionSpecs compiled
      , decisionSpecOrigin spec == AuthoredDecision
      ]
        ++ [ ( name
             , Map.findWithDefault
                 (error ("missing finite choice domain " ++ show name))
                 name
                 domains
             , "conditioned")
           | name <- categoricalNames
           ]
    algebraicDomains =
      [ ( decisionSpecName spec
        , map fst (decisionSpecAlternatives spec)
        , "algebraic")
      | spec <- compiledDecisionSpecs compiled
      , decisionSpecOrigin spec == AlgebraicPartition
      ]
    completionDomains = authoredAndCategoricalDomains ++ algebraicDomains
    feasible objective =
      feasibleCompletionWithHighs
        (boundTolerance (compiledDesignConfig compiled))
        domains
        objective
        problem
    -- IID positive costs treat every token symmetrically across seeds. Each
    -- domain is one-hot, so centering all of its costs would add only a
    -- constant; avoiding negative coefficients also keeps MIP serialization
    -- compatible with the bundled HiGHS solution parser.
    seededCompletionCosts =
      Map.fromList
        [ ( (name, token)
          , randomUnit seed ("design.deferred-mip." ++ name ++ "." ++ token))
        | (name, tokens, _) <- completionDomains
        , token <- tokens
        ]
    -- This operational search-work bound is independent of the exact-
    -- enumeration threshold. A conditioned completion should normally pass
    -- exact affine preparation immediately; sixteen attempts allow bounded
    -- recovery without turning one bad categorical corner into a multi-minute
    -- compile.
    attemptLimit :: Int
    attemptLimit = 16
    chooseDeferred attempts rejections partial remaining lastCompletion =
      case remaining of
        [] ->
          case lastCompletion of
            Nothing -> pure (Right Nothing)
            Just completion ->
              prepareCompletion
                rejections
                (Map.union partial (highsChoiceAssignment completion))
                (highsNumericValues completion)
        (name, tokens, category):rest ->
          tryDeferredTokens attempts rejections partial rest name ordered
          where
            ordered =
              sortOn
                (randomUnit seed
                   . (("design." ++ category ++ "." ++ name ++ ".") ++))
                tokens
    tryDeferredTokens _ _ _ _ _ [] = pure (Right Nothing)
    tryDeferredTokens attempts rejections partial remaining name (token:tokens) = do
      let candidate = Map.insert name token partial
      feasibility <- queryFeasible attempts rejections Map.empty candidate
      case feasibility of
        Left err -> pure (Left err)
        Right Nothing ->
          tryDeferredTokens attempts rejections partial remaining name tokens
        Right (Just completion) -> do
          nested <-
            chooseDeferred
              attempts
              rejections
              candidate
              remaining
              (Just completion)
          case nested of
            Left err -> pure (Left err)
            Right Nothing ->
              tryDeferredTokens
                attempts
                rejections
                partial
                remaining
                name
                tokens
            Right success -> pure (Right success)
    queryFeasible attempts rejections objective partial = do
      attempt <-
        atomicModifyIORef'
          attempts
          (\count ->
             let next = count + 1
              in (next, next))
      if attempt > attemptLimit
        then do
          rejected <- readIORef rejections
          pure
            (Left
               (SamplingFailed
                  ("conditioned feasibility search exceeded "
                     ++ show attemptLimit
                     ++ " attempts"
                     ++ case nub rejected of
                          []      -> ""
                          reasons -> ": " ++ intercalate "; " reasons)))
        else do
          feasibility <- feasible objective partial
          case feasibility of
            Left err         -> pure (Left (SamplingFailed err))
            Right completion -> pure (Right completion)
    prepareCompletion rejections completion hint =
      case Map.lookup completion cache of
        Just branch -> pure (Right (Just (cache, completion, branch)))
        Nothing ->
          case compileConditionedBranch compiled hint completion of
            Left (InfeasibleDesignSpace message) -> do
              modifyIORef' rejections (message :)
              pure (Right Nothing)
            Left err -> pure (Left err)
            Right branch ->
              pure
                (Right
                   (Just
                      (Map.insert completion branch cache, completion, branch)))

compileConditionedBranch ::
     CompiledDesignSpace
  -> Map String Double
  -> Map String String
  -> Either DesignSpaceError CompiledBranch
compileConditionedBranch compiled numericHint completion = do
  active <-
    activeDecisionPath
      completion
      (solverConstraints (compiledDesignProblem compiled))
  let assignment =
        Map.fromList
          [ (selectedDecisionName selected, selectedDecisionToken selected)
          | selected <- active
          ]
  compileMipBranchWithHint numericHint compiled 0 assignment active

visibleConditionedChoices ::
     CompiledDesignSpace
  -> Map String String
  -> CompiledBranch
  -> Either DesignSpaceError (Map String String)
visibleConditionedChoices compiled fixed branch = do
  let problem = compiledDesignProblem compiled
      complete = Map.union (branchAssignment branch) fixed
      registeredChoiceNames =
        Set.fromList
          [ name
          | constraint <- solverChoiceConstraints problem
          , (name, _) <- choiceConstraintSpecs constraint
          ]
  active <- activeDecisionPath complete (solverConstraints problem)
  let visibleDecisionNames =
        Set.fromList
          [ selectedDecisionName selected
          | selected <- active
          , selectedDecisionOrigin selected == AuthoredDecision
          ]
  pure
    (Map.restrictKeys
       complete
       (Set.union visibleDecisionNames registeredChoiceNames))

compileMipBranchWithHint ::
     Map String Double
  -> CompiledDesignSpace
  -> Int
  -> Map String String
  -> [DecisionSelection]
  -> Either DesignSpaceError CompiledBranch
compileMipBranchWithHint numericHint compiled index assignment decisions = do
  resolved <- resolveAssignment (compiledDesignProblem compiled) assignment
  affine <-
    case classifyAffineProblem
           (boundTolerance (compiledDesignConfig compiled))
           (solverConstraints resolved) of
      AffineReady value        -> Right value
      AffineInvalid message    -> Left (InfeasibleDesignSpace message)
      AffineUnsupported reason -> Left (UnsupportedDesignSpace reason)
  -- Keep authored overrides, but let all other coordinates start from their
  -- normalized midpoints. The MIP feasibility point is often a box corner;
  -- hit-and-run cannot leave such a corner in a random direction in a large
  -- affine region. It remains a bounded fallback if midpoint repair fails.
  let preferredHint =
        explicitInitialValues (compiledDesignConfig compiled) resolved
  prepared <-
    case prepareAffineRegionWithPhaseOneLimit
           midpointProjectionSweeps
           preferredHint
           affine of
      Right region -> Right region
      Left preferredFailure ->
        either
          (\fallbackFailure ->
             Left
               (InfeasibleDesignSpace
                  (feasibilityMessage fallbackFailure
                     ++ numericHintDiagnostic numericHint affine
                     ++ "; preferred midpoint hint also failed: "
                     ++ feasibilityMessage preferredFailure)))
          Right
          (prepareAffineRegion numericHint affine)
       -- Phase I projects the midpoint into the chosen region; if the bounded
       -- projection does not converge, the already-feasible HiGHS point is
       -- the deterministic fallback.
  let inspection =
        compiledInspection
          (compileProblem
             (compiledDesignConfig compiled)
             resolved {solverChoiceConstraints = []})
  pure
    CompiledBranch
      { branchIndex = index
      , branchAssignment = assignment
      , branchDecisions = decisions
      , branchAffineProblem = affine
      , branchPreparedRegion = prepared
      , branchDefaultMeasure =
          estimatePreparedAffineLogVolume
            defaultVolumeBudget
            (deriveSeed (RandomSeed 0) ("algebraic.branch." ++ show index))
            prepared
      , branchInspection = inspection
      }
  where
    -- Each projection sweep touches every affine inequality. Up to 512
    -- sweeps admit interior starts for nested visual mappings; preparation
    -- stops as soon as it is feasible and retains the HiGHS fallback when
    -- deeply constrained branches cannot converge within this budget.
    midpointProjectionSweeps = 512

numericHintDiagnostic :: Map String Double -> AffineProblem -> String
numericHintDiagnostic hint problem =
  "; initial hint matched "
    ++ show matchedCount
    ++ "/"
    ++ show (length names)
    ++ " variables, maximum raw equality residual="
    ++ show maximumEqualityResidual
    ++ ", maximum raw inequality violation="
    ++ show maximumInequalityViolation
  where
    names = affineVariableNames problem
    matchedCount = length [name | name <- names, Map.member name hint]
    rowValue row =
      sum
        [ coefficient * Map.findWithDefault 0 name hint
        | (name, coefficient) <- Map.toAscList (affineRowCoefficients row)
        ]
    maximumEqualityResidual =
      maximum
        (0
           : [ abs (rowValue row - affineRowRhs row)
             | row <- affineEqualities problem
             ])
    maximumInequalityViolation =
      maximum
        (0
           : [ rowValue row - affineRowRhs row
             | row <- affineInequalities problem
             ])

makeAffineSolution ::
     SamplingProvenance
  -> RandomSeed
  -> Map String String
  -> CompiledBranch
  -> Either DesignSpaceError Solution
makeAffineSolution provenance seed choices branch = do
  (values, statistics) <-
    either
      (Left . SamplingFailed . feasibilityMessage)
      Right
      (samplePreparedAffineRegion seed (branchPreparedRegion branch))
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
               (estimatePreparedAffineLogVolume
                  budget
                  (deriveSeed (RandomSeed 0) ("branch." ++ show index))
                  (branchPreparedRegion branch)))
          (zip [0 :: Int ..] branches)
      let dimensions = Set.fromList (map volumeDimension estimates)
      if Set.size dimensions > 1
        then Left
               (UnsupportedDesignSpace
                  "geometric branch weighting requires a common intrinsic dimension")
        else let logMeasures = map volumeLogMeasure estimates
                 largest = maximum (0 : logMeasures)
              in Right [exp (measure - largest) | measure <- logMeasures]

selectWeighted ::
     RandomSeed -> String -> [a] -> [Double] -> Either DesignSpaceError a
selectWeighted seed label values weights =
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
    target = randomUnit seed label * total
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

validateDecisionOrigins :: [DecisionSpec] -> Either DesignSpaceError ()
validateDecisionOrigins = go Map.empty
  where
    go _ [] = Right ()
    go origins (spec:rest) =
      let name = decisionSpecName spec
          origin = decisionSpecOrigin spec
       in case Map.lookup name origins of
            Nothing -> go (Map.insert name origin origins) rest
            Just previous
              | previous == origin -> go origins rest
              | otherwise ->
                Left
                  (InvalidDecision
                     ("decision is both authored and algebraic: " ++ show name))

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

largestChoiceComponentProduct ::
     Map String [String] -> [ChoiceConstraint] -> Integer
largestChoiceComponentProduct domains constraints =
  maximum
    (0
       : [ domainProduct (Map.restrictKeys domains choiceComponent)
         | choiceComponent <- Set.toList components
         ])
  where
    names =
      Set.fromList
        [ name
        | constraint <- constraints
        , (name, _) <- choiceConstraintSpecs constraint
        ]
    components =
      Set.fromList
        [ choiceClosure (Set.singleton name) constraints
        | name <- Set.toList names
        ]

domainProduct :: Map String [String] -> Integer
domainProduct = product . map (toInteger . length) . Map.elems

boundedDomainProduct :: Map String [String] -> Int
boundedDomainProduct domains = boundedInteger (domainProduct domains)

boundedInteger :: Integer -> Int
boundedInteger = fromInteger . min (toInteger (maxBound :: Int))

feasibilityMessage :: FeasibilityFailure -> String
feasibilityMessage (FeasibilityFailure message) = message
