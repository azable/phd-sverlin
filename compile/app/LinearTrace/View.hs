{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE EmptyCase            #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE GADTs                #-}
{-# LANGUAGE LinearTypes          #-}
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
  , ViewBlock(..)
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
  , -- * Style accessors/setters
    opacity
  , zIndex
  , fontSize
  , radius
  , strokeWidth
  , alpha
  , fill
  , stroke
  , setOpacity
  , setZIndex
  , setFontSize
  , setRadius
  , setFill
  , setStroke
  , setStrokeWidth
  , setAlpha
  , setFontFamily
  , setFontWeight
  , setFontStyle
  , setTextAlign
  , setBorderStyle
  , setWhiteSpace
  , setCssClass
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

import           Data.Proxy                  (Proxy (..))
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

visualBlock :: Visual state dx l r w cx dy t b h cy tag -> BlockView tag
visualBlock (Visual block) = block

instance HasBounds (Visual state dx l r w cx dy t b h cy tag) where
  top visual = top (visualBlock visual)
  left visual = left (visualBlock visual)
  width visual = width (visualBlock visual)
  height visual = height (visualBlock visual)

instance HasStyle (Visual state dx l r w cx dy t b h cy tag) where
  style visual = style (visualBlock visual)

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
class C.Traceable tag =>
      ViewBlock tag
  where
  styleBlock :: Proxy tag -> Style -> Style
  styleBlock _ = id
  viewBlock :: BlockView tag -> ViewBuilder events ()

viewNewBlock ::
     forall tag events. ViewBlock tag
  => BlockView tag
  -> ViewBuilder events ()
viewNewBlock block0 = do
  let block =
        block0
          {blockStyle = styleBlock (Proxy :: Proxy tag) (blockStyle block0)}
  emitViewNode (BlockViewNode block)
  registerInitialStyleBounds (blockStyle block)
  constrainStyle (blockStyle block)
  insideCanvas block
  viewBlock block

--------------------------------------------------------------------------------
-- Explicit token handling
--------------------------------------------------------------------------------
createVisual :: ViewToken (C.Create tag) %1 -> ViewBuilder events (Ur (NewVisual tag))
createVisual token =
  case token of
    CreatedToken block -> pure (Ur (Visual block))

observeVisual :: ViewToken (C.Observe tag) %1 -> ViewBuilder events (Ur (LiveVisual tag))
observeVisual token =
  case token of
    ObservedToken block -> pure (Ur (Visual block))

inspectVisual :: ViewToken (C.Inspect tag) %1 -> ViewBuilder events (Ur (LiveVisual tag))
inspectVisual token =
  case token of
    InspectedToken block -> pure (Ur (Visual block))

useVisual :: ViewToken (C.Use tag) %1 -> ViewBuilder events (Ur (LiveVisual tag))
useVisual token =
  case token of
    UsedToken block -> pure (Ur (Visual block))

copyVisual ::
     ViewToken (C.Copy tag)
     %1 -> ViewBuilder events (Ur (LiveVisual tag, NewVisual tag))
copyVisual token =
  case token of
    CopiedToken original copy' -> pure (Ur (Visual original, Visual copy'))

replaceVisual ::
     ViewToken (C.Replace tag)
     %1 -> ViewBuilder events (Ur (LiveVisual tag, LiveVisual tag, NewVisual tag))
replaceVisual token =
  case token of
    ReplacedToken old incoming output ->
      pure (Ur (Visual old, Visual incoming, Visual output))

computeVisual :: ViewToken (C.Compute tag) %1 -> ViewBuilder events (Ur (NewVisual tag))
computeVisual token =
  case token of
    ComputedToken block -> pure (Ur (Visual block))

destroyVisual :: ViewToken (C.Destroy tag) %1 -> ViewBuilder events (Ur (LiveVisual tag))
destroyVisual token =
  case token of
    DestroyedToken block -> pure (Ur (Visual block))

sealVisual ::
     ViewToken (C.Seal owner tag)
     %1 -> ViewBuilder events (Ur (LiveVisual owner, LiveVisual tag))
sealVisual token =
  case token of
    SealedToken owner child -> pure (Ur (Visual owner, Visual child))

unsealVisual ::
     ViewToken (C.Unseal owner tag)
     %1 -> ViewBuilder events (Ur (LiveVisual owner, LiveVisual tag))
unsealVisual token =
  case token of
    UnsealedToken owner child -> pure (Ur (Visual owner, Visual child))

decideVisual :: ViewToken (C.Decide tag) %1 -> ViewBuilder events (Ur (LiveVisual tag))
decideVisual token =
  case token of
    DecidedToken block -> pure (Ur (Visual block))

fresh ::
     ViewBlock tag
  => Visual Unrendered dx l r w cx dy t b h cy tag
     %1 -> ViewBuilder events (Ur (Visual Rendered dx l r w cx dy t b h cy tag))
fresh visual =
  case visual of
    Visual block -> do
      viewNewBlock block
      emitRenderIntent (RenderFresh (blockRef block))
      pure (Ur (Visual block))

continueFrom ::
     ViewBlock tag
  => LiveVisual oldTag
  -> Visual Unrendered dx l r w cx dy t b h cy tag
     %1 -> ViewBuilder events (Ur (Visual Rendered dx l r w cx dy t b h cy tag))
continueFrom source visual =
  case visual of
    Visual block -> do
      viewNewBlock block
      emitRenderIntent (RenderContinue (blockRef (visualBlock source)) (blockRef block))
      pure (Ur (Visual block))

forkFrom ::
     ViewBlock tag
  => LiveVisual oldTag
  -> Visual Unrendered dx l r w cx dy t b h cy tag
     %1 -> ViewBuilder events (Ur (Visual Rendered dx l r w cx dy t b h cy tag))
forkFrom source visual =
  case visual of
    Visual block -> do
      viewNewBlock block
      emitRenderIntent (RenderFork (blockRef (visualBlock source)) (blockRef block))
      pure (Ur (Visual block))

remove :: Visual Rendered dx l r w cx dy t b h cy tag %1 -> ViewBuilder events ()
remove visual =
  case visual of
    Visual block -> emitRenderIntent (RenderRemove (blockRef block))

discard :: Visual state dx l r w cx dy t b h cy tag %1 -> ViewBuilder events ()
discard visual =
  case visual of
    Visual _ -> pure ()

takeLeft ::
     CanSpend dx
  => Visual state dx Available r w cx dy t b h cy tag
     %1 -> (Visual state (Inc dx) Taken r w cx dy t b h cy tag, LayoutExpr)
takeLeft visual =
  case visual of
    Visual block -> (Visual block, left block)

takeRight ::
     CanSpend dx
  => Visual state dx l Available w cx dy t b h cy tag
     %1 -> (Visual state (Inc dx) l Taken w cx dy t b h cy tag, LayoutExpr)
takeRight visual =
  case visual of
    Visual block -> (Visual block, right block)

takeWidth ::
     CanSpend dx
  => Visual state dx l r Available cx dy t b h cy tag
     %1 -> (Visual state (Inc dx) l r Taken cx dy t b h cy tag, LayoutExpr)
takeWidth visual =
  case visual of
    Visual block -> (Visual block, width block)

takeCenterX ::
     CanSpend dx
  => Visual state dx l r w Available dy t b h cy tag
     %1 -> (Visual state (Inc dx) l r w Taken dy t b h cy tag, LayoutExpr)
takeCenterX visual =
  case visual of
    Visual block -> (Visual block, centerX block)

takeTop ::
     CanSpend dy
  => Visual state dx l r w cx dy Available b h cy tag
     %1 -> (Visual state dx l r w cx (Inc dy) Taken b h cy tag, LayoutExpr)
takeTop visual =
  case visual of
    Visual block -> (Visual block, top block)

takeBottom ::
     CanSpend dy
  => Visual state dx l r w cx dy t Available h cy tag
     %1 -> (Visual state dx l r w cx (Inc dy) t Taken h cy tag, LayoutExpr)
takeBottom visual =
  case visual of
    Visual block -> (Visual block, bottom block)

takeHeight ::
     CanSpend dy
  => Visual state dx l r w cx dy t b Available cy tag
     %1 -> (Visual state dx l r w cx (Inc dy) t b Taken cy tag, LayoutExpr)
takeHeight visual =
  case visual of
    Visual block -> (Visual block, height block)

takeCenterY ::
     CanSpend dy
  => Visual state dx l r w cx dy t b h Available tag
     %1 -> (Visual state dx l r w cx (Inc dy) t b h Taken tag, LayoutExpr)
takeCenterY visual =
  case visual of
    Visual block -> (Visual block, centerY block)

--------------------------------------------------------------------------------
-- Per-event visualisation
--------------------------------------------------------------------------------
class ViewEvent event where
  viewEvent :: event -> ViewTokens (C.Actions event) %1 -> ViewBuilder events ()

class ViewEvents choices where
  viewUnion ::
       C.EventChoice choices acts -> ViewTokens acts %1 -> ViewBuilder events ()

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
