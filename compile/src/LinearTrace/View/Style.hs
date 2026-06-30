{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}

-- | Symbolic node style schema for the view layer. A 'NodeStyle' contains
-- required bounds plus optional style fields. This module is the field
-- catalogue: each supported field defines its symbolic value, constraints, and
-- materialization behavior through the 'StyleField' class.
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
  , -- * Field markers
    -- | Type-level names for supported optional node-style fields.
    Opacity
  , ZIndex
  , Padding
  , FontSize
  , Radius
  , StrokeWidth
  , Alpha
  , Fill
  , Stroke
  , -- * Node style representation
    -- | Internal style model shared by graph construction, access lowering,
    -- solving, and materialization. Callers should prefer named setters and
    -- accessors unless they are implementing those lowering phases.
    NodeStyle
  , nodeStyleWithBounds
  , nodeStyleBounds
  , nodeStyleFields
  , AnyStyleField(..)
  , StyleField(..)
  , StyleValueVars(..)
  , StyleValueUnit(..)
  , ConcreteStyleField(..)
  , ConcreteStyleValue(..)
  , getStyleField
  , setStyleField
  , requireStyleField
  , mapNodeStyleExprs
  , mapNodeStyleExprLeaves
  , solvedNodeStyleExprs
  , nodeStyleConstraints
  , nodeStyleChoiceConstraints
  , materializeAnyStyleField
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
import           Data.Proxy                  (Proxy (..))
import           Data.Type.Equality          ((:~:) (..))
import           Data.Typeable               (Typeable, eqT)
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
-- Node style representation
--------------------------------------------------------------------------------
data StyleValueUnit
  = StyleNumber
  | StylePixels
  | StyleHidden
  deriving (Eq, Show)

data StyleCategory value
  = FixedCategory value
  | VariableCategory (Choice value)
  deriving (Eq, Show)

data StyleValueVars = StyleValueVars
  { styleExprVar :: forall (ty :: Type). SymbolicType ty =>
                                           [String] -> String -> Expr ty
  , styleChoiceVar :: forall value. StyleCategoryType value =>
                                      String -> Choice value
  }

data ConcreteStyleValue
  = ConcreteScalar Double StyleValueUnit
  | ConcreteColor ConcreteHsl
  | ConcreteToken String
  deriving (Eq, Show)

data ConcreteStyleField = ConcreteStyleField
  { concreteStyleFieldName    :: String
  , concreteStyleFieldCssName :: Maybe String
  , concreteStyleFieldValue   :: ConcreteStyleValue
  } deriving (Eq, Show)

class Typeable field =>
      StyleField (field :: Type)
  where
  type StyleValue field
  styleFieldName :: Proxy field -> String
  styleFieldCssName :: Proxy field -> Maybe String
  styleFieldCssName proxy = Just (styleFieldName proxy)
  generatedStyleValue :: Proxy field -> StyleValueVars -> StyleValue field
  mapStyleValueExprs ::
       (forall (ty :: Type). Expr ty -> Expr ty)
    -> StyleValue field
    -> StyleValue field
  styleValueExprLeaves :: Proxy field -> StyleValue field -> [StyleExprLeaf]
  styleValueConstraints :: Proxy field -> StyleValue field -> [Constraint]
  styleValueConstraints _ _ = []
  styleValueChoices :: Proxy field -> StyleValue field -> [ChoiceConstraint]
  styleValueChoices _ _ = []
  materializeStyleValue ::
       Proxy field
    -> Solution
    -> StyleValue field
    -> Either String ConcreteStyleValue

data AnyStyleField where
  AnyStyleField
    :: StyleField field => Proxy field -> StyleValue field -> AnyStyleField

anyStyleFieldName :: AnyStyleField -> String
anyStyleFieldName field =
  case field of
    AnyStyleField proxy _ -> styleFieldName proxy

data NodeStyle = NodeStyle
  { nodeStyleBounds :: BoundsExpr
  , nodeStyleFields :: [AnyStyleField]
  }

nodeStyleWithBounds :: BoundsExpr -> NodeStyle
nodeStyleWithBounds bounds =
  NodeStyle {nodeStyleBounds = bounds, nodeStyleFields = []}

instance HasBounds NodeStyle where
  top = top . nodeStyleBounds
  left = left . nodeStyleBounds
  width = width . nodeStyleBounds
  height = height . nodeStyleBounds

getStyleField ::
     forall field. StyleField field
  => NodeStyle
  -> Maybe (StyleValue field)
getStyleField style' = go (nodeStyleFields style')
  where
    go fields =
      case fields of
        [] -> Nothing
        AnyStyleField (_ :: Proxy other) value:rest ->
          case eqT @field @other of
            Just Refl -> Just value
            Nothing   -> go rest

setStyleField ::
     forall field. StyleField field
  => StyleValue field
  -> NodeStyle
  -> NodeStyle
setStyleField value style' =
  style'
    { nodeStyleFields =
        replaceByName
          anyStyleFieldName
          (AnyStyleField (Proxy :: Proxy field) value)
          (nodeStyleFields style')
    }

requireStyleField ::
     forall field. StyleField field
  => StyleValueVars
  -> NodeStyle
  -> NodeStyle
requireStyleField vars style' =
  case getStyleField @field style' of
    Just _ -> style'
    Nothing ->
      setStyleField @field (generatedStyleValue (Proxy @field) vars) style'

mapNodeStyleExprs ::
     (forall (ty :: Type). Expr ty -> Expr ty) -> NodeStyle -> NodeStyle
mapNodeStyleExprs f style' =
  NodeStyle
    { nodeStyleBounds = fmap f (nodeStyleBounds style')
    , nodeStyleFields = map (mapAnyStyleFieldExprs f) (nodeStyleFields style')
    }

mapAnyStyleFieldExprs ::
     (forall (ty :: Type). Expr ty -> Expr ty) -> AnyStyleField -> AnyStyleField
mapAnyStyleFieldExprs f field =
  case field of
    AnyStyleField (proxy :: Proxy field) value ->
      AnyStyleField proxy (mapStyleValueExprs @field f value)

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
-- Style inspection and lowering
--------------------------------------------------------------------------------
data StyleExprLeaf where
  StyleExprLeaf :: String -> Expr (ty :: Type) -> StyleExprLeaf

nodeStyleExprLeaves :: NodeStyle -> [StyleExprLeaf]
nodeStyleExprLeaves style' =
  [ StyleExprLeaf "top" (top style')
  , StyleExprLeaf "left" (left style')
  , StyleExprLeaf "width" (width style')
  , StyleExprLeaf "height" (height style')
  ]
    ++ concatMap anyStyleFieldExprLeaves (nodeStyleFields style')

anyStyleFieldExprLeaves :: AnyStyleField -> [StyleExprLeaf]
anyStyleFieldExprLeaves field =
  case field of
    AnyStyleField proxy value -> styleValueExprLeaves proxy value

mapNodeStyleExprLeaves ::
     (forall (ty :: Type). String -> Expr ty -> a) -> NodeStyle -> [a]
mapNodeStyleExprLeaves f style' = map go (nodeStyleExprLeaves style')
  where
    go leaf =
      case leaf of
        StyleExprLeaf name expr -> f name expr

solvedNodeStyleExprs :: Solution -> NodeStyle -> [(String, Double)]
solvedNodeStyleExprs solution = mapMaybe solveLeaf . nodeStyleExprLeaves
  where
    solveLeaf leaf =
      case leaf of
        StyleExprLeaf name expr ->
          case evalExpr solution expr of
            Nothing    -> Nothing
            Just value -> Just (name, value)

nodeStyleConstraints :: NodeStyle -> [Constraint]
nodeStyleConstraints style' =
  concatMap anyStyleFieldConstraints (nodeStyleFields style')

anyStyleFieldConstraints :: AnyStyleField -> [Constraint]
anyStyleFieldConstraints field =
  case field of
    AnyStyleField proxy value -> styleValueConstraints proxy value

nodeStyleChoiceConstraints :: NodeStyle -> [ChoiceConstraint]
nodeStyleChoiceConstraints style' =
  concatMap anyStyleFieldChoices (nodeStyleFields style')

anyStyleFieldChoices :: AnyStyleField -> [ChoiceConstraint]
anyStyleFieldChoices field =
  case field of
    AnyStyleField proxy value -> styleValueChoices proxy value

materializeAnyStyleField ::
     Solution -> AnyStyleField -> Either String ConcreteStyleField
materializeAnyStyleField solution field =
  case field of
    AnyStyleField proxy value ->
      ConcreteStyleField (styleFieldName proxy) (styleFieldCssName proxy)
        <$> materializeStyleValue proxy solution value

--------------------------------------------------------------------------------
-- Field helpers
--------------------------------------------------------------------------------
scalarExpr ::
     forall field (ty :: Type). (StyleField field, SymbolicType ty)
  => Proxy field
  -> StyleValueVars
  -> Expr ty
scalarExpr proxy vars = styleExprVar vars [] (styleFieldName proxy)

scalarLeaves ::
     forall field (ty :: Type). StyleField field
  => Proxy field
  -> Expr ty
  -> [StyleExprLeaf]
scalarLeaves proxy expr = [StyleExprLeaf (styleFieldName proxy) expr]

scalarConstraints ::
     forall (ty :: Type). SymbolicType ty
  => Maybe Range
  -> (Expr ty -> [Constraint])
  -> Expr ty
  -> [Constraint]
scalarConstraints range extra expr =
  case range of
    Just range' -> within expr range' : extra expr
    Nothing     -> extra expr

materializeScalar ::
     forall field (ty :: Type). StyleField field
  => Proxy field
  -> StyleValueUnit
  -> Solution
  -> Expr ty
  -> Either String ConcreteStyleValue
materializeScalar proxy unit solution expr =
  ConcreteScalar
    <$> requireSolvedExpr solution (styleFieldName proxy) expr
    <*> pure unit

noConstraints :: forall (ty :: Type). Expr ty -> [Constraint]
noConstraints _ = []

nonNegativeConstraints ::
     forall (ty :: Type). SymbolicType ty
  => Expr ty
  -> [Constraint]
nonNegativeConstraints expr = [num 0 @<=@ expr]

colorValue :: StyleField field => Proxy field -> StyleValueVars -> ColorExpr
colorValue proxy vars =
  Hsl
    (styleExprVar vars [styleFieldName proxy] "hue")
    (styleExprVar vars [styleFieldName proxy] "saturation")
    (styleExprVar vars [styleFieldName proxy] "lightness")

colorLeaves :: StyleField field => Proxy field -> ColorExpr -> [StyleExprLeaf]
colorLeaves proxy hsl =
  [ StyleExprLeaf (styleFieldName proxy ++ ".hue") (hue hsl)
  , StyleExprLeaf (styleFieldName proxy ++ ".saturation") (saturation hsl)
  , StyleExprLeaf (styleFieldName proxy ++ ".lightness") (lightness hsl)
  ]

mapColorExprs ::
     (forall (ty :: Type). Expr ty -> Expr ty) -> ColorExpr -> ColorExpr
mapColorExprs f hsl = Hsl (f (hue hsl)) (f (saturation hsl)) (f (lightness hsl))

colorConstraints :: ColorExpr -> [Constraint]
colorConstraints hsl =
  [ within (hue hsl) angleRange
  , within (saturation hsl) unitRange
  , within (lightness hsl) unitRange
  ]

materializeColor :: Solution -> ColorExpr -> Either String ConcreteStyleValue
materializeColor solution hsl =
  ConcreteColor
    <$> (Hsl
           <$> requireSolvedExpr solution "hue" (hue hsl)
           <*> requireSolvedExpr solution "saturation" (saturation hsl)
           <*> requireSolvedExpr solution "lightness" (lightness hsl))

categoryValue ::
     forall value field. (StyleField field, StyleCategoryType value)
  => Proxy field
  -> StyleValueVars
  -> StyleCategory value
categoryValue proxy vars =
  VariableCategory (styleChoiceVar vars (styleFieldName proxy))

categoryChoices :: StyleCategory value -> [ChoiceConstraint]
categoryChoices value =
  case value of
    FixedCategory _           -> []
    VariableCategory selected -> [freeChoice selected]

materializeCategory ::
     StyleCategoryType value
  => Proxy field
  -> Solution
  -> StyleCategory value
  -> Either String ConcreteStyleValue
materializeCategory _ solution value =
  ConcreteToken . styleCategoryToken
    <$> case value of
          FixedCategory fixed -> Right fixed
          VariableCategory selected -> do
            selectedCategory <-
              maybe
                (Left
                   "could not materialize a style category from the solver solution")
                Right
                (evalChoice solution selected)
            requireCategoryValue (categoryName selectedCategory)

requireCategoryValue :: StyleCategoryType value => String -> Either String value
requireCategoryValue name =
  case go styleCategoryDomain of
    Just value -> Right value
    Nothing -> Left ("could not map solved style category to a value: " ++ name)
  where
    go values =
      case values of
        [] -> Nothing
        value:rest
          | styleCategoryToken value == name -> Just value
          | otherwise -> go rest

mapFixed :: StyleCategory value -> StyleCategory value
mapFixed = id

requireSolvedExpr :: Solution -> String -> Expr ty -> Either String Double
requireSolvedExpr solution label expr =
  case evalExpr solution expr of
    Just value -> Right value
    Nothing ->
      Left
        ("could not materialize "
           ++ label
           ++ " from the solver solution; the expression probably references a \
             \variable that was not included in any constraint")

--------------------------------------------------------------------------------
-- Scalar style fields
--------------------------------------------------------------------------------
data Opacity

data ZIndex

data Padding

data FontSize

data Radius

data StrokeWidth

data Alpha

instance StyleField Opacity where
  type StyleValue Opacity = UnitExpr
  styleFieldName _ = "opacity"
  generatedStyleValue = scalarExpr
  mapStyleValueExprs f = f
  styleValueExprLeaves = scalarLeaves
  styleValueConstraints _ = scalarConstraints (Just unitRange) noConstraints
  materializeStyleValue proxy = materializeScalar proxy StyleNumber

instance StyleField ZIndex where
  type StyleValue ZIndex = FreeExpr
  styleFieldName _ = "zIndex"
  generatedStyleValue = scalarExpr
  mapStyleValueExprs f = f
  styleValueExprLeaves = scalarLeaves
  styleValueConstraints _ =
    scalarConstraints (Just (Range (-10) 10)) noConstraints
  materializeStyleValue proxy = materializeScalar proxy StyleNumber

instance StyleField Padding where
  type StyleValue Padding = LayoutExpr
  styleFieldName _ = "padding"
  generatedStyleValue = scalarExpr
  mapStyleValueExprs f = f
  styleValueExprLeaves = scalarLeaves
  styleValueConstraints _ =
    scalarConstraints (Just (Range 0 24)) nonNegativeConstraints
  materializeStyleValue proxy = materializeScalar proxy StylePixels

instance StyleField FontSize where
  type StyleValue FontSize = LayoutExpr
  styleFieldName _ = "fontSize"
  generatedStyleValue = scalarExpr
  mapStyleValueExprs f = f
  styleValueExprLeaves = scalarLeaves
  styleValueConstraints _ =
    scalarConstraints (Just (Range 8 48)) nonNegativeConstraints
  materializeStyleValue proxy = materializeScalar proxy StylePixels

instance StyleField Radius where
  type StyleValue Radius = LayoutExpr
  styleFieldName _ = "radius"
  styleFieldCssName _ = Just "borderRadius"
  generatedStyleValue = scalarExpr
  mapStyleValueExprs f = f
  styleValueExprLeaves = scalarLeaves
  styleValueConstraints _ =
    scalarConstraints (Just (Range 0 32)) nonNegativeConstraints
  materializeStyleValue proxy = materializeScalar proxy StylePixels

instance StyleField StrokeWidth where
  type StyleValue StrokeWidth = LayoutExpr
  styleFieldName _ = "strokeWidth"
  styleFieldCssName _ = Just "borderWidth"
  generatedStyleValue = scalarExpr
  mapStyleValueExprs f = f
  styleValueExprLeaves = scalarLeaves
  styleValueConstraints _ =
    scalarConstraints (Just (Range 0 8)) nonNegativeConstraints
  materializeStyleValue proxy = materializeScalar proxy StylePixels

instance StyleField Alpha where
  type StyleValue Alpha = UnitExpr
  styleFieldName _ = "alpha"
  styleFieldCssName _ = Nothing
  generatedStyleValue = scalarExpr
  mapStyleValueExprs f = f
  styleValueExprLeaves = scalarLeaves
  styleValueConstraints _ = scalarConstraints (Just unitRange) noConstraints
  materializeStyleValue proxy = materializeScalar proxy StyleHidden

--------------------------------------------------------------------------------
-- Compound scalar style fields
--------------------------------------------------------------------------------
data Fill

data Stroke

instance StyleField Fill where
  type StyleValue Fill = ColorExpr
  styleFieldName _ = "fill"
  styleFieldCssName _ = Just "backgroundColor"
  generatedStyleValue = colorValue
  mapStyleValueExprs = mapColorExprs
  styleValueExprLeaves = colorLeaves
  styleValueConstraints _ = colorConstraints
  materializeStyleValue _ = materializeColor

instance StyleField Stroke where
  type StyleValue Stroke = ColorExpr
  styleFieldName _ = "stroke"
  styleFieldCssName _ = Just "borderColor"
  generatedStyleValue = colorValue
  mapStyleValueExprs = mapColorExprs
  styleValueExprLeaves = colorLeaves
  styleValueConstraints _ = colorConstraints
  materializeStyleValue _ = materializeColor

--------------------------------------------------------------------------------
-- Categorical style fields
--------------------------------------------------------------------------------
instance StyleField FontFamily where
  type StyleValue FontFamily = StyleCategory FontFamily
  styleFieldName _ = "fontFamily"
  generatedStyleValue = categoryValue
  mapStyleValueExprs _ = mapFixed
  styleValueExprLeaves _ _ = []
  styleValueChoices _ = categoryChoices
  materializeStyleValue = materializeCategory

instance StyleField FontWeight where
  type StyleValue FontWeight = StyleCategory FontWeight
  styleFieldName _ = "fontWeight"
  generatedStyleValue = categoryValue
  mapStyleValueExprs _ = mapFixed
  styleValueExprLeaves _ _ = []
  styleValueChoices _ = categoryChoices
  materializeStyleValue = materializeCategory

instance StyleField FontStyle where
  type StyleValue FontStyle = StyleCategory FontStyle
  styleFieldName _ = "fontStyle"
  generatedStyleValue = categoryValue
  mapStyleValueExprs _ = mapFixed
  styleValueExprLeaves _ _ = []
  styleValueChoices _ = categoryChoices
  materializeStyleValue = materializeCategory

instance StyleField TextAlign where
  type StyleValue TextAlign = StyleCategory TextAlign
  styleFieldName _ = "textAlign"
  generatedStyleValue = categoryValue
  mapStyleValueExprs _ = mapFixed
  styleValueExprLeaves _ _ = []
  styleValueChoices _ = categoryChoices
  materializeStyleValue = materializeCategory

instance StyleField BorderStyle where
  type StyleValue BorderStyle = StyleCategory BorderStyle
  styleFieldName _ = "borderStyle"
  generatedStyleValue = categoryValue
  mapStyleValueExprs _ = mapFixed
  styleValueExprLeaves _ _ = []
  styleValueChoices _ = categoryChoices
  materializeStyleValue = materializeCategory

instance StyleField WhiteSpace where
  type StyleValue WhiteSpace = StyleCategory WhiteSpace
  styleFieldName _ = "whiteSpace"
  generatedStyleValue = categoryValue
  mapStyleValueExprs _ = mapFixed
  styleValueExprLeaves _ _ = []
  styleValueChoices _ = categoryChoices
  materializeStyleValue = materializeCategory

--------------------------------------------------------------------------------
-- Public field accessors and setters
--------------------------------------------------------------------------------
opacity :: NodeStyle -> Maybe UnitExpr
opacity = getStyleField @Opacity

setOpacity :: UnitExpr -> NodeStyle -> NodeStyle
setOpacity = setStyleField @Opacity

zIndex :: NodeStyle -> Maybe FreeExpr
zIndex = getStyleField @ZIndex

setZIndex :: FreeExpr -> NodeStyle -> NodeStyle
setZIndex = setStyleField @ZIndex

padding :: NodeStyle -> Maybe LayoutExpr
padding = getStyleField @Padding

setPadding :: LayoutExpr -> NodeStyle -> NodeStyle
setPadding = setStyleField @Padding

fontSize :: NodeStyle -> Maybe LayoutExpr
fontSize = getStyleField @FontSize

setFontSize :: LayoutExpr -> NodeStyle -> NodeStyle
setFontSize = setStyleField @FontSize

radius :: NodeStyle -> Maybe LayoutExpr
radius = getStyleField @Radius

setRadius :: LayoutExpr -> NodeStyle -> NodeStyle
setRadius = setStyleField @Radius

strokeWidth :: NodeStyle -> Maybe LayoutExpr
strokeWidth = getStyleField @StrokeWidth

setStrokeWidth :: LayoutExpr -> NodeStyle -> NodeStyle
setStrokeWidth = setStyleField @StrokeWidth

alpha :: NodeStyle -> Maybe UnitExpr
alpha = getStyleField @Alpha

setAlpha :: UnitExpr -> NodeStyle -> NodeStyle
setAlpha = setStyleField @Alpha

fill :: NodeStyle -> Maybe ColorExpr
fill = getStyleField @Fill

setFill :: ColorExpr -> NodeStyle -> NodeStyle
setFill = setStyleField @Fill

stroke :: NodeStyle -> Maybe ColorExpr
stroke = getStyleField @Stroke

setStroke :: ColorExpr -> NodeStyle -> NodeStyle
setStroke = setStyleField @Stroke

fontFamily :: NodeStyle -> Maybe (StyleCategory FontFamily)
fontFamily = getStyleField @FontFamily

setFontFamily :: StyleCategory FontFamily -> NodeStyle -> NodeStyle
setFontFamily = setStyleField @FontFamily

fontWeight :: NodeStyle -> Maybe (StyleCategory FontWeight)
fontWeight = getStyleField @FontWeight

setFontWeight :: StyleCategory FontWeight -> NodeStyle -> NodeStyle
setFontWeight = setStyleField @FontWeight

fontStyle :: NodeStyle -> Maybe (StyleCategory FontStyle)
fontStyle = getStyleField @FontStyle

setFontStyle :: StyleCategory FontStyle -> NodeStyle -> NodeStyle
setFontStyle = setStyleField @FontStyle

textAlign :: NodeStyle -> Maybe (StyleCategory TextAlign)
textAlign = getStyleField @TextAlign

setTextAlign :: StyleCategory TextAlign -> NodeStyle -> NodeStyle
setTextAlign = setStyleField @TextAlign

borderStyle :: NodeStyle -> Maybe (StyleCategory BorderStyle)
borderStyle = getStyleField @BorderStyle

setBorderStyle :: StyleCategory BorderStyle -> NodeStyle -> NodeStyle
setBorderStyle = setStyleField @BorderStyle

whiteSpace :: NodeStyle -> Maybe (StyleCategory WhiteSpace)
whiteSpace = getStyleField @WhiteSpace

setWhiteSpace :: StyleCategory WhiteSpace -> NodeStyle -> NodeStyle
setWhiteSpace = setStyleField @WhiteSpace
