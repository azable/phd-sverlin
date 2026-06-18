{-# LANGUAGE DataKinds            #-}
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
  , -- * Solver domains
    Range(..)
  , InitialVar(..)
  , Free
  , Layout
  , Unit
  , Angle
  , FreeExpr
  , LayoutExpr
  , UnitExpr
  , AngleExpr
  , HueExpr
  , HslExpr
  , MaterializedHsl
  , -- * Expressions, vectors, and constraints
    Expr
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
  , (@+@)
  , (@-@)
  , (@*@)
  , (@/@)
  , (@^@)
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
  , solveCSPWithSeed
  , SolveConfig(..)
  , RandomSeed(..)
  , RandomSample(..)
  , defaultSolveConfig
  , defaultRandomSeed
  , ensure
  , encourage
  , registerInitialRange
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
  , angleBounds
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
-- Domain aliases
--------------------------------------------------------------------------------
type FreeExpr = Expr Free

type LayoutExpr = Expr Layout

type UnitExpr = Expr Unit

type AngleExpr = Expr Angle

type HueExpr = Expr Angle

type HslExpr = Hsl HueExpr UnitExpr

type MaterializedHsl = Hsl Double Double

--------------------------------------------------------------------------------
-- Block views
--------------------------------------------------------------------------------
data Box a = Box
  { boxTop    :: a
  , boxLeft   :: a
  , boxWidth  :: a
  , boxHeight :: a
  } deriving (Eq, Show, Functor, Foldable, Traversable)

data Hsl hue unit = Hsl
  { hue        :: hue
  , saturation :: unit
  , lightness  :: unit
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
-- Numeric/interpolatable values are represented as typed solver expressions.
-- Discrete/non-interpolatable CSS-like values are stored directly.
data Style = Style
  { styleBox         :: Box LayoutExpr
    -- Interpolatable / constrainable attributes.
  , styleOpacity     :: Maybe UnitExpr
  , styleZIndex      :: Maybe FreeExpr
  , styleFontSize    :: Maybe LayoutExpr
  , styleRadius      :: Maybe LayoutExpr
  , styleFill        :: Maybe HslExpr
  , styleStroke      :: Maybe HslExpr
  , styleStrokeWidth :: Maybe LayoutExpr
  , styleAlpha       :: Maybe UnitExpr
    -- Discrete / non-interpolatable CSS-like attributes.
  , styleFontFamily  :: Maybe CssText
  , styleFontWeight  :: Maybe FontWeight
  , styleFontStyle   :: Maybe FontStyle
  , styleTextAlign   :: Maybe TextAlign
  , styleBorderStyle :: Maybe BorderStyle
  , styleWhiteSpace  :: Maybe WhiteSpace
  , styleCssClass    :: Maybe CssText
  } deriving (Eq, Show)

data Bounds = Bounds
  { boundsTop    :: LayoutExpr
  , boundsLeft   :: LayoutExpr
  , boundsRight  :: LayoutExpr
  , boundsBottom :: LayoutExpr
  }

data BlockView tag = BlockView
  { blockRef   :: C.BlockRef tag
  , blockLabel :: C.PayloadView
  , blockStyle :: Style
  }

top :: Style -> LayoutExpr
top = boxTop . styleBox

left :: Style -> LayoutExpr
left = boxLeft . styleBox

width :: Style -> LayoutExpr
width = boxWidth . styleBox

height :: Style -> LayoutExpr
height = boxHeight . styleBox

topOf :: BlockView tag -> LayoutExpr
topOf = top . blockStyle

bottomOf :: BlockView tag -> LayoutExpr
bottomOf block = topOf block `plus` heightOf block

leftOf :: BlockView tag -> LayoutExpr
leftOf = left . blockStyle

rightOf :: BlockView tag -> LayoutExpr
rightOf block = leftOf block `plus` widthOf block

widthOf :: BlockView tag -> LayoutExpr
widthOf = width . blockStyle

heightOf :: BlockView tag -> LayoutExpr
heightOf = height . blockStyle

positionOf :: BlockView tag -> Vec2 LayoutExpr
positionOf block = Vec2 (leftOf block) (topOf block)

sizeOf :: BlockView tag -> Vec2 LayoutExpr
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
  , viewInitialVars :: [InitialVar]
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
  , materializedFill        :: Maybe MaterializedHsl
  , materializedStroke      :: Maybe MaterializedHsl
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

materializeBox :: Solution -> Box LayoutExpr -> Maybe (Box Double)
materializeBox solution = traverse (evalExpr solution)

materializeHsl :: Solution -> HslExpr -> Maybe MaterializedHsl
materializeHsl solution hsl =
  Hsl
    <$> evalExpr solution (hue hsl)
    <*> evalExpr solution (saturation hsl)
    <*> evalExpr solution (lightness hsl)

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
  , emittedSteps       :: [ViewStep events]
  , emittedConstraints :: [Constraint]
  , emittedInitialVars :: [InitialVar]
  }

instance Semigroup (ViewOutput events) where
  ViewOutput nodesA stepsA constraintsA initialsA <> ViewOutput nodesB stepsB constraintsB initialsB =
    ViewOutput
      { emittedNodes = nodesA ++ nodesB
      , emittedSteps = stepsA ++ stepsB
      , emittedConstraints = constraintsA ++ constraintsB
      , emittedInitialVars = initialsA ++ initialsB
      }

instance Monoid (ViewOutput events) where
  mempty =
    ViewOutput
      { emittedNodes = []
      , emittedSteps = []
      , emittedConstraints = []
      , emittedInitialVars = []
      }

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

between :: Expr ty -> Expr ty -> Expr ty -> ViewBuilder events ()
between lo x hi = do
  ensure $ lo @<@ x
  ensure $ x @<@ hi

unitBounds :: UnitExpr -> ViewBuilder events ()
unitBounds x = between (num 0) x (num 1)

angleBounds :: AngleExpr -> ViewBuilder events ()
angleBounds angle = between (num 0) angle (num 360)

hslBounds :: HslExpr -> ViewBuilder events ()
hslBounds hsl = do
  angleBounds (hue hsl)
  unitBounds (saturation hsl)
  unitBounds (lightness hsl)

nonNegative :: SymbolicType ty => Expr ty -> ViewBuilder events ()
nonNegative expr = ensure $ num 0 @<@ expr

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

-- centeredWithin :: BlockView a -> BlockView b -> ViewBuilder events ()
-- centeredWithin inner outer = do
--   ensure
--     $ leftOf inner
--         @+@ (widthOf inner @/@ num 2)
--         @=@ leftOf outer
--         @+@ (widthOf outer @/@ num 2)
--   ensure
--     $ topOf inner
--         @+@ (heightOf inner @/@ num 2)
--         @=@ topOf outer
--         @+@ (heightOf outer @/@ num 2)
sameVec2 :: Vec2 LayoutExpr -> Vec2 LayoutExpr -> ViewBuilder events ()
sameVec2 (Vec2 ax ay) (Vec2 bx by) = do
  ensure $ ax @=@ bx
  ensure $ ay @=@ by

sameHsl :: HslExpr -> HslExpr -> ViewBuilder events ()
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
withOpacity :: UnitExpr -> Style -> Style
withOpacity value style = style {styleOpacity = Just value}

withZIndex :: FreeExpr -> Style -> Style
withZIndex value style = style {styleZIndex = Just value}

withFontSize :: LayoutExpr -> Style -> Style
withFontSize value style = style {styleFontSize = Just value}

withRadius :: LayoutExpr -> Style -> Style
withRadius value style = style {styleRadius = Just value}

withFill :: HslExpr -> Style -> Style
withFill value style = style {styleFill = Just value}

withStroke :: HslExpr -> Style -> Style
withStroke value style = style {styleStroke = Just value}

withStrokeWidth :: LayoutExpr -> Style -> Style
withStrokeWidth value style = style {styleStrokeWidth = Just value}

withAlpha :: UnitExpr -> Style -> Style
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
class C.Traceable tag =>
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
  registerInitialStyleBounds (blockStyle block)
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
      initialVars = emittedInitialVars output
   in BuiltViewStep
        { stepView = ViewStep traceEvent nodes constraints
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
registerMaybeInitialRange :: Range -> Maybe (Expr ty) -> ViewBuilder events ()
registerMaybeInitialRange range maybeExpr =
  case maybeExpr of
    Nothing   -> pure ()
    Just expr -> registerInitialRange expr range

registerInitialHslBounds :: HslExpr -> ViewBuilder events ()
registerInitialHslBounds hsl = do
  registerInitialRange (hue hsl) (Range 0 360)
  registerInitialRange (saturation hsl) (Range 0 1)
  registerInitialRange (lightness hsl) (Range 0 1)

registerMaybeInitialHslBounds :: Maybe HslExpr -> ViewBuilder events ()
registerMaybeInitialHslBounds maybeHsl =
  case maybeHsl of
    Nothing  -> pure ()
    Just hsl -> registerInitialHslBounds hsl

registerInitialStyleBounds :: Style -> ViewBuilder events ()
registerInitialStyleBounds style = do
  env <- ask
  let canvasW = canvasWidthValue env
      canvasH = canvasHeightValue env
  registerInitialRange (left style) (Range 0 canvasW)
  registerInitialRange (top style) (Range 0 canvasH)
  registerInitialRange (width style) (Range 20 (max 20 (canvasW / 4)))
  registerInitialRange (height style) (Range 20 (max 20 (canvasH / 4)))
  registerMaybeInitialRange (Range 0 1) (styleOpacity style)
  registerMaybeInitialRange (Range (-10) 10) (styleZIndex style)
  registerMaybeInitialRange (Range 8 48) (styleFontSize style)
  registerMaybeInitialRange (Range 0 32) (styleRadius style)
  registerMaybeInitialHslBounds (styleFill style)
  registerMaybeInitialHslBounds (styleStroke style)
  registerMaybeInitialRange (Range 0 8) (styleStrokeWidth style)
  registerMaybeInitialRange (Range 0 1) (styleAlpha style)

constrainMaybe ::
     (a -> ViewBuilder events ()) -> Maybe a -> ViewBuilder events ()
constrainMaybe f maybeValue =
  case maybeValue of
    Nothing    -> pure ()
    Just value -> f value

constrainMaybeHsl :: Maybe HslExpr -> ViewBuilder events ()
constrainMaybeHsl maybeHsl =
  case maybeHsl of
    Nothing  -> pure ()
    Just hsl -> hslBounds hsl

constrainStyle :: Style -> ViewBuilder events ()
constrainStyle style = do
  -- Unit and hue ranges are already known to the solver from their types.
  -- Keeping these constraints here makes the visual-layer contract explicit.
  constrainMaybe unitBounds (styleOpacity style)
  constrainMaybe nonNegative (styleZIndex style)
  constrainMaybe nonNegative (styleFontSize style)
  constrainMaybe nonNegative (styleRadius style)
  constrainMaybeHsl (styleFill style)
  constrainMaybeHsl (styleStroke style)
  constrainMaybe nonNegative (styleStrokeWidth style)
  constrainMaybe unitBounds (styleAlpha style)
