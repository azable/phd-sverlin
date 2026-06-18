{-# LANGUAGE DeriveTraversable   #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE KindSignatures      #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}

module LinearTrace.Visualize.Style
  ( -- * Expression aliases
    FreeExpr
  , LayoutExpr
  , UnitExpr
  , AngleExpr
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
  , StyleField(..)
  , styleBounds
  , styleFields
  , defaultStyleFields
  , setStyleField
  , mapStyleExprLeaves
  , solvedStyleExprs
  , styleInitialVars
  , styleConstraints
  , -- * Public style accessors/setters
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
  , materializedTop
  , materializedLeft
  , materializedWidth
  , materializedHeight
  , materializedScalarValue
  , materializedScalars
  , materializedColors
  , materializedDiscrete
  , materializedCssClass
  , materializedClassName
  , materializedCssFields
  , materializedCssAttrsWith
  , materializeStyle
  ) where

import           Data.Kind          (Type)
import           Data.Maybe         (mapMaybe, maybeToList)
import           LinearTrace.Solver
import           Prelude

--------------------------------------------------------------------------------
-- Expression aliases
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
        All [at @==@ bt, al @==@ bl, aw @==@ bw, ah @==@ bh]

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

data StyleField
  = StyleFreeField StyleScalarSpec FreeExpr
  | StyleLayoutField StyleScalarSpec LayoutExpr
  | StyleUnitField StyleScalarSpec UnitExpr
  | StyleAngleField StyleScalarSpec AngleExpr
  | StyleColorField StyleTextSpec (Maybe HslExpr)
  | StyleTextField StyleTextSpec (Maybe CssText)
  | StyleFontWeightField StyleTextSpec (Maybe FontWeight)
  | StyleFontStyleField StyleTextSpec (Maybe FontStyle)
  | StyleTextAlignField StyleTextSpec (Maybe TextAlign)
  | StyleBorderStyleField StyleTextSpec (Maybe BorderStyle)
  | StyleWhiteSpaceField StyleTextSpec (Maybe WhiteSpace)
  | StyleClassField StyleTextSpec (Maybe CssText)

fieldName :: StyleField -> String
fieldName field =
  case field of
    StyleFreeField spec _        -> styleScalarName spec
    StyleLayoutField spec _      -> styleScalarName spec
    StyleUnitField spec _        -> styleScalarName spec
    StyleAngleField spec _       -> styleScalarName spec
    StyleColorField spec _       -> styleTextName spec
    StyleTextField spec _        -> styleTextName spec
    StyleFontWeightField spec _  -> styleTextName spec
    StyleFontStyleField spec _   -> styleTextName spec
    StyleTextAlignField spec _   -> styleTextName spec
    StyleBorderStyleField spec _ -> styleTextName spec
    StyleWhiteSpaceField spec _  -> styleTextName spec
    StyleClassField spec _       -> styleTextName spec

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
    StyleFontWeightField _ _ -> []
    StyleFontStyleField _ _ -> []
    StyleTextAlignField _ _ -> []
    StyleBorderStyleField _ _ -> []
    StyleWhiteSpaceField _ _ -> []
    StyleClassField _ _ -> []

mapStyleExprLeaves ::
     (forall (ty :: Type). String -> Expr ty -> a)
  -> Style
  -> [a]
mapStyleExprLeaves f style' = map go (styleExprLeaves style')
  where
    go leaf =
      case leaf of
        StyleExprLeaf name expr -> f name expr

solvedStyleExprs :: Solution -> Style -> [(String, Double)]
solvedStyleExprs solution =
  mapMaybe solveLeaf . styleExprLeaves
  where
    solveLeaf leaf =
      case leaf of
        StyleExprLeaf name expr ->
          case evalExpr solution expr of
            Nothing    -> Nothing
            Just value -> Just (name, value)

styleInitialVars :: Style -> [InitialVar]
styleInitialVars style' = concatMap fieldInitialVars (styleFields style')

fieldInitialVars :: StyleField -> [InitialVar]
fieldInitialVars field =
  case field of
    StyleFreeField spec expr -> scalarInitialVars spec expr
    StyleLayoutField spec expr -> scalarInitialVars spec expr
    StyleUnitField spec expr -> scalarInitialVars spec expr
    StyleAngleField spec expr -> scalarInitialVars spec expr
    StyleColorField _ maybeHsl ->
      case maybeHsl of
        Nothing -> []
        Just hsl ->
          concat
            [ maybeToList (initialRangeFor (hue hsl) (Range 0 360))
            , maybeToList (initialRangeFor (saturation hsl) (Range 0 1))
            , maybeToList (initialRangeFor (lightness hsl) (Range 0 1))
            ]
    StyleTextField _ _ -> []
    StyleFontWeightField _ _ -> []
    StyleFontStyleField _ _ -> []
    StyleTextAlignField _ _ -> []
    StyleBorderStyleField _ _ -> []
    StyleWhiteSpaceField _ _ -> []
    StyleClassField _ _ -> []

scalarInitialVars :: StyleScalarSpec -> Expr ty -> [InitialVar]
scalarInitialVars spec expr =
  case styleScalarInitialRange spec of
    Nothing    -> []
    Just range -> maybeToList (initialRangeFor expr range)

styleConstraints :: Style -> [Constraint]
styleConstraints style' = concatMap fieldConstraints (styleFields style')

fieldConstraints :: StyleField -> [Constraint]
fieldConstraints field =
  case field of
    StyleFreeField spec _ -> styleScalarConstraints spec
    StyleLayoutField spec _ -> styleScalarConstraints spec
    StyleUnitField spec _ -> styleScalarConstraints spec
    StyleAngleField spec _ -> styleScalarConstraints spec
    StyleColorField _ maybeHsl ->
      case maybeHsl of
        Nothing -> []
        Just hsl ->
          concat
            [ angleConstraints (hue hsl)
            , unitConstraints (saturation hsl)
            , unitConstraints (lightness hsl)
            ]
    StyleTextField _ _ -> []
    StyleFontWeightField _ _ -> []
    StyleFontStyleField _ _ -> []
    StyleTextAlignField _ _ -> []
    StyleBorderStyleField _ _ -> []
    StyleWhiteSpaceField _ _ -> []
    StyleClassField _ _ -> []

--------------------------------------------------------------------------------
-- Constraint helpers used by attributes
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

angleScalarField ::
     String
  -> Maybe String
  -> StyleValueUnit
  -> Maybe Range
  -> (AngleExpr -> [Constraint])
  -> AngleExpr
  -> StyleField
angleScalarField name cssName unit range constraints expr =
  StyleAngleField
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
fontWeightField :: Maybe FontWeight -> StyleField
fontWeightField =
  StyleFontWeightField (textSpec "fontWeight" (Just "fontWeight"))

setFontWeight :: FontWeight -> Style -> Style
setFontWeight = setStyleField . fontWeightField . Just

--------------------------------------------------------------------------------
-- Attribute: fontStyle
--------------------------------------------------------------------------------
fontStyleField :: Maybe FontStyle -> StyleField
fontStyleField = StyleFontStyleField (textSpec "fontStyle" (Just "fontStyle"))

setFontStyle :: FontStyle -> Style -> Style
setFontStyle = setStyleField . fontStyleField . Just

--------------------------------------------------------------------------------
-- Attribute: textAlign
--------------------------------------------------------------------------------
textAlignField :: Maybe TextAlign -> StyleField
textAlignField = StyleTextAlignField (textSpec "textAlign" (Just "textAlign"))

setTextAlign :: TextAlign -> Style -> Style
setTextAlign = setStyleField . textAlignField . Just

--------------------------------------------------------------------------------
-- Attribute: borderStyle
--------------------------------------------------------------------------------
borderStyleField :: Maybe BorderStyle -> StyleField
borderStyleField =
  StyleBorderStyleField (textSpec "borderStyle" (Just "borderStyle"))

setBorderStyle :: BorderStyle -> Style -> Style
setBorderStyle = setStyleField . borderStyleField . Just

--------------------------------------------------------------------------------
-- Attribute: whiteSpace
--------------------------------------------------------------------------------
whiteSpaceField :: Maybe WhiteSpace -> StyleField
whiteSpaceField =
  StyleWhiteSpaceField (textSpec "whiteSpace" (Just "whiteSpace"))

setWhiteSpace :: WhiteSpace -> Style -> Style
setWhiteSpace = setStyleField . whiteSpaceField . Just

--------------------------------------------------------------------------------
-- Attribute: cssClass
--------------------------------------------------------------------------------
cssClassField :: Maybe CssText -> StyleField
cssClassField = StyleClassField (textSpec "cssClass" Nothing)

setCssClass :: String -> Style -> Style
setCssClass = setStyleField . cssClassField . Just . CssText

--------------------------------------------------------------------------------
-- Defaults
--------------------------------------------------------------------------------
defaultStyleFields :: [StyleField]
defaultStyleFields =
  [ opacityField opacityDefault
  , zIndexField zIndexDefault
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
  , cssClassField Nothing
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
  | MaterializedFontWeightField String (Maybe String) (Maybe FontWeight)
  | MaterializedFontStyleField String (Maybe String) (Maybe FontStyle)
  | MaterializedTextAlignField String (Maybe String) (Maybe TextAlign)
  | MaterializedBorderStyleField String (Maybe String) (Maybe BorderStyle)
  | MaterializedWhiteSpaceField String (Maybe String) (Maybe WhiteSpace)
  | MaterializedClassField String (Maybe CssText)
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
  | MaterializedClassAttr String (Maybe CssText)
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
        MaterializedFontWeightField name _ value ->
          [MaterializedFontWeightAttr name value]
        MaterializedFontStyleField name _ value ->
          [MaterializedFontStyleAttr name value]
        MaterializedTextAlignField name _ value ->
          [MaterializedTextAlignAttr name value]
        MaterializedBorderStyleField name _ value ->
          [MaterializedBorderStyleAttr name value]
        MaterializedWhiteSpaceField name _ value ->
          [MaterializedWhiteSpaceAttr name value]
        MaterializedClassField name value -> [MaterializedClassAttr name value]
        _ -> []

materializedCssClass :: MaterializedStyle -> Maybe CssText
materializedCssClass style' = go (materializedFields style')
  where
    go fields =
      case fields of
        []                                        -> Nothing
        MaterializedClassField "cssClass" value:_ -> value
        _:rest                                    -> go rest

materializedClassName :: MaterializedStyle -> Maybe String
materializedClassName style' = cssTextString <$> materializedCssClass style'

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
        CssNumberValue x      -> number x
        CssPixelsValue x      -> pixels x
        CssTextValue value'   -> text value'
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
    MaterializedFontWeightField _ cssName maybeValue ->
      cssStringField cssName (fontWeightCss <$> maybeValue)
    MaterializedFontStyleField _ cssName maybeValue ->
      cssStringField cssName (fontStyleCss <$> maybeValue)
    MaterializedTextAlignField _ cssName maybeValue ->
      cssStringField cssName (textAlignCss <$> maybeValue)
    MaterializedBorderStyleField _ cssName maybeValue ->
      cssStringField cssName (borderStyleCss <$> maybeValue)
    MaterializedWhiteSpaceField _ cssName maybeValue ->
      cssStringField cssName (whiteSpaceCss <$> maybeValue)
    MaterializedClassField _ _ -> []

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
    StyleFontWeightField spec value ->
      Just
        (MaterializedFontWeightField
           (styleTextName spec)
           (styleTextCssName spec)
           value)
    StyleFontStyleField spec value ->
      Just
        (MaterializedFontStyleField
           (styleTextName spec)
           (styleTextCssName spec)
           value)
    StyleTextAlignField spec value ->
      Just
        (MaterializedTextAlignField
           (styleTextName spec)
           (styleTextCssName spec)
           value)
    StyleBorderStyleField spec value ->
      Just
        (MaterializedBorderStyleField
           (styleTextName spec)
           (styleTextCssName spec)
           value)
    StyleWhiteSpaceField spec value ->
      Just
        (MaterializedWhiteSpaceField
           (styleTextName spec)
           (styleTextCssName spec)
           value)
    StyleClassField spec value ->
      Just (MaterializedClassField (styleTextName spec) value)

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
