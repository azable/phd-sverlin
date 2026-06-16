{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE EmptyCase            #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE GADTs                #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module LinearTrace.Visualize
  ( -- * View graph
    ViewGraph(..)
  , ViewNode(..)
  , ViewStep(..)
  , BlockView(..)
  , Style(..)
  , Bounds(..)
  , MaterializedStyle(..)
  , MaterializedBlockView(..)
  , MaterializedViewNode(..)
  , -- * Expressions and constraints
    Expr(..)
  , Constraint(..)
  , var
  , varName
  , global
  , (@=@)
  , (@<@)
  , plus
  , minus
  , times
  , dividedBy
  , squared
  , num
  , -- * View audit
    ViewAuditStep(..)
  , ViewAudit(..)
  , -- * Builder
    ViewEnv(..)
  , ViewBuilder
  , VisualizeBlock(..)
  , VisualizeEvent(..)
  , VisualizeEvents(..)
  , buildCSP
  , solveCSP
  , defaultSolveConfig
  , ensure
  , encourage
  , -- * Style helpers
    topOf
  , leftOf
  , bottomOf
  , rightOf
  , widthOf
  , heightOf
  , blockBounds
  , canvasBounds
  , contains
  , sameTop
  , sameBottom
  , sameRight
  , sameLeft
  , sameWidth
  , sameHeight
  , sameBounds
  , materializeStyle
  , materializeBlockView
  , materializeViewNode
  , (|=|)
  ) where

import           Control.Monad.Reader
import           Control.Monad.Writer.Strict
import qualified LinearTrace.Core            as C
import           LinearTrace.Solver
import           Prelude

infixr 5 :&
--------------------------------------------------------------------------------
-- Block views
--------------------------------------------------------------------------------
data Style = Style
  { top    :: Expr
  , left   :: Expr
  , width  :: Expr
  , height :: Expr
  }

data Bounds = Bounds
  { boundsTop    :: Expr
  , boundsLeft   :: Expr
  , boundsRight  :: Expr
  , boundsBottom :: Expr
  }

data BlockView tag = BlockView
  { blockRef   :: C.BlockRef tag
  , blockLabel :: C.PayloadView
  , blockStyle :: Style
  }

topOf :: BlockView tag -> Expr
topOf = top . blockStyle

bottomOf :: BlockView tag -> Expr
bottomOf block = topOf block `plus` heightOf block

leftOf :: BlockView tag -> Expr
leftOf = left . blockStyle

rightOf :: BlockView tag -> Expr
rightOf block = leftOf block `plus` widthOf block

widthOf :: BlockView tag -> Expr
widthOf = width . blockStyle

heightOf :: BlockView tag -> Expr
heightOf = height . blockStyle

blockBounds :: BlockView tag -> Bounds
blockBounds block =
  Bounds
    { boundsTop = topOf block
    , boundsLeft = leftOf block
    , boundsRight = rightOf block
    , boundsBottom = bottomOf block
    }

data ViewNode where
  BlockViewNode :: BlockView tag -> ViewNode

data ViewStep events where
  ViewStep
    :: C.TraceEvent events -> [ViewNode] -> [Constraint] -> ViewStep events

data ViewGraph events = ViewGraph
  { viewNodes       :: [ViewNode]
  , viewSteps       :: [ViewStep events]
  , viewConstraints :: [Constraint]
  }

--------------------------------------------------------------------------------
-- Materialized views
--------------------------------------------------------------------------------
data MaterializedStyle = MaterializedStyle
  { materializedTop    :: Double
  , materializedLeft   :: Double
  , materializedWidth  :: Double
  , materializedHeight :: Double
  } deriving (Eq, Show)

data MaterializedBlockView tag = MaterializedBlockView
  { materializedBlockRef   :: C.BlockRef tag
  , materializedBlockLabel :: C.PayloadView
  , materializedBlockStyle :: MaterializedStyle
  }

data MaterializedViewNode where
  MaterializedBlockViewNode :: MaterializedBlockView tag -> MaterializedViewNode

materializeStyle :: Solution -> Style -> Maybe MaterializedStyle
materializeStyle solution style =
  MaterializedStyle
    <$> evalExpr solution (top style)
    <*> evalExpr solution (left style)
    <*> evalExpr solution (width style)
    <*> evalExpr solution (height style)

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
  VReplaced :: BlockView tag -> BlockView tag -> ViewAuditStep (C.Replace tag)
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
-- Reader + Writer builder
--------------------------------------------------------------------------------
data ViewEnv = ViewEnv
  { canvasWidth  :: Expr
  , canvasHeight :: Expr
  }

defaultViewEnv :: ViewEnv
defaultViewEnv = ViewEnv {canvasWidth = num 800, canvasHeight = num 600}

data ViewOutput events = ViewOutput
  { emittedNodes       :: [ViewNode]
  , emittedSteps       :: [ViewStep events]
  , emittedConstraints :: [Constraint]
  }

instance Semigroup (ViewOutput events) where
  ViewOutput nodesA stepsA constraintsA <> ViewOutput nodesB stepsB constraintsB =
    ViewOutput
      { emittedNodes = nodesA ++ nodesB
      , emittedSteps = stepsA ++ stepsB
      , emittedConstraints = constraintsA ++ constraintsB
      }

instance Monoid (ViewOutput events) where
  mempty =
    ViewOutput {emittedNodes = [], emittedSteps = [], emittedConstraints = []}

type ViewBuilder events a = ReaderT ViewEnv (Writer (ViewOutput events)) a

ensure :: Constraint -> ViewBuilder events ()
ensure constraint = tell mempty {emittedConstraints = [constraint]}

encourage :: Expr -> ViewBuilder events ()
encourage objective = tell mempty {emittedConstraints = [minimize objective]}

--------------------------------------------------------------------------------
-- Constraint constructors/helpers
--------------------------------------------------------------------------------
global :: String -> Expr
global name = var ("global." ++ name)

canvasBounds :: ViewBuilder events Bounds
canvasBounds = do
  env <- ask
  return
    Bounds
      { boundsTop = num 0
      , boundsLeft = num 0
      , boundsRight = canvasWidth env
      , boundsBottom = canvasHeight env
      }

contains :: Bounds -> Bounds -> ViewBuilder events ()
contains outer inner = do
  ensure $ boundsLeft outer @<@ boundsLeft inner
  ensure $ boundsTop outer @<@ boundsTop inner
  ensure $ boundsRight inner @<@ boundsRight outer
  ensure $ boundsBottom inner @<@ boundsBottom outer

containsCanvas :: BlockView tag -> ViewBuilder events ()
containsCanvas block = do
  canvas <- canvasBounds
  canvas `contains` blockBounds block

sameTop :: BlockView a -> BlockView b -> ViewBuilder events ()
sameTop a b = ensure $ topOf a @=@ topOf b

sameLeft :: BlockView a -> BlockView b -> ViewBuilder events ()
sameLeft a b = ensure $ leftOf a @=@ leftOf b

sameBottom :: BlockView a -> BlockView b -> ViewBuilder events ()
sameBottom a b = ensure $ bottomOf a @=@ bottomOf b

sameRight :: BlockView a -> BlockView b -> ViewBuilder events ()
sameRight a b = ensure $ rightOf a @=@ rightOf b

sameWidth :: BlockView a -> BlockView b -> ViewBuilder events ()
sameWidth a b = ensure $ widthOf a @=@ widthOf b

sameHeight :: BlockView a -> BlockView b -> ViewBuilder events ()
sameHeight a b = ensure $ heightOf a @=@ heightOf b

sameBounds :: BlockView a -> BlockView b -> ViewBuilder events ()
sameBounds a b = do
  sameTop a b
  sameLeft a b
  sameWidth a b
  sameHeight a b

-- | Adjacent blocks with the same y coordinate.
(|=|) :: BlockView a -> BlockView b -> ViewBuilder events ()
(|=|) a b = do
  sameTop a b
  ensure $ rightOf a @=@ leftOf b

--------------------------------------------------------------------------------
-- Per-block visualisation
--------------------------------------------------------------------------------
class C.TraceBlock tag =>
      VisualizeBlock tag
  where
  visualizeBlock :: BlockView tag -> ViewBuilder events ()

visualizeNewBlock ::
     VisualizeBlock tag => BlockView tag -> ViewBuilder events ()
visualizeNewBlock block = do
  containsCanvas block
  visualizeBlock block

--------------------------------------------------------------------------------
-- Automatic block visualisation from audit steps
--------------------------------------------------------------------------------
class VisualizeAuditBlock act where
  visualizeAuditBlockStep :: ViewAuditStep act -> ViewBuilder events ()

instance VisualizeBlock tag => VisualizeAuditBlock (C.Create tag) where
  visualizeAuditBlockStep step =
    case step of
      VCreated block -> visualizeNewBlock block

instance VisualizeAuditBlock (C.Observe tag) where
  visualizeAuditBlockStep _ = pure ()

instance VisualizeAuditBlock (C.Inspect tag) where
  visualizeAuditBlockStep _ = pure ()

instance VisualizeAuditBlock (C.Use tag) where
  visualizeAuditBlockStep _ = pure ()

instance VisualizeBlock tag => VisualizeAuditBlock (C.Copy tag) where
  visualizeAuditBlockStep step =
    case step of
      VCopied _original copy' -> visualizeNewBlock copy'

instance VisualizeAuditBlock (C.Replace tag) where
  visualizeAuditBlockStep _ = pure ()

instance VisualizeBlock tag => VisualizeAuditBlock (C.Compute tag) where
  visualizeAuditBlockStep step =
    case step of
      VComputed block -> visualizeNewBlock block

instance VisualizeAuditBlock (C.Destroy tag) where
  visualizeAuditBlockStep _ = pure ()

instance VisualizeAuditBlock (C.Seal owner tag) where
  visualizeAuditBlockStep _ = pure ()

instance VisualizeAuditBlock (C.Unseal owner tag) where
  visualizeAuditBlockStep _ = pure ()

instance VisualizeAuditBlock (C.Decide tag) where
  visualizeAuditBlockStep _ = pure ()

class VisualizeAuditBlocks acts where
  visualizeAuditBlocks :: ViewAudit acts -> ViewBuilder events ()

instance VisualizeAuditBlocks '[] where
  visualizeAuditBlocks VDone = pure ()

instance (VisualizeAuditBlock act, VisualizeAuditBlocks acts) =>
         VisualizeAuditBlocks (act : acts) where
  visualizeAuditBlocks (step :& rest) = do
    visualizeAuditBlockStep step
    visualizeAuditBlocks rest

--------------------------------------------------------------------------------
-- Per-event visualisation
--------------------------------------------------------------------------------
class C.TraceEventSpec event =>
      VisualizeEvent event
  where
  visualizeEvent ::
       event -> ViewAudit (C.EventActs event) -> ViewBuilder events ()

class VisualizeEvents choices where
  visualizeUnion ::
       C.EventUnion choices acts -> ViewAudit acts -> ViewBuilder events ()

instance VisualizeEvents '[] where
  visualizeUnion union _ = case union of {}

instance ( VisualizeEvent event
         , VisualizeAuditBlocks (C.EventActs event)
         , VisualizeEvents rest
         ) =>
         VisualizeEvents (event : rest) where
  visualizeUnion union audit =
    case union of
      C.Here event -> do
        visualizeAuditBlocks audit
        visualizeEvent event audit
      C.There rest -> visualizeUnion rest audit

--------------------------------------------------------------------------------
-- Build a view graph
--------------------------------------------------------------------------------
buildCSP :: VisualizeEvents events => C.TraceGraph events -> ViewGraph events
buildCSP graph@(C.TraceGraph blocks events) =
  let env = buildViewEnv graph
      staticNodes = map viewNodeOfBlock blocks
      stepOutputs = map (visualizeTraceEvent env) events
      viewSteps' = map stepView stepOutputs
      dynamicNodes = concatMap stepNodes stepOutputs
      constraints = concatMap stepConstraints stepOutputs
   in ViewGraph
        { viewNodes = staticNodes ++ dynamicNodes
        , viewSteps = viewSteps'
        , viewConstraints = constraints
        }

solveCSP :: SolveConfig -> ViewGraph events -> IO Solution
solveCSP config graph = solve config (viewConstraints graph)

data BuiltViewStep events = BuiltViewStep
  { stepView        :: ViewStep events
  , stepNodes       :: [ViewNode]
  , stepConstraints :: [Constraint]
  }

visualizeTraceEvent ::
     VisualizeEvents events
  => ViewEnv
  -> C.TraceEvent events
  -> BuiltViewStep events
visualizeTraceEvent env traceEvent@(C.TraceEvent event audit) =
  let output =
        execWriter (runReaderT (visualizeUnion event (viewAudit audit)) env)
      nodes = emittedNodes output
      constraints = emittedConstraints output
   in BuiltViewStep
        { stepView = ViewStep traceEvent nodes constraints
        , stepNodes = nodes
        , stepConstraints = constraints
        }

buildViewEnv :: C.TraceGraph events -> ViewEnv
buildViewEnv _ = defaultViewEnv

--------------------------------------------------------------------------------
-- Static block pass
--------------------------------------------------------------------------------
viewNodeOfBlock :: C.BlockRecord -> ViewNode
viewNodeOfBlock (C.BlockRecord snapshot) =
  BlockViewNode (blockViewOfSnapshot snapshot)

blockViewOfSnapshot :: C.BlockSnapshot tag -> BlockView tag
blockViewOfSnapshot (C.BlockSnapshot ref _payload payloadView) =
  BlockView
    {blockRef = ref, blockLabel = payloadView, blockStyle = styleForRef ref}

styleForRef :: C.BlockRef tag -> Style
styleForRef ref =
  Style
    { top = blockVar ref "top"
    , left = blockVar ref "left"
    , width = blockVar ref "width"
    , height = blockVar ref "height"
    }

blockVar :: C.BlockRef tag -> String -> Expr
blockVar (C.BlockRef blockId) field =
  var ("block." ++ show blockId ++ "." ++ field)

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
    C.ReplaceStep old new ->
      VReplaced (blockViewOfSnapshot old) (blockViewOfSnapshot new)
    C.ComputeStep snapshot -> VComputed (blockViewOfSnapshot snapshot)
    C.DestroyStep snapshot -> VDestroyed (blockViewOfSnapshot snapshot)
    C.SealStep owner child ->
      VSealed (blockViewOfSnapshot owner) (blockViewOfSnapshot child)
    C.UnsealStep owner child ->
      VUnsealed (blockViewOfSnapshot owner) (blockViewOfSnapshot child)
    C.DecideStep snapshot -> VDecided (blockViewOfSnapshot snapshot)
