{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE KindSignatures      #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}

module LinearTrace.View.Style
  ( -- * Style values
    StyleText
  , styleTextString
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
  , DiscreteStyleValue
  , StyleField(..)
  , styleBounds
  , styleFields
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
  ) where

import           Data.Kind                   (Type)
import           Data.Maybe                  (mapMaybe)
import           Data.Type.Equality          ((:~:) (..))
import           LinearTrace.View.Primitives
import           Prelude
import           Solver                      hiding (num)

newtype StyleText =
  StyleText String
  deriving (Eq, Show)

styleTextString :: StyleText -> String
styleTextString styleText =
  case styleText of
    StyleText text -> text

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

fontWeightToken :: FontWeight -> String
fontWeightToken value =
  case value of
    FontWeightNormal   -> "normal"
    FontWeightBold     -> "bold"
    FontWeightBolder   -> "bolder"
    FontWeightLighter  -> "lighter"
    FontWeightNumber n -> show n

fontStyleToken :: FontStyle -> String
fontStyleToken value =
  case value of
    FontStyleNormal  -> "normal"
    FontStyleItalic  -> "italic"
    FontStyleOblique -> "oblique"

textAlignToken :: TextAlign -> String
textAlignToken value =
  case value of
    TextAlignLeft    -> "left"
    TextAlignCenter  -> "center"
    TextAlignRight   -> "right"
    TextAlignJustify -> "justify"

borderStyleToken :: BorderStyle -> String
borderStyleToken value =
  case value of
    BorderNone   -> "none"
    BorderSolid  -> "solid"
    BorderDashed -> "dashed"
    BorderDotted -> "dotted"
    BorderDouble -> "double"

whiteSpaceToken :: WhiteSpace -> String
whiteSpaceToken value =
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
  categoricalDomain _ = map (category . fontWeightToken) fontWeightChoices

instance CategoricalType FontStyle where
  categoricalDomain _ = map (category . fontStyleToken) fontStyleChoices

instance CategoricalType TextAlign where
  categoricalDomain _ = map (category . textAlignToken) textAlignChoices

instance CategoricalType BorderStyle where
  categoricalDomain _ = map (category . borderStyleToken) borderStyleChoices

instance CategoricalType WhiteSpace where
  categoricalDomain _ = map (category . whiteSpaceToken) whiteSpaceChoices

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
  , styleScalarAttrName     :: Maybe String
  , styleScalarInitialRange :: Maybe Range
  , styleScalarValueUnit    :: StyleValueUnit
  , styleScalarConstraints  :: [Constraint]
  }

data StyleScalarKind ty where
  StyleFreeScalar :: StyleScalarKind FreeDomain
  StyleLayoutScalar :: StyleScalarKind LayoutDomain
  StyleUnitScalar :: StyleScalarKind UnitDomain
  StyleAngleScalar :: StyleScalarKind AngleDomain

sameStyleScalarKind ::
     StyleScalarKind lhs -> StyleScalarKind rhs -> Maybe (lhs :~: rhs)
sameStyleScalarKind lhs rhs =
  case (lhs, rhs) of
    (StyleFreeScalar, StyleFreeScalar)     -> Just Refl
    (StyleLayoutScalar, StyleLayoutScalar) -> Just Refl
    (StyleUnitScalar, StyleUnitScalar)     -> Just Refl
    (StyleAngleScalar, StyleAngleScalar)   -> Just Refl
    _                                      -> Nothing

data StyleTextSpec = StyleTextSpec
  { styleTextName     :: String
  , styleTextAttrName :: Maybe String
  }

data StyleChoiceValue value
  = FixedStyleChoice value
  | SolvedStyleChoice (Choice value)
  deriving (Eq, Show)

data DiscreteStyleValue
  = DiscreteFontWeight String (Maybe FontWeight)
  | DiscreteFontStyle String (Maybe FontStyle)
  | DiscreteTextAlign String (Maybe TextAlign)
  | DiscreteBorderStyle String (Maybe BorderStyle)
  | DiscreteWhiteSpace String (Maybe WhiteSpace)
  deriving (Eq, Show)

data StyleChoiceSpec value = StyleChoiceSpec
  { styleChoiceName          :: String
  , styleChoiceAttrName      :: Maybe String
  , styleChoiceDomainValues  :: [value]
  , styleChoiceCategoryName  :: value -> String
  , styleChoiceAttrValue     :: value -> String
  , styleChoiceDiscreteValue :: Maybe value -> DiscreteStyleValue
  }

data StyleField where
  StyleScalarField
    :: SymbolicType ty=> StyleScalarKind ty
    -> StyleScalarSpec
    -> Expr ty
    -> StyleField
  StyleColorField :: StyleTextSpec -> Maybe ColorExpr -> StyleField
  StyleTextField :: StyleTextSpec -> Maybe StyleText -> StyleField
  StyleChoiceField
    :: StyleChoiceSpec value -> Maybe (StyleChoiceValue value) -> StyleField

fieldName :: StyleField -> String
fieldName field =
  case field of
    StyleScalarField _ spec _ -> styleScalarName spec
    StyleColorField spec _    -> styleTextName spec
    StyleTextField spec _     -> styleTextName spec
    StyleChoiceField spec _   -> styleChoiceName spec

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
    StyleScalarField kind spec expr -> StyleScalarField kind spec (f expr)
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
    StyleScalarField _ spec expr -> [StyleExprLeaf (styleScalarName spec) expr]
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
    StyleScalarField _ spec expr -> scalarConstraints spec expr
    StyleColorField _ maybeHsl ->
      case maybeHsl of
        Nothing -> []
        Just hsl ->
          [ within (hue hsl) angleRange
          , within (saturation hsl) unitRange
          , within (lightness hsl) unitRange
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

--------------------------------------------------------------------------------
-- Field constructors
--------------------------------------------------------------------------------
scalarField ::
     SymbolicType ty
  => StyleScalarKind ty
  -> String
  -> Maybe String
  -> StyleValueUnit
  -> Maybe Range
  -> (Expr ty -> [Constraint])
  -> Expr ty
  -> StyleField
scalarField kind name cssName unit range constraints expr =
  StyleScalarField
    kind
    StyleScalarSpec
      { styleScalarName = name
      , styleScalarAttrName = cssName
      , styleScalarInitialRange = range
      , styleScalarValueUnit = unit
      , styleScalarConstraints = constraints expr
      }
    expr

textSpec :: String -> Maybe String -> StyleTextSpec
textSpec name cssName =
  StyleTextSpec {styleTextName = name, styleTextAttrName = cssName}

choiceSpec ::
     String
  -> Maybe String
  -> [value]
  -> (value -> String)
  -> (Maybe value -> DiscreteStyleValue)
  -> StyleChoiceSpec value
choiceSpec name attrName values toToken toDiscrete =
  StyleChoiceSpec
    { styleChoiceName = name
    , styleChoiceAttrName = attrName
    , styleChoiceDomainValues = values
    , styleChoiceCategoryName = toToken
    , styleChoiceAttrValue = toToken
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
  scalarField
    StyleUnitScalar
    "opacity"
    (Just "opacity")
    StyleNumber
    (Just unitRange)
    noConstraints

opacity :: HasStyle a => a -> UnitExpr
opacity value =
  lookupScalarField StyleUnitScalar "opacity" opacityDefault (style value)

setOpacity :: UnitExpr -> Style -> Style
setOpacity = setStyleField . opacityField

--------------------------------------------------------------------------------
-- Attribute: zIndex
--------------------------------------------------------------------------------
zIndexDefault :: FreeExpr
zIndexDefault = num 0

zIndexField :: FreeExpr -> StyleField
zIndexField =
  scalarField
    StyleFreeScalar
    "zIndex"
    (Just "zIndex")
    StyleNumber
    (Just (Range (-10) 10))
    noConstraints

zIndex :: HasStyle a => a -> FreeExpr
zIndex value =
  lookupScalarField StyleFreeScalar "zIndex" zIndexDefault (style value)

setZIndex :: FreeExpr -> Style -> Style
setZIndex = setStyleField . zIndexField

--------------------------------------------------------------------------------
-- Attribute: padding
--------------------------------------------------------------------------------
paddingDefault :: LayoutExpr
paddingDefault = num 0

paddingField :: LayoutExpr -> StyleField
paddingField =
  scalarField
    StyleLayoutScalar
    "padding"
    (Just "padding")
    StylePixels
    (Just (Range 0 24))
    nonNegativeConstraints

padding :: HasStyle a => a -> LayoutExpr
padding value =
  lookupScalarField StyleLayoutScalar "padding" paddingDefault (style value)

setPadding :: LayoutExpr -> Style -> Style
setPadding = setStyleField . paddingField

--------------------------------------------------------------------------------
-- Attribute: fontSize
--------------------------------------------------------------------------------
fontSizeDefault :: LayoutExpr
fontSizeDefault = num 16

fontSizeField :: LayoutExpr -> StyleField
fontSizeField =
  scalarField
    StyleLayoutScalar
    "fontSize"
    (Just "fontSize")
    StylePixels
    (Just (Range 8 48))
    nonNegativeConstraints

fontSize :: HasStyle a => a -> LayoutExpr
fontSize value =
  lookupScalarField StyleLayoutScalar "fontSize" fontSizeDefault (style value)

setFontSize :: LayoutExpr -> Style -> Style
setFontSize = setStyleField . fontSizeField

--------------------------------------------------------------------------------
-- Attribute: radius
--------------------------------------------------------------------------------
radiusDefault :: LayoutExpr
radiusDefault = num 0

radiusField :: LayoutExpr -> StyleField
radiusField =
  scalarField
    StyleLayoutScalar
    "radius"
    (Just "borderRadius")
    StylePixels
    (Just (Range 0 32))
    nonNegativeConstraints

radius :: HasStyle a => a -> LayoutExpr
radius value =
  lookupScalarField StyleLayoutScalar "radius" radiusDefault (style value)

setRadius :: LayoutExpr -> Style -> Style
setRadius = setStyleField . radiusField

--------------------------------------------------------------------------------
-- Attribute: strokeWidth
--------------------------------------------------------------------------------
strokeWidthDefault :: LayoutExpr
strokeWidthDefault = num 0

strokeWidthField :: LayoutExpr -> StyleField
strokeWidthField =
  scalarField
    StyleLayoutScalar
    "strokeWidth"
    (Just "borderWidth")
    StylePixels
    (Just (Range 0 8))
    nonNegativeConstraints

strokeWidth :: HasStyle a => a -> LayoutExpr
strokeWidth value =
  lookupScalarField
    StyleLayoutScalar
    "strokeWidth"
    strokeWidthDefault
    (style value)

setStrokeWidth :: LayoutExpr -> Style -> Style
setStrokeWidth = setStyleField . strokeWidthField

--------------------------------------------------------------------------------
-- Attribute: alpha
--------------------------------------------------------------------------------
alphaDefault :: UnitExpr
alphaDefault = num 1

alphaField :: UnitExpr -> StyleField
alphaField =
  scalarField
    StyleUnitScalar
    "alpha"
    Nothing
    StyleHidden
    (Just unitRange)
    noConstraints

alpha :: HasStyle a => a -> UnitExpr
alpha value =
  lookupScalarField StyleUnitScalar "alpha" alphaDefault (style value)

setAlpha :: UnitExpr -> Style -> Style
setAlpha = setStyleField . alphaField

--------------------------------------------------------------------------------
-- Attribute: fill
--------------------------------------------------------------------------------
fillDefault :: Maybe ColorExpr
fillDefault = Nothing

fillField :: Maybe ColorExpr -> StyleField
fillField = StyleColorField (textSpec "fill" (Just "backgroundColor"))

fill :: HasStyle a => a -> Maybe ColorExpr
fill value = lookupColorField "fill" fillDefault (style value)

setFill :: ColorExpr -> Style -> Style
setFill = setStyleField . fillField . Just

--------------------------------------------------------------------------------
-- Attribute: stroke
--------------------------------------------------------------------------------
strokeDefault :: Maybe ColorExpr
strokeDefault = Nothing

strokeField :: Maybe ColorExpr -> StyleField
strokeField = StyleColorField (textSpec "stroke" (Just "borderColor"))

stroke :: HasStyle a => a -> Maybe ColorExpr
stroke value = lookupColorField "stroke" strokeDefault (style value)

setStroke :: ColorExpr -> Style -> Style
setStroke = setStyleField . strokeField . Just

--------------------------------------------------------------------------------
-- Attribute: fontFamily
--------------------------------------------------------------------------------
fontFamilyField :: Maybe StyleText -> StyleField
fontFamilyField = StyleTextField (textSpec "fontFamily" (Just "fontFamily"))

setFontFamily :: String -> Style -> Style
setFontFamily = setStyleField . fontFamilyField . Just . StyleText

--------------------------------------------------------------------------------
-- Attribute: fontWeight
--------------------------------------------------------------------------------
fontWeightSpec :: StyleChoiceSpec FontWeight
fontWeightSpec =
  choiceSpec
    "fontWeight"
    (Just "fontWeight")
    fontWeightChoices
    fontWeightToken
    (DiscreteFontWeight "fontWeight")

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
    fontStyleToken
    (DiscreteFontStyle "fontStyle")

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
    textAlignToken
    (DiscreteTextAlign "textAlign")

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
    borderStyleToken
    (DiscreteBorderStyle "borderStyle")

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
    whiteSpaceToken
    (DiscreteWhiteSpace "whiteSpace")

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
lookupScalarField :: StyleScalarKind ty -> String -> Expr ty -> Style -> Expr ty
lookupScalarField expectedKind name fallback style' = go (styleFields style')
  where
    go fields =
      case fields of
        [] -> fallback
        StyleScalarField actualKind spec expr:rest
          | styleScalarName spec == name
          , Just Refl <- sameStyleScalarKind expectedKind actualKind -> expr
          | otherwise -> go rest
        _:rest -> go rest

lookupColorField :: String -> Maybe ColorExpr -> Style -> Maybe ColorExpr
lookupColorField name fallback style' = go (styleFields style')
  where
    go fields =
      case fields of
        [] -> fallback
        StyleColorField spec value:rest
          | styleTextName spec == name -> value
          | otherwise -> go rest
        _:rest -> go rest
