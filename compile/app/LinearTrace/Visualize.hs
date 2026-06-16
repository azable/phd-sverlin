{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE EmptyCase            #-}
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
  , MaterializedStyle(..)
  , MaterializedBlockView(..)
  , MaterializedViewNode(..)
  , -- * Expressions and constraints
    Expr(..)
  , Constraint(..)
  , var
  , varName
  , global
  , equals
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
  , -- * Style helpers
    topOf
  , leftOf
  , bottomOf
  , rightOf
  , widthOf
  , heightOf
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
import           LinearTrace.Solver          (Constraint (..), Expr (..),
                                              defaultSolveConfig, dividedBy,
                                              equals, minus, num, plus, squared,
                                              times, var, varName)
import qualified LinearTrace.Solver          as S
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

materializeStyle :: S.Solution -> Style -> Maybe MaterializedStyle
materializeStyle solution style =
  MaterializedStyle
    <$> S.evalExpr solution (top style)
    <*> S.evalExpr solution (left style)
    <*> S.evalExpr solution (width style)
    <*> S.evalExpr solution (height style)

materializeBlockView ::
     S.Solution -> BlockView tag -> Maybe (MaterializedBlockView tag)
materializeBlockView solution block =
  MaterializedBlockView (blockRef block) (blockLabel block)
    <$> materializeStyle solution (blockStyle block)

materializeViewNode :: S.Solution -> ViewNode -> Maybe MaterializedViewNode
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

--------------------------------------------------------------------------------
-- Per-block visualisation
--------------------------------------------------------------------------------
class C.TraceBlock tag =>
      VisualizeBlock tag
  where
  visualizeBlock :: BlockView tag -> ViewBuilder events ()

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

instance (VisualizeEvent event, VisualizeEvents rest) =>
         VisualizeEvents (event : rest) where
  visualizeUnion union audit =
    case union of
      C.Here event -> visualizeEvent event audit
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

solveCSP :: S.SolveConfig -> ViewGraph events -> IO S.Solution
solveCSP config graph = S.solve config (viewConstraints graph)

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

global :: String -> Expr
global name = var ("global." ++ name)

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

--------------------------------------------------------------------------------
-- Constraint helpers
--------------------------------------------------------------------------------
sameTop :: BlockView a -> BlockView b -> ViewBuilder events ()
sameTop a b = ensure $ equals (topOf a) (topOf b)

sameLeft :: BlockView a -> BlockView b -> ViewBuilder events ()
sameLeft a b = ensure $ equals (leftOf a) (leftOf b)

sameBottom :: BlockView a -> BlockView b -> ViewBuilder events ()
sameBottom a b = ensure $ equals (bottomOf a) (bottomOf b)

sameRight :: BlockView a -> BlockView b -> ViewBuilder events ()
sameRight a b = ensure $ equals (rightOf a) (rightOf b)

sameWidth :: BlockView a -> BlockView b -> ViewBuilder events ()
sameWidth a b = ensure $ equals (widthOf a) (widthOf b)

sameHeight :: BlockView a -> BlockView b -> ViewBuilder events ()
sameHeight a b = ensure $ equals (heightOf a) (heightOf b)

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
  ensure $ equals (rightOf a) (leftOf b)
