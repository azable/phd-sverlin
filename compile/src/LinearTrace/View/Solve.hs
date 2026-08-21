-- | Tuned solver bridge for view graphs. Choreography uses settings distinct
-- from the conservative public solver defaults.
module LinearTrace.View.Solve
  ( -- * View solving
    -- | Solve a symbolic view graph with deterministic seeded initialization
    -- and a retry configuration for low-energy visualization output.
    solveCSPWithSeed
  ) where

import           LinearTrace.View.Graph
import           Prelude                (Maybe (..))
import qualified Prelude                as P
import qualified Solver                 as S
import           Solver                 (RandomSeed, Solution, SolveConfig,
                                         SolverProblem)

solveCSP :: SolveConfig -> ViewGraph -> P.IO Solution
solveCSP config graph = S.solveProblem config (viewSolveProblem graph)

solveCSPWithSeed :: RandomSeed -> ViewGraph -> P.IO Solution
solveCSPWithSeed seed graph =
  solveCSP (viewSolveConfig seed) graph P.>>= \solution ->
    case viewSolutionAcceptable solution of
      P.True  -> P.pure solution
      P.False -> solveCSP (viewRetrySolveConfig seed) graph

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
viewSolutionAcceptable solution = S.solutionEnergy solution P.<= 1e-4

viewSolveProblem :: ViewGraph -> SolverProblem
viewSolveProblem graph =
  S.solverProblemWithChoices
    (viewConstraints graph)
    (viewChoiceConstraints graph)
