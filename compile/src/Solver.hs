-- | Public API for the symbolic numeric solver used by the trace view layer.
--
-- Most callers should import this module only. The implementation modules
-- under @Solver.*@ are kept separate so the expression language, constraint
-- layer, problem compiler, and optimizer backend can be tested independently
-- without making those modules part of the public surface.
module Solver
  ( -- * Numeric domains
    -- | Domains describe numeric variable compatibility and cyclic wrapping.
    -- Bounds are provided with 'within'; compilation lowers direct variable
    -- ranges to native optimizer bounds and keeps compound ranges as energy
    -- terms.
    Range(..)
  , Domain
  , domainName
  , domainCircularPeriod
  , realDomain
  , cyclicDomain
  , NumericType
  , SymbolicType(..)
  , -- * Categorical choices
    -- | Choices are finite-domain variables. They intentionally do not share
    -- the 'Expr' arithmetic API. A compiled problem samples a satisfying
    -- categorical assignment before numeric solving.
    Category
  , category
  , categoryName
  , Choice
  , choice
  , choiceName
  , CategoricalType(..)
  , ChoiceConstraint
  , choose
  , sameChoice
  , differentChoice
  , -- * Numeric expressions and vectors
    -- | Symbolic expressions are opaque. Use 'ExprView' for read-only
    -- diagnostic rendering.
    Expr
  , ExprView(..)
  , var
  , num
  , exprView
  , (@+@)
  , (@-@)
  , (@*@)
  , (@/@)
  , (@^@)
  , absExpr
  , minExpr
  , maxExpr
  , Vec2(..)
  , vec2
  , -- * Constraints and objectives
    -- | Hard constraints are emitted directly; wrap a constraint in 'soften'
    -- or use 'minimize' to contribute soft objective terms.
    Constraint
  , ConstraintView(..)
  , ConstrainEq(..)
  , ConstrainOrd(..)
  , (@==@)
  , (@<=@)
  , (@>=@)
  , allOf
  , within
  , minimize
  , soften
  , constraintViews
  , constraintCount
  , -- * Multi-component relations
    -- | Components let higher layers relate structured values such as vectors
    -- and HSL colours without constructing raw solver constraints themselves.
    Component
  , ComponentRelation(..)
  , component
  , exprComponent
  , relateComponents
  , directedBridgeComponents
  , symmetricBridgeComponents
  , -- * Solving and inspection
    -- | A 'SolverProblem' compiles constraints, samples finite categorical
    -- choices, canonicalizes repeated constraints, infers native bounds, seeds
    -- initial values, and solves through the bounded optimizer backend.
    SolveConfig
  , defaultSolveConfig
  , withInitialSeed
  , withInitialOverrides
  , withConstraintWeights
  , withMaxCategoricalBranches
  , withOptimizerTolerances
  , withMaxOptimizerIterations
  , withOptimizerMaxCorrections
  , SolverProblem
  , solverProblem
  , solverProblemWithChoices
  , withChoiceConstraints
  , withProblemInitialOverrides
  , CompiledProblem
  , compiledInspection
  , ProblemInspection
  , inspectedVariableCount
  , inspectedNativeBoundCount
  , inspectedEnergyTermCount
  , inspectedFlattenedCount
  , inspectedRawCount
  , inspectedCanonicalCount
  , inspectedEliminatedCount
  , inspectedChoiceCount
  , inspectedChoiceBranchCount
  , inspectedNativeBoundNames
  , Solution
  , solutionSuccess
  , solutionSeed
  , solutionEnergy
  , solutionValues
  , solutionChoices
  , solutionInspection
  , solutionIterations
  , solutionFunctionEvaluations
  , solutionGradientEvaluations
  , solve
  , solveProblem
  , solveCompiledProblem
  , compileProblem
  , inspectConstraints
  , -- * Seeded randomness
    -- | Seeds make initial sampling deterministic for tests and repeatable
    -- visualization output.
    RandomSeed(..)
  , -- * Result evaluation
    -- | Evaluate symbolic expressions against a solved result.
    evalExpr
  , evalChoice
  ) where

import           Solver.Choice
import           Solver.Constraint
import           Solver.Expr
import           Solver.Problem
