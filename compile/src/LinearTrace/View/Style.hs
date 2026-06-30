{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE KindSignatures      #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Symbolic style schema for the view layer. Choreography uses the setters as
-- the public DSL surface; build/solve/materialize use the field specs and
-- constraints to lower styles through the solver and into concrete CSS values.
module LinearTrace.View.Style
  ( -- * Style values
    -- | CSS-like fixed style tokens and text values. These stay independent of
    -- layout primitives except where style fields reference symbolic values.
    FontFamily(..)
  , FontWeight(..)
  , FontStyle(..)
  , TextAlign(..)
  , BorderStyle(..)
  , WhiteSpace(..)
  , StyleCategoryType(..)
  , StyleCategory(..)
  , -- * Unified style representation
    -- | Internal style field model shared by build constraints, choice solving,
    -- and materialization. Callers should prefer the named setters/accessors
    -- unless they are part of those lowering phases.
    Style
  , styleWithBounds
  , HasStyle(..)
  , StyleValueUnit(..)
  , StyleScalarSpec(..)
  , StyleAttrSpec(..)
  , StyleCategorySpec(..)
  , StyleField(..)
  , styleBounds
  , styleFields
  , mapStyleExprs
  , mapStyleExprLeaves
  , solvedStyleExprs
  , styleConstraints
  , styleCategoryConstraints
  , -- * Public style accessors/setters
    -- | Named style accessors and setters used by choreography and view access.
    -- These are the intended API for manipulating symbolic style values.
    opacity
  , zIndex
  , padding
  , fontSize
  , radius
  , strokeWidth
  , alpha
  , fill
  , stroke
  , fontFamily
  , fontWeight
  , fontStyle
  , textAlign
  , borderStyle
  , whiteSpace
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
  , setFontStyle
  , setTextAlign
  , setBorderStyle
  , setWhiteSpace
  ) where

import           Data.Kind                   (Type)
import           Data.Maybe                  (mapMaybe)
import           Data.Type.Equality          ((:~:) (..))
import           Data.Typeable               (Typeable, cast)
import           LinearTrace.View.Primitives
import           Prelude
import           Solver                      hiding (num)

data FontFamily
  = FontInter
  | FontSystem
  | FontMono
  | FontSerif
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

class (CategoricalType value, Typeable value) =>
      StyleCategoryType value
  where
  styleCategoryDomain :: [value]
  styleCategoryToken :: value -> String

fontFamilyToken :: FontFamily -> String
fontFamilyToken value =
  case value of
    FontInter  -> "Inter"
    FontSystem -> "system-ui"
    FontMono   -> "monospace"
    FontSerif  -> "serif"

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

fontFamilyChoices :: [FontFamily]
fontFamilyChoices = [FontInter, FontSystem, FontMono, FontSerif]

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

instance CategoricalType FontFamily where
  categoricalDomain _ = map (category . fontFamilyToken) fontFamilyChoices

instance StyleCategoryType FontFamily where
  styleCategoryDomain = fontFamilyChoices
  styleCategoryToken = fontFamilyToken

instance CategoricalType FontWeight where
  categoricalDomain _ = map (category . fontWeightToken) fontWeightChoices

instance StyleCategoryType FontWeight where
  styleCategoryDomain = fontWeightChoices
  styleCategoryToken = fontWeightToken

instance CategoricalType FontStyle where
  categoricalDomain _ = map (category . fontStyleToken) fontStyleChoices

instance StyleCategoryType FontStyle where
  styleCategoryDomain = fontStyleChoices
  styleCategoryToken = fontStyleToken

instance CategoricalType TextAlign where
  categoricalDomain _ = map (category . textAlignToken) textAlignChoices

instance StyleCategoryType TextAlign where
  styleCategoryDomain = textAlignChoices
  styleCategoryToken = textAlignToken

instance CategoricalType BorderStyle where
  categoricalDomain _ = map (category . borderStyleToken) borderStyleChoices

instance StyleCategoryType BorderStyle where
  styleCategoryDomain = borderStyleChoices
  styleCategoryToken = borderStyleToken

instance CategoricalType WhiteSpace where
  categoricalDomain _ = map (category . whiteSpaceToken) whiteSpaceChoices

instance StyleCategoryType WhiteSpace where
  styleCategoryDomain = whiteSpaceChoices
  styleCategoryToken = whiteSpaceToken

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

data StyleAttrSpec = StyleAttrSpec
  { styleAttrName    :: String
  , styleAttrCssName :: Maybe String
  }

data StyleCategory value
  = FixedCategory value
  | VariableCategory (Choice value)
  deriving (Eq, Show)

data StyleCategorySpec value = StyleCategorySpec
  { styleCategoryName         :: String
  , styleCategoryAttrName     :: Maybe String
  , styleCategoryDomainValues :: [value]
  , styleCategoryValueToken   :: value -> String
  }

data StyleField where
  StyleScalarField
    :: SymbolicType ty=> StyleScalarKind ty
    -> StyleScalarSpec
    -> Expr ty
    -> StyleField
  StyleColorField :: StyleAttrSpec -> ColorExpr -> StyleField
  StyleCategoryField
    :: StyleCategoryType value=> StyleCategorySpec value
    -> StyleCategory value
    -> StyleField

fieldName :: StyleField -> String
fieldName field =
  case field of
    StyleScalarField _ spec _ -> styleScalarName spec
    StyleColorField spec _    -> styleAttrName spec
    StyleCategoryField spec _ -> styleCategoryName spec

data Style = Style
  { styleBounds :: BoundsExpr
  , styleFields :: [StyleField]
  }

styleWithBounds :: BoundsExpr -> Style
styleWithBounds bounds = Style {styleBounds = bounds, styleFields = []}

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
    StyleColorField spec hsl        -> StyleColorField spec (fmap f hsl)
    StyleCategoryField _ _          -> field

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
    StyleColorField spec hsl ->
      [ StyleExprLeaf (styleAttrName spec ++ ".hue") (hue hsl)
      , StyleExprLeaf (styleAttrName spec ++ ".saturation") (saturation hsl)
      , StyleExprLeaf (styleAttrName spec ++ ".lightness") (lightness hsl)
      ]
    StyleCategoryField _ _ -> []

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

styleCategoryConstraints :: Style -> [ChoiceConstraint]
styleCategoryConstraints style' =
  concatMap fieldCategoryConstraints (styleFields style')

fieldConstraints :: StyleField -> [Constraint]
fieldConstraints field =
  case field of
    StyleScalarField _ spec expr -> scalarConstraints spec expr
    StyleColorField _ hsl ->
      [ within (hue hsl) angleRange
      , within (saturation hsl) unitRange
      , within (lightness hsl) unitRange
      ]
    StyleCategoryField _ _ -> []

fieldCategoryConstraints :: StyleField -> [ChoiceConstraint]
fieldCategoryConstraints field =
  case field of
    StyleCategoryField _ value ->
      case value of
        FixedCategory _           -> []
        VariableCategory selected -> [freeChoice selected]
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

attrSpec :: String -> Maybe String -> StyleAttrSpec
attrSpec name cssName =
  StyleAttrSpec {styleAttrName = name, styleAttrCssName = cssName}

categorySpec ::
     StyleCategoryType value
  => String
  -> Maybe String
  -> StyleCategorySpec value
categorySpec name attrName =
  StyleCategorySpec
    { styleCategoryName = name
    , styleCategoryAttrName = attrName
    , styleCategoryDomainValues = styleCategoryDomain
    , styleCategoryValueToken = styleCategoryToken
    }

categoryField ::
     StyleCategoryType value
  => StyleCategorySpec value
  -> StyleCategory value
  -> StyleField
categoryField = StyleCategoryField

--------------------------------------------------------------------------------
-- Attribute: opacity
--------------------------------------------------------------------------------
opacityField :: UnitExpr -> StyleField
opacityField =
  scalarField
    StyleUnitScalar
    "opacity"
    (Just "opacity")
    StyleNumber
    (Just unitRange)
    noConstraints

opacity :: HasStyle a => a -> Maybe UnitExpr
opacity value = lookupScalarField StyleUnitScalar "opacity" (style value)

setOpacity :: UnitExpr -> Style -> Style
setOpacity = setStyleField . opacityField

--------------------------------------------------------------------------------
-- Attribute: zIndex
--------------------------------------------------------------------------------
zIndexField :: FreeExpr -> StyleField
zIndexField =
  scalarField
    StyleFreeScalar
    "zIndex"
    (Just "zIndex")
    StyleNumber
    (Just (Range (-10) 10))
    noConstraints

zIndex :: HasStyle a => a -> Maybe FreeExpr
zIndex value = lookupScalarField StyleFreeScalar "zIndex" (style value)

setZIndex :: FreeExpr -> Style -> Style
setZIndex = setStyleField . zIndexField

--------------------------------------------------------------------------------
-- Attribute: padding
--------------------------------------------------------------------------------
paddingField :: LayoutExpr -> StyleField
paddingField =
  scalarField
    StyleLayoutScalar
    "padding"
    (Just "padding")
    StylePixels
    (Just (Range 0 24))
    nonNegativeConstraints

padding :: HasStyle a => a -> Maybe LayoutExpr
padding value = lookupScalarField StyleLayoutScalar "padding" (style value)

setPadding :: LayoutExpr -> Style -> Style
setPadding = setStyleField . paddingField

--------------------------------------------------------------------------------
-- Attribute: fontSize
--------------------------------------------------------------------------------
fontSizeField :: LayoutExpr -> StyleField
fontSizeField =
  scalarField
    StyleLayoutScalar
    "fontSize"
    (Just "fontSize")
    StylePixels
    (Just (Range 8 48))
    nonNegativeConstraints

fontSize :: HasStyle a => a -> Maybe LayoutExpr
fontSize value = lookupScalarField StyleLayoutScalar "fontSize" (style value)

setFontSize :: LayoutExpr -> Style -> Style
setFontSize = setStyleField . fontSizeField

--------------------------------------------------------------------------------
-- Attribute: radius
--------------------------------------------------------------------------------
radiusField :: LayoutExpr -> StyleField
radiusField =
  scalarField
    StyleLayoutScalar
    "radius"
    (Just "borderRadius")
    StylePixels
    (Just (Range 0 32))
    nonNegativeConstraints

radius :: HasStyle a => a -> Maybe LayoutExpr
radius value = lookupScalarField StyleLayoutScalar "radius" (style value)

setRadius :: LayoutExpr -> Style -> Style
setRadius = setStyleField . radiusField

--------------------------------------------------------------------------------
-- Attribute: strokeWidth
--------------------------------------------------------------------------------
strokeWidthField :: LayoutExpr -> StyleField
strokeWidthField =
  scalarField
    StyleLayoutScalar
    "strokeWidth"
    (Just "borderWidth")
    StylePixels
    (Just (Range 0 8))
    nonNegativeConstraints

strokeWidth :: HasStyle a => a -> Maybe LayoutExpr
strokeWidth value =
  lookupScalarField StyleLayoutScalar "strokeWidth" (style value)

setStrokeWidth :: LayoutExpr -> Style -> Style
setStrokeWidth = setStyleField . strokeWidthField

--------------------------------------------------------------------------------
-- Attribute: alpha
--------------------------------------------------------------------------------
alphaField :: UnitExpr -> StyleField
alphaField =
  scalarField
    StyleUnitScalar
    "alpha"
    Nothing
    StyleHidden
    (Just unitRange)
    noConstraints

alpha :: HasStyle a => a -> Maybe UnitExpr
alpha value = lookupScalarField StyleUnitScalar "alpha" (style value)

setAlpha :: UnitExpr -> Style -> Style
setAlpha = setStyleField . alphaField

--------------------------------------------------------------------------------
-- Attribute: fill
--------------------------------------------------------------------------------
fillField :: ColorExpr -> StyleField
fillField = StyleColorField (attrSpec "fill" (Just "backgroundColor"))

fill :: HasStyle a => a -> Maybe ColorExpr
fill value = lookupColorField "fill" (style value)

setFill :: ColorExpr -> Style -> Style
setFill = setStyleField . fillField

--------------------------------------------------------------------------------
-- Attribute: stroke
--------------------------------------------------------------------------------
strokeField :: ColorExpr -> StyleField
strokeField = StyleColorField (attrSpec "stroke" (Just "borderColor"))

stroke :: HasStyle a => a -> Maybe ColorExpr
stroke value = lookupColorField "stroke" (style value)

setStroke :: ColorExpr -> Style -> Style
setStroke = setStyleField . strokeField

--------------------------------------------------------------------------------
-- Attribute: fontFamily
--------------------------------------------------------------------------------
fontFamilySpec :: StyleCategorySpec FontFamily
fontFamilySpec = categorySpec "fontFamily" (Just "fontFamily")

fontFamilyField :: StyleCategory FontFamily -> StyleField
fontFamilyField = categoryField fontFamilySpec

fontFamily :: HasStyle a => a -> Maybe (StyleCategory FontFamily)
fontFamily value = lookupCategoryField "fontFamily" (style value)

setFontFamily :: StyleCategory FontFamily -> Style -> Style
setFontFamily = setStyleField . fontFamilyField

--------------------------------------------------------------------------------
-- Attribute: fontWeight
--------------------------------------------------------------------------------
fontWeightSpec :: StyleCategorySpec FontWeight
fontWeightSpec = categorySpec "fontWeight" (Just "fontWeight")

fontWeightField :: StyleCategory FontWeight -> StyleField
fontWeightField = categoryField fontWeightSpec

fontWeight :: HasStyle a => a -> Maybe (StyleCategory FontWeight)
fontWeight value = lookupCategoryField "fontWeight" (style value)

setFontWeight :: StyleCategory FontWeight -> Style -> Style
setFontWeight = setStyleField . fontWeightField

--------------------------------------------------------------------------------
-- Attribute: fontStyle
--------------------------------------------------------------------------------
fontStyleSpec :: StyleCategorySpec FontStyle
fontStyleSpec = categorySpec "fontStyle" (Just "fontStyle")

fontStyleField :: StyleCategory FontStyle -> StyleField
fontStyleField = categoryField fontStyleSpec

fontStyle :: HasStyle a => a -> Maybe (StyleCategory FontStyle)
fontStyle value = lookupCategoryField "fontStyle" (style value)

setFontStyle :: StyleCategory FontStyle -> Style -> Style
setFontStyle = setStyleField . fontStyleField

--------------------------------------------------------------------------------
-- Attribute: textAlign
--------------------------------------------------------------------------------
textAlignSpec :: StyleCategorySpec TextAlign
textAlignSpec = categorySpec "textAlign" (Just "textAlign")

textAlignField :: StyleCategory TextAlign -> StyleField
textAlignField = categoryField textAlignSpec

textAlign :: HasStyle a => a -> Maybe (StyleCategory TextAlign)
textAlign value = lookupCategoryField "textAlign" (style value)

setTextAlign :: StyleCategory TextAlign -> Style -> Style
setTextAlign = setStyleField . textAlignField

--------------------------------------------------------------------------------
-- Attribute: borderStyle
--------------------------------------------------------------------------------
borderStyleSpec :: StyleCategorySpec BorderStyle
borderStyleSpec = categorySpec "borderStyle" (Just "borderStyle")

borderStyleField :: StyleCategory BorderStyle -> StyleField
borderStyleField = categoryField borderStyleSpec

borderStyle :: HasStyle a => a -> Maybe (StyleCategory BorderStyle)
borderStyle value = lookupCategoryField "borderStyle" (style value)

setBorderStyle :: StyleCategory BorderStyle -> Style -> Style
setBorderStyle = setStyleField . borderStyleField

--------------------------------------------------------------------------------
-- Attribute: whiteSpace
--------------------------------------------------------------------------------
whiteSpaceSpec :: StyleCategorySpec WhiteSpace
whiteSpaceSpec = categorySpec "whiteSpace" (Just "whiteSpace")

whiteSpaceField :: StyleCategory WhiteSpace -> StyleField
whiteSpaceField = categoryField whiteSpaceSpec

whiteSpace :: HasStyle a => a -> Maybe (StyleCategory WhiteSpace)
whiteSpace value = lookupCategoryField "whiteSpace" (style value)

setWhiteSpace :: StyleCategory WhiteSpace -> Style -> Style
setWhiteSpace = setStyleField . whiteSpaceField

--------------------------------------------------------------------------------
-- Field lookup
--------------------------------------------------------------------------------
lookupScalarField :: StyleScalarKind ty -> String -> Style -> Maybe (Expr ty)
lookupScalarField expectedKind name style' = go (styleFields style')
  where
    go fields =
      case fields of
        [] -> Nothing
        StyleScalarField actualKind spec expr:rest
          | styleScalarName spec == name ->
            case sameStyleScalarKind expectedKind actualKind of
              Just Refl -> Just expr
              Nothing   -> go rest
          | otherwise -> go rest
        _:rest -> go rest

lookupColorField :: String -> Style -> Maybe ColorExpr
lookupColorField name style' = go (styleFields style')
  where
    go fields =
      case fields of
        [] -> Nothing
        StyleColorField spec value:rest
          | styleAttrName spec == name -> Just value
          | otherwise -> go rest
        _:rest -> go rest

lookupCategoryField ::
     StyleCategoryType value => String -> Style -> Maybe (StyleCategory value)
lookupCategoryField name style' = go (styleFields style')
  where
    go fields =
      case fields of
        [] -> Nothing
        StyleCategoryField spec value:rest
          | styleCategoryName spec == name ->
            case cast value of
              Just typedValue -> typedValue
              Nothing         -> go rest
          | otherwise -> go rest
        _:rest -> go rest
