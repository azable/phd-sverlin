{-# LANGUAGE DeriveTraversable   #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE KindSignatures      #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}

module LinearTrace.View.Style
  ( -- * Expression aliases
    Free
  , Layout
  , Unit
  , Angle
  , FreeExpr
  , LayoutExpr
  , UnitExpr
  , AngleExpr
  , Hue
  , HueExpr
  , HslExpr
  , MaterializedHsl
  , -- * Bounds
    Bounds(..)
  , BoundsExpr
  , MaterializedBounds
  , HasBounds(..)
  , -- * Basic CSS/style values
    Hsl(..)
  , CssText(..)
  , cssTextString
  , FontWeight(..)
  , FontStyle(..)
  , TextAlign(..)
  , BorderStyle(..)
  , WhiteSpace(..)
  , -- * Unified style representation
    Style
  , styleWithBounds
  , HasStyle(..)
  , StyleValueUnit(..)
  , StyleScalarSpec(..)
  , StyleTextSpec(..)
  , StyleChoiceSpec(..)
  , StyleChoiceValue(..)
  , StyleField(..)
  , styleBounds
  , styleFields
  , defaultStyleFields
  , setStyleField
  , mapStyleExprs
  , mapStyleExprLeaves
  , solvedStyleExprs
  , styleConstraints
  , styleChoiceConstraints
  , -- * Public style accessors/setters
    opacity
  , zIndex
  , padding
  , fontSize
  , radius
  , strokeWidth
  , alpha
  , fill
  , stroke
  , setOpacity
  , setZIndex
  , setPadding
  , setFontSize
  , setRadius
  , setFill
  , setStroke
  , setStrokeWidth
  , setAlpha
  , setFontFamily
  , setFontWeight
  , setFontWeightChoice
  , setFontStyle
  , setFontStyleChoice
  , setTextAlign
  , setTextAlignChoice
  , setBorderStyle
  , setBorderStyleChoice
  , setWhiteSpace
  , setWhiteSpaceChoice
  , -- * Materialization
    MaterializedStyle(..)
  , MaterializedField(..)
  , MaterializedScalar(..)
  , MaterializedColor(..)
  , MaterializedDiscrete(..)
  , MaterializedCssField(..)
  , MaterializedCssValue(..)
  , materializedTop
  , materializedLeft
  , materializedWidth
  , materializedHeight
  , materializedScalarValue
  , materializedScalars
  , materializedColors
  , materializedDiscrete
  , materializedCssFields
  , materializedCssAttrsWith
  , materializeStyle
  ) where

import           Data.Kind  (Type)
import           Data.Maybe (mapMaybe)
import           Prelude
import           Solver

--------------------------------------------------------------------------------
-- Expression aliases
--------------------------------------------------------------------------------
data Free

data Layout

data Unit

data Angle

instance SymbolicType Free where
  symbolicDomain _ = realDomain "free"

instance SymbolicType Layout where
  symbolicDomain _ = realDomain "layout"

instance SymbolicType Unit where
  symbolicDomain _ = realDomain "unit"

instance SymbolicType Angle where
  symbolicDomain _ = cyclicDomain "angle" 360

type FreeExpr = Expr Free

type LayoutExpr = Expr Layout

type UnitExpr = Expr Unit

type AngleExpr = Expr Angle

type Hue = Expr Angle

type HueExpr = Hue

type HslExpr = Hsl Hue UnitExpr

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
        allOf [at @==@ bt, al @==@ bl, aw @==@ bw, ah @==@ bh]

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

cssTextString :: CssText -> String
cssTextString cssText =
  case cssText of
    CssText text -> text

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

fontWeightCss :: FontWeight -> String
fontWeightCss value =
  case value of
    FontWeightNormal   -> "normal"
    FontWeightBold     -> "bold"
    FontWeightBolder   -> "bolder"
    FontWeightLighter  -> "lighter"
    FontWeightNumber n -> show n

fontStyleCss :: FontStyle -> String
fontStyleCss value =
  case value of
    FontStyleNormal  -> "normal"
    FontStyleItalic  -> "italic"
    FontStyleOblique -> "oblique"

textAlignCss :: TextAlign -> String
textAlignCss value =
  case value of
    TextAlignLeft    -> "left"
    TextAlignCenter  -> "center"
    TextAlignRight   -> "right"
    TextAlignJustify -> "justify"

borderStyleCss :: BorderStyle -> String
borderStyleCss value =
  case value of
    BorderNone   -> "none"
    BorderSolid  -> "solid"
    BorderDashed -> "dashed"
    BorderDotted -> "dotted"
    BorderDouble -> "double"

whiteSpaceCss :: WhiteSpace -> String
whiteSpaceCss value =
  case value of
    WhiteSpaceNormal  -> "normal"
    WhiteSpaceNoWrap  -> "nowrap"
    WhiteSpacePre     -> "pre"
    WhiteSpacePreWrap -> "pre-wrap"

fontWeightChoices :: [FontWeight]
fontWeightChoices =
  [FontWeightNormal, FontWeightBold, FontWeightBolder, FontWeightLighter]
    ++ map FontWeightNumber [100,200 .. 900]

fontStyleChoices :: [FontStyle]
fontStyleChoices = [FontStyleNormal, FontStyleItalic, FontStyleOblique]

textAlignChoices :: [TextAlign]
textAlignChoices =
  [TextAlignLeft, TextAlignCenter, TextAlignRight, TextAlignJustify]

borderStyleChoices :: [BorderStyle]
borderStyleChoices =
  [BorderNone, BorderSolid, BorderDashed, BorderDotted, BorderDouble]

whiteSpaceChoices :: [WhiteSpace]
whiteSpaceChoices =
  [WhiteSpaceNormal, WhiteSpaceNoWrap, WhiteSpacePre, WhiteSpacePreWrap]

instance CategoricalType FontWeight where
  categoricalDomain _ = map (category . fontWeightCss) fontWeightChoices

instance CategoricalType FontStyle where
  categoricalDomain _ = map (category . fontStyleCss) fontStyleChoices

instance CategoricalType TextAlign where
  categoricalDomain _ = map (category . textAlignCss) textAlignChoices

instance CategoricalType BorderStyle where
  categoricalDomain _ = map (category . borderStyleCss) borderStyleChoices

instance CategoricalType WhiteSpace where
  categoricalDomain _ = map (category . whiteSpaceCss) whiteSpaceChoices

--------------------------------------------------------------------------------
-- Unified style representation
--------------------------------------------------------------------------------
data StyleValueUnit
  = StyleNumber
  | StylePixels
  | StyleHidden
  deriving (Eq, Show)

data StyleScalarSpec = StyleScalarSpec
  { styleScalarName         :: String
  , styleScalarCssName      :: Maybe String
  , styleScalarInitialRange :: Maybe Range
  , styleScalarValueUnit    :: StyleValueUnit
  , styleScalarConstraints  :: [Constraint]
  }

data StyleTextSpec = StyleTextSpec
  { styleTextName    :: String
  , styleTextCssName :: Maybe String
  }

data StyleChoiceValue value
  = FixedStyleChoice value
  | SolvedStyleChoice (Choice value)
  deriving (Eq, Show)

data StyleChoiceSpec value = StyleChoiceSpec
  { styleChoiceName          :: String
  , styleChoiceCssName       :: Maybe String
  , styleChoiceDomainValues  :: [value]
  , styleChoiceCategoryName  :: value -> String
  , styleChoiceCssValue      :: value -> String
  , styleChoiceDiscreteValue :: Maybe value -> MaterializedDiscrete
  }

data StyleField where
  StyleFreeField :: StyleScalarSpec -> FreeExpr -> StyleField
  StyleLayoutField :: StyleScalarSpec -> LayoutExpr -> StyleField
  StyleUnitField :: StyleScalarSpec -> UnitExpr -> StyleField
  StyleAngleField :: StyleScalarSpec -> AngleExpr -> StyleField
  StyleColorField :: StyleTextSpec -> Maybe HslExpr -> StyleField
  StyleTextField :: StyleTextSpec -> Maybe CssText -> StyleField
  StyleChoiceField
    :: StyleChoiceSpec value -> Maybe (StyleChoiceValue value) -> StyleField

fieldName :: StyleField -> String
fieldName field =
  case field of
    StyleFreeField spec _   -> styleScalarName spec
    StyleLayoutField spec _ -> styleScalarName spec
    StyleUnitField spec _   -> styleScalarName spec
    StyleAngleField spec _  -> styleScalarName spec
    StyleColorField spec _  -> styleTextName spec
    StyleTextField spec _   -> styleTextName spec
    StyleChoiceField spec _ -> styleChoiceName spec

data Style = Style
  { styleBounds :: BoundsExpr
  , styleFields :: [StyleField]
  }

styleWithBounds :: BoundsExpr -> Style
styleWithBounds bounds =
  Style {styleBounds = bounds, styleFields = defaultStyleFields}

instance HasBounds Style where
  top = top . styleBounds
  left = left . styleBounds
  width = width . styleBounds
  height = height . styleBounds

class HasStyle a where
  style :: a -> Style

instance HasStyle Style where
  style = id

setStyleField :: StyleField -> Style -> Style
setStyleField newField style' =
  style' {styleFields = replaceByName fieldName newField (styleFields style')}

mapStyleExprs :: (forall (ty :: Type). Expr ty -> Expr ty) -> Style -> Style
mapStyleExprs f style' =
  Style
    { styleBounds = fmap f (styleBounds style')
    , styleFields = map (mapStyleFieldExprs f) (styleFields style')
    }

mapStyleFieldExprs ::
     (forall (ty :: Type). Expr ty -> Expr ty) -> StyleField -> StyleField
mapStyleFieldExprs f field =
  case field of
    StyleFreeField spec expr -> StyleFreeField spec (f expr)
    StyleLayoutField spec expr -> StyleLayoutField spec (f expr)
    StyleUnitField spec expr -> StyleUnitField spec (f expr)
    StyleAngleField spec expr -> StyleAngleField spec (f expr)
    StyleColorField spec maybeHsl ->
      StyleColorField spec (fmap (fmap f) maybeHsl)
    StyleTextField _ _ -> field
    StyleChoiceField _ _ -> field

replaceByName :: (a -> String) -> a -> [a] -> [a]
replaceByName getName newValue = go
  where
    target = getName newValue
    go xs =
      case xs of
        [] -> [newValue]
        x:rest
          | getName x == target -> newValue : rest
          | otherwise -> x : go rest

--------------------------------------------------------------------------------
-- Style inspection
--------------------------------------------------------------------------------
data StyleExprLeaf where
  StyleExprLeaf :: String -> Expr (ty :: Type) -> StyleExprLeaf

styleExprLeaves :: Style -> [StyleExprLeaf]
styleExprLeaves style' =
  [ StyleExprLeaf "top" (top style')
  , StyleExprLeaf "left" (left style')
  , StyleExprLeaf "width" (width style')
  , StyleExprLeaf "height" (height style')
  ]
    ++ concatMap fieldExprLeaves (styleFields style')

fieldExprLeaves :: StyleField -> [StyleExprLeaf]
fieldExprLeaves field =
  case field of
    StyleFreeField spec expr -> [StyleExprLeaf (styleScalarName spec) expr]
    StyleLayoutField spec expr -> [StyleExprLeaf (styleScalarName spec) expr]
    StyleUnitField spec expr -> [StyleExprLeaf (styleScalarName spec) expr]
    StyleAngleField spec expr -> [StyleExprLeaf (styleScalarName spec) expr]
    StyleColorField spec maybeHsl ->
      case maybeHsl of
        Nothing -> []
        Just hsl ->
          [ StyleExprLeaf (styleTextName spec ++ ".hue") (hue hsl)
          , StyleExprLeaf (styleTextName spec ++ ".saturation") (saturation hsl)
          , StyleExprLeaf (styleTextName spec ++ ".lightness") (lightness hsl)
          ]
    StyleTextField _ _ -> []
    StyleChoiceField _ _ -> []

mapStyleExprLeaves ::
     (forall (ty :: Type). String -> Expr ty -> a) -> Style -> [a]
mapStyleExprLeaves f style' = map go (styleExprLeaves style')
  where
    go leaf =
      case leaf of
        StyleExprLeaf name expr -> f name expr

solvedStyleExprs :: Solution -> Style -> [(String, Double)]
solvedStyleExprs solution = mapMaybe solveLeaf . styleExprLeaves
  where
    solveLeaf leaf =
      case leaf of
        StyleExprLeaf name expr ->
          case evalExpr solution expr of
            Nothing    -> Nothing
            Just value -> Just (name, value)

styleConstraints :: Style -> [Constraint]
styleConstraints style' = concatMap fieldConstraints (styleFields style')

styleChoiceConstraints :: Style -> [ChoiceConstraint]
styleChoiceConstraints style' =
  concatMap fieldChoiceConstraints (styleFields style')

fieldConstraints :: StyleField -> [Constraint]
fieldConstraints field =
  case field of
    StyleFreeField spec expr -> scalarConstraints spec expr
    StyleLayoutField spec expr -> scalarConstraints spec expr
    StyleUnitField spec expr -> scalarConstraints spec expr
    StyleAngleField spec expr -> scalarConstraints spec expr
    StyleColorField _ maybeHsl ->
      case maybeHsl of
        Nothing -> []
        Just hsl ->
          [ within (hue hsl) (Range 0 360)
          , within (saturation hsl) (Range 0 1)
          , within (lightness hsl) (Range 0 1)
          ]
    StyleTextField _ _ -> []
    StyleChoiceField _ _ -> []

fieldChoiceConstraints :: StyleField -> [ChoiceConstraint]
fieldChoiceConstraints field =
  case field of
    StyleChoiceField _ (Just (SolvedStyleChoice selected)) ->
      [freeChoice selected]
    _ -> []

scalarConstraints ::
     SymbolicType ty => StyleScalarSpec -> Expr ty -> [Constraint]
scalarConstraints spec expr =
  case styleScalarInitialRange spec of
    Just range -> within expr range : styleScalarConstraints spec
    Nothing    -> styleScalarConstraints spec

--------------------------------------------------------------------------------
-- Constraint helpers used by attributes
--------------------------------------------------------------------------------
noConstraints :: Expr ty -> [Constraint]
noConstraints _ = []

nonNegativeConstraints :: SymbolicType ty => Expr ty -> [Constraint]
nonNegativeConstraints expr = [num 0 @<=@ expr]

unitConstraints :: UnitExpr -> [Constraint]
unitConstraints expr = [num 0 @<=@ expr, expr @<=@ num 1]

--------------------------------------------------------------------------------
-- Field constructors
--------------------------------------------------------------------------------
freeScalarField ::
     String
  -> Maybe String
  -> StyleValueUnit
  -> Maybe Range
  -> (FreeExpr -> [Constraint])
  -> FreeExpr
  -> StyleField
freeScalarField name cssName unit range constraints expr =
  StyleFreeField
    StyleScalarSpec
      { styleScalarName = name
      , styleScalarCssName = cssName
      , styleScalarInitialRange = range
      , styleScalarValueUnit = unit
      , styleScalarConstraints = constraints expr
      }
    expr

layoutScalarField ::
     String
  -> Maybe String
  -> StyleValueUnit
  -> Maybe Range
  -> (LayoutExpr -> [Constraint])
  -> LayoutExpr
  -> StyleField
layoutScalarField name cssName unit range constraints expr =
  StyleLayoutField
    StyleScalarSpec
      { styleScalarName = name
      , styleScalarCssName = cssName
      , styleScalarInitialRange = range
      , styleScalarValueUnit = unit
      , styleScalarConstraints = constraints expr
      }
    expr

unitScalarField ::
     String
  -> Maybe String
  -> StyleValueUnit
  -> Maybe Range
  -> (UnitExpr -> [Constraint])
  -> UnitExpr
  -> StyleField
unitScalarField name cssName unit range constraints expr =
  StyleUnitField
    StyleScalarSpec
      { styleScalarName = name
      , styleScalarCssName = cssName
      , styleScalarInitialRange = range
      , styleScalarValueUnit = unit
      , styleScalarConstraints = constraints expr
      }
    expr

textSpec :: String -> Maybe String -> StyleTextSpec
textSpec name cssName =
  StyleTextSpec {styleTextName = name, styleTextCssName = cssName}

choiceSpec ::
     String
  -> Maybe String
  -> [value]
  -> (value -> String)
  -> (Maybe value -> MaterializedDiscrete)
  -> StyleChoiceSpec value
choiceSpec name cssName values toCss toDiscrete =
  StyleChoiceSpec
    { styleChoiceName = name
    , styleChoiceCssName = cssName
    , styleChoiceDomainValues = values
    , styleChoiceCategoryName = toCss
    , styleChoiceCssValue = toCss
    , styleChoiceDiscreteValue = toDiscrete
    }

choiceField ::
     StyleChoiceSpec value -> Maybe (StyleChoiceValue value) -> StyleField
choiceField = StyleChoiceField

--------------------------------------------------------------------------------
-- Attribute: opacity
--------------------------------------------------------------------------------
opacityDefault :: UnitExpr
opacityDefault = num 1

opacityField :: UnitExpr -> StyleField
opacityField =
  unitScalarField
    "opacity"
    (Just "opacity")
    StyleNumber
    (Just (Range 0 1))
    unitConstraints

opacity :: HasStyle a => a -> UnitExpr
opacity value = lookupUnitField "opacity" opacityDefault (style value)

setOpacity :: UnitExpr -> Style -> Style
setOpacity = setStyleField . opacityField

--------------------------------------------------------------------------------
-- Attribute: zIndex
--------------------------------------------------------------------------------
zIndexDefault :: FreeExpr
zIndexDefault = num 0

zIndexField :: FreeExpr -> StyleField
zIndexField =
  freeScalarField
    "zIndex"
    (Just "zIndex")
    StyleNumber
    (Just (Range (-10) 10))
    noConstraints

zIndex :: HasStyle a => a -> FreeExpr
zIndex value = lookupFreeField "zIndex" zIndexDefault (style value)

setZIndex :: FreeExpr -> Style -> Style
setZIndex = setStyleField . zIndexField

--------------------------------------------------------------------------------
-- Attribute: padding
--------------------------------------------------------------------------------
paddingDefault :: LayoutExpr
paddingDefault = num 0

paddingField :: LayoutExpr -> StyleField
paddingField =
  layoutScalarField
    "padding"
    (Just "padding")
    StylePixels
    (Just (Range 0 24))
    nonNegativeConstraints

padding :: HasStyle a => a -> LayoutExpr
padding value = lookupLayoutField "padding" paddingDefault (style value)

setPadding :: LayoutExpr -> Style -> Style
setPadding = setStyleField . paddingField

--------------------------------------------------------------------------------
-- Attribute: fontSize
--------------------------------------------------------------------------------
fontSizeDefault :: LayoutExpr
fontSizeDefault = num 16

fontSizeField :: LayoutExpr -> StyleField
fontSizeField =
  layoutScalarField
    "fontSize"
    (Just "fontSize")
    StylePixels
    (Just (Range 8 48))
    nonNegativeConstraints

fontSize :: HasStyle a => a -> LayoutExpr
fontSize value = lookupLayoutField "fontSize" fontSizeDefault (style value)

setFontSize :: LayoutExpr -> Style -> Style
setFontSize = setStyleField . fontSizeField

--------------------------------------------------------------------------------
-- Attribute: radius
--------------------------------------------------------------------------------
radiusDefault :: LayoutExpr
radiusDefault = num 0

radiusField :: LayoutExpr -> StyleField
radiusField =
  layoutScalarField
    "radius"
    (Just "borderRadius")
    StylePixels
    (Just (Range 0 32))
    nonNegativeConstraints

radius :: HasStyle a => a -> LayoutExpr
radius value = lookupLayoutField "radius" radiusDefault (style value)

setRadius :: LayoutExpr -> Style -> Style
setRadius = setStyleField . radiusField

--------------------------------------------------------------------------------
-- Attribute: strokeWidth
--------------------------------------------------------------------------------
strokeWidthDefault :: LayoutExpr
strokeWidthDefault = num 0

strokeWidthField :: LayoutExpr -> StyleField
strokeWidthField =
  layoutScalarField
    "strokeWidth"
    (Just "borderWidth")
    StylePixels
    (Just (Range 0 8))
    nonNegativeConstraints

strokeWidth :: HasStyle a => a -> LayoutExpr
strokeWidth value =
  lookupLayoutField "strokeWidth" strokeWidthDefault (style value)

setStrokeWidth :: LayoutExpr -> Style -> Style
setStrokeWidth = setStyleField . strokeWidthField

--------------------------------------------------------------------------------
-- Attribute: alpha
--------------------------------------------------------------------------------
alphaDefault :: UnitExpr
alphaDefault = num 1

alphaField :: UnitExpr -> StyleField
alphaField =
  unitScalarField "alpha" Nothing StyleHidden (Just (Range 0 1)) unitConstraints

alpha :: HasStyle a => a -> UnitExpr
alpha value = lookupUnitField "alpha" alphaDefault (style value)

setAlpha :: UnitExpr -> Style -> Style
setAlpha = setStyleField . alphaField

--------------------------------------------------------------------------------
-- Attribute: fill
--------------------------------------------------------------------------------
fillDefault :: Maybe HslExpr
fillDefault = Nothing

fillField :: Maybe HslExpr -> StyleField
fillField = StyleColorField (textSpec "fill" (Just "backgroundColor"))

fill :: HasStyle a => a -> Maybe HslExpr
fill value = lookupColorField "fill" fillDefault (style value)

setFill :: HslExpr -> Style -> Style
setFill = setStyleField . fillField . Just

--------------------------------------------------------------------------------
-- Attribute: stroke
--------------------------------------------------------------------------------
strokeDefault :: Maybe HslExpr
strokeDefault = Nothing

strokeField :: Maybe HslExpr -> StyleField
strokeField = StyleColorField (textSpec "stroke" (Just "borderColor"))

stroke :: HasStyle a => a -> Maybe HslExpr
stroke value = lookupColorField "stroke" strokeDefault (style value)

setStroke :: HslExpr -> Style -> Style
setStroke = setStyleField . strokeField . Just

--------------------------------------------------------------------------------
-- Attribute: fontFamily
--------------------------------------------------------------------------------
fontFamilyField :: Maybe CssText -> StyleField
fontFamilyField = StyleTextField (textSpec "fontFamily" (Just "fontFamily"))

setFontFamily :: String -> Style -> Style
setFontFamily = setStyleField . fontFamilyField . Just . CssText

--------------------------------------------------------------------------------
-- Attribute: fontWeight
--------------------------------------------------------------------------------
fontWeightSpec :: StyleChoiceSpec FontWeight
fontWeightSpec =
  choiceSpec
    "fontWeight"
    (Just "fontWeight")
    fontWeightChoices
    fontWeightCss
    (MaterializedFontWeightAttr "fontWeight")

fontWeightField :: Maybe (StyleChoiceValue FontWeight) -> StyleField
fontWeightField = choiceField fontWeightSpec

setFontWeight :: FontWeight -> Style -> Style
setFontWeight = setStyleField . fontWeightField . Just . FixedStyleChoice

setFontWeightChoice :: Choice FontWeight -> Style -> Style
setFontWeightChoice = setStyleField . fontWeightField . Just . SolvedStyleChoice

--------------------------------------------------------------------------------
-- Attribute: fontStyle
--------------------------------------------------------------------------------
fontStyleSpec :: StyleChoiceSpec FontStyle
fontStyleSpec =
  choiceSpec
    "fontStyle"
    (Just "fontStyle")
    fontStyleChoices
    fontStyleCss
    (MaterializedFontStyleAttr "fontStyle")

fontStyleField :: Maybe (StyleChoiceValue FontStyle) -> StyleField
fontStyleField = choiceField fontStyleSpec

setFontStyle :: FontStyle -> Style -> Style
setFontStyle = setStyleField . fontStyleField . Just . FixedStyleChoice

setFontStyleChoice :: Choice FontStyle -> Style -> Style
setFontStyleChoice = setStyleField . fontStyleField . Just . SolvedStyleChoice

--------------------------------------------------------------------------------
-- Attribute: textAlign
--------------------------------------------------------------------------------
textAlignSpec :: StyleChoiceSpec TextAlign
textAlignSpec =
  choiceSpec
    "textAlign"
    (Just "textAlign")
    textAlignChoices
    textAlignCss
    (MaterializedTextAlignAttr "textAlign")

textAlignField :: Maybe (StyleChoiceValue TextAlign) -> StyleField
textAlignField = choiceField textAlignSpec

setTextAlign :: TextAlign -> Style -> Style
setTextAlign = setStyleField . textAlignField . Just . FixedStyleChoice

setTextAlignChoice :: Choice TextAlign -> Style -> Style
setTextAlignChoice = setStyleField . textAlignField . Just . SolvedStyleChoice

--------------------------------------------------------------------------------
-- Attribute: borderStyle
--------------------------------------------------------------------------------
borderStyleSpec :: StyleChoiceSpec BorderStyle
borderStyleSpec =
  choiceSpec
    "borderStyle"
    (Just "borderStyle")
    borderStyleChoices
    borderStyleCss
    (MaterializedBorderStyleAttr "borderStyle")

borderStyleField :: Maybe (StyleChoiceValue BorderStyle) -> StyleField
borderStyleField = choiceField borderStyleSpec

setBorderStyle :: BorderStyle -> Style -> Style
setBorderStyle = setStyleField . borderStyleField . Just . FixedStyleChoice

setBorderStyleChoice :: Choice BorderStyle -> Style -> Style
setBorderStyleChoice =
  setStyleField . borderStyleField . Just . SolvedStyleChoice

--------------------------------------------------------------------------------
-- Attribute: whiteSpace
--------------------------------------------------------------------------------
whiteSpaceSpec :: StyleChoiceSpec WhiteSpace
whiteSpaceSpec =
  choiceSpec
    "whiteSpace"
    (Just "whiteSpace")
    whiteSpaceChoices
    whiteSpaceCss
    (MaterializedWhiteSpaceAttr "whiteSpace")

whiteSpaceField :: Maybe (StyleChoiceValue WhiteSpace) -> StyleField
whiteSpaceField = choiceField whiteSpaceSpec

setWhiteSpace :: WhiteSpace -> Style -> Style
setWhiteSpace = setStyleField . whiteSpaceField . Just . FixedStyleChoice

setWhiteSpaceChoice :: Choice WhiteSpace -> Style -> Style
setWhiteSpaceChoice = setStyleField . whiteSpaceField . Just . SolvedStyleChoice

--------------------------------------------------------------------------------
-- Defaults
--------------------------------------------------------------------------------
defaultStyleFields :: [StyleField]
defaultStyleFields =
  [ opacityField opacityDefault
  , zIndexField zIndexDefault
  , paddingField paddingDefault
  , fontSizeField fontSizeDefault
  , radiusField radiusDefault
  , strokeWidthField strokeWidthDefault
  , alphaField alphaDefault
  , fillField fillDefault
  , strokeField strokeDefault
  , fontFamilyField Nothing
  , fontWeightField Nothing
  , fontStyleField Nothing
  , textAlignField Nothing
  , borderStyleField Nothing
  , whiteSpaceField Nothing
  ]

--------------------------------------------------------------------------------
-- Field lookup
--------------------------------------------------------------------------------
lookupFreeField :: String -> FreeExpr -> Style -> FreeExpr
lookupFreeField name fallback style' = go (styleFields style')
  where
    go fields =
      case fields of
        [] -> fallback
        StyleFreeField spec expr:rest
          | styleScalarName spec == name -> expr
          | otherwise -> go rest
        _:rest -> go rest

lookupLayoutField :: String -> LayoutExpr -> Style -> LayoutExpr
lookupLayoutField name fallback style' = go (styleFields style')
  where
    go fields =
      case fields of
        [] -> fallback
        StyleLayoutField spec expr:rest
          | styleScalarName spec == name -> expr
          | otherwise -> go rest
        _:rest -> go rest

lookupUnitField :: String -> UnitExpr -> Style -> UnitExpr
lookupUnitField name fallback style' = go (styleFields style')
  where
    go fields =
      case fields of
        [] -> fallback
        StyleUnitField spec expr:rest
          | styleScalarName spec == name -> expr
          | otherwise -> go rest
        _:rest -> go rest

lookupColorField :: String -> Maybe HslExpr -> Style -> Maybe HslExpr
lookupColorField name fallback style' = go (styleFields style')
  where
    go fields =
      case fields of
        [] -> fallback
        StyleColorField spec value:rest
          | styleTextName spec == name -> value
          | otherwise -> go rest
        _:rest -> go rest

--------------------------------------------------------------------------------
-- Materialization
--------------------------------------------------------------------------------
data MaterializedField
  = MaterializedScalarField String (Maybe String) Double StyleValueUnit
  | MaterializedColorField String (Maybe String) (Maybe MaterializedHsl)
  | MaterializedTextField String (Maybe String) (Maybe CssText)
  | MaterializedChoiceField
      String
      (Maybe String)
      (Maybe String)
      MaterializedDiscrete
  deriving (Eq, Show)

data MaterializedStyle = MaterializedStyle
  { materializedBounds :: MaterializedBounds
  , materializedFields :: [MaterializedField]
  } deriving (Eq, Show)

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
  deriving (Eq, Show)

data MaterializedCssField =
  MaterializedCssField String MaterializedCssValue
  deriving (Eq, Show)

data MaterializedCssValue
  = CssNumberValue Double
  | CssPixelsValue Double
  | CssTextValue String
  | CssHslValue Double MaterializedHsl
  deriving (Eq, Show)

materializedTop :: MaterializedStyle -> Double
materializedTop = boundsTop . materializedBounds

materializedLeft :: MaterializedStyle -> Double
materializedLeft = boundsLeft . materializedBounds

materializedWidth :: MaterializedStyle -> Double
materializedWidth = boundsWidth . materializedBounds

materializedHeight :: MaterializedStyle -> Double
materializedHeight = boundsHeight . materializedBounds

materializedScalarValue :: String -> Double -> MaterializedStyle -> Double
materializedScalarValue name fallback style' = go (materializedFields style')
  where
    go fields =
      case fields of
        [] -> fallback
        MaterializedScalarField name' _ value _:rest
          | name == name' -> value
          | otherwise -> go rest
        _:rest -> go rest

materializedScalars :: MaterializedStyle -> [MaterializedScalar]
materializedScalars style' = concatMap fieldScalar (materializedFields style')
  where
    fieldScalar field =
      case field of
        MaterializedScalarField name _ value unit ->
          [MaterializedScalar name value unit]
        _ -> []

materializedColors :: MaterializedStyle -> [MaterializedColor]
materializedColors style' = concatMap fieldColor (materializedFields style')
  where
    fieldColor field =
      case field of
        MaterializedColorField name _ value -> [MaterializedColor name value]
        _                                   -> []

materializedDiscrete :: MaterializedStyle -> [MaterializedDiscrete]
materializedDiscrete style' =
  concatMap fieldDiscrete (materializedFields style')
  where
    fieldDiscrete field =
      case field of
        MaterializedTextField name _ value -> [MaterializedTextAttr name value]
        MaterializedChoiceField _ _ _ discrete -> [discrete]
        _ -> []

materializedCssFields :: MaterializedStyle -> [MaterializedCssField]
materializedCssFields style' =
  concatMap (fieldCss alphaValue) (materializedFields style')
  where
    alphaValue = materializedScalarValue "alpha" 1 style'

materializedCssAttrsWith ::
     (Double -> a)
  -> (Double -> a)
  -> (String -> a)
  -> (Double -> MaterializedHsl -> a)
  -> MaterializedStyle
  -> [(String, a)]
materializedCssAttrsWith number pixels text hsl style' =
  map convertField (materializedCssFields style')
  where
    convertField field =
      case field of
        MaterializedCssField name value -> (name, convertValue value)
    convertValue value =
      case value of
        CssNumberValue x            -> number x
        CssPixelsValue x            -> pixels x
        CssTextValue value'         -> text value'
        CssHslValue alphaValue hsl' -> hsl alphaValue hsl'

fieldCss :: Double -> MaterializedField -> [MaterializedCssField]
fieldCss alphaValue field =
  case field of
    MaterializedScalarField _ cssName value unit ->
      case (cssName, unit) of
        (Just name, StyleNumber) ->
          [MaterializedCssField name (CssNumberValue value)]
        (Just name, StylePixels) ->
          [MaterializedCssField name (CssPixelsValue value)]
        _ -> []
    MaterializedColorField _ cssName maybeHsl ->
      case (cssName, maybeHsl) of
        (Just name, Just hsl) ->
          [MaterializedCssField name (CssHslValue alphaValue hsl)]
        _ -> []
    MaterializedTextField _ cssName maybeText -> cssTextField cssName maybeText
    MaterializedChoiceField _ cssName maybeCss _ ->
      cssStringField cssName maybeCss

cssTextField :: Maybe String -> Maybe CssText -> [MaterializedCssField]
cssTextField maybeName maybeText =
  cssStringField maybeName (cssTextString <$> maybeText)

cssStringField :: Maybe String -> Maybe String -> [MaterializedCssField]
cssStringField maybeName maybeText =
  case (maybeName, maybeText) of
    (Just name, Just text) -> [MaterializedCssField name (CssTextValue text)]
    _                      -> []

materializeStyle :: Solution -> Style -> Maybe MaterializedStyle
materializeStyle solution style' =
  MaterializedStyle
    <$> materializeBounds solution (styleBounds style')
    <*> traverse (materializeField solution) (styleFields style')

materializeBounds :: Solution -> BoundsExpr -> Maybe MaterializedBounds
materializeBounds solution = traverse (evalExpr solution)

materializeField :: Solution -> StyleField -> Maybe MaterializedField
materializeField solution field =
  case field of
    StyleFreeField spec expr -> materializeScalar solution spec expr
    StyleLayoutField spec expr -> materializeScalar solution spec expr
    StyleUnitField spec expr -> materializeScalar solution spec expr
    StyleAngleField spec expr -> materializeScalar solution spec expr
    StyleColorField spec maybeHsl ->
      MaterializedColorField (styleTextName spec) (styleTextCssName spec)
        <$> traverse (materializeHsl solution) maybeHsl
    StyleTextField spec value ->
      Just
        (MaterializedTextField
           (styleTextName spec)
           (styleTextCssName spec)
           value)
    StyleChoiceField spec value -> materializeChoiceField solution spec value

materializeChoiceField ::
     Solution
  -> StyleChoiceSpec value
  -> Maybe (StyleChoiceValue value)
  -> Maybe MaterializedField
materializeChoiceField solution spec maybeValue = do
  materializedValue <-
    traverse (materializeChoiceValue solution spec) maybeValue
  pure
    (MaterializedChoiceField
       (styleChoiceName spec)
       (styleChoiceCssName spec)
       (styleChoiceCssValue spec <$> materializedValue)
       (styleChoiceDiscreteValue spec materializedValue))

materializeChoiceValue ::
     Solution -> StyleChoiceSpec value -> StyleChoiceValue value -> Maybe value
materializeChoiceValue solution spec value =
  case value of
    FixedStyleChoice fixed -> Just fixed
    SolvedStyleChoice selected -> do
      selectedCategory <- evalChoice solution selected
      lookupChoiceValue spec (categoryName selectedCategory)

lookupChoiceValue :: StyleChoiceSpec value -> String -> Maybe value
lookupChoiceValue spec name = go (styleChoiceDomainValues spec)
  where
    go values =
      case values of
        [] -> Nothing
        value:rest
          | styleChoiceCategoryName spec value == name -> Just value
          | otherwise -> go rest

materializeScalar ::
     Solution -> StyleScalarSpec -> Expr ty -> Maybe MaterializedField
materializeScalar solution spec expr =
  MaterializedScalarField (styleScalarName spec) (styleScalarCssName spec)
    <$> evalExpr solution expr
    <*> pure (styleScalarValueUnit spec)

materializeHsl :: Solution -> HslExpr -> Maybe MaterializedHsl
materializeHsl solution hsl =
  Hsl
    <$> evalExpr solution (hue hsl)
    <*> evalExpr solution (saturation hsl)
    <*> evalExpr solution (lightness hsl)
