{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE DeriveTraversable    #-}
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
    ViewGraph(..)
  , ViewNode(..)
  , ViewStep(..)
  , BlockView(..)
  , Style(..)
  , Bounds(..)
  , BoundsExpr
  , MaterializedBounds
  , HasBounds(..)
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
  , ViewBlock(..)
  , ViewEvent(..)
  , ViewEvents(..)
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
  , -- * Bounds and layout helpers
    canvasBounds
  , contains
  , insideCanvas
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
  , sameCenterX
  , sameCenterY
  , sameCenter
  , above
  , below
  , beside
  , besideWithGap
  , belowWithGap
  , sameVec2
  , sameHsl
  , -- * Style helpers
    withOpacity
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
infixl 6 |=|
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
-- Bounds
--------------------------------------------------------------------------------
-- | A rectangle represented by top, left, width, and height.
--
-- Right, bottom, position, size, and center are derived handles exposed through
-- 'HasBounds'.
data Bounds a =
  Bounds a a a a
  deriving (Eq, Show, Functor, Foldable, Traversable)

type BoundsExpr = Bounds LayoutExpr

type MaterializedBounds = Bounds Double

boundsTop :: Bounds a -> a
boundsTop bounds =
  case bounds of
    Bounds t _ _ _ -> t

boundsLeft :: Bounds a -> a
boundsLeft bounds =
  case bounds of
    Bounds _ l _ _ -> l

boundsWidth :: Bounds a -> a
boundsWidth bounds =
  case bounds of
    Bounds _ _ w _ -> w

boundsHeight :: Bounds a -> a
boundsHeight bounds =
  case bounds of
    Bounds _ _ _ h -> h

class HasBounds a where
  top :: a -> LayoutExpr
  left :: a -> LayoutExpr
  width :: a -> LayoutExpr
  height :: a -> LayoutExpr
  right :: a -> LayoutExpr
  right x = left x @+@ width x
  bottom :: a -> LayoutExpr
  bottom x = top x @+@ height x
  centerX :: a -> LayoutExpr
  centerX x = left x @+@ (width x @/@ num 2)
  centerY :: a -> LayoutExpr
  centerY x = top x @+@ (height x @/@ num 2)
  center :: a -> Vec2 LayoutExpr
  center x = Vec2 (centerX x) (centerY x)
  position :: a -> Vec2 LayoutExpr
  position x = Vec2 (left x) (top x)
  size :: a -> Vec2 LayoutExpr
  size x = Vec2 (width x) (height x)

instance HasBounds (Bounds (Expr Layout)) where
  top = boundsTop
  left = boundsLeft
  width = boundsWidth
  height = boundsHeight

--------------------------------------------------------------------------------
-- Block views
--------------------------------------------------------------------------------
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
  { styleBounds      :: BoundsExpr
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

instance HasBounds Style where
  top = top . styleBounds
  left = left . styleBounds
  width = width . styleBounds
  height = height . styleBounds

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
-- | Solved style.
--
-- Expr-valued attributes become Double-valued attributes.
-- Discrete CSS-like attributes are copied through unchanged.
data MaterializedStyle = MaterializedStyle
  { materializedBounds      :: MaterializedBounds
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
materializedTop = boundsTop . materializedBounds

materializedLeft :: MaterializedStyle -> Double
materializedLeft = boundsLeft . materializedBounds

materializedWidth :: MaterializedStyle -> Double
materializedWidth = boundsWidth . materializedBounds

materializedHeight :: MaterializedStyle -> Double
materializedHeight = boundsHeight . materializedBounds

data MaterializedBlockView tag = MaterializedBlockView
  { materializedBlockRef   :: C.BlockRef tag
  , materializedBlockLabel :: C.PayloadView
  , materializedBlockStyle :: MaterializedStyle
  }

data MaterializedViewNode where
  MaterializedBlockViewNode :: MaterializedBlockView tag -> MaterializedViewNode

materializeBounds :: Solution -> BoundsExpr -> Maybe MaterializedBounds
materializeBounds solution = traverse (evalExpr solution)

materializeHsl :: Solution -> HslExpr -> Maybe MaterializedHsl
materializeHsl solution hsl =
  Hsl
    <$> evalExpr solution (hue hsl)
    <*> evalExpr solution (saturation hsl)
    <*> evalExpr solution (lightness hsl)

materializeStyle :: Solution -> Style -> Maybe MaterializedStyle
materializeStyle solution style =
  MaterializedStyle
    <$> materializeBounds solution (styleBounds style)
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

canvasBounds :: ViewBuilder events BoundsExpr
canvasBounds = do
  env <- ask
  return (Bounds (num 0) (num 0) (canvasWidth env) (canvasHeight env))

contains ::
     (HasBounds outer, HasBounds inner)
  => outer
  -> inner
  -> ViewBuilder events ()
contains outer inner = do
  ensure $ left outer @<@ left inner
  ensure $ top outer @<@ top inner
  ensure $ right inner @<@ right outer
  ensure $ bottom inner @<@ bottom outer

insideCanvas :: HasBounds block => block -> ViewBuilder events ()
insideCanvas block = do
  canvas <- canvasBounds
  canvas `contains` block

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

sameTop :: (HasBounds a, HasBounds b) => a -> b -> ViewBuilder events ()
sameTop a b = ensure $ top a @=@ top b

sameLeft :: (HasBounds a, HasBounds b) => a -> b -> ViewBuilder events ()
sameLeft a b = ensure $ left a @=@ left b

sameBottom :: (HasBounds a, HasBounds b) => a -> b -> ViewBuilder events ()
sameBottom a b = ensure $ bottom a @=@ bottom b

sameRight :: (HasBounds a, HasBounds b) => a -> b -> ViewBuilder events ()
sameRight a b = ensure $ right a @=@ right b

sameWidth :: (HasBounds a, HasBounds b) => a -> b -> ViewBuilder events ()
sameWidth a b = ensure $ width a @=@ width b

sameHeight :: (HasBounds a, HasBounds b) => a -> b -> ViewBuilder events ()
sameHeight a b = ensure $ height a @=@ height b

sameBounds :: (HasBounds a, HasBounds b) => a -> b -> ViewBuilder events ()
sameBounds a b = do
  sameTop a b
  sameLeft a b
  sameWidth a b
  sameHeight a b

sameCenterX :: (HasBounds a, HasBounds b) => a -> b -> ViewBuilder events ()
sameCenterX a b = ensure $ centerX a @=@ centerX b

sameCenterY :: (HasBounds a, HasBounds b) => a -> b -> ViewBuilder events ()
sameCenterY a b = ensure $ centerY a @=@ centerY b

sameCenter :: (HasBounds a, HasBounds b) => a -> b -> ViewBuilder events ()
sameCenter a b = do
  sameCenterX a b
  sameCenterY a b

above :: (HasBounds a, HasBounds b) => a -> b -> ViewBuilder events ()
above a b = ensure $ bottom a @<@ top b

below :: (HasBounds a, HasBounds b) => a -> b -> ViewBuilder events ()
below a b = ensure $ bottom b @<@ top a

beside :: (HasBounds a, HasBounds b) => a -> b -> ViewBuilder events ()
beside a b = do
  sameCenterY a b
  ensure $ right a @=@ left b

besideWithGap ::
     (HasBounds a, HasBounds b) => LayoutExpr -> a -> b -> ViewBuilder events ()
besideWithGap gap a b = do
  sameCenterY a b
  ensure $ right a @+@ gap @=@ left b

belowWithGap ::
     (HasBounds a, HasBounds b) => LayoutExpr -> a -> b -> ViewBuilder events ()
belowWithGap gap a b = do
  sameCenterX a b
  ensure $ bottom a @+@ gap @=@ top b

sameVec2 :: Vec2 LayoutExpr -> Vec2 LayoutExpr -> ViewBuilder events ()
sameVec2 (Vec2 ax ay) (Vec2 bx by) = do
  ensure $ ax @=@ bx
  ensure $ ay @=@ by

sameHsl :: HslExpr -> HslExpr -> ViewBuilder events ()
sameHsl a b = do
  ensure $ hue a @=@ hue b
  ensure $ saturation a @=@ saturation b
  ensure $ lightness a @=@ lightness b

-- | Adjacent blocks aligned by vertical center.
(|=|) :: (HasBounds a, HasBounds b) => a -> b -> ViewBuilder events ()
(|=|) = beside

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
  Style
    { styleBounds =
        Bounds
          (blockVar ref "top")
          (blockVar ref "left")
          (blockVar ref "width")
          (blockVar ref "height")
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
