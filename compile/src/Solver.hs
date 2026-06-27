-- | Public API for the symbolic numeric solver used by the trace view layer.
--
-- Most callers should import this module only. The implementation modules
-- under @Solver.*@ are kept separate so the expression language, constraint
-- layer, problem compiler, and optimizer backend can be tested independently
-- without making those modules part of the public surface.
module Solver
  ( -- * Symbolic domains
    -- | Scalar domains carry typing and native range metadata for solver
    -- variables. The view DSL primarily uses 'Layout', 'Unit', and 'Angle'.
    Range(..)
  , ScalarType(..)
  , InitialBounds(..)
  , SymbolicType(..)
  , Free
  , Layout
  , Unit
  , Angle
  , -- * Expressions and vectors
    -- | Symbolic expressions form the arithmetic language lowered to the
    -- optimizer. 'RawExpr' is exposed for diagnostics and debug rendering.
    Var(..)
  , varName
  , Expr
  , exprType
  , exprRaw
  , RawExpr(..)
  , var
  , substituteExprVars
  , labelName
  , num
  , (@+@)
  , (@-@)
  , (@*@)
  , (@/@)
  , (@^@)
  , absExpr
  , minExpr
  , maxExpr
  , Vec2(..)
  , Vec3(..)
  , Vec4(..)
  , vec2
  , vec3
  , vec4
  , -- * Constraints and objectives
    -- | Hard constraints are emitted directly; wrap a constraint in 'soften'
    -- or use 'minimize' to contribute soft objective terms.
    Constraint(..)
  , ConstrainEq(..)
  , ConstrainOrd(..)
  , (@==@)
  , (@<=@)
  , (@>=@)
  , within
  , minimize
  , soften
  , flattenConstraint
  , flattenConstraints
  , -- * Multi-component relations
    -- | Components let higher layers relate structured values such as vectors
    -- and HSL colours without constructing raw solver constraints themselves.
    Component
  , ComponentRelation(..)
  , component
  , exprComponent
  , componentConstraints
  , relateComponents
  , directedBridgeComponents
  , symmetricBridgeComponents
  , -- * Solving and inspection
    -- | A 'SolverProblem' compiles constraints, infers native bounds, seeds
    -- initial values, and solves through the bounded optimizer backend.
    SolveConfig(..)
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
  , -- * Seeded randomness
    -- | Seeds make initial sampling deterministic for tests and repeatable
    -- visualization output.
    RandomSeed(..)
  , RandomSample(..)
  , randomSamplesFromSeed
  , randomUnitsFromSeed
  , -- * Result evaluation
    -- | Evaluate symbolic expressions against a solved result.
    evalExpr
  ) where

import           Solver.Constraint
import           Solver.Expr
import           Solver.Problem
