-- | Internal facade for symbolic view construction. Choreography, printing, and
-- compile code import this module when they need the stable view surface; more
-- specialized internals live under @LinearTrace.View.*@ and should be imported
-- directly only by sibling implementation modules.
module LinearTrace.View
  ( -- * Re-exported from LinearTrace.View.Types
    -- | View identity, labels, tags, and content payloads.
    ViewId(..)
  , viewIdInt
  , ViewRef(..)
  , viewRefId
  , viewRefInt
  , viewRefFromId
  , ViewLabel(..)
  , ViewTagValue(..)
  , ViewTags(..)
  , emptyViewTags
  , viewTagsToList
  , ContentMode(..)
  , -- * Re-exported from LinearTrace.View.Graph
    -- | Symbolic view graph, nodes, render intents, layout accessors, and
    -- stable solver variable naming helpers.
    ViewGraph
  , ViewNode(..)
  , Node(..)
  , NodeOrigin(..)
  , GeneratedMeta(..)
  , NodeStructure(..)
  , CompoundFit(..)
  , NodeChild(..)
  , NodeVarRoot(..)
  , ViewStep(..)
  , RenderIntent(..)
  , LayoutAttr(..)
  , AnyTraceNode(..)
  , AnyLayoutView(..)
  , defaultNodeKey
  , styleForRef
  , mapNodeStyleExprLeaves
  , solvedNodeExprs
  , traceNodeTags
  , generatedNodeMeta
  , nodeChildFromTraceNode
  , viewTraceNodes
  , traceNodeRoot
  , generatedNodeRoot
  , generatedNodeId
  , styleForNodeRoot
  , nodeVarName
  , nodeVar
  , viewNodes
  , viewSteps
  , viewConstraints
  , viewChoiceConstraints
  , viewRenderFrames
  , -- * Re-exported from LinearTrace.View.Build
    -- | View-output accumulation and final graph construction helpers.
    ViewOutput(..)
  , emptyViewOutput
  , appendViewOutput
  , flushViewOutput
  , renderIntentOutput
  , mergeInitialRenderIntents
  , withImplicitInitialFrame
  , patchedNodeOutput
  , finalizeViewGraph
  , -- * Re-exported from LinearTrace.View.Style
    -- | Public symbolic node style and style choice domains needed by the DSL.
    -- Concrete style lowering is deliberately kept at the compile boundary.
    NodeStyle
  , FontFamily(..)
  , FontWeight(..)
  , FontStyle(..)
  , TextAlign(..)
  , BorderStyle(..)
  , WhiteSpace(..)
  , -- * Re-exported from LinearTrace.View.Primitives
    -- | Solver-backed expression aliases and geometry/colour primitives used by
    -- the view DSL.
    Bounds(..)
  , BoundsExpr
  , Hsl(..)
  , Free
  , Layout
  , Unit
  , Angle
  , FreeExpr
  , LayoutExpr
  , UnitExpr
  , AngleExpr
  , ColorExpr
  , global
  , num
  , absExpr
  , -- * Re-exported from LinearTrace.View.Solve
    -- | Tuned solve entrypoint used by choreography.
    solveCSPWithSeed
  , -- * Re-exported from Solver
    -- | Solver expression, constraint, and seed types surfaced by the view
    -- facade.
    Expr
  , Constraint
  , RandomSeed(..)
  ) where

import           LinearTrace.View.Build
import           LinearTrace.View.Graph
import           LinearTrace.View.Primitives
import           LinearTrace.View.Solve
import           LinearTrace.View.Style      hiding (mapNodeStyleExprLeaves)
import           LinearTrace.View.Types
import           Solver                      (Constraint, Expr, RandomSeed (..))
