module LinearTrace.View
  ( -- * View graph
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
  , ValueComponent
  , ValueAccess
  , StyleLayoutAttr(..)
  , StyleUnitAttr(..)
  , StyleFreeAttr(..)
  , StyleColorAttr(..)
  , HslPart(..)
  , StyleRequirement(..)
  , layoutValueAccess
  , styleLayoutValueAccess
  , styleUnitValueAccess
  , styleFreeValueAccess
  , styleColorPartValueAccess
  , valueAccessComponent
  , valueAccessRequirements
  , applyStyleRequirements
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
  , viewRenderFrames
  , -- * Styles
    Style
  , Bounds(..)
  , BoundsExpr
  , Hsl(..)
  , StyleText(..)
  , styleTextString
  , FontWeight(..)
  , FontStyle(..)
  , TextAlign(..)
  , BorderStyle(..)
  , WhiteSpace(..)
  , styleBounds
  , mapStyleExprLeaves
  , solvedStyleExprs
  , -- * Expressions
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
    ViewOutput(..)
  , emptyViewOutput
  , appendViewOutput
  , flushViewOutput
  , renderIntentOutput
  , mergeInitialRenderIntents
  , withImplicitInitialFrame
  , solveCSP
  , solveCSPWithSeed
  , RandomSeed(..)
  , -- * Style accessors
    opacity
  , zIndex
  , fontSize
  , radius
  , strokeWidth
  , alpha
  , fill
  , stroke
  ) where

import           LinearTrace.View.Access
import           LinearTrace.View.Build
import           LinearTrace.View.Graph
import           LinearTrace.View.Primitives
import           LinearTrace.View.Solve
import           LinearTrace.View.Style
import           LinearTrace.View.Types
import           Solver                      (Constraint, Expr, RandomSeed (..))
