{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE EmptyCase            #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE GADTs                #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module LinearTrace.Visualize
  ( -- * View graph
    ViewGraph
  , ViewNode(..)
  , ViewStep(..)
  , BlockView(..)
  , ViewAudit(..)
  , ViewAuditStep(..)
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
  , StyleValueUnit(..)
  , StyleScalarSpec(..)
  , StyleTextSpec(..)
  , StyleField(..)
  , styleBounds
  , styleFields
  , setStyleField
  , styleExprLeaves
  , StyleExprLeaf(..)
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
    MaterializedStyle(..)
  , MaterializedField(..)
  , MaterializedScalar(..)
  , MaterializedColor(..)
  , MaterializedDiscrete(..)
  , MaterializedCssField(..)
  , MaterializedCssValue(..)
  , MaterializedBlockView(..)
  , MaterializedViewNode(..)
  , materializedTop
  , materializedLeft
  , materializedWidth
  , materializedHeight
  , materializedScalarValue
  , materializedScalars
  , materializedColors
  , materializedDiscrete
  , materializedCssClass
  , materializedCssFields
  , materializeViewNode
  ) where

import           Control.Monad.Reader
import           Control.Monad.Writer.Strict
import           Data.Proxy                  (Proxy (..))
import qualified LinearTrace.Core            as C
import           LinearTrace.Solver
import           LinearTrace.Visualize.Style
import           Prelude

infixr 5 :&
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
  top = top . blockStyle
  left = left . blockStyle
  width = width . blockStyle
  height = height . blockStyle

instance HasStyle (BlockView tag) where
  style = blockStyle

data ViewNode where
  BlockViewNode :: BlockView tag -> ViewNode

data ViewStep events where
  ViewStep
    :: C.RecordedEvent events -> [ViewNode] -> [Constraint] -> ViewStep events

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
  MaterializedBlockView (blockRef block) (blockLabel block)
    <$> materializeStyle solution (blockStyle block)

materializeViewNode :: Solution -> ViewNode -> Maybe MaterializedViewNode
materializeViewNode solution node =
  case node of
    BlockViewNode block ->
      MaterializedBlockViewNode <$> materializeBlockView solution block

--------------------------------------------------------------------------------
-- View audit
--------------------------------------------------------------------------------
data ViewAuditStep act where
  VCreated :: BlockView tag -> ViewAuditStep (C.Create tag)
  VObserved :: BlockView tag -> ViewAuditStep (C.Observe tag)
  VInspected :: BlockView tag -> ViewAuditStep (C.Inspect tag)
  VUsed :: BlockView tag -> ViewAuditStep (C.Use tag)
  VCopied :: BlockView tag -> BlockView tag -> ViewAuditStep (C.Copy tag)
  VReplaced
    :: BlockView tag
    -> BlockView tag
    -> BlockView tag
    -> ViewAuditStep (C.Replace tag)
  VComputed :: BlockView tag -> ViewAuditStep (C.Compute tag)
  VDestroyed :: BlockView tag -> ViewAuditStep (C.Destroy tag)
  VSealed
    :: BlockView owner -> BlockView tag -> ViewAuditStep (C.Seal owner tag)
  VUnsealed
    :: BlockView owner -> BlockView tag -> ViewAuditStep (C.Unseal owner tag)
  VDecided :: BlockView tag -> ViewAuditStep (C.Decide tag)

data ViewAudit acts where
  VDone :: ViewAudit '[]
  (:&) :: ViewAuditStep act -> ViewAudit acts -> ViewAudit (act : acts)

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
  { emittedNodes       :: [ViewNode]
  , emittedConstraints :: [Constraint]
  , emittedInitialVars :: [InitialVar]
  }

instance Semigroup (ViewOutput events) where
  ViewOutput nodesA constraintsA initialsA <> ViewOutput nodesB constraintsB initialsB =
    ViewOutput
      { emittedNodes = nodesA ++ nodesB
      , emittedConstraints = constraintsA ++ constraintsB
      , emittedInitialVars = initialsA ++ initialsB
      }

instance Monoid (ViewOutput events) where
  mempty =
    ViewOutput
      {emittedNodes = [], emittedConstraints = [], emittedInitialVars = []}

type ViewBuilder events a = ReaderT ViewEnv (Writer (ViewOutput events)) a

ensure :: Constraint -> ViewBuilder events ()
ensure constraint = tell mempty {emittedConstraints = [constraint]}

encourage :: Expr ty -> ViewBuilder events ()
encourage objective = tell mempty {emittedConstraints = [minimize objective]}

registerInitialVar :: InitialVar -> ViewBuilder events ()
registerInitialVar initial = tell mempty {emittedInitialVars = [initial]}

registerInitialRange :: Expr ty -> Range -> ViewBuilder events ()
registerInitialRange expr range =
  case initialRangeFor expr range of
    Nothing      -> pure ()
    Just initial -> registerInitialVar initial

emitViewNode :: ViewNode -> ViewBuilder events ()
emitViewNode node = tell mempty {emittedNodes = [node]}

--------------------------------------------------------------------------------
-- Constraint constructors/helpers
--------------------------------------------------------------------------------
global :: SymbolicType ty => String -> Expr ty
global name = var ("global." ++ name)

canvasBounds :: ViewBuilder events BoundsExpr
canvasBounds = do
  env <- ask
  pure (Bounds (num 0) (num 0) (canvasWidth env) (canvasHeight env))

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
  canvas <- canvasBounds
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
-- Automatic block visualisation from audit steps
--------------------------------------------------------------------------------
class ViewAction act where
  viewAction :: ViewAuditStep act -> ViewBuilder events ()

instance ViewBlock tag => ViewAction (C.Create tag) where
  viewAction step =
    case step of
      VCreated block -> viewNewBlock block

instance ViewAction (C.Observe tag) where
  viewAction _ = pure ()

instance ViewAction (C.Inspect tag) where
  viewAction _ = pure ()

instance ViewAction (C.Use tag) where
  viewAction _ = pure ()

instance ViewBlock tag => ViewAction (C.Copy tag) where
  viewAction step =
    case step of
      VCopied _original copy' -> viewNewBlock copy'

instance ViewBlock tag => ViewAction (C.Replace tag) where
  viewAction step =
    case step of
      VReplaced _old _incoming output -> viewNewBlock output

instance ViewBlock tag => ViewAction (C.Compute tag) where
  viewAction step =
    case step of
      VComputed block -> viewNewBlock block

instance ViewAction (C.Destroy tag) where
  viewAction _ = pure ()

instance ViewAction (C.Seal owner tag) where
  viewAction _ = pure ()

instance ViewAction (C.Unseal owner tag) where
  viewAction _ = pure ()

instance ViewAction (C.Decide tag) where
  viewAction _ = pure ()

class ViewActions acts where
  viewActions :: ViewAudit acts -> ViewBuilder events ()

instance ViewActions '[] where
  viewActions VDone = pure ()

instance (ViewAction act, ViewActions acts) => ViewActions (act : acts) where
  viewActions (step :& rest) = do
    viewAction step
    viewActions rest

--------------------------------------------------------------------------------
-- Per-event visualisation
--------------------------------------------------------------------------------
class ViewEvent event where
  viewEvent :: event -> ViewAudit (C.Actions event) -> ViewBuilder events ()

class ViewEvents choices where
  viewUnion ::
       C.EventChoice choices acts -> ViewAudit acts -> ViewBuilder events ()

instance ViewEvents '[] where
  viewUnion union _ = case union of {}

instance (ViewEvent event, ViewActions (C.Actions event), ViewEvents rest) =>
         ViewEvents (event : rest) where
  viewUnion union audit =
    case union of
      C.Here event -> do
        viewActions audit
        viewEvent event audit
      C.There rest -> viewUnion rest audit

--------------------------------------------------------------------------------
-- Build a view graph
--------------------------------------------------------------------------------
buildCSP :: ViewEvents events => C.TraceGraph events -> ViewGraph events
buildCSP graph@(C.TraceGraph _blocks events) =
  let env = buildViewEnv graph
      stepOutputs = map (viewRecordedEvent env) events
      viewSteps' = map stepView stepOutputs
      nodes = concatMap stepNodes stepOutputs
      constraints = concatMap stepConstraints stepOutputs
      initialVars = concatMap stepInitialVars stepOutputs
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
  let output = execWriter (runReaderT (viewUnion event (viewAudit audit)) env)
      nodes = emittedNodes output
      constraints = emittedConstraints output
      initialVars = emittedInitialVars output
   in BuiltViewStep
        { stepView = ViewStep recordedEvent nodes constraints
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
-- Core audit -> view audit
--------------------------------------------------------------------------------
viewAudit :: C.Audit acts -> ViewAudit acts
viewAudit audit =
  case audit of
    C.EmptyAudit   -> VDone
    step C.:> rest -> viewAuditStep step :& viewAudit rest

viewAuditStep :: C.AuditStep act -> ViewAuditStep act
viewAuditStep step =
  case step of
    C.CreateStep snapshot -> VCreated (blockViewOfSnapshot snapshot)
    C.ObserveStep snapshot -> VObserved (blockViewOfSnapshot snapshot)
    C.InspectStep snapshot -> VInspected (blockViewOfSnapshot snapshot)
    C.UseStep snapshot -> VUsed (blockViewOfSnapshot snapshot)
    C.CopyStep original copy' ->
      VCopied (blockViewOfSnapshot original) (blockViewOfSnapshot copy')
    C.ReplaceStep old incoming output ->
      VReplaced
        (blockViewOfSnapshot old)
        (blockViewOfSnapshot incoming)
        (blockViewOfSnapshot output)
    C.ComputeStep snapshot -> VComputed (blockViewOfSnapshot snapshot)
    C.DestroyStep snapshot -> VDestroyed (blockViewOfSnapshot snapshot)
    C.SealStep owner child ->
      VSealed (blockViewOfSnapshot owner) (blockViewOfSnapshot child)
    C.UnsealStep owner child ->
      VUnsealed (blockViewOfSnapshot owner) (blockViewOfSnapshot child)
    C.DecideStep snapshot -> VDecided (blockViewOfSnapshot snapshot)

--------------------------------------------------------------------------------
-- Style bounds / registration
--------------------------------------------------------------------------------
registerInitialStyleBounds :: Style -> ViewBuilder events ()
registerInitialStyleBounds style' = do
  env <- ask
  let canvasW = canvasWidthValue env
      canvasH = canvasHeightValue env
  registerInitialRange (left style') (Range 0 canvasW)
  registerInitialRange (top style') (Range 0 canvasH)
  registerInitialRange (width style') (Range 20 (max 20 (canvasW / 4)))
  registerInitialRange (height style') (Range 20 (max 20 (canvasH / 4)))
  mapM_ registerInitialVar (styleInitialVars style')

constrainStyle :: Style -> ViewBuilder events ()
constrainStyle style' = mapM_ ensure (styleConstraints style')
