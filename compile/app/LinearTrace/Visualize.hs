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
  , -- * Expressions and constraints
    Expr(..)
  , Constraint(..)
  , equals
  , plus
  , times
  , num
  , varName
  , -- * View audit
    ViewAuditStep(..)
  , ViewAudit(..)
  , -- * Builder
    ViewEnv(..)
  , Globals(..)
  , ViewBuilder
  , VisualizeEvent(..)
  , VisualizeEvents(..)
  , buildVisualization
  , ensure
  , -- * Style helpers
    topOf
  , leftOf
  , widthOf
  , heightOf
  , sameTop
  , sameLeft
  , placeBelow
  ) where

import           Control.Monad.Reader
import           Control.Monad.Writer.Strict
import qualified LinearTrace.Core            as C
import           Prelude

infixr 5 :&
--------------------------------------------------------------------------------
-- Symbolic layout language
--------------------------------------------------------------------------------
newtype Var =
  Var String

varName :: Var -> String
varName (Var name) = name

data Expr
  = EVar Var
  | ELit Double
  | EAdd Expr Expr
  | EMul Expr Expr

data Constraint
  = Equals Expr Expr
  | Minimize Expr

var :: String -> Expr
var = EVar . Var

num :: Double -> Expr
num = ELit

plus :: Expr -> Expr -> Expr
plus = EAdd

times :: Expr -> Expr -> Expr
times = EMul

equals :: Expr -> Expr -> Constraint
equals = Equals

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

leftOf :: BlockView tag -> Expr
leftOf = left . blockStyle

widthOf :: BlockView tag -> Expr
widthOf = width . blockStyle

heightOf :: BlockView tag -> Expr
heightOf = height . blockStyle

data ViewNode where
  BlockViewNode :: BlockView tag -> ViewNode

data ViewStep events where
  ViewStep :: C.TraceEvent events -> ViewStep events

data ViewGraph events = ViewGraph
  { viewNodes       :: [ViewNode]
  , viewSteps       :: [ViewStep events]
  , viewConstraints :: [Constraint]
  }

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
data Globals = Globals
  { globalGap       :: Expr
  , globalCellGap   :: Expr
  , globalCellWidth :: Expr
  }

data ViewEnv = ViewEnv
  { globals :: Globals
  }

defaultViewEnv :: ViewEnv
defaultViewEnv =
  ViewEnv
    { globals =
        Globals
          { globalGap = var "global.gap"
          , globalCellGap = var "global.cellGap"
          , globalCellWidth = var "global.cellWidth"
          }
    }

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

emitStep :: ViewStep events -> ViewBuilder events ()
emitStep step = tell mempty {emittedSteps = [step]}

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
buildVisualization ::
     VisualizeEvents events => C.TraceGraph events -> ViewGraph events
buildVisualization graph@(C.TraceGraph blocks events) =
  let staticNodes = map viewNodeOfBlock blocks
      output =
        execWriter
          (runReaderT (mapM_ visualizeTraceEvent events) (buildViewEnv graph))
   in ViewGraph
        { viewNodes = staticNodes ++ emittedNodes output
        , viewSteps = emittedSteps output
        , viewConstraints = emittedConstraints output
        }

buildViewEnv :: C.TraceGraph events -> ViewEnv
buildViewEnv _ = defaultViewEnv

visualizeTraceEvent ::
     VisualizeEvents events => C.TraceEvent events -> ViewBuilder events ()
visualizeTraceEvent traceEvent@(C.TraceEvent event audit) = do
  emitStep (ViewStep traceEvent)
  visualizeUnion event (viewAudit audit)

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

--------------------------------------------------------------------------------
-- Constraint helpers
--------------------------------------------------------------------------------
sameTop :: BlockView a -> BlockView b -> ViewBuilder events ()
sameTop a b = ensure $ equals (topOf a) (topOf b)

sameLeft :: BlockView a -> BlockView b -> ViewBuilder events ()
sameLeft a b = ensure $ equals (leftOf a) (leftOf b)

placeBelow :: BlockView below -> BlockView above -> ViewBuilder events ()
placeBelow below above = do
  env <- ask
  let gap = globalGap (globals env)
  ensure $ equals (topOf below) (topOf above `plus` heightOf above `plus` gap)
