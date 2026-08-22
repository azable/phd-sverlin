-- | Tuned solver bridge for view graphs. Choreography uses settings distinct
-- from the conservative public solver defaults.
module LinearTrace.View.Solve
  ( -- * View solving
    -- | Solve a symbolic view graph with deterministic seeded initialization
    -- and a retry configuration for low-energy visualization output.
    solveCSPWithSeed
  , solveCSPWithSeeds
  ) where

import           LinearTrace.View.Graph
import           Prelude                (Maybe (..))
import qualified Prelude                as P
import qualified Solver                 as S
import           Solver                 (RandomSeed, Solution, SolveConfig,
                                         SolverProblem)

solveCSP :: RandomSeed -> SolveConfig -> ViewGraph -> P.IO Solution
solveCSP seed config graph =
  case S.compileDesignSpace config (viewSolveProblem graph) of
    P.Right designSpace ->
      S.sampleDesignSpace S.BalancedDesignChoices seed designSpace
        P.>>= P.either designSpaceFailure P.pure
    P.Left err
      | S.hasConstraintDecisions (viewConstraints graph) ->
        designSpaceFailure err
      | P.otherwise -> S.solveProblem config (viewSolveProblem graph)

solveCSPWithSeed :: RandomSeed -> ViewGraph -> P.IO Solution
solveCSPWithSeed seed graph =
  solveCSP seed (viewSolveConfig seed) graph P.>>= acceptOrRetry seed graph

acceptOrRetry :: RandomSeed -> ViewGraph -> Solution -> P.IO Solution
acceptOrRetry seed graph solution =
  case viewSolutionAcceptable solution of
    P.True -> P.pure solution
    P.False ->
      case S.solutionBackend solution of
        S.PenaltyOptimizer ->
          S.solveProblem (viewRetrySolveConfig seed) (viewSolveProblem graph)
            P.>>= requireAcceptable
        S.AffineSampler -> rejectSolution solution

-- | Compile a view's affine branches once and sample every requested seed.
-- Non-affine legacy views retain the established per-seed optimizer path.
solveCSPWithSeeds :: [RandomSeed] -> ViewGraph -> P.IO [Solution]
solveCSPWithSeeds seeds graph =
  case seeds of
    [] -> P.pure []
    firstSeed:_ ->
      let config = viewSolveConfig firstSeed
       in case S.compileDesignSpace config (viewSolveProblem graph) of
            P.Right designSpace ->
              S.sampleDesignSpaceBatch S.BalancedDesignChoices seeds designSpace
                P.>>= P.either designSpaceFailure P.pure
            P.Left err
              | S.hasConstraintDecisions (viewConstraints graph) ->
                designSpaceFailure err
              | P.otherwise -> P.mapM (`solveLegacyWithSeed` graph) seeds

solveLegacyWithSeed :: RandomSeed -> ViewGraph -> P.IO Solution
solveLegacyWithSeed seed graph =
  S.solveProblem (viewSolveConfig seed) (viewSolveProblem graph)
    P.>>= acceptOrRetry seed graph

designSpaceFailure :: S.DesignSpaceError -> P.IO value
designSpaceFailure err =
  P.ioError
    (P.userError ("visualization design space failed: " P.++ P.show err))

viewSolveConfig :: RandomSeed -> SolveConfig
viewSolveConfig seed =
  S.withOptimizerTolerances (Just 1e-5) (Just 1e-3)
    P.$ S.withConstraintWeights
          (P.fromInteger (10 :: P.Integer))
          (P.fromInteger (1 :: P.Integer))
    P.$ S.withInitialSeed seed S.defaultSolveConfig

viewRetrySolveConfig :: RandomSeed -> SolveConfig
viewRetrySolveConfig seed =
  S.withMaxOptimizerIterations 3000
    P.$ S.withOptimizerTolerances (Just 1e-7) (Just 1e-5)
    P.$ S.withConstraintWeights
          (P.fromInteger (10 :: P.Integer))
          (P.fromInteger (1 :: P.Integer))
    P.$ S.withInitialSeed seed S.defaultSolveConfig

viewSolutionAcceptable :: Solution -> P.Bool
viewSolutionAcceptable solution =
  S.solutionSuccess solution P.&& S.solutionEnergy solution P.<= 1e-4

requireAcceptable :: Solution -> P.IO Solution
requireAcceptable solution =
  case viewSolutionAcceptable solution of
    P.True  -> P.pure solution
    P.False -> rejectSolution solution

rejectSolution :: Solution -> P.IO a
rejectSolution solution =
  P.ioError
    (P.userError
       ("visualization constraints were not solved successfully (backend="
          P.++ P.show (S.solutionBackend solution)
          P.++ ", hard energy="
          P.++ P.show (S.solutionEnergy solution)
          P.++ ")"))

viewSolveProblem :: ViewGraph -> SolverProblem
viewSolveProblem graph =
  S.solverProblemWithChoices
    (viewConstraints graph)
    (viewChoiceConstraints graph)
