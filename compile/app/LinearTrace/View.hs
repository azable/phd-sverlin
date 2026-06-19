{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE EmptyCase            #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE GADTs                #-}
{-# LANGUAGE LinearTypes          #-}
{-# LANGUAGE RankNTypes           #-}
{-# LANGUAGE RebindableSyntax     #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module LinearTrace.View
  ( -- * View graph
    ViewGraph
  , ViewNode(..)
  , ViewStep(..)
  , BlockView(..)
  , ViewToken(..)
  , ViewTokens(..)
  , RenderIntent(..)
  , Visual
  , Unrendered
  , Rendered
  , D0
  , D1
  , D2
  , Available
  , Taken
  , NewVisual
  , LiveVisual
  , ViewDefinition(..)
  , LayoutUse(..)
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
  , visualBlock
  , createVisual
  , observeVisual
  , inspectVisual
  , useVisual
  , copyVisual
  , replaceVisual
  , computeVisual
  , destroyVisual
  , sealVisual
  , unsealVisual
  , decideVisual
  , fresh
  , continueFrom
  , forkFrom
  , remove
  , discard
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
  , -- * Styles
    Style
  , HasStyle(..)
  , HasBounds(..)
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
  , (@==@)
  , (@<=@)
  , (@>=@)
  , -- * Builder
    ViewBuilder
  , ViewEvent(..)
  , ViewEvents
  , buildCSP
  , solveCSP
  , solveCSPWithSeed
  , RandomSeed(..)
  , ensure
  , encourage
  , -- * Layout helpers
    contains
  , between
  , unitBounds
  , angleBounds
  , hslBounds
  , above
  , below
  , beside
  , besideWithGap
  , belowWithGap
  , (|=|)
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

import           Data.Kind                   (Type)
import           Control.Functor.Linear      hiding ((<$>), (<*>))
import qualified LinearTrace.Core            as C
import           LinearTrace.Solver
import           LinearTrace.View.Style
import qualified Prelude                     as P
import           Prelude.Linear

infixl 6 |=|
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

data ViewStep events where
  ViewStep
    :: C.RecordedEvent events
    -> [ViewNode]
    -> [Constraint]
    -> [RenderIntent]
    -> ViewStep events

data ViewGraph events = ViewGraph
  { viewNodes       :: [ViewNode]
  , viewSteps       :: [ViewStep events]
  , viewConstraints :: [Constraint]
  , viewInitialVars :: [InitialVar]
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

--------------------------------------------------------------------------------
-- Linear view tokens
--------------------------------------------------------------------------------
data ViewToken act where
  CreatedToken :: BlockView tag -> ViewToken (C.Create tag)
  ObservedToken :: BlockView tag -> ViewToken (C.Observe tag)
  InspectedToken :: BlockView tag -> ViewToken (C.Inspect tag)
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

data ViewTokens acts where
  VNil :: ViewTokens '[]
  VCons :: ViewToken act %1 -> ViewTokens acts %1 -> ViewTokens (act : acts)

data RenderIntent where
  RenderFresh :: C.BlockRef tag -> RenderIntent
  RenderContinue :: C.BlockRef old -> C.BlockRef tag -> RenderIntent
  RenderFork :: C.BlockRef old -> C.BlockRef tag -> RenderIntent
  RenderRemove :: C.BlockRef tag -> RenderIntent

data Unrendered
data Rendered
data D0
data D1
data D2
data Available
data Taken

type family Inc dof where
  Inc D0 = D1
  Inc D1 = D2

class CanSpend dof

instance CanSpend D0
instance CanSpend D1

data Visual state dx l r w cx dy t b h cy tag where
  Visual :: BlockView tag -> Visual state dx l r w cx dy t b h cy tag

type NewVisual tag =
  Visual Unrendered D0 Available Available Available Available D0 Available Available Available Available tag

type LiveVisual tag =
  Visual Rendered D0 Available Available Available Available D0 Available Available Available Available tag

data StyleDraft opacity zIndex fontSize radius strokeWidth alpha fill stroke fontFamily fontWeight fontStyle textAlign borderStyle whiteSpace cssClass where
  StyleDraft
    :: Ur Style
       %1 -> StyleDraft opacity zIndex fontSize radius strokeWidth alpha fill stroke fontFamily fontWeight fontStyle textAlign borderStyle whiteSpace cssClass

type EmptyStyleDraft =
  StyleDraft Available Available Available Available Available Available Available Available Available Available Available Available Available Available Available

finalizeStyle ::
     StyleDraft opacity zIndex fontSize radius strokeWidth alpha fill stroke fontFamily fontWeight fontStyle textAlign borderStyle whiteSpace cssClass
     %1 -> Style
finalizeStyle draft =
  case draft of
    StyleDraft (Ur style') -> style'

setOpacityOnce ::
     UnitExpr
  -> StyleDraft Available zIndex fontSize radius strokeWidth alpha fill stroke fontFamily fontWeight fontStyle textAlign borderStyle whiteSpace cssClass
     %1 -> StyleDraft Taken zIndex fontSize radius strokeWidth alpha fill stroke fontFamily fontWeight fontStyle textAlign borderStyle whiteSpace cssClass
setOpacityOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setOpacity value style'))

setZIndexOnce ::
     FreeExpr
  -> StyleDraft opacity Available fontSize radius strokeWidth alpha fill stroke fontFamily fontWeight fontStyle textAlign borderStyle whiteSpace cssClass
     %1 -> StyleDraft opacity Taken fontSize radius strokeWidth alpha fill stroke fontFamily fontWeight fontStyle textAlign borderStyle whiteSpace cssClass
setZIndexOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setZIndex value style'))

setFontSizeOnce ::
     LayoutExpr
  -> StyleDraft opacity zIndex Available radius strokeWidth alpha fill stroke fontFamily fontWeight fontStyle textAlign borderStyle whiteSpace cssClass
     %1 -> StyleDraft opacity zIndex Taken radius strokeWidth alpha fill stroke fontFamily fontWeight fontStyle textAlign borderStyle whiteSpace cssClass
setFontSizeOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setFontSize value style'))

setRadiusOnce ::
     LayoutExpr
  -> StyleDraft opacity zIndex fontSize Available strokeWidth alpha fill stroke fontFamily fontWeight fontStyle textAlign borderStyle whiteSpace cssClass
     %1 -> StyleDraft opacity zIndex fontSize Taken strokeWidth alpha fill stroke fontFamily fontWeight fontStyle textAlign borderStyle whiteSpace cssClass
setRadiusOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setRadius value style'))

setStrokeWidthOnce ::
     LayoutExpr
  -> StyleDraft opacity zIndex fontSize radius Available alpha fill stroke fontFamily fontWeight fontStyle textAlign borderStyle whiteSpace cssClass
     %1 -> StyleDraft opacity zIndex fontSize radius Taken alpha fill stroke fontFamily fontWeight fontStyle textAlign borderStyle whiteSpace cssClass
setStrokeWidthOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setStrokeWidth value style'))

setAlphaOnce ::
     UnitExpr
  -> StyleDraft opacity zIndex fontSize radius strokeWidth Available fill stroke fontFamily fontWeight fontStyle textAlign borderStyle whiteSpace cssClass
     %1 -> StyleDraft opacity zIndex fontSize radius strokeWidth Taken fill stroke fontFamily fontWeight fontStyle textAlign borderStyle whiteSpace cssClass
setAlphaOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setAlpha value style'))

setFillOnce ::
     HslExpr
  -> StyleDraft opacity zIndex fontSize radius strokeWidth alpha Available stroke fontFamily fontWeight fontStyle textAlign borderStyle whiteSpace cssClass
     %1 -> StyleDraft opacity zIndex fontSize radius strokeWidth alpha Taken stroke fontFamily fontWeight fontStyle textAlign borderStyle whiteSpace cssClass
setFillOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setFill value style'))

setStrokeOnce ::
     HslExpr
  -> StyleDraft opacity zIndex fontSize radius strokeWidth alpha fill Available fontFamily fontWeight fontStyle textAlign borderStyle whiteSpace cssClass
     %1 -> StyleDraft opacity zIndex fontSize radius strokeWidth alpha fill Taken fontFamily fontWeight fontStyle textAlign borderStyle whiteSpace cssClass
setStrokeOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setStroke value style'))

setFontFamilyOnce ::
     String
  -> StyleDraft opacity zIndex fontSize radius strokeWidth alpha fill stroke Available fontWeight fontStyle textAlign borderStyle whiteSpace cssClass
     %1 -> StyleDraft opacity zIndex fontSize radius strokeWidth alpha fill stroke Taken fontWeight fontStyle textAlign borderStyle whiteSpace cssClass
setFontFamilyOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setFontFamily value style'))

setFontWeightOnce ::
     FontWeight
  -> StyleDraft opacity zIndex fontSize radius strokeWidth alpha fill stroke fontFamily Available fontStyle textAlign borderStyle whiteSpace cssClass
     %1 -> StyleDraft opacity zIndex fontSize radius strokeWidth alpha fill stroke fontFamily Taken fontStyle textAlign borderStyle whiteSpace cssClass
setFontWeightOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setFontWeight value style'))

setFontStyleOnce ::
     FontStyle
  -> StyleDraft opacity zIndex fontSize radius strokeWidth alpha fill stroke fontFamily fontWeight Available textAlign borderStyle whiteSpace cssClass
     %1 -> StyleDraft opacity zIndex fontSize radius strokeWidth alpha fill stroke fontFamily fontWeight Taken textAlign borderStyle whiteSpace cssClass
setFontStyleOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setFontStyle value style'))

setTextAlignOnce ::
     TextAlign
  -> StyleDraft opacity zIndex fontSize radius strokeWidth alpha fill stroke fontFamily fontWeight fontStyle Available borderStyle whiteSpace cssClass
     %1 -> StyleDraft opacity zIndex fontSize radius strokeWidth alpha fill stroke fontFamily fontWeight fontStyle Taken borderStyle whiteSpace cssClass
setTextAlignOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setTextAlign value style'))

setBorderStyleOnce ::
     BorderStyle
  -> StyleDraft opacity zIndex fontSize radius strokeWidth alpha fill stroke fontFamily fontWeight fontStyle textAlign Available whiteSpace cssClass
     %1 -> StyleDraft opacity zIndex fontSize radius strokeWidth alpha fill stroke fontFamily fontWeight fontStyle textAlign Taken whiteSpace cssClass
setBorderStyleOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setBorderStyle value style'))

setWhiteSpaceOnce ::
     WhiteSpace
  -> StyleDraft opacity zIndex fontSize radius strokeWidth alpha fill stroke fontFamily fontWeight fontStyle textAlign borderStyle Available cssClass
     %1 -> StyleDraft opacity zIndex fontSize radius strokeWidth alpha fill stroke fontFamily fontWeight fontStyle textAlign borderStyle Taken cssClass
setWhiteSpaceOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setWhiteSpace value style'))

setCssClassOnce ::
     String
  -> StyleDraft opacity zIndex fontSize radius strokeWidth alpha fill stroke fontFamily fontWeight fontStyle textAlign borderStyle whiteSpace Available
     %1 -> StyleDraft opacity zIndex fontSize radius strokeWidth alpha fill stroke fontFamily fontWeight fontStyle textAlign borderStyle whiteSpace Taken
setCssClassOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setCssClass value style'))

data ViewDefinition tag where
  ViewDefinition
    :: (EmptyStyleDraft %1 -> Style)
    -> (forall (events :: [Type]). BlockView tag -> ViewBuilder events ())
    -> ViewDefinition tag

data LayoutUse visual where
  LayoutUse :: visual %1 -> LayoutExpr -> LayoutUse visual

visualBlock :: Visual state dx l r w cx dy t b h cy tag -> BlockView tag
visualBlock (Visual block) = block

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

data ViewOutput events = ViewOutput
  { emittedNodes         :: [ViewNode]
  , emittedConstraints   :: [Constraint]
  , emittedInitialVars   :: [InitialVar]
  , emittedRenderIntents :: [RenderIntent]
  }

instance Semigroup (ViewOutput events) where
  ViewOutput nodesA constraintsA initialsA intentsA <> ViewOutput nodesB constraintsB initialsB intentsB =
    ViewOutput
      { emittedNodes = nodesA ++ nodesB
      , emittedConstraints = constraintsA ++ constraintsB
      , emittedInitialVars = initialsA ++ initialsB
      , emittedRenderIntents = intentsA ++ intentsB
      }

instance Monoid (ViewOutput events) where
  mempty =
    ViewOutput
      { emittedNodes = []
      , emittedConstraints = []
      , emittedInitialVars = []
      , emittedRenderIntents = []
      }

data ViewState events where
  ViewState :: Ur ViewEnv %1 -> Ur (ViewOutput events) %1 -> ViewState events

type ViewBuilder events a = State (ViewState events) a

instance Consumable (ViewState events) where
  consume (ViewState env output) =
    consume env `lseq` consume output

instance Dupable (ViewState events) where
  dup2 (ViewState env output) =
    case dup2 env of
      (env1, env2) ->
        case dup2 output of
          (output1, output2) -> (ViewState env1 output1, ViewState env2 output2)

runViewBuilder :: ViewEnv -> ViewBuilder events a -> (a, ViewOutput events)
runViewBuilder env builder =
  let (result, ViewState _ (Ur output)) =
        runState builder (ViewState (Ur env) (Ur mempty))
   in (result, output)

askViewEnv :: ViewBuilder events (Ur ViewEnv)
askViewEnv = do
  ViewState (Ur env) output <- get
  put (ViewState (Ur env) output)
  return (Ur env)

tellOutput :: ViewOutput events -> ViewBuilder events ()
tellOutput newOutput = do
  ViewState env (Ur oldOutput) <- get
  put (ViewState env (Ur (oldOutput <> newOutput)))

traverseView_ :: (a -> ViewBuilder events ()) -> [a] -> ViewBuilder events ()
traverseView_ action values =
  case values of
    [] -> return ()
    value:rest -> do
      action value
      traverseView_ action rest

traverseMaybeView_ :: (a -> ViewBuilder events ()) -> Maybe a -> ViewBuilder events ()
traverseMaybeView_ action value =
  case value of
    Nothing -> return ()
    Just x  -> action x

ensure :: Constraint -> ViewBuilder events ()
ensure constraint = tellOutput mempty {emittedConstraints = [constraint]}

encourage :: Expr ty -> ViewBuilder events ()
encourage objective = tellOutput mempty {emittedConstraints = [minimize objective]}

registerInitialVar :: InitialVar -> ViewBuilder events ()
registerInitialVar initial = tellOutput mempty {emittedInitialVars = [initial]}

registerInitialRange :: Expr ty -> Range -> ViewBuilder events ()
registerInitialRange expr range =
  traverseMaybeView_ registerInitialVar (initialRangeFor expr range)

emitViewNode :: ViewNode -> ViewBuilder events ()
emitViewNode node = tellOutput mempty {emittedNodes = [node]}

emitRenderIntent :: RenderIntent -> ViewBuilder events ()
emitRenderIntent intent = tellOutput mempty {emittedRenderIntents = [intent]}

--------------------------------------------------------------------------------
-- Constraint constructors/helpers
--------------------------------------------------------------------------------
global :: SymbolicType ty => String -> Expr ty
global name = var ("global." ++ name)

canvasBounds :: ViewBuilder events (Ur BoundsExpr)
canvasBounds = do
  Ur env <- askViewEnv
  pure (Ur (Bounds (num 0) (num 0) (canvasWidth env) (canvasHeight env)))

contains ::
     (HasBounds outer, HasBounds inner)
  => outer
  -> inner
  -> ViewBuilder events ()
contains outer inner = do
  ensure $ left outer @<=@ left inner
  ensure $ top outer @<=@ top inner
  ensure $ right inner @<=@ right outer
  ensure $ bottom inner @<=@ bottom outer

insideCanvas :: HasBounds block => block -> ViewBuilder events ()
insideCanvas block = do
  Ur canvas <- canvasBounds
  canvas `contains` block

between ::
     SymbolicType ty => Expr ty -> Expr ty -> Expr ty -> ViewBuilder events ()
between lo x hi = do
  ensure $ lo @<=@ x
  ensure $ x @<=@ hi

unitBounds :: UnitExpr -> ViewBuilder events ()
unitBounds x = between (num 0) x (num 1)

angleBounds :: AngleExpr -> ViewBuilder events ()
angleBounds angle = between (num 0) angle (num 360)

hslBounds :: HslExpr -> ViewBuilder events ()
hslBounds hsl = do
  angleBounds (hue hsl)
  unitBounds (saturation hsl)
  unitBounds (lightness hsl)

above :: (HasBounds a, HasBounds b) => a -> b -> ViewBuilder events ()
above a b = ensure $ bottom a @<=@ top b

below :: (HasBounds a, HasBounds b) => a -> b -> ViewBuilder events ()
below a b = ensure $ bottom b @<=@ top a

beside :: (HasBounds a, HasBounds b) => a -> b -> ViewBuilder events ()
beside a b = do
  ensure $ centerY a @==@ centerY b
  ensure $ right a @==@ left b

besideWithGap ::
     (HasBounds a, HasBounds b) => LayoutExpr -> a -> b -> ViewBuilder events ()
besideWithGap gap a b = do
  ensure $ centerY a @==@ centerY b
  ensure $ right a @+@ gap @==@ left b

belowWithGap ::
     (HasBounds a, HasBounds b) => LayoutExpr -> a -> b -> ViewBuilder events ()
belowWithGap gap a b = do
  ensure $ centerX a @==@ centerX b
  ensure $ bottom a @+@ gap @==@ top b

(|=|) :: (HasBounds a, HasBounds b) => a -> b -> ViewBuilder events ()
(|=|) = beside

--------------------------------------------------------------------------------
-- Per-block visualisation
--------------------------------------------------------------------------------
defineNewBlock ::
     forall tag (events :: [Type]).
     ViewDefinition tag
     %1 -> BlockView tag
  -> ViewBuilder events (Ur (BlockView tag))
defineNewBlock definition block0 =
  case definition of
    ViewDefinition styleDefinition viewDefinition -> do
      let block =
            block0
              { blockStyle =
                  styleDefinition (StyleDraft (Ur (blockStyle block0)))
              }
      emitViewNode (BlockViewNode block)
      registerInitialStyleBounds (blockStyle block)
      constrainStyle (blockStyle block)
      insideCanvas block
      viewDefinition block
      pure (Ur block)

--------------------------------------------------------------------------------
-- Explicit token handling
--------------------------------------------------------------------------------
createVisual :: ViewToken (C.Create tag) %1 -> ViewBuilder events (NewVisual tag)
createVisual token =
  case token of
    CreatedToken block -> pure (Visual block)

observeVisual :: ViewToken (C.Observe tag) %1 -> ViewBuilder events (LiveVisual tag)
observeVisual token =
  case token of
    ObservedToken block -> pure (Visual block)

inspectVisual :: ViewToken (C.Inspect tag) %1 -> ViewBuilder events (LiveVisual tag)
inspectVisual token =
  case token of
    InspectedToken block -> pure (Visual block)

useVisual :: ViewToken (C.Use tag) %1 -> ViewBuilder events (LiveVisual tag)
useVisual token =
  case token of
    UsedToken block -> pure (Visual block)

copyVisual ::
     ViewToken (C.Copy tag)
     %1 -> ViewBuilder events (LiveVisual tag, NewVisual tag)
copyVisual token =
  case token of
    CopiedToken original copy' -> pure (Visual original, Visual copy')

replaceVisual ::
     ViewToken (C.Replace tag)
     %1 -> ViewBuilder events (LiveVisual tag, LiveVisual tag, NewVisual tag)
replaceVisual token =
  case token of
    ReplacedToken old incoming output ->
      pure (Visual old, Visual incoming, Visual output)

computeVisual :: ViewToken (C.Compute tag) %1 -> ViewBuilder events (NewVisual tag)
computeVisual token =
  case token of
    ComputedToken block -> pure (Visual block)

destroyVisual :: ViewToken (C.Destroy tag) %1 -> ViewBuilder events (LiveVisual tag)
destroyVisual token =
  case token of
    DestroyedToken block -> pure (Visual block)

sealVisual ::
     ViewToken (C.Seal owner tag)
     %1 -> ViewBuilder events (LiveVisual owner, LiveVisual tag)
sealVisual token =
  case token of
    SealedToken owner child -> pure (Visual owner, Visual child)

unsealVisual ::
     ViewToken (C.Unseal owner tag)
     %1 -> ViewBuilder events (LiveVisual owner, LiveVisual tag)
unsealVisual token =
  case token of
    UnsealedToken owner child -> pure (Visual owner, Visual child)

decideVisual :: ViewToken (C.Decide tag) %1 -> ViewBuilder events (LiveVisual tag)
decideVisual token =
  case token of
    DecidedToken block -> pure (Visual block)

fresh ::
     forall tag dx l r w cx dy t b h cy (events :: [Type]).
     ViewDefinition tag
     %1 -> Visual Unrendered dx l r w cx dy t b h cy tag
     %1 -> ViewBuilder events (Visual Rendered dx l r w cx dy t b h cy tag)
fresh definition visual =
  case visual of
    Visual block -> do
      Ur renderedBlock <- defineNewBlock definition block
      emitRenderIntent (RenderFresh (blockRef block))
      pure (Visual renderedBlock)

continueFrom ::
     forall tag oldTag dx l r w cx dy t b h cy (events :: [Type]).
     ViewDefinition tag
     %1 -> LiveVisual oldTag
     %1 -> Visual Unrendered dx l r w cx dy t b h cy tag
     %1 -> ViewBuilder events (Visual Rendered dx l r w cx dy t b h cy tag)
continueFrom definition source visual =
  case source of
    Visual sourceBlock ->
      case visual of
        Visual block -> do
          Ur renderedBlock <- defineNewBlock definition block
          emitRenderIntent (RenderContinue (blockRef sourceBlock) (blockRef block))
          pure (Visual renderedBlock)

forkFrom ::
     forall tag oldTag dx l r w cx dy t b h cy (events :: [Type]).
     ViewDefinition tag
     %1 -> LiveVisual oldTag
     %1 -> Visual Unrendered dx l r w cx dy t b h cy tag
     %1 -> ViewBuilder events (LiveVisual oldTag, Visual Rendered dx l r w cx dy t b h cy tag)
forkFrom definition source visual =
  case source of
    Visual sourceBlock ->
      case visual of
        Visual block -> do
          Ur renderedBlock <- defineNewBlock definition block
          emitRenderIntent (RenderFork (blockRef sourceBlock) (blockRef block))
          pure (Visual sourceBlock, Visual renderedBlock)

remove :: Visual Rendered dx l r w cx dy t b h cy tag %1 -> ViewBuilder events ()
remove visual =
  case visual of
    Visual block -> emitRenderIntent (RenderRemove (blockRef block))

discard :: Visual Rendered dx l r w cx dy t b h cy tag %1 -> ViewBuilder events ()
discard visual =
  case visual of
    Visual _ -> pure ()

takeLeft ::
     CanSpend dx
  => Visual state dx Available r w cx dy t b h cy tag
     %1 -> LayoutUse (Visual state (Inc dx) Taken r w cx dy t b h cy tag)
takeLeft visual =
  case visual of
    Visual block -> LayoutUse (Visual block) (left block)

takeRight ::
     CanSpend dx
  => Visual state dx l Available w cx dy t b h cy tag
     %1 -> LayoutUse (Visual state (Inc dx) l Taken w cx dy t b h cy tag)
takeRight visual =
  case visual of
    Visual block -> LayoutUse (Visual block) (right block)

takeWidth ::
     CanSpend dx
  => Visual state dx l r Available cx dy t b h cy tag
     %1 -> LayoutUse (Visual state (Inc dx) l r Taken cx dy t b h cy tag)
takeWidth visual =
  case visual of
    Visual block -> LayoutUse (Visual block) (width block)

takeCenterX ::
     CanSpend dx
  => Visual state dx l r w Available dy t b h cy tag
     %1 -> LayoutUse (Visual state (Inc dx) l r w Taken dy t b h cy tag)
takeCenterX visual =
  case visual of
    Visual block -> LayoutUse (Visual block) (centerX block)

takeTop ::
     CanSpend dy
  => Visual state dx l r w cx dy Available b h cy tag
     %1 -> LayoutUse (Visual state dx l r w cx (Inc dy) Taken b h cy tag)
takeTop visual =
  case visual of
    Visual block -> LayoutUse (Visual block) (top block)

takeBottom ::
     CanSpend dy
  => Visual state dx l r w cx dy t Available h cy tag
     %1 -> LayoutUse (Visual state dx l r w cx (Inc dy) t Taken h cy tag)
takeBottom visual =
  case visual of
    Visual block -> LayoutUse (Visual block) (bottom block)

takeHeight ::
     CanSpend dy
  => Visual state dx l r w cx dy t b Available cy tag
     %1 -> LayoutUse (Visual state dx l r w cx (Inc dy) t b Taken cy tag)
takeHeight visual =
  case visual of
    Visual block -> LayoutUse (Visual block) (height block)

takeCenterY ::
     CanSpend dy
  => Visual state dx l r w cx dy t b h Available tag
     %1 -> LayoutUse (Visual state dx l r w cx (Inc dy) t b h Taken tag)
takeCenterY visual =
  case visual of
    Visual block -> LayoutUse (Visual block) (centerY block)

--------------------------------------------------------------------------------
-- Per-event visualisation
--------------------------------------------------------------------------------
class ViewEvent event where
  viewEvent ::
       forall (events :: [Type]).
       event
    -> ViewTokens (C.Actions event)
       %1 -> ViewBuilder events ()

class ViewEvents (choices :: [Type]) where
  viewUnion ::
       forall (acts :: [Type]) (events :: [Type]).
       C.EventChoice choices acts
    -> ViewTokens acts
       %1 -> ViewBuilder events ()

instance ViewEvents '[] where
  viewUnion union _tokens = case union of {}

instance (ViewEvent event, ViewEvents rest) => ViewEvents (event : rest) where
  viewUnion union audit =
    case union of
      C.Here event -> viewEvent event audit
      C.There rest -> viewUnion rest audit

--------------------------------------------------------------------------------
-- Build a view graph
--------------------------------------------------------------------------------
buildCSP :: ViewEvents events => C.TraceGraph events -> ViewGraph events
buildCSP graph@(C.TraceGraph _blocks events) =
  let env = buildViewEnv graph
      stepOutputs = P.map (viewRecordedEvent env) events
      viewSteps' = P.map stepView stepOutputs
      nodes = P.concatMap stepNodes stepOutputs
      constraints = P.concatMap stepConstraints stepOutputs
      initialVars = P.concatMap stepInitialVars stepOutputs
   in ViewGraph
        { viewNodes = nodes
        , viewSteps = viewSteps'
        , viewConstraints = constraints
        , viewInitialVars = initialVars
        }

solveCSP :: SolveConfig -> ViewGraph events -> IO Solution
solveCSP config graph =
  solveWithInitialVars config (viewInitialVars graph) (viewConstraints graph)

solveCSPWithSeed :: RandomSeed -> ViewGraph events -> IO Solution
solveCSPWithSeed seed = solveCSP defaultSolveConfig {initialSeed = seed}

data BuiltViewStep events = BuiltViewStep
  { stepView        :: ViewStep events
  , stepNodes       :: [ViewNode]
  , stepConstraints :: [Constraint]
  , stepInitialVars :: [InitialVar]
  }

viewRecordedEvent ::
     ViewEvents events
  => ViewEnv
  -> C.RecordedEvent events
  -> BuiltViewStep events
viewRecordedEvent env recordedEvent@(C.RecordedEvent event audit) =
  let (_result, output) = runViewBuilder env (viewUnion event (viewTokens audit))
      nodes = emittedNodes output
      constraints = emittedConstraints output
      initialVars = emittedInitialVars output
      renderIntents = emittedRenderIntents output
   in BuiltViewStep
        { stepView = ViewStep recordedEvent nodes constraints renderIntents
        , stepNodes = nodes
        , stepConstraints = constraints
        , stepInitialVars = initialVars
        }

buildViewEnv :: C.TraceGraph events -> ViewEnv
buildViewEnv _ = defaultViewEnv

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

--------------------------------------------------------------------------------
-- Core audit -> view tokens
--------------------------------------------------------------------------------
viewTokens :: C.Audit acts -> ViewTokens acts
viewTokens audit =
  case audit of
    C.EmptyAudit   -> VNil
    step C.:> rest -> VCons (viewToken step) (viewTokens rest)

viewToken :: C.AuditStep act -> ViewToken act
viewToken step =
  case step of
    C.CreateStep snapshot -> CreatedToken (blockViewOfSnapshot snapshot)
    C.ObserveStep snapshot -> ObservedToken (blockViewOfSnapshot snapshot)
    C.InspectStep snapshot -> InspectedToken (blockViewOfSnapshot snapshot)
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
registerInitialStyleBounds :: Style -> ViewBuilder events ()
registerInitialStyleBounds style' = do
  Ur env <- askViewEnv
  let canvasW = canvasWidthValue env
      canvasH = canvasHeightValue env
  registerInitialRange (left style') (Range 0 canvasW)
  registerInitialRange (top style') (Range 0 canvasH)
  registerInitialRange (width style') (Range 20 (max 20 (canvasW / 4)))
  registerInitialRange (height style') (Range 20 (max 20 (canvasH / 4)))
  traverseView_ registerInitialVar (styleInitialVars style')

constrainStyle :: Style -> ViewBuilder events ()
constrainStyle style' = traverseView_ ensure (styleConstraints style')
