{-# LANGUAGE DataKinds              #-}
{-# LANGUAGE FlexibleContexts       #-}
{-# LANGUAGE FlexibleInstances      #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE GADTs                  #-}
{-# LANGUAGE LinearTypes            #-}
{-# LANGUAGE RankNTypes             #-}
{-# LANGUAGE RebindableSyntax       #-}
{-# LANGUAGE ScopedTypeVariables    #-}
{-# LANGUAGE TypeFamilies           #-}
{-# LANGUAGE TypeOperators          #-}
{-# LANGUAGE UndecidableInstances   #-}

module LinearTrace.View
  ( -- * View graph
    ViewGraph
  , ViewNode(..)
  , ViewStep(..)
  , BlockView
  , blockViewRef
  , blockViewLabel
  , mapBlockViewStyleExprLeaves
  , solvedBlockViewExprs
  , VisualExplainToken
  , ExplainedVisual
  , RenderIntent(..)
  , Visual
  , Unrendered
  , Rendered
  , Stable
  , Consumed
  , LayoutAttr(..)
  , Available
  , Taken
  , NewVisual
  , LiveVisual
  , ConsumedVisual
  , CopiedVisual
  , BoxAttrs
  , SizeAttrs
  , BoxVisual
  , SizeVisual
  , BoxDefinition
  , SizeDefinition
  , boxDefinition
  , sizeDefinition
  , ViewDefinition(..)
  , LayoutUse(..)
  , OneExpr
  , OneConstraint
  , (|>)
  , StyleDraft
  , EmptyStyleDraft
  , finalizeStyle
  , setOpacityOnce
  , setZIndexOnce
  , setFontSizeOnce
  , setRadiusOnce
  , setFillOnce
  , setStrokeOnce
  , setStrokeWidthOnce
  , setAlphaOnce
  , setFontFamilyOnce
  , setFontWeightOnce
  , setFontStyleOnce
  , setTextAlignOnce
  , setBorderStyleOnce
  , setWhiteSpaceOnce
  , setCssClassOnce
  , fresh
  , freshCopy
  , forkCopy
  , continueFrom
  , remove
  , complete
  , checkpoint
  , takeLeft
  , takeRight
  , takeWidth
  , takeCenterX
  , takeTop
  , takeBottom
  , takeHeight
  , takeCenterY
  , viewNodes
  , viewSteps
  , viewConstraints
  , viewInitialVars
  , viewRenderFrames
  , -- * Styles
    Style
  , Bounds(..)
  , BoundsExpr
  , MaterializedBounds
  , Hsl(..)
  , CssText(..)
  , cssTextString
  , FontWeight(..)
  , FontStyle(..)
  , TextAlign(..)
  , BorderStyle(..)
  , WhiteSpace(..)
  , styleBounds
  , mapStyleExprLeaves
  , solvedStyleExprs
  , -- * Expressions
    Expr
  , Constraint
  , FreeExpr
  , LayoutExpr
  , UnitExpr
  , AngleExpr
  , HueExpr
  , HslExpr
  , MaterializedHsl
  , global
  , num
  , (@+@)
  , (@-@)
  , (@*@)
  , (@/@)
  , (@^@)
  , absExpr
  , (@==@)
  , (@<=@)
  , (@>=@)
  , -- * Builder
    ViewBuilder
  , ViewScript
  , VisualTraceBuilder
  , VisualTraceGraph
  , Created(..)
  , Observed(..)
  , Used(..)
  , Copied(..)
  , Replaced(..)
  , Computed(..)
  , Destroyed(..)
  , Sealed(..)
  , Unsealed(..)
  , Decided(..)
  , create
  , observe
  , use
  , copy
  , replace
  , compute
  , destroy
  , seal
  , unseal
  , decide
  , explainVisual
  , (==>)
  , explain
  , discard
  , buildGraph
  , buildCSP
  , solveCSP
  , solveCSPWithSeed
  , RandomSeed(..)
  , ensure
  , encourage
  , -- * Style accessors
    opacity
  , zIndex
  , fontSize
  , radius
  , strokeWidth
  , alpha
  , fill
  , stroke
  , -- * Materialization
    MaterializedStyle
  , MaterializedBlockView(..)
  , MaterializedViewNode(..)
  , materializedTop
  , materializedLeft
  , materializedWidth
  , materializedHeight
  , materializedClassName
  , materializedCssAttrsWith
  , materializeViewNode
  ) where

import           Control.Functor.Linear                hiding ((<$>), (<*>))
import qualified Control.Functor.Linear.Internal.State as LinearState
import           Data.Kind                             (Type)
import qualified Data.Kind                             as K
import           GHC.TypeLits                          (ErrorMessage (..), Nat,
                                                        TypeError, type (+),
                                                        type CmpNat)
import qualified LinearTrace.Core.Internal             as C
import           LinearTrace.Solver                    hiding (absExpr, num,
                                                        (@*@), (@+@), (@-@),
                                                        (@/@), (@<=@), (@==@),
                                                        (@>=@), (@^@))
import qualified LinearTrace.Solver                    as S
import           LinearTrace.View.Style
import qualified Prelude                               as P
import           Prelude.Linear
import qualified Unsafe.Coerce                         as Unsafe

--------------------------------------------------------------------------------
-- Block views
--------------------------------------------------------------------------------
data BlockView tag = BlockView
  { blockRef   :: C.BlockRef tag
  , blockLabel :: C.PayloadView
  , blockStyle :: Style
  }

instance HasBounds (BlockView tag) where
  top block = top (blockStyle block)
  left block = left (blockStyle block)
  width block = width (blockStyle block)
  height block = height (blockStyle block)

instance HasStyle (BlockView tag) where
  style = blockStyle

data ViewNode where
  BlockViewNode :: BlockView tag -> ViewNode

data ViewStep where
  ViewStep
    :: C.TraceStep -> [ViewNode] -> [Constraint] -> [[RenderIntent]] -> ViewStep

data ViewGraph = ViewGraph
  { viewNodes        :: [ViewNode]
  , viewSteps        :: [ViewStep]
  , viewConstraints  :: [Constraint]
  , viewInitialVars  :: [InitialVar]
  , viewRenderFrames :: [[RenderIntent]]
  }

--------------------------------------------------------------------------------
-- Materialized views
--------------------------------------------------------------------------------
data MaterializedBlockView tag = MaterializedBlockView
  { materializedBlockRef   :: C.BlockRef tag
  , materializedBlockLabel :: C.PayloadView
  , materializedBlockStyle :: MaterializedStyle
  }

data MaterializedViewNode where
  MaterializedBlockViewNode :: MaterializedBlockView tag -> MaterializedViewNode

materializeBlockView ::
     Solution -> BlockView tag -> Maybe (MaterializedBlockView tag)
materializeBlockView solution block =
  P.fmap
    (MaterializedBlockView (blockRef block) (blockLabel block))
    (materializeStyle solution (blockStyle block))

materializeViewNode :: Solution -> ViewNode -> Maybe MaterializedViewNode
materializeViewNode solution node =
  case node of
    BlockViewNode block ->
      P.fmap MaterializedBlockViewNode (materializeBlockView solution block)

blockViewRef :: BlockView tag -> C.BlockRef tag
blockViewRef = blockRef

blockViewLabel :: BlockView tag -> C.PayloadView
blockViewLabel = blockLabel

mapBlockViewStyleExprLeaves ::
     (forall (ty :: Type). String -> Expr ty -> a) -> BlockView tag -> [a]
mapBlockViewStyleExprLeaves f block = mapStyleExprLeaves f (blockStyle block)

solvedBlockViewExprs :: Solution -> BlockView tag -> [(String, Double)]
solvedBlockViewExprs solution block =
  solvedStyleExprs solution (blockStyle block)

--------------------------------------------------------------------------------
-- Linear view tokens
--------------------------------------------------------------------------------
data ViewToken act where
  CreatedToken :: BlockView tag -> ViewToken (C.Create tag)
  ObservedToken :: BlockView tag -> ViewToken (C.Observe tag)
  UsedToken :: BlockView tag -> ViewToken (C.Use tag)
  CopiedToken :: BlockView tag -> BlockView tag -> ViewToken (C.Copy tag)
  ReplacedToken
    :: BlockView tag
    -> BlockView tag
    -> BlockView tag
    -> ViewToken (C.Replace tag)
  ComputedToken :: BlockView tag -> ViewToken (C.Compute tag)
  DestroyedToken :: BlockView tag -> ViewToken (C.Destroy tag)
  SealedToken
    :: BlockView owner -> BlockView tag -> ViewToken (C.Seal owner tag)
  UnsealedToken
    :: BlockView owner -> BlockView tag -> ViewToken (C.Unseal owner tag)
  DecidedToken :: BlockView tag -> ViewToken (C.Decide tag)

type family ExplainedVisual act :: Type where
  ExplainedVisual (C.Create tag) = NewVisual tag
  ExplainedVisual (C.Observe tag) = LiveVisual tag
  ExplainedVisual (C.Use tag) = ConsumedVisual tag
  ExplainedVisual (C.Copy tag) = CopiedVisual tag
  ExplainedVisual (C.Replace tag) = ( ConsumedVisual tag
                                    , ConsumedVisual tag
                                    , NewVisual tag)
  ExplainedVisual (C.Compute tag) = NewVisual tag
  ExplainedVisual (C.Destroy tag) = ConsumedVisual tag
  ExplainedVisual (C.Seal owner tag) = (LiveVisual owner, LiveVisual tag)
  ExplainedVisual (C.Unseal owner tag) = (LiveVisual owner, LiveVisual tag)
  ExplainedVisual (C.Decide tag) = ConsumedVisual tag

data VisualExplainToken act where
  VisualExplainToken :: ExplainedVisual act %1 -> VisualExplainToken act

data Created tag where
  Created
    :: C.Block tag %1 -> VisualExplainToken (C.Create tag) %1 -> Created tag

data Observed tag where
  Observed
    :: C.Block tag %1 -> VisualExplainToken (C.Observe tag) %1 -> Observed tag

data Used tag where
  Used
    :: C.OneUse (C.Payload tag)
       %1 -> VisualExplainToken (C.Use tag)
       %1 -> Used tag

data Copied tag where
  Copied
    :: C.Block tag
       %1 -> C.Block tag
       %1 -> VisualExplainToken (C.Copy tag)
       %1 -> Copied tag

data Replaced tag where
  Replaced
    :: C.Block tag %1 -> VisualExplainToken (C.Replace tag) %1 -> Replaced tag

data Computed tag where
  Computed
    :: C.Block tag %1 -> VisualExplainToken (C.Compute tag) %1 -> Computed tag

data Destroyed tag where
  Destroyed :: VisualExplainToken (C.Destroy tag) %1 -> Destroyed tag

data Sealed owner tag where
  Sealed
    :: C.Block owner
       %1 -> C.Slot owner tag
       %1 -> VisualExplainToken (C.Seal owner tag)
       %1 -> Sealed owner tag

data Unsealed owner tag where
  Unsealed
    :: C.Block owner
       %1 -> C.Block tag
       %1 -> VisualExplainToken (C.Unseal owner tag)
       %1 -> Unsealed owner tag

data Decided tag where
  DecidedTrue :: VisualExplainToken (C.Decide tag) %1 -> Decided tag
  DecidedFalse :: VisualExplainToken (C.Decide tag) %1 -> Decided tag

data RenderIntent where
  RenderFresh :: C.BlockRef tag -> RenderIntent
  RenderContinue :: C.BlockRef old -> C.BlockRef tag -> RenderIntent
  RenderFork :: C.BlockRef old -> C.BlockRef tag -> RenderIntent
  RenderRemove :: C.BlockRef tag -> RenderIntent

data Unrendered

data Rendered

data Stable

data Consumed

data Available

data Taken

data LayoutAttr
  = AttrLeft
  | AttrRight
  | AttrWidth
  | AttrCenterX
  | AttrTop
  | AttrBottom
  | AttrHeight
  | AttrCenterY

data Axis
  = XAxis
  | YAxis

type family AttrRank (attr :: LayoutAttr) :: Nat where
  AttrRank AttrLeft = 0
  AttrRank AttrRight = 1
  AttrRank AttrWidth = 2
  AttrRank AttrCenterX = 3
  AttrRank AttrTop = 4
  AttrRank AttrBottom = 5
  AttrRank AttrHeight = 6
  AttrRank AttrCenterY = 7

type family Insert (attr :: LayoutAttr) (used :: [LayoutAttr]) :: [LayoutAttr] where
  Insert attr '[] = '[ attr]
  Insert attr (current : rest) = InsertByRank
    (CmpNat (AttrRank attr) (AttrRank current))
    attr
    current
    rest

type family InsertByRank (ordering :: Ordering) (attr :: LayoutAttr) (current :: LayoutAttr) (rest :: [LayoutAttr]) :: [LayoutAttr] where
  InsertByRank 'LT attr current rest = attr : current : rest
  InsertByRank 'EQ attr current rest = current : rest
  InsertByRank 'GT attr current rest = current : Insert attr rest

type family AttrEq (lhs :: LayoutAttr) (rhs :: LayoutAttr) :: Bool where
  AttrEq AttrLeft AttrLeft = 'True
  AttrEq AttrRight AttrRight = 'True
  AttrEq AttrWidth AttrWidth = 'True
  AttrEq AttrCenterX AttrCenterX = 'True
  AttrEq AttrTop AttrTop = 'True
  AttrEq AttrBottom AttrBottom = 'True
  AttrEq AttrHeight AttrHeight = 'True
  AttrEq AttrCenterY AttrCenterY = 'True
  AttrEq _ _ = 'False

type family MemberAttr (attr :: LayoutAttr) (used :: [LayoutAttr]) :: Bool where
  MemberAttr attr '[] = 'False
  MemberAttr attr (current : rest) = MemberAttrStep
    (AttrEq attr current)
    attr
    rest

type family MemberAttrStep (found :: Bool) (attr :: LayoutAttr) (rest :: [LayoutAttr]) :: Bool where
  MemberAttrStep 'True attr rest = 'True
  MemberAttrStep 'False attr rest = MemberAttr attr rest

type family AxisOf (attr :: LayoutAttr) :: Axis where
  AxisOf AttrLeft = XAxis
  AxisOf AttrRight = XAxis
  AxisOf AttrWidth = XAxis
  AxisOf AttrCenterX = XAxis
  AxisOf AttrTop = YAxis
  AxisOf AttrBottom = YAxis
  AxisOf AttrHeight = YAxis
  AxisOf AttrCenterY = YAxis

type family AxisEq (lhs :: Axis) (rhs :: Axis) :: Bool where
  AxisEq XAxis XAxis = 'True
  AxisEq YAxis YAxis = 'True
  AxisEq _ _ = 'False

type family AxisCount (axis :: Axis) (used :: [LayoutAttr]) :: Nat where
  AxisCount axis '[] = 0
  AxisCount axis (attr : rest) = AxisCountStep
    (AxisEq axis (AxisOf attr))
    axis
    rest

type family AxisCountStep (matches :: Bool) (axis :: Axis) (rest :: [LayoutAttr]) :: Nat where
  AxisCountStep 'True axis rest = 1 + AxisCount axis rest
  AxisCountStep 'False axis rest = AxisCount axis rest

type family CanTakeAttr (attr :: LayoutAttr) (used :: [LayoutAttr]) :: K.Constraint where
  CanTakeAttr attr used = CheckUnusedAttr (MemberAttr attr used) attr used

type family CheckUnusedAttr (alreadyUsed :: Bool) (attr :: LayoutAttr) (used :: [LayoutAttr]) :: K.Constraint where
  CheckUnusedAttr 'True attr used = TypeError
    ('Text "Layout attribute " :<>: 'ShowType attr :<>: 'Text
       " has already been used for this visual.")
  CheckUnusedAttr 'False attr used = CheckAxisRoom
    (CmpNat (AxisCount (AxisOf attr) used) 2)
    attr

type family CheckAxisRoom (ordering :: Ordering) (attr :: LayoutAttr) :: K.Constraint where
  CheckAxisRoom 'LT attr = ()
  CheckAxisRoom 'EQ attr = TypeError
    ('Text "Cannot use layout attribute " :<>: 'ShowType attr :<>: 'Text
       ": this visual already has two attributes on that axis.")
  CheckAxisRoom 'GT attr = TypeError
    ('Text "Cannot use layout attribute " :<>: 'ShowType attr :<>: 'Text
       ": this visual already has more than two attributes on that axis.")

data Visual state lifecycle (used :: [LayoutAttr]) tag where
  Visual :: BlockView tag -> Visual state lifecycle used tag

type NewVisual tag = Visual Unrendered Stable '[] tag

type LiveVisual tag = Visual Rendered Stable '[] tag

type ConsumedVisual tag = Visual Rendered Consumed '[] tag

data CopiedVisual tag where
  CopiedVisual :: LiveVisual tag %1 -> NewVisual tag %1 -> CopiedVisual tag

type BoxAttrs = '[ AttrLeft, AttrWidth, AttrTop, AttrHeight]

type SizeAttrs = '[ AttrWidth, AttrHeight]

type BoxVisual tag = Visual Rendered Stable BoxAttrs tag

type SizeVisual tag = Visual Rendered Stable SizeAttrs tag

data StyleDraft opacity zIndex fontSize radius strokeWidth alpha fill stroke fontFamily fontWeight fontStyle textAlign borderStyle whiteSpace cssClass where
  StyleDraft
    :: Ur Style
       %1 -> StyleDraft
         opacity
         zIndex
         fontSize
         radius
         strokeWidth
         alpha
         fill
         stroke
         fontFamily
         fontWeight
         fontStyle
         textAlign
         borderStyle
         whiteSpace
         cssClass

type EmptyStyleDraft
  = StyleDraft
      Available
      Available
      Available
      Available
      Available
      Available
      Available
      Available
      Available
      Available
      Available
      Available
      Available
      Available
      Available

finalizeStyle ::
     StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
       cssClass
     %1 -> Style
finalizeStyle draft =
  case draft of
    StyleDraft (Ur style') -> style'

setOpacityOnce ::
     UnitExpr
  -> StyleDraft
       Available
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
       cssClass
     %1 -> StyleDraft
       Taken
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
       cssClass
setOpacityOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setOpacity value style'))

setZIndexOnce ::
     FreeExpr
  -> StyleDraft
       opacity
       Available
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
       cssClass
     %1 -> StyleDraft
       opacity
       Taken
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
       cssClass
setZIndexOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setZIndex value style'))

setFontSizeOnce ::
     LayoutExpr
  -> StyleDraft
       opacity
       zIndex
       Available
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
       cssClass
     %1 -> StyleDraft
       opacity
       zIndex
       Taken
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
       cssClass
setFontSizeOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setFontSize value style'))

setRadiusOnce ::
     LayoutExpr
  -> StyleDraft
       opacity
       zIndex
       fontSize
       Available
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
       cssClass
     %1 -> StyleDraft
       opacity
       zIndex
       fontSize
       Taken
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
       cssClass
setRadiusOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setRadius value style'))

setStrokeWidthOnce ::
     LayoutExpr
  -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       Available
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
       cssClass
     %1 -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       Taken
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
       cssClass
setStrokeWidthOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setStrokeWidth value style'))

setAlphaOnce ::
     UnitExpr
  -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       Available
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
       cssClass
     %1 -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       Taken
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
       cssClass
setAlphaOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setAlpha value style'))

setFillOnce ::
     HslExpr
  -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       Available
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
       cssClass
     %1 -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       Taken
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
       cssClass
setFillOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setFill value style'))

setStrokeOnce ::
     HslExpr
  -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       Available
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
       cssClass
     %1 -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       Taken
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
       cssClass
setStrokeOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setStroke value style'))

setFontFamilyOnce ::
     String
  -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       Available
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
       cssClass
     %1 -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       Taken
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
       cssClass
setFontFamilyOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setFontFamily value style'))

setFontWeightOnce ::
     FontWeight
  -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       Available
       fontStyle
       textAlign
       borderStyle
       whiteSpace
       cssClass
     %1 -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       Taken
       fontStyle
       textAlign
       borderStyle
       whiteSpace
       cssClass
setFontWeightOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setFontWeight value style'))

setFontStyleOnce ::
     FontStyle
  -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       Available
       textAlign
       borderStyle
       whiteSpace
       cssClass
     %1 -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       Taken
       textAlign
       borderStyle
       whiteSpace
       cssClass
setFontStyleOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setFontStyle value style'))

setTextAlignOnce ::
     TextAlign
  -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       Available
       borderStyle
       whiteSpace
       cssClass
     %1 -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       Taken
       borderStyle
       whiteSpace
       cssClass
setTextAlignOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setTextAlign value style'))

setBorderStyleOnce ::
     BorderStyle
  -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       Available
       whiteSpace
       cssClass
     %1 -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       Taken
       whiteSpace
       cssClass
setBorderStyleOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setBorderStyle value style'))

setWhiteSpaceOnce ::
     WhiteSpace
  -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       Available
       cssClass
     %1 -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       Taken
       cssClass
setWhiteSpaceOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setWhiteSpace value style'))

setCssClassOnce ::
     String
  -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
       Available
     %1 -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
       Taken
setCssClassOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setCssClass value style'))

data ViewDefinition tag (used :: [LayoutAttr]) where
  ViewDefinition
    :: (EmptyStyleDraft %1 -> Style)
    -> (LiveVisual tag %1 -> ViewBuilder (Visual Rendered Stable used tag))
    -> ViewDefinition tag used

type BoxDefinition tag = ViewDefinition tag BoxAttrs

type SizeDefinition tag = ViewDefinition tag SizeAttrs

boxDefinition ::
     (EmptyStyleDraft %1 -> Style)
  -> (LiveVisual tag %1 -> ViewBuilder (BoxVisual tag))
  -> BoxDefinition tag
boxDefinition = ViewDefinition

sizeDefinition ::
     (EmptyStyleDraft %1 -> Style)
  -> (LiveVisual tag %1 -> ViewBuilder (SizeVisual tag))
  -> SizeDefinition tag
sizeDefinition = ViewDefinition

data LayoutUse visual where
  LayoutUse :: visual %1 -> OneExpr Layout %1 -> LayoutUse visual

data OneExpr (ty :: Type) where
  OneExpr :: Ur (Expr ty) %1 -> OneExpr ty

data OneConstraint where
  OneConstraint :: Ur Constraint %1 -> OneConstraint

infixl 1 |>
(|>) :: a %1 -> (a %1 -> b) -> b
value |> next = next value

-- Solver expressions are immutable metadata; the linear obligation is the
-- OneExpr/OneConstraint wrapper that controls use at the View boundary.
unsafeUr :: forall a. a %1 -> Ur a
unsafeUr = Unsafe.unsafeCoerce (Ur :: a -> Ur a)

class BinaryExpr lhs rhs result | lhs rhs -> result where
  binaryExpr ::
       (forall (ty :: Type). Expr ty -> Expr ty -> Expr ty)
    -> lhs
       %1 -> rhs
       %1 -> result

instance BinaryExpr (Expr (ty :: Type)) (Expr ty) (Expr ty) where
  binaryExpr op lhs rhs =
    case unsafeUr lhs of
      Ur lhsRaw ->
        case unsafeUr rhs of
          Ur rhsRaw -> op lhsRaw rhsRaw

instance BinaryExpr (OneExpr (ty :: Type)) (Expr ty) (OneExpr ty) where
  binaryExpr op lhs rhs =
    case lhs of
      OneExpr (Ur lhsRaw) ->
        case unsafeUr rhs of
          Ur rhsRaw -> OneExpr (Ur (op lhsRaw rhsRaw))

instance BinaryExpr (Expr (ty :: Type)) (OneExpr ty) (OneExpr ty) where
  binaryExpr op lhs rhs =
    case unsafeUr lhs of
      Ur lhsRaw ->
        case rhs of
          OneExpr (Ur rhsRaw) -> OneExpr (Ur (op lhsRaw rhsRaw))

instance BinaryExpr (OneExpr (ty :: Type)) (OneExpr ty) (OneExpr ty) where
  binaryExpr op lhs rhs =
    case lhs of
      OneExpr (Ur lhsRaw) ->
        case rhs of
          OneExpr (Ur rhsRaw) -> OneExpr (Ur (op lhsRaw rhsRaw))

class RelateExpr lhs rhs where
  relateExpr ::
       (forall (ty :: Type). Expr ty -> Expr ty -> Constraint)
    -> lhs
       %1 -> rhs
       %1 -> OneConstraint

instance RelateExpr (Expr (ty :: Type)) (Expr ty) where
  relateExpr op lhs rhs =
    case unsafeUr lhs of
      Ur lhsRaw ->
        case unsafeUr rhs of
          Ur rhsRaw -> OneConstraint (Ur (op lhsRaw rhsRaw))

instance RelateExpr (OneExpr (ty :: Type)) (Expr ty) where
  relateExpr op lhs rhs =
    case lhs of
      OneExpr (Ur lhsRaw) ->
        case unsafeUr rhs of
          Ur rhsRaw -> OneConstraint (Ur (op lhsRaw rhsRaw))

instance RelateExpr (Expr (ty :: Type)) (OneExpr ty) where
  relateExpr op lhs rhs =
    case unsafeUr lhs of
      Ur lhsRaw ->
        case rhs of
          OneExpr (Ur rhsRaw) -> OneConstraint (Ur (op lhsRaw rhsRaw))

instance RelateExpr (OneExpr (ty :: Type)) (OneExpr ty) where
  relateExpr op lhs rhs =
    case lhs of
      OneExpr (Ur lhsRaw) ->
        case rhs of
          OneExpr (Ur rhsRaw) -> OneConstraint (Ur (op lhsRaw rhsRaw))

num :: SymbolicType ty => Double -> Expr ty
num = S.num

global :: SymbolicType ty => String -> Expr ty
global name = S.var ("global." ++ name)

infixl 6 @+@
infixl 6 @-@
infixl 7 @*@
infixl 7 @/@
infixr 8 @^@
infix 4 @==@
infix 4 @<=@
infix 4 @>=@
(@+@) :: BinaryExpr lhs rhs result => lhs %1 -> rhs %1 -> result
(@+@) = binaryExpr (S.@+@)

(@-@) :: BinaryExpr lhs rhs result => lhs %1 -> rhs %1 -> result
(@-@) = binaryExpr (S.@-@)

(@*@) :: BinaryExpr lhs rhs result => lhs %1 -> rhs %1 -> result
(@*@) = binaryExpr (S.@*@)

(@/@) :: BinaryExpr lhs rhs result => lhs %1 -> rhs %1 -> result
(@/@) = binaryExpr (S.@/@)

(@^@) :: BinaryExpr lhs rhs result => lhs %1 -> rhs %1 -> result
(@^@) = binaryExpr (S.@^@)

absExpr :: Expr ty -> Expr ty
absExpr = S.absExpr

(@==@) :: RelateExpr lhs rhs => lhs %1 -> rhs %1 -> OneConstraint
(@==@) = relateExpr (S.@==@)

(@<=@) :: RelateExpr lhs rhs => lhs %1 -> rhs %1 -> OneConstraint
(@<=@) = relateExpr (S.@<=@)

(@>=@) :: RelateExpr lhs rhs => lhs %1 -> rhs %1 -> OneConstraint
(@>=@) = relateExpr (flip (S.@<=@))

--------------------------------------------------------------------------------
-- Reader + writer builder
--------------------------------------------------------------------------------
data ViewEnv = ViewEnv
  { canvasWidthValue  :: Double
  , canvasHeightValue :: Double
  , canvasWidth       :: LayoutExpr
  , canvasHeight      :: LayoutExpr
  }

defaultViewEnv :: ViewEnv
defaultViewEnv =
  ViewEnv
    { canvasWidthValue = 800
    , canvasHeightValue = 600
    , canvasWidth = num 800
    , canvasHeight = num 600
    }

data ViewOutput = ViewOutput
  { emittedNodes         :: [ViewNode]
  , emittedConstraints   :: [Constraint]
  , emittedInitialVars   :: [InitialVar]
  , emittedRenderFrames  :: [[RenderIntent]]
  , pendingRenderIntents :: [RenderIntent]
  }

type family Append (lhs :: [Type]) (rhs :: [Type]) :: [Type] where
  Append '[] rhs = rhs
  Append (act : acts) rhs = act : Append acts rhs

data SomeAudit where
  SomeAudit :: C.Audit acts -> SomeAudit

emptySomeAudit :: SomeAudit
emptySomeAudit = SomeAudit C.EmptyAudit

singletonSomeAudit :: C.AuditStep act -> SomeAudit
singletonSomeAudit step = SomeAudit (step C.:> C.EmptyAudit)

appendAudit :: C.Audit lhs -> C.Audit rhs -> C.Audit (Append lhs rhs)
appendAudit lhs rhs =
  case lhs of
    C.EmptyAudit   -> rhs
    step C.:> rest -> step C.:> appendAudit rest rhs

appendSomeAudit :: SomeAudit -> SomeAudit -> SomeAudit
appendSomeAudit lhs rhs =
  case lhs of
    SomeAudit lhsAudit ->
      case rhs of
        SomeAudit rhsAudit -> SomeAudit (appendAudit lhsAudit rhsAudit)

instance Semigroup ViewOutput where
  ViewOutput nodesA constraintsA initialsA framesA pendingA <> ViewOutput nodesB constraintsB initialsB framesB pendingB =
    ViewOutput
      { emittedNodes = nodesA ++ nodesB
      , emittedConstraints = constraintsA ++ constraintsB
      , emittedInitialVars = initialsA ++ initialsB
      , emittedRenderFrames = framesA ++ framesB
      , pendingRenderIntents = pendingA ++ pendingB
      }

instance Monoid ViewOutput where
  mempty =
    ViewOutput
      { emittedNodes = []
      , emittedConstraints = []
      , emittedInitialVars = []
      , emittedRenderFrames = []
      , pendingRenderIntents = []
      }

data ViewState where
  ViewState :: Ur ViewEnv %1 -> Ur ViewOutput %1 -> ViewState

type ViewBuilder a = State ViewState a

data ViewScript acts where
  ViewScript :: ViewOutput -> ViewScript acts

data VisualTraceState where
  VisualTraceState
    :: Ur (C.TraceBuilderState ViewScript)
       %1 -> Ur SomeAudit
       %1 -> VisualTraceState

type VisualTraceBuilder a = State VisualTraceState a

type VisualTraceGraph = C.TraceGraphWith ViewScript

infixr 0 ==>
(==>) :: P.String -> ViewBuilder () %1 -> VisualTraceBuilder ()
(==>) = explain

explain :: P.String -> ViewBuilder () %1 -> VisualTraceBuilder ()
explain label script0 =
  case unsafeUr script0 of
    Ur script -> do
      audit <- takePendingAudit
      let (_result, output) =
            runViewBuilderWithOutput defaultViewEnv mempty script
      case audit of
        SomeAudit auditSteps ->
          runCoreBuilder
            (C.explainAuditWith label (ViewScript output) auditSteps)

discard :: P.String -> VisualTraceBuilder ()
discard reason = do
  audit <- takePendingAudit
  case audit of
    SomeAudit auditSteps -> runCoreBuilder (C.discardAudit reason auditSteps)

initialVisualTraceState :: VisualTraceState
initialVisualTraceState =
  VisualTraceState
    (Ur (C.TraceBuilderState (Ur 0) (Ur []) (Ur [])))
    (Ur emptySomeAudit)

buildGraph :: VisualTraceBuilder () -> VisualTraceGraph
buildGraph builder =
  let (_result, finalState) = runState builder initialVisualTraceState
      VisualTraceState (Ur coreState) _pendingAudit = finalState
      C.TraceBuilderState (Ur _nextBlockId) (Ur blocks) (Ur steps) = coreState
   in C.TraceGraph blocks steps

instance Consumable ViewState where
  consume (ViewState env output) = consume env `lseq` consume output

instance Dupable ViewState where
  dup2 (ViewState env output) =
    case dup2 env of
      (env1, env2) ->
        case dup2 output of
          (output1, output2) -> (ViewState env1 output1, ViewState env2 output2)

instance Consumable VisualTraceState where
  consume (VisualTraceState coreState pendingAudit) =
    consume coreState `lseq` consume pendingAudit

instance Dupable VisualTraceState where
  dup2 (VisualTraceState coreState pendingAudit) =
    case dup2 coreState of
      (coreState1, coreState2) ->
        case dup2 pendingAudit of
          (pendingAudit1, pendingAudit2) ->
            ( VisualTraceState coreState1 pendingAudit1
            , VisualTraceState coreState2 pendingAudit2)

runCoreBuilder :: C.TraceBuilderWith ViewScript a -> VisualTraceBuilder a
runCoreBuilder builder =
  LinearState.state
    (\(VisualTraceState (Ur coreState) pendingAudit) ->
       let (result, nextCoreState) = runState builder coreState
        in (result, VisualTraceState (Ur nextCoreState) pendingAudit))

appendPendingAudit :: C.AuditStep act -> VisualTraceBuilder ()
appendPendingAudit step = do
  VisualTraceState coreState (Ur pendingAudit) <- get
  put
    (VisualTraceState
       coreState
       (Ur (appendSomeAudit pendingAudit (singletonSomeAudit step))))

takePendingAudit :: VisualTraceBuilder SomeAudit
takePendingAudit = do
  VisualTraceState coreState (Ur pendingAudit) <- get
  put (VisualTraceState coreState (Ur emptySomeAudit))
  return pendingAudit

runViewBuilderWithOutput ::
     ViewEnv -> ViewOutput -> ViewBuilder a -> (a, ViewOutput)
runViewBuilderWithOutput env initialOutput builder =
  let (result, ViewState _ (Ur output)) =
        runState builder (ViewState (Ur env) (Ur initialOutput))
   in (result, output)

askViewEnv :: ViewBuilder (Ur ViewEnv)
askViewEnv = do
  ViewState (Ur env) output <- get
  put (ViewState (Ur env) output)
  return (Ur env)

tellOutput :: ViewOutput -> ViewBuilder ()
tellOutput newOutput = do
  ViewState env (Ur oldOutput) <- get
  put (ViewState env (Ur (oldOutput <> newOutput)))

traverseView_ :: (a -> ViewBuilder ()) -> [a] -> ViewBuilder ()
traverseView_ action values =
  case values of
    [] -> return ()
    value:rest -> do
      action value
      traverseView_ action rest

traverseMaybeView_ :: (a -> ViewBuilder ()) -> Maybe a -> ViewBuilder ()
traverseMaybeView_ action value
  {- HLINT ignore "Use forM_" -}
 =
  case value of
    Nothing -> return ()
    Just x  -> action x

ensure :: OneConstraint %1 -> ViewBuilder ()
ensure oneConstraint =
  case oneConstraint of
    OneConstraint (Ur constraint) -> ensureRaw constraint

ensureRaw :: Constraint -> ViewBuilder ()
ensureRaw constraint = tellOutput mempty {emittedConstraints = [constraint]}

encourage :: Expr ty -> ViewBuilder ()
encourage objective =
  tellOutput mempty {emittedConstraints = [S.minimize objective]}

registerInitialVar :: InitialVar -> ViewBuilder ()
registerInitialVar initial = tellOutput mempty {emittedInitialVars = [initial]}

registerInitialRange :: Expr ty -> Range -> ViewBuilder ()
registerInitialRange expr range =
  traverseMaybeView_ registerInitialVar (initialRangeFor expr range)

emitViewNode :: ViewNode -> ViewBuilder ()
emitViewNode node = tellOutput mempty {emittedNodes = [node]}

emitRenderIntent :: RenderIntent -> ViewBuilder ()
emitRenderIntent intent = tellOutput mempty {pendingRenderIntents = [intent]}

flushPendingOutput :: ViewOutput -> ViewOutput
flushPendingOutput output =
  case pendingRenderIntents output of
    [] -> output
    intents ->
      output
        { emittedRenderFrames = emittedRenderFrames output ++ [intents]
        , pendingRenderIntents = []
        }

checkpoint :: ViewBuilder ()
checkpoint = do
  ViewState env (Ur output) <- get
  put (ViewState env (Ur (flushPendingOutput output)))

--------------------------------------------------------------------------------
-- Per-block visualisation
--------------------------------------------------------------------------------
defineNewBlock ::
     forall tag used.
     ViewDefinition tag used
     %1 -> BlockView tag
  -> ViewBuilder (Visual Rendered Stable used tag)
defineNewBlock definition block0 =
  case definition of
    ViewDefinition styleDefinition viewDefinition -> do
      Ur env <- askViewEnv
      let block =
            block0
              { blockStyle =
                  styleDefinition (StyleDraft (Ur (blockStyle block0)))
              }
      emitViewNode (BlockViewNode block)
      registerInitialStyleBounds (blockStyle block)
      constrainStyle (blockStyle block)
      ensureRaw (S.num 0 S.@<=@ left block)
      ensureRaw (S.num 0 S.@<=@ top block)
      ensureRaw (right block S.@<=@ canvasWidth env)
      ensureRaw (bottom block S.@<=@ canvasHeight env)
      viewDefinition (Visual block)

--------------------------------------------------------------------------------
-- Explicit token handling
--------------------------------------------------------------------------------
explainedVisual :: ViewToken act %1 -> ExplainedVisual act
explainedVisual token =
  case token of
    CreatedToken block -> Visual block
    ObservedToken block -> Visual block
    UsedToken block -> Visual block
    CopiedToken original copy' -> CopiedVisual (Visual original) (Visual copy')
    ReplacedToken old incoming output ->
      (Visual old, Visual incoming, Visual output)
    ComputedToken block -> Visual block
    DestroyedToken block -> Visual block
    SealedToken owner child -> (Visual owner, Visual child)
    UnsealedToken owner child -> (Visual owner, Visual child)
    DecidedToken block -> Visual block

visualExplainToken ::
     C.ExplainToken act %1 -> VisualTraceBuilder (VisualExplainToken act)
visualExplainToken explainToken =
  case C.explainTokenToAuditStep explainToken of
    Ur step -> do
      appendPendingAudit step
      return (VisualExplainToken (explainedVisual (viewToken step)))

create ::
     forall tag. C.Traceable tag
  => C.Payload tag
     %1 -> VisualTraceBuilder (Created tag)
create payload =
  case unsafeUr payload of
    Ur payload' -> do
      C.Created block explainToken <- runCoreBuilder (C.create payload')
      token <- visualExplainToken explainToken
      return (Created block token)

observe ::
     forall tag. C.Traceable tag
  => C.Block tag
     %1 -> VisualTraceBuilder (Observed tag)
observe block0 =
  case unsafeUr block0 of
    Ur block0' -> do
      C.Observed block explainToken <- runCoreBuilder (C.observe block0')
      token <- visualExplainToken explainToken
      return (Observed block token)

use ::
     forall tag. C.Traceable tag
  => C.Block tag
     %1 -> VisualTraceBuilder (Used tag)
use block =
  case unsafeUr block of
    Ur block' -> do
      C.Used payload explainToken <- runCoreBuilder (C.use block')
      token <- visualExplainToken explainToken
      return (Used payload token)

copy ::
     forall tag. C.Traceable tag
  => C.Block tag
     %1 -> VisualTraceBuilder (Copied tag)
copy block =
  case unsafeUr block of
    Ur block' -> do
      C.Copied original copy' explainToken <- runCoreBuilder (C.copy block')
      token <- visualExplainToken explainToken
      return (Copied original copy' token)

replace ::
     forall tag. C.Traceable tag
  => C.Block tag
     %1 -> C.Block tag
     %1 -> VisualTraceBuilder (Replaced tag)
replace oldBlock incomingBlock =
  case unsafeUr oldBlock of
    Ur oldBlock' ->
      case unsafeUr incomingBlock of
        Ur incomingBlock' -> do
          C.Replaced output explainToken <-
            runCoreBuilder (C.replace oldBlock' incomingBlock')
          token <- visualExplainToken explainToken
          return (Replaced output token)

compute ::
     forall tag. C.Traceable tag
  => C.OneUse (C.Payload tag)
     %1 -> VisualTraceBuilder (Computed tag)
compute payload =
  case unsafeUr payload of
    Ur payload' -> do
      C.Computed block explainToken <- runCoreBuilder (C.compute payload')
      token <- visualExplainToken explainToken
      return (Computed block token)

destroy ::
     forall tag. C.Traceable tag
  => C.Block tag
     %1 -> VisualTraceBuilder (Destroyed tag)
destroy block =
  case unsafeUr block of
    Ur block' -> do
      C.Destroyed explainToken <- runCoreBuilder (C.destroy block')
      token <- visualExplainToken explainToken
      return (Destroyed token)

seal ::
     forall owner tag. (C.Traceable owner, C.Traceable tag)
  => C.Block owner
     %1 -> C.Block tag
     %1 -> VisualTraceBuilder (Sealed owner tag)
seal owner child =
  case unsafeUr owner of
    Ur owner' ->
      case unsafeUr child of
        Ur child' -> do
          C.Sealed ownerBlock childSlot explainToken <-
            runCoreBuilder (C.seal owner' child')
          token <- visualExplainToken explainToken
          return (Sealed ownerBlock childSlot token)

unseal ::
     forall owner tag. (C.Traceable owner, C.Traceable tag)
  => C.Block owner
     %1 -> C.Slot owner tag
     %1 -> VisualTraceBuilder (Unsealed owner tag)
unseal owner slot =
  case unsafeUr owner of
    Ur owner' ->
      case unsafeUr slot of
        Ur slot' -> do
          C.Unsealed ownerBlock childBlock explainToken <-
            runCoreBuilder (C.unseal owner' slot')
          token <- visualExplainToken explainToken
          return (Unsealed ownerBlock childBlock token)

decide ::
     forall tag. C.Traceable tag
  => (C.Payload tag %1 -> Bool)
  -> C.Block tag
     %1 -> VisualTraceBuilder (Decided tag)
decide predicate block =
  case unsafeUr block of
    Ur block' -> do
      decision <- runCoreBuilder (C.decide predicate block')
      case decision of
        C.DecidedTrue explainToken -> do
          token <- visualExplainToken explainToken
          return (DecidedTrue token)
        C.DecidedFalse explainToken -> do
          token <- visualExplainToken explainToken
          return (DecidedFalse token)

explainVisual :: VisualExplainToken act %1 -> ViewBuilder (ExplainedVisual act)
explainVisual token =
  case token of
    VisualExplainToken visual' -> return visual'

class ToNewVisual visual tag | visual -> tag where
  toNewVisual :: visual %1 -> ViewBuilder (NewVisual tag)

instance ToNewVisual (NewVisual tag) tag where
  toNewVisual = return

instance ToNewVisual (VisualExplainToken (C.Create tag)) tag where
  toNewVisual = explainVisual

instance ToNewVisual (VisualExplainToken (C.Compute tag)) tag where
  toNewVisual = explainVisual

class ToCopiedVisual visual tag | visual -> tag where
  toCopiedVisual :: visual %1 -> ViewBuilder (CopiedVisual tag)

instance ToCopiedVisual (CopiedVisual tag) tag where
  toCopiedVisual = return

instance ToCopiedVisual (VisualExplainToken (C.Copy tag)) tag where
  toCopiedVisual = explainVisual

class ToLiveVisual visual tag | visual -> tag where
  toLiveVisual :: visual %1 -> ViewBuilder (LiveVisual tag)

instance ToLiveVisual (LiveVisual tag) tag where
  toLiveVisual = return

instance ToLiveVisual (VisualExplainToken (C.Observe tag)) tag where
  toLiveVisual = explainVisual

class Removable visual where
  remove :: visual %1 -> ViewBuilder ()

instance Removable (Visual Rendered Consumed used tag) where
  remove visual' =
    case visual' of
      Visual block -> emitRenderIntent (RenderRemove (blockRef block))

instance Removable (VisualExplainToken (C.Use tag)) where
  remove token = do
    visual' <- explainVisual token
    remove visual'

instance Removable (VisualExplainToken (C.Destroy tag)) where
  remove token = do
    visual' <- explainVisual token
    remove visual'

instance Removable (VisualExplainToken (C.Decide tag)) where
  remove token = do
    visual' <- explainVisual token
    remove visual'

fresh ::
     forall tag used visual. ToNewVisual visual tag
  => ViewDefinition tag used
     %1 -> visual
     %1 -> ViewBuilder (Visual Rendered Stable used tag)
fresh definition visual0 = do
  visual1 <- toNewVisual visual0
  freshRaw definition visual1

freshRaw ::
     forall tag used.
     ViewDefinition tag used
     %1 -> NewVisual tag
     %1 -> ViewBuilder (Visual Rendered Stable used tag)
freshRaw definition visual =
  case visual of
    Visual block -> do
      rendered <- defineNewBlock definition block
      emitRenderIntent (RenderFresh (blockRef block))
      pure rendered

freshCopy ::
     forall tag used visual. ToCopiedVisual visual tag
  => ViewDefinition tag used
     %1 -> visual
     %1 -> ViewBuilder (LiveVisual tag, Visual Rendered Stable used tag)
freshCopy definition copied0 = do
  copied <- toCopiedVisual copied0
  freshCopyRaw definition copied

freshCopyRaw ::
     forall tag used.
     ViewDefinition tag used
     %1 -> CopiedVisual tag
     %1 -> ViewBuilder (LiveVisual tag, Visual Rendered Stable used tag)
freshCopyRaw definition copied =
  case copied of
    CopiedVisual source visual ->
      case source of
        Visual sourceBlock ->
          case visual of
            Visual block -> do
              rendered <- defineNewBlock definition block
              emitRenderIntent (RenderFresh (blockRef block))
              pure (Visual sourceBlock, rendered)

forkCopy ::
     forall tag used visual. ToCopiedVisual visual tag
  => ViewDefinition tag used
     %1 -> visual
     %1 -> ViewBuilder (LiveVisual tag, Visual Rendered Stable used tag)
forkCopy definition copied0 = do
  copied <- toCopiedVisual copied0
  forkCopyRaw definition copied

forkCopyRaw ::
     forall tag used.
     ViewDefinition tag used
     %1 -> CopiedVisual tag
     %1 -> ViewBuilder (LiveVisual tag, Visual Rendered Stable used tag)
forkCopyRaw definition copied =
  case copied of
    CopiedVisual source visual ->
      case source of
        Visual sourceBlock ->
          case visual of
            Visual block -> do
              rendered <- defineNewBlock definition block
              emitRenderIntent
                (RenderFork (blockRef sourceBlock) (blockRef block))
              pure (Visual sourceBlock, rendered)

continueFrom ::
     forall tag oldTag used source visual.
     (ToLiveVisual source oldTag, ToNewVisual visual tag)
  => ViewDefinition tag used
     %1 -> source
     %1 -> visual
     %1 -> ViewBuilder (Visual Rendered Stable used tag)
continueFrom definition source0 visual0 = do
  source <- toLiveVisual source0
  visual1 <- toNewVisual visual0
  continueFromRaw definition source visual1

continueFromRaw ::
     forall tag oldTag used.
     ViewDefinition tag used
     %1 -> LiveVisual oldTag
     %1 -> NewVisual tag
     %1 -> ViewBuilder (Visual Rendered Stable used tag)
continueFromRaw definition source visual =
  case source of
    Visual sourceBlock ->
      case visual of
        Visual block -> do
          rendered <- defineNewBlock definition block
          emitRenderIntent
            (RenderContinue (blockRef sourceBlock) (blockRef block))
          pure rendered

complete :: Visual Rendered Stable used tag %1 -> ViewBuilder ()
complete visual =
  case visual of
    Visual _ -> pure ()

takeLeft ::
     CanTakeAttr AttrLeft used
  => Visual state lifecycle used tag
     %1 -> ViewBuilder
       (LayoutUse (Visual state lifecycle (Insert AttrLeft used) tag))
takeLeft visual =
  case visual of
    Visual block -> pure (LayoutUse (Visual block) (OneExpr (Ur (left block))))

takeRight ::
     CanTakeAttr AttrRight used
  => Visual state lifecycle used tag
     %1 -> ViewBuilder
       (LayoutUse (Visual state lifecycle (Insert AttrRight used) tag))
takeRight visual =
  case visual of
    Visual block -> pure (LayoutUse (Visual block) (OneExpr (Ur (right block))))

takeWidth ::
     CanTakeAttr AttrWidth used
  => Visual state lifecycle used tag
     %1 -> ViewBuilder
       (LayoutUse (Visual state lifecycle (Insert AttrWidth used) tag))
takeWidth visual =
  case visual of
    Visual block -> pure (LayoutUse (Visual block) (OneExpr (Ur (width block))))

takeCenterX ::
     CanTakeAttr AttrCenterX used
  => Visual state lifecycle used tag
     %1 -> ViewBuilder
       (LayoutUse (Visual state lifecycle (Insert AttrCenterX used) tag))
takeCenterX visual =
  case visual of
    Visual block ->
      pure (LayoutUse (Visual block) (OneExpr (Ur (centerX block))))

takeTop ::
     CanTakeAttr AttrTop used
  => Visual state lifecycle used tag
     %1 -> ViewBuilder
       (LayoutUse (Visual state lifecycle (Insert AttrTop used) tag))
takeTop visual =
  case visual of
    Visual block -> pure (LayoutUse (Visual block) (OneExpr (Ur (top block))))

takeBottom ::
     CanTakeAttr AttrBottom used
  => Visual state lifecycle used tag
     %1 -> ViewBuilder
       (LayoutUse (Visual state lifecycle (Insert AttrBottom used) tag))
takeBottom visual =
  case visual of
    Visual block ->
      pure (LayoutUse (Visual block) (OneExpr (Ur (bottom block))))

takeHeight ::
     CanTakeAttr AttrHeight used
  => Visual state lifecycle used tag
     %1 -> ViewBuilder
       (LayoutUse (Visual state lifecycle (Insert AttrHeight used) tag))
takeHeight visual =
  case visual of
    Visual block ->
      pure (LayoutUse (Visual block) (OneExpr (Ur (height block))))

takeCenterY ::
     CanTakeAttr AttrCenterY used
  => Visual state lifecycle used tag
     %1 -> ViewBuilder
       (LayoutUse (Visual state lifecycle (Insert AttrCenterY used) tag))
takeCenterY visual =
  case visual of
    Visual block ->
      pure (LayoutUse (Visual block) (OneExpr (Ur (centerY block))))

--------------------------------------------------------------------------------
-- Build a view graph
--------------------------------------------------------------------------------
buildCSP :: VisualTraceGraph -> ViewGraph
buildCSP (C.TraceGraph _blocks steps) =
  let stepsOutput = viewTraceSteps steps
      viewSteps' = builtSteps stepsOutput
      nodes = builtNodes stepsOutput
      constraints = builtConstraints stepsOutput
      initialVars = builtInitialVars stepsOutput
      renderFrames = builtRenderFrames stepsOutput
   in ViewGraph
        { viewNodes = nodes
        , viewSteps = viewSteps'
        , viewConstraints = constraints
        , viewInitialVars = initialVars
        , viewRenderFrames = renderFrames
        }

solveCSP :: SolveConfig -> ViewGraph -> IO Solution
solveCSP config graph =
  solveWithInitialVars config (viewInitialVars graph) (viewConstraints graph)

solveCSPWithSeed :: RandomSeed -> ViewGraph -> IO Solution
solveCSPWithSeed seed = solveCSP defaultSolveConfig {initialSeed = seed}

data BuiltViewStep = BuiltViewStep
  { stepView                 :: ViewStep
  , stepNodes                :: [ViewNode]
  , stepConstraints          :: [Constraint]
  , stepInitialVars          :: [InitialVar]
  , stepRenderFrames         :: [[RenderIntent]]
  , stepPendingRenderIntents :: [RenderIntent]
  }

data BuiltViewSteps = BuiltViewSteps
  { builtSteps        :: [ViewStep]
  , builtNodes        :: [ViewNode]
  , builtConstraints  :: [Constraint]
  , builtInitialVars  :: [InitialVar]
  , builtRenderFrames :: [[RenderIntent]]
  }

viewTraceSteps :: [C.TraceStepWith ViewScript] -> BuiltViewSteps
viewTraceSteps = viewTraceStepsWith viewTraceStep [] [] [] [] [] []

viewTraceStepsWith ::
     ([RenderIntent] -> record -> BuiltViewStep)
  -> [ViewStep]
  -> [ViewNode]
  -> [Constraint]
  -> [InitialVar]
  -> [[RenderIntent]]
  -> [RenderIntent]
  -> [record]
  -> BuiltViewSteps
viewTraceStepsWith buildStep steps nodes constraints initialVars renderFrames pending records =
  case records of
    [] ->
      let finalOutput =
            flushPendingOutput mempty {pendingRenderIntents = pending}
          finalFrames = renderFrames ++ emittedRenderFrames finalOutput
       in BuiltViewSteps
            { builtSteps = steps
            , builtNodes = nodes
            , builtConstraints = constraints
            , builtInitialVars = initialVars
            , builtRenderFrames = withImplicitInitialFrame finalFrames
            }
    record:rest ->
      let builtStep = buildStep pending record
       in viewTraceStepsWith
            buildStep
            (steps ++ [stepView builtStep])
            (nodes ++ stepNodes builtStep)
            (constraints ++ stepConstraints builtStep)
            (initialVars ++ stepInitialVars builtStep)
            (renderFrames ++ stepRenderFrames builtStep)
            (stepPendingRenderIntents builtStep)
            rest

withImplicitInitialFrame :: [[RenderIntent]] -> [[RenderIntent]]
withImplicitInitialFrame frames =
  case frames of
    [] -> []
    first:rest ->
      case splitLeadingFresh first of
        ([], _)          -> first : rest
        (freshes, [])    -> freshes : rest
        (freshes, tail') -> freshes : tail' : rest

splitLeadingFresh :: [RenderIntent] -> ([RenderIntent], [RenderIntent])
splitLeadingFresh intents =
  case intents of
    RenderFresh ref:rest ->
      case splitLeadingFresh rest of
        (freshes, tail') -> (RenderFresh ref : freshes, tail')
    _ -> ([], intents)

viewTraceStep :: [RenderIntent] -> C.TraceStepWith ViewScript -> BuiltViewStep
viewTraceStep pending step =
  case step of
    C.ExplainedStep label (ViewScript rawOutput) audit ->
      let plainStep = C.ExplainedStep label C.NoStepPayload audit
          output = mergeInitialRenderIntents pending rawOutput
          nodes = emittedNodes output
          constraints = emittedConstraints output
          initialVars = emittedInitialVars output
          renderFrames = emittedRenderFrames output
       in BuiltViewStep
            { stepView = ViewStep plainStep nodes constraints []
            , stepNodes = nodes
            , stepConstraints = constraints
            , stepInitialVars = initialVars
            , stepRenderFrames = renderFrames
            , stepPendingRenderIntents = pendingRenderIntents output
            }
    C.DiscardedStep reason audit ->
      BuiltViewStep
        { stepView = ViewStep (C.DiscardedStep reason audit) [] [] []
        , stepNodes = []
        , stepConstraints = []
        , stepInitialVars = []
        , stepRenderFrames = []
        , stepPendingRenderIntents = pending
        }

mergeInitialRenderIntents :: [RenderIntent] -> ViewOutput -> ViewOutput
mergeInitialRenderIntents pending output =
  case pending of
    [] -> output
    _ ->
      case emittedRenderFrames output of
        [] ->
          output {pendingRenderIntents = pending ++ pendingRenderIntents output}
        firstFrame:restFrames ->
          output {emittedRenderFrames = (pending ++ firstFrame) : restFrames}

--------------------------------------------------------------------------------
-- Core block snapshots -> base block views
--------------------------------------------------------------------------------
blockViewOfSnapshot :: C.BlockSnapshot tag -> BlockView tag
blockViewOfSnapshot (C.BlockSnapshot ref _payload payloadView) =
  BlockView
    {blockRef = ref, blockLabel = payloadView, blockStyle = styleForRef ref}

styleForRef :: C.BlockRef tag -> Style
styleForRef ref =
  styleWithBounds
    (Bounds
       (blockVar ref "top")
       (blockVar ref "left")
       (blockVar ref "width")
       (blockVar ref "height"))

blockVar :: SymbolicType ty => C.BlockRef tag -> String -> Expr ty
blockVar (C.BlockRef blockId) field = var ("B" ++ show blockId ++ "." ++ field)

viewToken :: C.AuditStep act -> ViewToken act
viewToken step =
  case step of
    C.CreateStep snapshot -> CreatedToken (blockViewOfSnapshot snapshot)
    C.ObserveStep snapshot -> ObservedToken (blockViewOfSnapshot snapshot)
    C.UseStep snapshot -> UsedToken (blockViewOfSnapshot snapshot)
    C.CopyStep original copy' ->
      CopiedToken (blockViewOfSnapshot original) (blockViewOfSnapshot copy')
    C.ReplaceStep old incoming output ->
      ReplacedToken
        (blockViewOfSnapshot old)
        (blockViewOfSnapshot incoming)
        (blockViewOfSnapshot output)
    C.ComputeStep snapshot -> ComputedToken (blockViewOfSnapshot snapshot)
    C.DestroyStep snapshot -> DestroyedToken (blockViewOfSnapshot snapshot)
    C.SealStep owner child ->
      SealedToken (blockViewOfSnapshot owner) (blockViewOfSnapshot child)
    C.UnsealStep owner child ->
      UnsealedToken (blockViewOfSnapshot owner) (blockViewOfSnapshot child)
    C.DecideStep snapshot -> DecidedToken (blockViewOfSnapshot snapshot)

--------------------------------------------------------------------------------
-- Style bounds / registration
--------------------------------------------------------------------------------
registerInitialStyleBounds :: Style -> ViewBuilder ()
registerInitialStyleBounds style' = do
  Ur env <- askViewEnv
  let canvasW = canvasWidthValue env
      canvasH = canvasHeightValue env
  registerInitialRange (left style') (Range 0 canvasW)
  registerInitialRange (top style') (Range 0 canvasH)
  registerInitialRange (width style') (Range 20 (max 20 (canvasW / 4)))
  registerInitialRange (height style') (Range 20 (max 20 (canvasH / 4)))
  traverseView_ registerInitialVar (styleInitialVars style')

constrainStyle :: Style -> ViewBuilder ()
constrainStyle style' = traverseView_ ensureRaw (styleConstraints style')
