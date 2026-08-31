-- | Tuned solver bridge for view graphs. Choreography uses settings distinct
-- from the conservative public solver defaults.
module LinearTrace.View.Solve
  ( -- * View solving
    -- | Solve a symbolic view graph with deterministic seeded initialization
    -- and a retry configuration for low-energy visualization output.
    solveCSPWithSeed
  , solveCSPWithSeeds
  , solveCSPWithPinnedSolution
  ) where

import           LinearTrace.View.Graph
import qualified Prelude                as P
import qualified Solver                 as S
import           Solver                 (RandomSeed, Solution, SolveConfig,
                                         SolverProblem)

solveCSP :: RandomSeed -> SolveConfig -> ViewGraph -> P.IO Solution
solveCSP seed config graph =
  solveViewProblem seed config graph (viewSolveProblem graph)

solveViewProblem ::
     RandomSeed -> SolveConfig -> ViewGraph -> SolverProblem -> P.IO Solution
solveViewProblem seed config _graph problem =
  case S.compileDesignSpace config problem of
    P.Right designSpace ->
      S.sampleDesignSpace S.BalancedDesignChoices seed designSpace
        P.>>= P.either designSpaceFailure P.pure
    P.Left err -> designSpaceFailure err

solveCSPWithSeed :: RandomSeed -> ViewGraph -> P.IO Solution
solveCSPWithSeed seed graph =
  solveCSP seed (viewSolveConfig seed) graph P.>>= requireAcceptable

-- | Re-solve a text-prepared view while retaining every finite aesthetic and
-- structure decision from the initial solution.
solveCSPWithPinnedSolution ::
     RandomSeed -> Solution -> ViewGraph -> P.IO Solution
solveCSPWithPinnedSolution seed initial graph =
  case S.pinProblemChoices (S.solutionChoices initial) (viewSolveProblem graph) of
    P.Left err ->
      P.ioError (P.userError ("could not pin visualization choices: " P.++ err))
    P.Right pinned ->
      let problem =
            S.withProblemInitialOverrides (S.solutionValues initial) pinned
       in solveViewProblem seed (viewSolveConfig seed) graph problem
            P.>>= requireAcceptable

-- | Compile a view's affine branches once and sample every requested seed.
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
            P.Left err -> designSpaceFailure err

designSpaceFailure :: S.DesignSpaceError -> P.IO value
designSpaceFailure err =
  P.ioError
    (P.userError ("visualization design space failed: " P.++ P.show err))

viewSolveConfig :: RandomSeed -> SolveConfig
viewSolveConfig seed = S.withInitialSeed seed S.defaultSolveConfig

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
