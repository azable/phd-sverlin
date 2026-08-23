{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}

-- | Type-applied choreography style API. This module translates public DSL
-- style fields into view style updates and selected-field accessors.
module LinearTrace.Choreography.Style
  ( StyleChoice(..)
  , style
  , withoutStyle
  , styleCase
  , styleFamily
  , styleOf
  , sat
  ) where

import           Data.Kind                     (Type)
import           LinearTrace.Choreography.Node (NodeRecipe, Selected (..),
                                                SelectionCategory (..),
                                                SelectionValue (..), Span,
                                                setNodePatch, spanExpr)
import           LinearTrace.View.Access       (HslPart (..),
                                                styleChoiceValueAccess,
                                                styleColorPartValueAccess,
                                                styleValueAccess)
import qualified LinearTrace.View.Patch        as VP
import           LinearTrace.View.Primitives   (Angle, Color, Free, Hsl (..),
                                                Unit)
import           LinearTrace.View.Style        (Alpha, BorderStyle, Fill,
                                                FontFamily, FontSize, FontStyle,
                                                FontWeight, Opacity, Padding,
                                                Radius, Stroke, StrokeWidth,
                                                TextAlign, WhiteSpace, ZIndex)
import qualified LinearTrace.View.Style        as VS
import qualified Prelude                       as P
import           Prelude.Linear
import qualified Solver                        as S

data StyleChoice value
  = FixedStyle value
  | VariableStyle (S.Choice value)

setStyleWith :: (VS.NodeStyle -> VS.NodeStyle) -> NodeRecipe ()
setStyleWith update =
  setNodePatch (P.const VP.emptyNodePatch {VP.nodePatchStyleUpdate = update})

style ::
     forall field. (VS.StyleField field, StyleFieldInput field)
  => StyleInputValue field
  -> NodeRecipe ()
style input =
  setStyleWith (VS.setStyleField @field (styleFieldInput @field input))

withoutStyle :: forall field. VS.StyleField field => NodeRecipe ()
withoutStyle = setStyleWith (VS.forbidStyleField @field)

styleCase ::
     forall field value.
     (VS.StyleField field, StyleFieldInput field, S.ChoiceDomain value)
  => S.Choice value
  -> (value -> P.Maybe (StyleInputValue field))
  -> NodeRecipe ()
styleCase selected inputFor =
  setStyleWith
    (VS.setConditionalStyleField @field
       selected
       (P.fmap (styleFieldInput @field) P.. inputFor))

styleFamily :: P.String -> NodeRecipe ()
styleFamily family = setStyleWith (VS.setStyleFamily family)

class StyleFieldInput field where
  type StyleInputValue field
  styleFieldInput :: StyleInputValue field -> VS.StyleValue field

instance StyleFieldInput Opacity where
  type StyleInputValue Opacity = Unit
  styleFieldInput = P.id

instance StyleFieldInput ZIndex where
  type StyleInputValue ZIndex = Free
  styleFieldInput = P.id

instance StyleFieldInput Padding where
  type StyleInputValue Padding = Span
  styleFieldInput = spanExpr

instance StyleFieldInput FontSize where
  type StyleInputValue FontSize = Span
  styleFieldInput = spanExpr

instance StyleFieldInput Radius where
  type StyleInputValue Radius = Span
  styleFieldInput = spanExpr

instance StyleFieldInput StrokeWidth where
  type StyleInputValue StrokeWidth = Span
  styleFieldInput = spanExpr

instance StyleFieldInput Alpha where
  type StyleInputValue Alpha = Unit
  styleFieldInput = P.id

instance StyleFieldInput Fill where
  type StyleInputValue Fill = Color
  styleFieldInput = P.id

instance StyleFieldInput Stroke where
  type StyleInputValue Stroke = Color
  styleFieldInput = P.id

styleChoiceInput ::
     S.ChoiceDomain value => StyleChoice value -> S.ChoiceValue value
styleChoiceInput input =
  case input of
    FixedStyle value       -> S.Fixed value
    VariableStyle selected -> S.Variable selected

instance StyleFieldInput FontFamily where
  type StyleInputValue FontFamily = StyleChoice FontFamily
  styleFieldInput = styleChoiceInput

instance StyleFieldInput FontWeight where
  type StyleInputValue FontWeight = StyleChoice FontWeight
  styleFieldInput = styleChoiceInput

instance StyleFieldInput FontStyle where
  type StyleInputValue FontStyle = StyleChoice FontStyle
  styleFieldInput = styleChoiceInput

instance StyleFieldInput TextAlign where
  type StyleInputValue TextAlign = StyleChoice TextAlign
  styleFieldInput = styleChoiceInput

instance StyleFieldInput BorderStyle where
  type StyleInputValue BorderStyle = StyleChoice BorderStyle
  styleFieldInput = styleChoiceInput

instance StyleFieldInput WhiteSpace where
  type StyleInputValue WhiteSpace = StyleChoice WhiteSpace
  styleFieldInput = styleChoiceInput

class SelectStyle field where
  type SelectedStyle field tag
  selectStyle :: Selected tag -> SelectedStyle field tag

styleOf ::
     forall field tag. SelectStyle field
  => Selected tag
  -> SelectedStyle field tag
styleOf = selectStyle @field

selectedScalarStyle ::
     forall field value tag (ty :: Type).
     (VS.StyleField field, VS.StyleValue field ~ S.Expr ty, S.SymbolicType ty)
  => Selected tag
  -> SelectionValue value tag
selectedScalarStyle selection =
  SelectionValue selection (styleValueAccess @field)

selectedColorStyle ::
     forall field tag. (VS.StyleField field, VS.StyleValue field ~ Color)
  => Selected tag
  -> Hsl (SelectionValue Angle tag) (SelectionValue Unit tag)
selectedColorStyle selection =
  Hsl
    (SelectionValue selection (styleColorPartValueAccess @field HslHue))
    (SelectionValue selection (styleColorPartValueAccess @field HslSaturation))
    (SelectionValue selection (styleColorPartValueAccess @field HslLightness))

selectedChoiceStyle ::
     forall field value tag.
     (VS.StyleField field, VS.StyleValue field ~ S.ChoiceValue value)
  => Selected tag
  -> SelectionCategory value tag
selectedChoiceStyle selection =
  SelectionCategory selection (styleChoiceValueAccess @field)

instance SelectStyle Opacity where
  type SelectedStyle Opacity tag = SelectionValue Unit tag
  selectStyle = selectedScalarStyle @Opacity

instance SelectStyle ZIndex where
  type SelectedStyle ZIndex tag = SelectionValue Free tag
  selectStyle = selectedScalarStyle @ZIndex

instance SelectStyle Padding where
  type SelectedStyle Padding tag = SelectionValue Span tag
  selectStyle = selectedScalarStyle @Padding

instance SelectStyle FontSize where
  type SelectedStyle FontSize tag = SelectionValue Span tag
  selectStyle = selectedScalarStyle @FontSize

instance SelectStyle Radius where
  type SelectedStyle Radius tag = SelectionValue Span tag
  selectStyle = selectedScalarStyle @Radius

instance SelectStyle StrokeWidth where
  type SelectedStyle StrokeWidth tag = SelectionValue Span tag
  selectStyle = selectedScalarStyle @StrokeWidth

instance SelectStyle Alpha where
  type SelectedStyle Alpha tag = SelectionValue Unit tag
  selectStyle = selectedScalarStyle @Alpha

instance SelectStyle Fill where
  type SelectedStyle Fill tag = Hsl
    (SelectionValue Angle tag)
    (SelectionValue Unit tag)
  selectStyle = selectedColorStyle @Fill

instance SelectStyle Stroke where
  type SelectedStyle Stroke tag = Hsl
    (SelectionValue Angle tag)
    (SelectionValue Unit tag)
  selectStyle = selectedColorStyle @Stroke

instance SelectStyle FontFamily where
  type SelectedStyle FontFamily tag = SelectionCategory FontFamily tag
  selectStyle = selectedChoiceStyle @FontFamily

instance SelectStyle FontWeight where
  type SelectedStyle FontWeight tag = SelectionCategory FontWeight tag
  selectStyle = selectedChoiceStyle @FontWeight

instance SelectStyle FontStyle where
  type SelectedStyle FontStyle tag = SelectionCategory FontStyle tag
  selectStyle = selectedChoiceStyle @FontStyle

instance SelectStyle TextAlign where
  type SelectedStyle TextAlign tag = SelectionCategory TextAlign tag
  selectStyle = selectedChoiceStyle @TextAlign

instance SelectStyle BorderStyle where
  type SelectedStyle BorderStyle tag = SelectionCategory BorderStyle tag
  selectStyle = selectedChoiceStyle @BorderStyle

instance SelectStyle WhiteSpace where
  type SelectedStyle WhiteSpace tag = SelectionCategory WhiteSpace tag
  selectStyle = selectedChoiceStyle @WhiteSpace

sat :: Hsl hue unit -> unit
sat = saturation
