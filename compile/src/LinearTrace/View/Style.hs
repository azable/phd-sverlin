{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeApplications  #-}
{-# LANGUAGE TypeFamilies      #-}

-- | Symbolic node-style field catalogue. Generic storage, lowering, and helper
-- implementations live under @LinearTrace.View.Style.*@; this module defines
-- the supported style values and fields.
module LinearTrace.View.Style
  ( -- * Choice values
    -- | CSS-like fixed style tokens. Each value type has a solver
    -- 'ChoiceDomain' instance, so solver choices and CSS materialization share
    -- one domain/token definition.
    FontFamily(..)
  , FontWeight(..)
  , FontStyle(..)
  , TextAlign(..)
  , BorderStyle(..)
  , WhiteSpace(..)
  , ChoiceValue(..)
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

import           LinearTrace.View.Primitives
import           LinearTrace.View.Style.FieldSpec
import           LinearTrace.View.Style.Lower
import           LinearTrace.View.Style.Model
import           Prelude
import           Solver                           (ChoiceDomain (..),
                                                   ChoiceValue (..), Range (..))

--------------------------------------------------------------------------------
-- Choice value definitions
--------------------------------------------------------------------------------
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

instance ChoiceDomain FontFamily where
  choiceDomain = [FontInter, FontSystem, FontMono, FontSerif]
  choiceToken value =
    case value of
      FontInter  -> "Inter"
      FontSystem -> "system-ui"
      FontMono   -> "monospace"
      FontSerif  -> "serif"

instance ChoiceDomain FontWeight where
  choiceDomain =
    [FontWeightNormal, FontWeightBold, FontWeightBolder, FontWeightLighter]
      ++ map FontWeightNumber [100,200 .. 900]
  choiceToken value =
    case value of
      FontWeightNormal   -> "normal"
      FontWeightBold     -> "bold"
      FontWeightBolder   -> "bolder"
      FontWeightLighter  -> "lighter"
      FontWeightNumber n -> show n

instance ChoiceDomain FontStyle where
  choiceDomain = [FontStyleNormal, FontStyleItalic, FontStyleOblique]
  choiceToken value =
    case value of
      FontStyleNormal  -> "normal"
      FontStyleItalic  -> "italic"
      FontStyleOblique -> "oblique"

instance ChoiceDomain TextAlign where
  choiceDomain =
    [TextAlignLeft, TextAlignCenter, TextAlignRight, TextAlignJustify]
  choiceToken value =
    case value of
      TextAlignLeft    -> "left"
      TextAlignCenter  -> "center"
      TextAlignRight   -> "right"
      TextAlignJustify -> "justify"

instance ChoiceDomain BorderStyle where
  choiceDomain =
    [BorderNone, BorderSolid, BorderDashed, BorderDotted, BorderDouble]
  choiceToken value =
    case value of
      BorderNone   -> "none"
      BorderSolid  -> "solid"
      BorderDashed -> "dashed"
      BorderDotted -> "dotted"
      BorderDouble -> "double"

instance ChoiceDomain WhiteSpace where
  choiceDomain =
    [WhiteSpaceNormal, WhiteSpaceNoWrap, WhiteSpacePre, WhiteSpacePreWrap]
  choiceToken value =
    case value of
      WhiteSpaceNormal  -> "normal"
      WhiteSpaceNoWrap  -> "nowrap"
      WhiteSpacePre     -> "pre"
      WhiteSpacePreWrap -> "pre-wrap"

--------------------------------------------------------------------------------
-- Scalar fields
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
  generatedStyleValue = scalarValue
  mapStyleValueExprs f = f
  styleValueExprLeaves = scalarLeaves
  styleValueConstraints _ = scalarConstraints (Just unitRange) noConstraints
  materializeStyleValue proxy = materializeScalar proxy StyleNumber

instance StyleField ZIndex where
  type StyleValue ZIndex = FreeExpr
  styleFieldName _ = "zIndex"
  generatedStyleValue = scalarValue
  mapStyleValueExprs f = f
  styleValueExprLeaves = scalarLeaves
  styleValueConstraints _ =
    scalarConstraints (Just (Range (-10) 10)) noConstraints
  materializeStyleValue proxy = materializeScalar proxy StyleNumber

instance StyleField Padding where
  type StyleValue Padding = LayoutExpr
  styleFieldName _ = "padding"
  generatedStyleValue = scalarValue
  mapStyleValueExprs f = f
  styleValueExprLeaves = scalarLeaves
  styleValueConstraints _ =
    scalarConstraints (Just (Range 0 24)) nonNegativeConstraints
  materializeStyleValue proxy = materializeScalar proxy StylePixels

instance StyleField FontSize where
  type StyleValue FontSize = LayoutExpr
  styleFieldName _ = "fontSize"
  generatedStyleValue = scalarValue
  mapStyleValueExprs f = f
  styleValueExprLeaves = scalarLeaves
  styleValueConstraints _ =
    scalarConstraints (Just (Range 8 48)) nonNegativeConstraints
  materializeStyleValue proxy = materializeScalar proxy StylePixels

instance StyleField Radius where
  type StyleValue Radius = LayoutExpr
  styleFieldName _ = "radius"
  styleFieldCssName _ = Just "borderRadius"
  generatedStyleValue = scalarValue
  mapStyleValueExprs f = f
  styleValueExprLeaves = scalarLeaves
  styleValueConstraints _ =
    scalarConstraints (Just (Range 0 32)) nonNegativeConstraints
  materializeStyleValue proxy = materializeScalar proxy StylePixels

instance StyleField StrokeWidth where
  type StyleValue StrokeWidth = LayoutExpr
  styleFieldName _ = "strokeWidth"
  styleFieldCssName _ = Just "borderWidth"
  generatedStyleValue = scalarValue
  mapStyleValueExprs f = f
  styleValueExprLeaves = scalarLeaves
  styleValueConstraints _ =
    scalarConstraints (Just (Range 0 8)) nonNegativeConstraints
  materializeStyleValue proxy = materializeScalar proxy StylePixels

instance StyleField Alpha where
  type StyleValue Alpha = UnitExpr
  styleFieldName _ = "alpha"
  styleFieldCssName _ = Nothing
  generatedStyleValue = scalarValue
  mapStyleValueExprs f = f
  styleValueExprLeaves = scalarLeaves
  styleValueConstraints _ = scalarConstraints (Just unitRange) noConstraints
  materializeStyleValue proxy = materializeScalar proxy StyleHidden

--------------------------------------------------------------------------------
-- Colour fields
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
-- Choice fields
--------------------------------------------------------------------------------
instance StyleField FontFamily where
  type StyleValue FontFamily = ChoiceValue FontFamily
  styleFieldName _ = "fontFamily"
  generatedStyleValue = choiceValue
  mapStyleValueExprs _ = mapChoiceValue
  styleValueExprLeaves _ _ = []
  styleValueChoices _ = choiceChoices
  materializeStyleValue = materializeChoice

instance StyleField FontWeight where
  type StyleValue FontWeight = ChoiceValue FontWeight
  styleFieldName _ = "fontWeight"
  generatedStyleValue = choiceValue
  mapStyleValueExprs _ = mapChoiceValue
  styleValueExprLeaves _ _ = []
  styleValueChoices _ = choiceChoices
  materializeStyleValue = materializeChoice

instance StyleField FontStyle where
  type StyleValue FontStyle = ChoiceValue FontStyle
  styleFieldName _ = "fontStyle"
  generatedStyleValue = choiceValue
  mapStyleValueExprs _ = mapChoiceValue
  styleValueExprLeaves _ _ = []
  styleValueChoices _ = choiceChoices
  materializeStyleValue = materializeChoice

instance StyleField TextAlign where
  type StyleValue TextAlign = ChoiceValue TextAlign
  styleFieldName _ = "textAlign"
  generatedStyleValue = choiceValue
  mapStyleValueExprs _ = mapChoiceValue
  styleValueExprLeaves _ _ = []
  styleValueChoices _ = choiceChoices
  materializeStyleValue = materializeChoice

instance StyleField BorderStyle where
  type StyleValue BorderStyle = ChoiceValue BorderStyle
  styleFieldName _ = "borderStyle"
  generatedStyleValue = choiceValue
  mapStyleValueExprs _ = mapChoiceValue
  styleValueExprLeaves _ _ = []
  styleValueChoices _ = choiceChoices
  materializeStyleValue = materializeChoice

instance StyleField WhiteSpace where
  type StyleValue WhiteSpace = ChoiceValue WhiteSpace
  styleFieldName _ = "whiteSpace"
  generatedStyleValue = choiceValue
  mapStyleValueExprs _ = mapChoiceValue
  styleValueExprLeaves _ _ = []
  styleValueChoices _ = choiceChoices
  materializeStyleValue = materializeChoice

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

fontFamily :: NodeStyle -> Maybe (ChoiceValue FontFamily)
fontFamily = getStyleField @FontFamily

setFontFamily :: ChoiceValue FontFamily -> NodeStyle -> NodeStyle
setFontFamily = setStyleField @FontFamily

fontWeight :: NodeStyle -> Maybe (ChoiceValue FontWeight)
fontWeight = getStyleField @FontWeight

setFontWeight :: ChoiceValue FontWeight -> NodeStyle -> NodeStyle
setFontWeight = setStyleField @FontWeight

fontStyle :: NodeStyle -> Maybe (ChoiceValue FontStyle)
fontStyle = getStyleField @FontStyle

setFontStyle :: ChoiceValue FontStyle -> NodeStyle -> NodeStyle
setFontStyle = setStyleField @FontStyle

textAlign :: NodeStyle -> Maybe (ChoiceValue TextAlign)
textAlign = getStyleField @TextAlign

setTextAlign :: ChoiceValue TextAlign -> NodeStyle -> NodeStyle
setTextAlign = setStyleField @TextAlign

borderStyle :: NodeStyle -> Maybe (ChoiceValue BorderStyle)
borderStyle = getStyleField @BorderStyle

setBorderStyle :: ChoiceValue BorderStyle -> NodeStyle -> NodeStyle
setBorderStyle = setStyleField @BorderStyle

whiteSpace :: NodeStyle -> Maybe (ChoiceValue WhiteSpace)
whiteSpace = getStyleField @WhiteSpace

setWhiteSpace :: ChoiceValue WhiteSpace -> NodeStyle -> NodeStyle
setWhiteSpace = setStyleField @WhiteSpace
