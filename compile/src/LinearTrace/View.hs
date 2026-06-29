-- | Internal facade for symbolic view construction. Choreography, printing, and
-- compile code import this module when they need the stable view surface; more
-- specialized internals live under @LinearTrace.View.*@ and should be imported
-- directly only by sibling implementation modules.
module LinearTrace.View
  ( -- * View graph
    -- | View identity, graph, render-intent, and lookup types. These are
    -- produced by choreography/building and consumed by solving, printing, and
    -- materialization.
    ViewId(..)
  , viewIdInt
  , ViewRef(..)
  , viewRefId
  , viewRefInt
  , syntheticViewRef
  , ViewLabel(..)
  , ViewTagValue(..)
  , ViewTags(..)
  , emptyViewTags
  , viewTagsToList
  , ViewGraph
  , ViewNode(..)
  , ViewStep(..)
  , BlockView(..)
  , VirtualView(..)
  , blockViewRef
  , blockViewLabel
  , blockViewTags
  , blockViewNodeKey
  , blockViewPieceKey
  , defaultNodeKey
  , defaultPieceKey
  , styleForRef
  , mapBlockViewStyleExprLeaves
  , solvedBlockViewExprs
  , RenderIntent(..)
  , ContentMode(..)
  , LayoutAttr(..)
  , AnyBlockView(..)
  , AnyLayoutView(..)
  , viewNodeBlocks
  , patchedBlockOutput
  , finalizeViewGraph
  , styleForVirtualKey
  , virtualBlockId
  , viewNodes
  , viewSteps
  , viewConstraints
  , viewChoiceConstraints
  , viewRenderFrames
  , -- * Styles
    -- | Public symbolic style and primitive value names needed by the DSL.
    -- Concrete style lowering is deliberately kept in
    -- 'LinearTrace.View.Materialize'.
    Style
  , Bounds(..)
  , BoundsExpr
  , Hsl(..)
  , FontFamily(..)
  , FontWeight(..)
  , FontStyle(..)
  , TextAlign(..)
  , BorderStyle(..)
  , WhiteSpace(..)
  , -- * Expressions
    -- | Solver-backed expression aliases used by the view DSL. The underlying
    -- solver API remains available through the top-level 'Solver' facade.
    Free
  , Layout
  , Unit
  , Angle
  , Expr
  , Constraint
  , FreeExpr
  , LayoutExpr
  , UnitExpr
  , AngleExpr
  , ColorExpr
  , global
  , num
  , absExpr
  , -- * Builder
    -- | View-output accumulation and the tuned solve entrypoint used by
    -- choreography when a symbolic view graph is ready.
    ViewOutput(..)
  , emptyViewOutput
  , appendViewOutput
  , flushViewOutput
  , renderIntentOutput
  , mergeInitialRenderIntents
  , withImplicitInitialFrame
  , solveCSPWithSeed
  , RandomSeed(..)
  ) where

import           LinearTrace.View.Build
import           LinearTrace.View.Graph
import           LinearTrace.View.Primitives
import           LinearTrace.View.Solve
import           LinearTrace.View.Style
import           LinearTrace.View.Types
import           Solver                      (Constraint, Expr, RandomSeed (..))
