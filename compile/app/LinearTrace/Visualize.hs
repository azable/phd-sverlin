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
  , -- * Styles
    Style(..)
  , StyleScalar(..)
  , StyleColor(..)
  , StyleDiscrete(..)
  , StyleValueUnit(..)
  , MaterializedStyle(..)
  , MaterializedScalar(..)
  , MaterializedColor(..)
  , MaterializedDiscrete(..)
  , StyleExprLeaf(..)
  , styleExprLeaves
  , materializedScalarValue
  , materializedCssClass
  , -- * Bounds/style values
    Bounds(..)
  , BoundsExpr
  , MaterializedBounds
  , HasBounds(..)
  , HasStyle(..)
  , boundsOf
  , Hsl(..)
  , CssText(..)
  , FontWeight(..)
  , FontStyle(..)
  , TextAlign(..)
  , BorderStyle(..)
  , WhiteSpace(..)
  , MaterializedHsl
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
  , -- * Expressions, vectors, and constraints
    Expr
  , Constraint(..)
  , ConstrainEq(..)
  , ConstrainOrd(..)
  , Vec2(..)
  , Vec3(..)
  , Vec4(..)
  , vec2
  , vec3
  , vec4
  , var
  , varName
  , global
  , (@+@)
  , (@-@)
  , (@*@)
  , (@/@)
  , (@^@)
  , (@=@)
  , (@<=@)
  , (@<@)
  , (@>=@)
  , (@>@)
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
  , nonNegative
  , centeredWithin
  , above
  , below
  , beside
  , besideWithGap
  , belowWithGap
  , (|=|)
  , -- * Common style accessors/setters
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
    materializedTop
  , materializedLeft
  , materializedWidth
  , materializedHeight
  , materializeStyle
  , materializeBlockView
  , materializeViewNode
  ) where

import           Control.Monad.Reader
import           Control.Monad.Writer.Strict
import           Data.Maybe                  (maybeToList)
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

instance ConstrainEq a => ConstrainEq (Bounds a) where
  constrainEqual lhs rhs =
    case (lhs, rhs) of
      (Bounds at al aw ah, Bounds bt bl bw bh) ->
        All [at @=@ bt, al @=@ bl, aw @=@ bw, ah @=@ bh]

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

boundsOf :: HasBounds a => a -> BoundsExpr
boundsOf x = Bounds (top x) (left x) (width x) (height x)

instance HasBounds BoundsExpr where
  top = boundsTop
  left = boundsLeft
  width = boundsWidth
  height = boundsHeight

--------------------------------------------------------------------------------
-- Basic style values
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

--------------------------------------------------------------------------------
-- Centralized style representation
--------------------------------------------------------------------------------
data StyleValueUnit
  = StyleNumber
  | StylePixels
  | StyleHidden
  deriving (Eq, Show)

data StyleScalar
  = StyleFreeScalar
      String
      FreeExpr
      (Maybe Range)
      (FreeExpr -> [Constraint])
      StyleValueUnit
  | StyleLayoutScalar
      String
      LayoutExpr
      (Maybe Range)
      (LayoutExpr -> [Constraint])
      StyleValueUnit
  | StyleUnitScalar
      String
      UnitExpr
      (Maybe Range)
      (UnitExpr -> [Constraint])
      StyleValueUnit
  | StyleAngleScalar
      String
      AngleExpr
      (Maybe Range)
      (AngleExpr -> [Constraint])
      StyleValueUnit

data StyleColor =
  StyleColor String (Maybe HslExpr)

data StyleDiscrete
  = StyleTextAttr String (Maybe CssText)
  | StyleFontWeightAttr String (Maybe FontWeight)
  | StyleFontStyleAttr String (Maybe FontStyle)
  | StyleTextAlignAttr String (Maybe TextAlign)
  | StyleBorderStyleAttr String (Maybe BorderStyle)
  | StyleWhiteSpaceAttr String (Maybe WhiteSpace)
  | StyleClassAttr String (Maybe CssText)

data Style = Style
  { styleBounds   :: BoundsExpr
  , styleScalars  :: [StyleScalar]
  , styleColors   :: [StyleColor]
  , styleDiscrete :: [StyleDiscrete]
  }

instance HasBounds Style where
  top = top . styleBounds
  left = left . styleBounds
  width = width . styleBounds
  height = height . styleBounds

data MaterializedScalar =
  MaterializedScalar String Double StyleValueUnit
  deriving (Eq, Show)

data MaterializedColor =
  MaterializedColor String (Maybe MaterializedHsl)
  deriving (Eq, Show)

data MaterializedDiscrete
  = MaterializedTextAttr String (Maybe CssText)
  | MaterializedFontWeightAttr String (Maybe FontWeight)
  | MaterializedFontStyleAttr String (Maybe FontStyle)
  | MaterializedTextAlignAttr String (Maybe TextAlign)
  | MaterializedBorderStyleAttr String (Maybe BorderStyle)
  | MaterializedWhiteSpaceAttr String (Maybe WhiteSpace)
  | MaterializedClassAttr String (Maybe CssText)
  deriving (Eq, Show)

data MaterializedStyle = MaterializedStyle
  { materializedBounds   :: MaterializedBounds
  , materializedScalars  :: [MaterializedScalar]
  , materializedColors   :: [MaterializedColor]
  , materializedDiscrete :: [MaterializedDiscrete]
  } deriving (Eq, Show)

materializedTop :: MaterializedStyle -> Double
materializedTop = boundsTop . materializedBounds

materializedLeft :: MaterializedStyle -> Double
materializedLeft = boundsLeft . materializedBounds

materializedWidth :: MaterializedStyle -> Double
materializedWidth = boundsWidth . materializedBounds

materializedHeight :: MaterializedStyle -> Double
materializedHeight = boundsHeight . materializedBounds

materializedScalarValue :: String -> Double -> MaterializedStyle -> Double
materializedScalarValue name fallback style' =
  findScalar fallback (materializedScalars style')
  where
    findScalar value scalars =
      case scalars of
        [] -> value
        MaterializedScalar name' x _:rest
          | name == name' -> x
          | otherwise -> findScalar value rest

materializedCssClass :: MaterializedStyle -> Maybe CssText
materializedCssClass style' = findClass (materializedDiscrete style')
  where
    findClass fields =
      case fields of
        []                                       -> Nothing
        MaterializedClassAttr "cssClass" value:_ -> value
        _:rest                                   -> findClass rest

--------------------------------------------------------------------------------
-- Generic style helpers
--------------------------------------------------------------------------------
data StyleExprLeaf where
  StyleExprLeaf :: String -> Expr ty -> StyleExprLeaf

styleScalarName :: StyleScalar -> String
styleScalarName scalar =
  case scalar of
    StyleFreeScalar name _ _ _ _   -> name
    StyleLayoutScalar name _ _ _ _ -> name
    StyleUnitScalar name _ _ _ _   -> name
    StyleAngleScalar name _ _ _ _  -> name

styleColorName :: StyleColor -> String
styleColorName color =
  case color of
    StyleColor name _ -> name

styleDiscreteName :: StyleDiscrete -> String
styleDiscreteName field =
  case field of
    StyleTextAttr name _        -> name
    StyleFontWeightAttr name _  -> name
    StyleFontStyleAttr name _   -> name
    StyleTextAlignAttr name _   -> name
    StyleBorderStyleAttr name _ -> name
    StyleWhiteSpaceAttr name _  -> name
    StyleClassAttr name _       -> name

replaceByName :: (a -> String) -> a -> [a] -> [a]
replaceByName getName newValue values = go values
  where
    target = getName newValue
    go xs =
      case xs of
        [] -> [newValue]
        x:rest
          | getName x == target -> newValue : rest
          | otherwise -> x : go rest

setStyleScalar :: StyleScalar -> Style -> Style
setStyleScalar scalar style' =
  style'
    {styleScalars = replaceByName styleScalarName scalar (styleScalars style')}

setStyleColor :: StyleColor -> Style -> Style
setStyleColor color style' =
  style' {styleColors = replaceByName styleColorName color (styleColors style')}

setStyleDiscrete :: StyleDiscrete -> Style -> Style
setStyleDiscrete field style' =
  style'
    { styleDiscrete =
        replaceByName styleDiscreteName field (styleDiscrete style')
    }

lookupFreeScalar :: String -> FreeExpr -> Style -> FreeExpr
lookupFreeScalar name fallback style' = go (styleScalars style')
  where
    go scalars =
      case scalars of
        [] -> fallback
        StyleFreeScalar name' expr _ _ _:_
          | name == name' -> expr
        _:rest -> go rest

lookupLayoutScalar :: String -> LayoutExpr -> Style -> LayoutExpr
lookupLayoutScalar name fallback style' = go (styleScalars style')
  where
    go scalars =
      case scalars of
        [] -> fallback
        StyleLayoutScalar name' expr _ _ _:_
          | name == name' -> expr
        _:rest -> go rest

lookupUnitScalar :: String -> UnitExpr -> Style -> UnitExpr
lookupUnitScalar name fallback style' = go (styleScalars style')
  where
    go scalars =
      case scalars of
        [] -> fallback
        StyleUnitScalar name' expr _ _ _:_
          | name == name' -> expr
        _:rest -> go rest

lookupColor :: String -> Maybe HslExpr -> Style -> Maybe HslExpr
lookupColor name fallback style' = go (styleColors style')
  where
    go colors =
      case colors of
        [] -> fallback
        StyleColor name' value:_
          | name == name' -> value
        _:rest -> go rest

styleExprLeaves :: Style -> [StyleExprLeaf]
styleExprLeaves style' =
  [ StyleExprLeaf "top" (top style')
  , StyleExprLeaf "left" (left style')
  , StyleExprLeaf "width" (width style')
  , StyleExprLeaf "height" (height style')
  ]
    ++ concatMap scalarLeaves (styleScalars style')
    ++ concatMap colorLeaves (styleColors style')
  where
    scalarLeaves scalar =
      case scalar of
        StyleFreeScalar name expr _ _ _   -> [StyleExprLeaf name expr]
        StyleLayoutScalar name expr _ _ _ -> [StyleExprLeaf name expr]
        StyleUnitScalar name expr _ _ _   -> [StyleExprLeaf name expr]
        StyleAngleScalar name expr _ _ _  -> [StyleExprLeaf name expr]
    colorLeaves color =
      case color of
        StyleColor name maybeHsl ->
          case maybeHsl of
            Nothing -> []
            Just hsl ->
              [ StyleExprLeaf (name ++ ".hue") (hue hsl)
              , StyleExprLeaf (name ++ ".saturation") (saturation hsl)
              , StyleExprLeaf (name ++ ".lightness") (lightness hsl)
              ]

styleInitialVars :: Style -> [InitialVar]
styleInitialVars style' =
  concatMap scalarInitialVars (styleScalars style')
    ++ concatMap colorInitialVars (styleColors style')
  where
    scalarInitialVars scalar =
      case scalar of
        StyleFreeScalar _ expr maybeRange _ _ ->
          maybe [] (maybeToList . initialRangeFor expr) maybeRange
        StyleLayoutScalar _ expr maybeRange _ _ ->
          maybe [] (maybeToList . initialRangeFor expr) maybeRange
        StyleUnitScalar _ expr maybeRange _ _ ->
          maybe [] (maybeToList . initialRangeFor expr) maybeRange
        StyleAngleScalar _ expr maybeRange _ _ ->
          maybe [] (maybeToList . initialRangeFor expr) maybeRange
    colorInitialVars color =
      case color of
        StyleColor _ maybeHsl ->
          case maybeHsl of
            Nothing -> []
            Just hsl ->
              concat
                [ maybeToList (initialRangeFor (hue hsl) (Range 0 360))
                , maybeToList (initialRangeFor (saturation hsl) (Range 0 1))
                , maybeToList (initialRangeFor (lightness hsl) (Range 0 1))
                ]

styleConstraints :: Style -> [Constraint]
styleConstraints style' =
  concatMap scalarConstraints (styleScalars style')
    ++ concatMap colorConstraints (styleColors style')
  where
    scalarConstraints scalar =
      case scalar of
        StyleFreeScalar _ expr _ constraints _   -> constraints expr
        StyleLayoutScalar _ expr _ constraints _ -> constraints expr
        StyleUnitScalar _ expr _ constraints _   -> constraints expr
        StyleAngleScalar _ expr _ constraints _  -> constraints expr
    colorConstraints color =
      case color of
        StyleColor _ maybeHsl ->
          case maybeHsl of
            Nothing -> []
            Just hsl ->
              concat
                [ angleConstraints (hue hsl)
                , unitConstraints (saturation hsl)
                , unitConstraints (lightness hsl)
                ]

--------------------------------------------------------------------------------
-- Shared constraint helpers for style attributes
--------------------------------------------------------------------------------
noConstraints :: Expr ty -> [Constraint]
noConstraints _ = []

nonNegativeConstraints :: SymbolicType ty => Expr ty -> [Constraint]
nonNegativeConstraints expr = [num 0 @<=@ expr]

unitConstraints :: UnitExpr -> [Constraint]
unitConstraints expr = [num 0 @<=@ expr, expr @<=@ num 1]

angleConstraints :: AngleExpr -> [Constraint]
angleConstraints expr = [num 0 @<=@ expr, expr @<=@ num 360]

--------------------------------------------------------------------------------
-- Attribute: opacity
--------------------------------------------------------------------------------
opacityDefault :: UnitExpr
opacityDefault = num 1

opacityScalar :: UnitExpr -> StyleScalar
opacityScalar expr =
  StyleUnitScalar "opacity" expr (Just (Range 0 1)) unitConstraints StyleNumber

opacity :: HasStyle a => a -> UnitExpr
opacity value = lookupUnitScalar "opacity" opacityDefault (style value)

setOpacity :: UnitExpr -> Style -> Style
setOpacity = setStyleScalar . opacityScalar

--------------------------------------------------------------------------------
-- Attribute: zIndex
--------------------------------------------------------------------------------
zIndexDefault :: FreeExpr
zIndexDefault = num 0

zIndexScalar :: FreeExpr -> StyleScalar
zIndexScalar expr =
  StyleFreeScalar
    "zIndex"
    expr
    (Just (Range (-10) 10))
    noConstraints
    StyleNumber

zIndex :: HasStyle a => a -> FreeExpr
zIndex value = lookupFreeScalar "zIndex" zIndexDefault (style value)

setZIndex :: FreeExpr -> Style -> Style
setZIndex = setStyleScalar . zIndexScalar

--------------------------------------------------------------------------------
-- Attribute: fontSize
--------------------------------------------------------------------------------
fontSizeDefault :: LayoutExpr
fontSizeDefault = num 16

fontSizeScalar :: LayoutExpr -> StyleScalar
fontSizeScalar expr =
  StyleLayoutScalar
    "fontSize"
    expr
    (Just (Range 8 48))
    nonNegativeConstraints
    StylePixels

fontSize :: HasStyle a => a -> LayoutExpr
fontSize value = lookupLayoutScalar "fontSize" fontSizeDefault (style value)

setFontSize :: LayoutExpr -> Style -> Style
setFontSize = setStyleScalar . fontSizeScalar

--------------------------------------------------------------------------------
-- Attribute: radius
--------------------------------------------------------------------------------
radiusDefault :: LayoutExpr
radiusDefault = num 0

radiusScalar :: LayoutExpr -> StyleScalar
radiusScalar expr =
  StyleLayoutScalar
    "radius"
    expr
    (Just (Range 0 32))
    nonNegativeConstraints
    StylePixels

radius :: HasStyle a => a -> LayoutExpr
radius value = lookupLayoutScalar "radius" radiusDefault (style value)

setRadius :: LayoutExpr -> Style -> Style
setRadius = setStyleScalar . radiusScalar

--------------------------------------------------------------------------------
-- Attribute: strokeWidth
--------------------------------------------------------------------------------
strokeWidthDefault :: LayoutExpr
strokeWidthDefault = num 0

strokeWidthScalar :: LayoutExpr -> StyleScalar
strokeWidthScalar expr =
  StyleLayoutScalar
    "strokeWidth"
    expr
    (Just (Range 0 8))
    nonNegativeConstraints
    StylePixels

strokeWidth :: HasStyle a => a -> LayoutExpr
strokeWidth value =
  lookupLayoutScalar "strokeWidth" strokeWidthDefault (style value)

setStrokeWidth :: LayoutExpr -> Style -> Style
setStrokeWidth = setStyleScalar . strokeWidthScalar

--------------------------------------------------------------------------------
-- Attribute: alpha
--------------------------------------------------------------------------------
alphaDefault :: UnitExpr
alphaDefault = num 1

alphaScalar :: UnitExpr -> StyleScalar
alphaScalar expr =
  StyleUnitScalar "alpha" expr (Just (Range 0 1)) unitConstraints StyleHidden

alpha :: HasStyle a => a -> UnitExpr
alpha value = lookupUnitScalar "alpha" alphaDefault (style value)

setAlpha :: UnitExpr -> Style -> Style
setAlpha = setStyleScalar . alphaScalar

--------------------------------------------------------------------------------
-- Attribute: fill
--------------------------------------------------------------------------------
fillDefault :: Maybe HslExpr
fillDefault = Nothing

fillColor :: Maybe HslExpr -> StyleColor
fillColor = StyleColor "fill"

fill :: HasStyle a => a -> Maybe HslExpr
fill value = lookupColor "fill" fillDefault (style value)

setFill :: HslExpr -> Style -> Style
setFill = setStyleColor . fillColor . Just

--------------------------------------------------------------------------------
-- Attribute: stroke
--------------------------------------------------------------------------------
strokeDefault :: Maybe HslExpr
strokeDefault = Nothing

strokeColor :: Maybe HslExpr -> StyleColor
strokeColor = StyleColor "stroke"

stroke :: HasStyle a => a -> Maybe HslExpr
stroke value = lookupColor "stroke" strokeDefault (style value)

setStroke :: HslExpr -> Style -> Style
setStroke = setStyleColor . strokeColor . Just

--------------------------------------------------------------------------------
-- Attribute: fontFamily
--------------------------------------------------------------------------------
fontFamilyDiscrete :: Maybe CssText -> StyleDiscrete
fontFamilyDiscrete = StyleTextAttr "fontFamily"

setFontFamily :: String -> Style -> Style
setFontFamily = setStyleDiscrete . fontFamilyDiscrete . Just . CssText

--------------------------------------------------------------------------------
-- Attribute: fontWeight
--------------------------------------------------------------------------------
fontWeightDiscrete :: Maybe FontWeight -> StyleDiscrete
fontWeightDiscrete = StyleFontWeightAttr "fontWeight"

setFontWeight :: FontWeight -> Style -> Style
setFontWeight = setStyleDiscrete . fontWeightDiscrete . Just

--------------------------------------------------------------------------------
-- Attribute: fontStyle
--------------------------------------------------------------------------------
fontStyleDiscrete :: Maybe FontStyle -> StyleDiscrete
fontStyleDiscrete = StyleFontStyleAttr "fontStyle"

setFontStyle :: FontStyle -> Style -> Style
setFontStyle = setStyleDiscrete . fontStyleDiscrete . Just

--------------------------------------------------------------------------------
-- Attribute: textAlign
--------------------------------------------------------------------------------
textAlignDiscrete :: Maybe TextAlign -> StyleDiscrete
textAlignDiscrete = StyleTextAlignAttr "textAlign"

setTextAlign :: TextAlign -> Style -> Style
setTextAlign = setStyleDiscrete . textAlignDiscrete . Just

--------------------------------------------------------------------------------
-- Attribute: borderStyle
--------------------------------------------------------------------------------
borderStyleDiscrete :: Maybe BorderStyle -> StyleDiscrete
borderStyleDiscrete = StyleBorderStyleAttr "borderStyle"

setBorderStyle :: BorderStyle -> Style -> Style
setBorderStyle = setStyleDiscrete . borderStyleDiscrete . Just

--------------------------------------------------------------------------------
-- Attribute: whiteSpace
--------------------------------------------------------------------------------
whiteSpaceDiscrete :: Maybe WhiteSpace -> StyleDiscrete
whiteSpaceDiscrete = StyleWhiteSpaceAttr "whiteSpace"

setWhiteSpace :: WhiteSpace -> Style -> Style
setWhiteSpace = setStyleDiscrete . whiteSpaceDiscrete . Just

--------------------------------------------------------------------------------
-- Attribute: cssClass
--------------------------------------------------------------------------------
cssClassDiscrete :: Maybe CssText -> StyleDiscrete
cssClassDiscrete = StyleClassAttr "cssClass"

setCssClass :: String -> Style -> Style
setCssClass = setStyleDiscrete . cssClassDiscrete . Just . CssText

--------------------------------------------------------------------------------
-- Central default style lists
--------------------------------------------------------------------------------
defaultStyleScalars :: [StyleScalar]
defaultStyleScalars =
  [ opacityScalar opacityDefault
  , zIndexScalar zIndexDefault
  , fontSizeScalar fontSizeDefault
  , radiusScalar radiusDefault
  , strokeWidthScalar strokeWidthDefault
  , alphaScalar alphaDefault
  ]

defaultStyleColors :: [StyleColor]
defaultStyleColors = [fillColor fillDefault, strokeColor strokeDefault]

defaultStyleDiscrete :: [StyleDiscrete]
defaultStyleDiscrete =
  [ fontFamilyDiscrete Nothing
  , fontWeightDiscrete Nothing
  , fontStyleDiscrete Nothing
  , textAlignDiscrete Nothing
  , borderStyleDiscrete Nothing
  , whiteSpaceDiscrete Nothing
  , cssClassDiscrete Nothing
  ]

--------------------------------------------------------------------------------
-- HasStyle
--------------------------------------------------------------------------------
class HasStyle a where
  style :: a -> Style

instance HasStyle Style where
  style = id

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
-- Materialization
--------------------------------------------------------------------------------
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

materializeScalar :: Solution -> StyleScalar -> Maybe MaterializedScalar
materializeScalar solution scalar =
  case scalar of
    StyleFreeScalar name expr _ _ unit ->
      MaterializedScalar name <$> evalExpr solution expr <*> pure unit
    StyleLayoutScalar name expr _ _ unit ->
      MaterializedScalar name <$> evalExpr solution expr <*> pure unit
    StyleUnitScalar name expr _ _ unit ->
      MaterializedScalar name <$> evalExpr solution expr <*> pure unit
    StyleAngleScalar name expr _ _ unit ->
      MaterializedScalar name <$> evalExpr solution expr <*> pure unit

materializeColor :: Solution -> StyleColor -> Maybe MaterializedColor
materializeColor solution color =
  case color of
    StyleColor name maybeHsl ->
      MaterializedColor name <$> traverse (materializeHsl solution) maybeHsl

materializeDiscrete :: StyleDiscrete -> MaterializedDiscrete
materializeDiscrete field =
  case field of
    StyleTextAttr name value        -> MaterializedTextAttr name value
    StyleFontWeightAttr name value  -> MaterializedFontWeightAttr name value
    StyleFontStyleAttr name value   -> MaterializedFontStyleAttr name value
    StyleTextAlignAttr name value   -> MaterializedTextAlignAttr name value
    StyleBorderStyleAttr name value -> MaterializedBorderStyleAttr name value
    StyleWhiteSpaceAttr name value  -> MaterializedWhiteSpaceAttr name value
    StyleClassAttr name value       -> MaterializedClassAttr name value

materializeStyle :: Solution -> Style -> Maybe MaterializedStyle
materializeStyle solution style' =
  MaterializedStyle
    <$> materializeBounds solution (styleBounds style')
    <*> traverse (materializeScalar solution) (styleScalars style')
    <*> traverse (materializeColor solution) (styleColors style')
    <*> pure (map materializeDiscrete (styleDiscrete style'))

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
  ensure $ left outer @<=@ left inner
  ensure $ top outer @<=@ top inner
  ensure $ right inner @<=@ right outer
  ensure $ bottom inner @<=@ bottom outer

insideCanvas :: HasBounds block => block -> ViewBuilder events ()
insideCanvas block = do
  canvas <- canvasBounds
  canvas `contains` block

between :: Expr ty -> Expr ty -> Expr ty -> ViewBuilder events ()
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

nonNegative :: SymbolicType ty => Expr ty -> ViewBuilder events ()
nonNegative expr = ensure $ num 0 @<=@ expr

centeredWithin ::
     (HasBounds inner, HasBounds outer)
  => inner
  -> outer
  -> ViewBuilder events ()
centeredWithin inner outer = do
  ensure $ center inner @=@ center outer
  outer `contains` inner

above :: (HasBounds a, HasBounds b) => a -> b -> ViewBuilder events ()
above a b = ensure $ bottom a @<=@ top b

below :: (HasBounds a, HasBounds b) => a -> b -> ViewBuilder events ()
below a b = ensure $ bottom b @<=@ top a

beside :: (HasBounds a, HasBounds b) => a -> b -> ViewBuilder events ()
beside a b = do
  ensure $ centerY a @=@ centerY b
  ensure $ right a @=@ left b

besideWithGap ::
     (HasBounds a, HasBounds b) => LayoutExpr -> a -> b -> ViewBuilder events ()
besideWithGap gap a b = do
  ensure $ centerY a @=@ centerY b
  ensure $ right a @+@ gap @=@ left b

belowWithGap ::
     (HasBounds a, HasBounds b) => LayoutExpr -> a -> b -> ViewBuilder events ()
belowWithGap gap a b = do
  ensure $ centerX a @=@ centerX b
  ensure $ bottom a @+@ gap @=@ top b

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
  Style
    { styleBounds =
        Bounds
          (blockVar ref "top")
          (blockVar ref "left")
          (blockVar ref "width")
          (blockVar ref "height")
    , styleScalars = defaultStyleScalars
    , styleColors = defaultStyleColors
    , styleDiscrete = defaultStyleDiscrete
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
