{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE DeriveFoldable       #-}
{-# LANGUAGE DeriveFunctor        #-}
{-# LANGUAGE DeriveTraversable    #-}
{-# LANGUAGE EmptyCase            #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE GADTs                #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module LinearTrace.Visualize
  ( -- * View graph
    ViewGraph(..)
  , ViewNode(..)
  , ViewStep(..)
  , BlockView(..)
  , Style(..)
  , Box(..)
  , Bounds(..)
  , Hsl(..)
  , CssText(..)
  , FontWeight(..)
  , FontStyle(..)
  , TextAlign(..)
  , BorderStyle(..)
  , WhiteSpace(..)
  , MaterializedStyle(..)
  , MaterializedBlockView(..)
  , MaterializedViewNode(..)
  , -- * Expressions, vectors, and constraints
    Expr(..)
  , Constraint(..)
  , Vec2(..)
  , Vec3(..)
  , Vec4(..)
  , vec2
  , vec3
  , vec4
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
    top
  , left
  , width
  , height
  , topOf
  , leftOf
  , bottomOf
  , rightOf
  , widthOf
  , heightOf
  , positionOf
  , sizeOf
  , blockBounds
  , canvasBounds
  , contains
  , between
  , unitBounds
  , hueBounds
  , hslBounds
  , sameTop
  , sameBottom
  , sameRight
  , sameLeft
  , sameWidth
  , sameHeight
  , sameBounds
  , sameVec2
  , sameHsl
  , withOpacity
  , withZIndex
  , withFontSize
  , withRadius
  , withFill
  , withStroke
  , withStrokeWidth
  , withAlpha
  , withFontFamily
  , withFontWeight
  , withFontStyle
  , withTextAlign
  , withBorderStyle
  , withWhiteSpace
  , withCssClass
  , materializedTop
  , materializedLeft
  , materializedWidth
  , materializedHeight
  , materializeStyle
  , materializeBlockView
  , materializeViewNode
  , (|=|)
  ) where

import           Control.Monad.Reader
import           Control.Monad.Writer.Strict
import           Data.Proxy                  (Proxy (..))
import qualified LinearTrace.Core            as C
import           LinearTrace.Solver
import           Prelude

infixr 5 :&
--------------------------------------------------------------------------------
-- Block views
--------------------------------------------------------------------------------
data Box a = Box
  { boxTop    :: a
  , boxLeft   :: a
  , boxWidth  :: a
  , boxHeight :: a
  } deriving (Eq, Show, Functor, Foldable, Traversable)

data Hsl a = Hsl
  { hue        :: a
  , saturation :: a
  , lightness  :: a
  } deriving (Eq, Show, Functor, Foldable, Traversable)

newtype CssText =
  CssText String
  deriving (Eq, Show)

data FontWeight
  = FontWeightNormal
  | FontWeightBold
  | FontWeightBolder
  | FontWeightLighter
  | FontWeightNumber Int
  deriving (Eq, Show)

data FontStyle
  = FontStyleNormal
  | FontStyleItalic
  | FontStyleOblique
  deriving (Eq, Show)

data TextAlign
  = TextAlignLeft
  | TextAlignCenter
  | TextAlignRight
  | TextAlignJustify
  deriving (Eq, Show)

data BorderStyle
  = BorderNone
  | BorderSolid
  | BorderDashed
  | BorderDotted
  | BorderDouble
  deriving (Eq, Show)

data WhiteSpace
  = WhiteSpaceNormal
  | WhiteSpaceNoWrap
  | WhiteSpacePre
  | WhiteSpacePreWrap
  deriving (Eq, Show)

-- | Symbolic style.
--
-- Numeric/interpolatable values are represented as Expr.
-- Discrete/non-interpolatable CSS-like values are stored directly.
data Style = Style
  { styleBox         :: Box Expr
    -- Interpolatable / constrainable attributes.
  , styleOpacity     :: Maybe Expr
  , styleZIndex      :: Maybe Expr
  , styleFontSize    :: Maybe Expr
  , styleRadius      :: Maybe Expr
  , styleFill        :: Maybe (Hsl Expr)
  , styleStroke      :: Maybe (Hsl Expr)
  , styleStrokeWidth :: Maybe Expr
  , styleAlpha       :: Maybe Expr
    -- Discrete / non-interpolatable CSS-like attributes.
  , styleFontFamily  :: Maybe CssText
  , styleFontWeight  :: Maybe FontWeight
  , styleFontStyle   :: Maybe FontStyle
  , styleTextAlign   :: Maybe TextAlign
  , styleBorderStyle :: Maybe BorderStyle
  , styleWhiteSpace  :: Maybe WhiteSpace
  , styleCssClass    :: Maybe CssText
  } deriving (Eq, Show)

top :: Style -> Expr
top = boxTop . styleBox

left :: Style -> Expr
left = boxLeft . styleBox

width :: Style -> Expr
width = boxWidth . styleBox

height :: Style -> Expr
height = boxHeight . styleBox

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

positionOf :: BlockView tag -> Vec2 Expr
positionOf block = Vec2 (leftOf block) (topOf block)

sizeOf :: BlockView tag -> Vec2 Expr
sizeOf block = Vec2 (widthOf block) (heightOf block)

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
-- | Solved style.
--
-- Expr-valued attributes become Double-valued attributes.
-- Discrete CSS-like attributes are copied through unchanged.
data MaterializedStyle = MaterializedStyle
  { materializedBox         :: Box Double
    -- Interpolatable / solved attributes.
  , materializedOpacity     :: Maybe Double
  , materializedZIndex      :: Maybe Double
  , materializedFontSize    :: Maybe Double
  , materializedRadius      :: Maybe Double
  , materializedFill        :: Maybe (Hsl Double)
  , materializedStroke      :: Maybe (Hsl Double)
  , materializedStrokeWidth :: Maybe Double
  , materializedAlpha       :: Maybe Double
    -- Discrete / copied attributes.
  , materializedFontFamily  :: Maybe CssText
  , materializedFontWeight  :: Maybe FontWeight
  , materializedFontStyle   :: Maybe FontStyle
  , materializedTextAlign   :: Maybe TextAlign
  , materializedBorderStyle :: Maybe BorderStyle
  , materializedWhiteSpace  :: Maybe WhiteSpace
  , materializedCssClass    :: Maybe CssText
  } deriving (Eq, Show)

materializedTop :: MaterializedStyle -> Double
materializedTop = boxTop . materializedBox

materializedLeft :: MaterializedStyle -> Double
materializedLeft = boxLeft . materializedBox

materializedWidth :: MaterializedStyle -> Double
materializedWidth = boxWidth . materializedBox

materializedHeight :: MaterializedStyle -> Double
materializedHeight = boxHeight . materializedBox

data MaterializedBlockView tag = MaterializedBlockView
  { materializedBlockRef   :: C.BlockRef tag
  , materializedBlockLabel :: C.PayloadView
  , materializedBlockStyle :: MaterializedStyle
  }

data MaterializedViewNode where
  MaterializedBlockViewNode :: MaterializedBlockView tag -> MaterializedViewNode

materializeBox :: Solution -> Box Expr -> Maybe (Box Double)
materializeBox solution = traverse (evalExpr solution)

materializeHsl :: Solution -> Hsl Expr -> Maybe (Hsl Double)
materializeHsl solution = traverse (evalExpr solution)

materializeStyle :: Solution -> Style -> Maybe MaterializedStyle
materializeStyle solution style =
  MaterializedStyle
    <$> materializeBox solution (styleBox style)
    <*> traverse (evalExpr solution) (styleOpacity style)
    <*> traverse (evalExpr solution) (styleZIndex style)
    <*> traverse (evalExpr solution) (styleFontSize style)
    <*> traverse (evalExpr solution) (styleRadius style)
    <*> traverse (materializeHsl solution) (styleFill style)
    <*> traverse (materializeHsl solution) (styleStroke style)
    <*> traverse (evalExpr solution) (styleStrokeWidth style)
    <*> traverse (evalExpr solution) (styleAlpha style)
    <*> pure (styleFontFamily style)
    <*> pure (styleFontWeight style)
    <*> pure (styleFontStyle style)
    <*> pure (styleTextAlign style)
    <*> pure (styleBorderStyle style)
    <*> pure (styleWhiteSpace style)
    <*> pure (styleCssClass style)

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

emitViewNode :: ViewNode -> ViewBuilder events ()
emitViewNode node = tell mempty {emittedNodes = [node]}

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

between :: Expr -> Expr -> Expr -> ViewBuilder events ()
between lo x hi = do
  ensure $ lo @<@ x
  ensure $ x @<@ hi

unitBounds :: Expr -> ViewBuilder events ()
unitBounds x = between (num 0) x (num 1)

hueBounds :: Expr -> ViewBuilder events ()
hueBounds h = between (num 0) h (num 360)

hslBounds :: Hsl Expr -> ViewBuilder events ()
hslBounds hsl = do
  hueBounds (hue hsl)
  unitBounds (saturation hsl)
  unitBounds (lightness hsl)

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

sameVec2 :: Vec2 Expr -> Vec2 Expr -> ViewBuilder events ()
sameVec2 (Vec2 ax ay) (Vec2 bx by) = do
  ensure $ ax @=@ bx
  ensure $ ay @=@ by

sameHsl :: Hsl Expr -> Hsl Expr -> ViewBuilder events ()
sameHsl a b = do
  ensure $ hue a @=@ hue b
  ensure $ saturation a @=@ saturation b
  ensure $ lightness a @=@ lightness b

-- | Adjacent blocks with the same y coordinate.
(|=|) :: BlockView a -> BlockView b -> ViewBuilder events ()
(|=|) a b = do
  sameTop a b
  ensure $ rightOf a @=@ leftOf b

--------------------------------------------------------------------------------
-- Style construction helpers
--------------------------------------------------------------------------------
withOpacity :: Expr -> Style -> Style
withOpacity value style = style {styleOpacity = Just value}

withZIndex :: Expr -> Style -> Style
withZIndex value style = style {styleZIndex = Just value}

withFontSize :: Expr -> Style -> Style
withFontSize value style = style {styleFontSize = Just value}

withRadius :: Expr -> Style -> Style
withRadius value style = style {styleRadius = Just value}

withFill :: Hsl Expr -> Style -> Style
withFill value style = style {styleFill = Just value}

withStroke :: Hsl Expr -> Style -> Style
withStroke value style = style {styleStroke = Just value}

withStrokeWidth :: Expr -> Style -> Style
withStrokeWidth value style = style {styleStrokeWidth = Just value}

withAlpha :: Expr -> Style -> Style
withAlpha value style = style {styleAlpha = Just value}

withFontFamily :: String -> Style -> Style
withFontFamily value style = style {styleFontFamily = Just (CssText value)}

withFontWeight :: FontWeight -> Style -> Style
withFontWeight value style = style {styleFontWeight = Just value}

withFontStyle :: FontStyle -> Style -> Style
withFontStyle value style = style {styleFontStyle = Just value}

withTextAlign :: TextAlign -> Style -> Style
withTextAlign value style = style {styleTextAlign = Just value}

withBorderStyle :: BorderStyle -> Style -> Style
withBorderStyle value style = style {styleBorderStyle = Just value}

withWhiteSpace :: WhiteSpace -> Style -> Style
withWhiteSpace value style = style {styleWhiteSpace = Just value}

withCssClass :: String -> Style -> Style
withCssClass value style = style {styleCssClass = Just (CssText value)}

--------------------------------------------------------------------------------
-- Per-block visualisation
--------------------------------------------------------------------------------
class C.TraceBlock tag =>
      VisualizeBlock tag
  where
  styleBlock :: Proxy tag -> Style -> Style
  styleBlock _ = id
  visualizeBlock :: BlockView tag -> ViewBuilder events ()

visualizeNewBlock ::
     forall tag events. VisualizeBlock tag
  => BlockView tag
  -> ViewBuilder events ()
visualizeNewBlock block0 = do
  let block =
        block0
          {blockStyle = styleBlock (Proxy :: Proxy tag) (blockStyle block0)}
  emitViewNode (BlockViewNode block)
  containsCanvas block
  constrainStyle (blockStyle block)
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

instance VisualizeBlock tag => VisualizeAuditBlock (C.Replace tag) where
  visualizeAuditBlockStep step =
    case step of
      VReplaced _old _incoming output -> visualizeNewBlock output

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
buildCSP graph@(C.TraceGraph _blocks events) =
  let env = buildViewEnv graph
      stepOutputs = map (visualizeTraceEvent env) events
      viewSteps' = map stepView stepOutputs
      nodes = concatMap stepNodes stepOutputs
      constraints = concatMap stepConstraints stepOutputs
   in ViewGraph
        { viewNodes = nodes
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
-- Core block snapshots -> base block views
--------------------------------------------------------------------------------
blockViewOfSnapshot :: C.BlockSnapshot tag -> BlockView tag
blockViewOfSnapshot (C.BlockSnapshot ref _payload payloadView) =
  BlockView
    {blockRef = ref, blockLabel = payloadView, blockStyle = styleForRef ref}

styleForRef :: C.BlockRef tag -> Style
styleForRef ref =
  Style
    { styleBox =
        Box
          { boxTop = blockVar ref "top"
          , boxLeft = blockVar ref "left"
          , boxWidth = blockVar ref "width"
          , boxHeight = blockVar ref "height"
          }
      -- Interpolatable/constrainable defaults.
    , styleOpacity = Nothing
    , styleZIndex = Nothing
    , styleFontSize = Nothing
    , styleRadius = Nothing
    , styleFill = Nothing
    , styleStroke = Nothing
    , styleStrokeWidth = Nothing
    , styleAlpha = Nothing
      -- Discrete CSS-like defaults.
    , styleFontFamily = Nothing
    , styleFontWeight = Nothing
    , styleFontStyle = Nothing
    , styleTextAlign = Nothing
    , styleBorderStyle = Nothing
    , styleWhiteSpace = Nothing
    , styleCssClass = Nothing
    }

blockVar :: C.BlockRef tag -> String -> Expr
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
constrainMaybe ::
     (Expr -> ViewBuilder events ()) -> Maybe Expr -> ViewBuilder events ()
constrainMaybe f maybeExpr =
  case maybeExpr of
    Nothing   -> pure ()
    Just expr -> f expr

nonNegative :: Expr -> ViewBuilder events ()
nonNegative expr = ensure $ num 0 @<@ expr

constrainMaybeHsl :: Maybe (Hsl Expr) -> ViewBuilder events ()
constrainMaybeHsl maybeHsl =
  case maybeHsl of
    Nothing  -> pure ()
    Just hsl -> hslBounds hsl

constrainStyle :: Style -> ViewBuilder events ()
constrainStyle style = do
  constrainMaybe unitBounds (styleOpacity style)
  constrainMaybe nonNegative (styleZIndex style)
  constrainMaybe nonNegative (styleFontSize style)
  constrainMaybe nonNegative (styleRadius style)
  constrainMaybeHsl (styleFill style)
  constrainMaybeHsl (styleStroke style)
  constrainMaybe nonNegative (styleStrokeWidth style)
  constrainMaybe unitBounds (styleAlpha style)
