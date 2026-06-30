{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeFamilies      #-}

-- | Symbolic node-style field catalogue. Generic storage, lowering, and helper
-- implementations live under @LinearTrace.View.Style.*@; this module defines
-- the supported style values and fields.
module LinearTrace.View.Style
  ( -- * Defined here: choice values
    -- | CSS-like fixed style tokens. Each value type has a solver
    -- 'ChoiceDomain' instance, so solver choices and CSS materialization share
    -- one domain/token definition.
    FontFamily(..)
  , FontWeight(..)
  , FontStyle(..)
  , TextAlign(..)
  , BorderStyle(..)
  , WhiteSpace(..)
  , -- * Defined here: field markers
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
  , -- * Re-exported from LinearTrace.View.Style.Model
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
  , -- * Re-exported from LinearTrace.View.Style.Lower
    -- | Generic expression traversal, constraint collection, and solved style
    -- materialization helpers for node styles.
    mapNodeStyleExprs
  , mapNodeStyleExprLeaves
  , solvedNodeStyleExprs
  , nodeStyleConstraints
  , nodeStyleChoiceConstraints
  , materializeAnyStyleField
  , -- * Re-exported from Solver
    -- | Categorical field values use the solver's fixed-or-variable choice
    -- wrapper directly.
    ChoiceValue(..)
  ) where

import           LinearTrace.View.Primitives
import           LinearTrace.View.Style.FieldSpec
import           LinearTrace.View.Style.Lower
import           LinearTrace.View.Style.Model
import           Prelude
import           Solver                           (ChoiceDomain (..),
                                                   ChoiceValue (..), Range (..))

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
data FontFamily
  = FontInter
  | FontSystem
  | FontMono
  | FontSerif
  deriving (Eq, Show)

instance ChoiceDomain FontFamily where
  choiceDomain = [FontInter, FontSystem, FontMono, FontSerif]
  choiceToken value =
    case value of
      FontInter  -> "Inter"
      FontSystem -> "system-ui"
      FontMono   -> "monospace"
      FontSerif  -> "serif"

instance StyleField FontFamily where
  type StyleValue FontFamily = ChoiceValue FontFamily
  styleFieldName _ = "fontFamily"
  generatedStyleValue = choiceValue
  mapStyleValueExprs _ = mapChoiceValue
  styleValueExprLeaves _ _ = []
  styleValueChoices _ = choiceChoices
  materializeStyleValue = materializeChoice

data FontWeight
  = FontWeightNormal
  | FontWeightBold
  | FontWeightBolder
  | FontWeightLighter
  | FontWeightNumber Int
  deriving (Eq, Show)

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

instance StyleField FontWeight where
  type StyleValue FontWeight = ChoiceValue FontWeight
  styleFieldName _ = "fontWeight"
  generatedStyleValue = choiceValue
  mapStyleValueExprs _ = mapChoiceValue
  styleValueExprLeaves _ _ = []
  styleValueChoices _ = choiceChoices
  materializeStyleValue = materializeChoice

data FontStyle
  = FontStyleNormal
  | FontStyleItalic
  | FontStyleOblique
  deriving (Eq, Show)

instance ChoiceDomain FontStyle where
  choiceDomain = [FontStyleNormal, FontStyleItalic, FontStyleOblique]
  choiceToken value =
    case value of
      FontStyleNormal  -> "normal"
      FontStyleItalic  -> "italic"
      FontStyleOblique -> "oblique"

instance StyleField FontStyle where
  type StyleValue FontStyle = ChoiceValue FontStyle
  styleFieldName _ = "fontStyle"
  generatedStyleValue = choiceValue
  mapStyleValueExprs _ = mapChoiceValue
  styleValueExprLeaves _ _ = []
  styleValueChoices _ = choiceChoices
  materializeStyleValue = materializeChoice

data TextAlign
  = TextAlignLeft
  | TextAlignCenter
  | TextAlignRight
  | TextAlignJustify
  deriving (Eq, Show)

instance ChoiceDomain TextAlign where
  choiceDomain =
    [TextAlignLeft, TextAlignCenter, TextAlignRight, TextAlignJustify]
  choiceToken value =
    case value of
      TextAlignLeft    -> "left"
      TextAlignCenter  -> "center"
      TextAlignRight   -> "right"
      TextAlignJustify -> "justify"

instance StyleField TextAlign where
  type StyleValue TextAlign = ChoiceValue TextAlign
  styleFieldName _ = "textAlign"
  generatedStyleValue = choiceValue
  mapStyleValueExprs _ = mapChoiceValue
  styleValueExprLeaves _ _ = []
  styleValueChoices _ = choiceChoices
  materializeStyleValue = materializeChoice

data BorderStyle
  = BorderNone
  | BorderSolid
  | BorderDashed
  | BorderDotted
  | BorderDouble
  deriving (Eq, Show)

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

instance StyleField BorderStyle where
  type StyleValue BorderStyle = ChoiceValue BorderStyle
  styleFieldName _ = "borderStyle"
  generatedStyleValue = choiceValue
  mapStyleValueExprs _ = mapChoiceValue
  styleValueExprLeaves _ _ = []
  styleValueChoices _ = choiceChoices
  materializeStyleValue = materializeChoice

data WhiteSpace
  = WhiteSpaceNormal
  | WhiteSpaceNoWrap
  | WhiteSpacePre
  | WhiteSpacePreWrap
  deriving (Eq, Show)

instance ChoiceDomain WhiteSpace where
  choiceDomain =
    [WhiteSpaceNormal, WhiteSpaceNoWrap, WhiteSpacePre, WhiteSpacePreWrap]
  choiceToken value =
    case value of
      WhiteSpaceNormal  -> "normal"
      WhiteSpaceNoWrap  -> "nowrap"
      WhiteSpacePre     -> "pre"
      WhiteSpacePreWrap -> "pre-wrap"

instance StyleField WhiteSpace where
  type StyleValue WhiteSpace = ChoiceValue WhiteSpace
  styleFieldName _ = "whiteSpace"
  generatedStyleValue = choiceValue
  mapStyleValueExprs _ = mapChoiceValue
  styleValueExprLeaves _ _ = []
  styleValueChoices _ = choiceChoices
  materializeStyleValue = materializeChoice
