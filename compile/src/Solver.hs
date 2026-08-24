-- | Public API for the symbolic numeric solver used by the trace view layer.
--
-- Most callers should import this module only. The implementation modules
-- under @Solver.*@ are kept separate so the expression language, constraint
-- layer, problem compiler, affine sampler, and penalty optimizer can be tested independently
-- without making those modules part of the public surface.
module Solver
  ( -- * Numeric domains
    -- | Domains describe numeric variable compatibility, cyclic wrapping, and
    -- default native optimizer bounds. Extra bounds are provided with 'within';
    -- compilation lowers direct variable ranges to native optimizer bounds and
    -- keeps compound ranges as energy terms.
    Range(..)
  , Domain
  , domainName
  , domainCircularPeriod
  , domainDefaultBounds
  , realDomain
  , boundedDomain
  , cyclicDomain
  , boundedCyclicDomain
  , NumericType
  , SymbolicType(..)
  , -- * Categorical choices
    -- | Choices are finite-domain variables with typed values and stable
    -- string tokens. They intentionally do not share the 'Expr' arithmetic
    -- API. Use 'freeChoice' to register an unconstrained finite choice, or
    -- relation constraints such as 'choose'/'sameChoice' to restrict it. A
    -- compiled problem samples a satisfying categorical assignment per
    -- independent component before numeric solving.
    ChoiceDomain(..)
  , ChoiceValue(..)
  , Choice
  , choice
  , choiceName
  , ChoiceConstraint
  , freeChoice
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
  , substituteExprVars
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
  , ConstrainEq(..)
  , ConstrainOrd(..)
  , (@==@)
  , (@<=@)
  , (@>=@)
  , allOf
  , within
  , minimize
  , soften
  , constraintCount
  , Alternative
  , alternative
  , oneOf
  , caseOf
  , hasConstraintDecisions
  , -- * Multi-component relations
    -- | Components let higher layers relate structured values such as vectors
    -- and HSL colours without constructing raw solver constraints themselves.
    Component
  , ComponentRelation(..)
  , component
  , exprComponent
  , componentConstraints
  , addComponentConstraints
  , addComponents
  , subtractComponents
  , scaleComponent
  , substituteComponentVars
  , componentConstantValue
  , substituteConstraintVars
  , relateComponents
  , directedBridgeComponents
  , symmetricBridgeComponents
  , -- * Solving and inspection
    -- | A 'SolverProblem' compiles constraints, samples finite categorical
    -- choices, canonicalizes repeated constraints, infers native bounds, seeds
    -- initial values, and dispatches bounded affine hard constraints to the
    -- sampler while retaining the optimizer for nonlinear fallback.
    SolveConfig
  , NumericBackend(..)
  , defaultSolveConfig
  , withNumericBackend
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
  , pinProblemChoices
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
  , inspectedChoiceComponentCount
  , inspectedLargestChoiceComponentBranches
  , inspectedNativeBoundNames
  , inspectedBackend
  , inspectedFallbackReason
  , inspectedAffineEqualityCount
  , inspectedAffineInequalityCount
  , inspectedIgnoredSoftConstraintCount
  , Solution
  , BackendStatistics(..)
  , OptimizationStatistics(..)
  , SamplingStatistics(..)
  , VolumeBudget(..)
  , defaultVolumeBudget
  , VolumeEstimate(..)
  , SamplingStrategy(..)
  , DecisionCoverage(..)
  , SamplingProvenance(..)
  , solutionSuccess
  , solutionSeed
  , solutionEnergy
  , solutionValues
  , solutionChoices
  , solutionInspection
  , solutionBackend
  , solutionBackendStatistics
  , solutionSampling
  , solve
  , solveProblem
  , solveCompiledProblem
  , compileProblem
  , inspectConstraints
  , DesignSpaceError(..)
  , CompiledDesignSpace
  , compileDesignSpace
  , sampleDesignSpace
  , sampleDesignSpaceBatch
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
import           Solver.DesignSpace
import           Solver.Expr
import           Solver.Problem
