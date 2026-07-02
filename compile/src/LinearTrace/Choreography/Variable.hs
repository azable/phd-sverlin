{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

-- | Symbolic variables and reusable visualization bindings.
module LinearTrace.Choreography.Variable
  ( global
  , bindInt
  , bindContent
  , variable
  , variableFrom
  , choice
  ) where

import LinearTrace.Choreography.Layout (mkCoord, mkOffset, mkScalar, mkSpan)
import LinearTrace.Choreography.Node
  ( Binding(..)
  , Bound(..)
  , ContentValue(..)
  , Coord
  , Offset
  , Scalar
  , Span
  , Variable(..)
  , VisualizationBuilder
  , emptyVisualizationBuilder
  , freshVisualizationValue
  )
import LinearTrace.Core (QueryInt, queryIntVar)
import qualified LinearTrace.View as V
import LinearTrace.View.Primitives (LayoutExpr)
import qualified Prelude as P
import qualified Solver as S

class VariableValue value where
  namedVariable :: P.String -> value

global :: VariableValue value => P.String -> value
global = namedVariable

globalCoord :: P.String -> Coord
globalCoord name = mkCoord (global name :: LayoutExpr) []

globalSpan :: P.String -> Span
globalSpan name = mkSpan (global name :: LayoutExpr) []

instance VariableValue Coord where
  namedVariable = globalCoord

instance VariableValue Span where
  namedVariable = globalSpan

instance VariableValue Offset where
  namedVariable name = mkOffset (global name :: LayoutExpr) []

instance VariableValue Scalar where
  namedVariable name = mkScalar (global name :: LayoutExpr) []

instance S.SymbolicType ty => VariableValue (S.Expr ty) where
  namedVariable = V.global

instance S.ChoiceDomain value => VariableValue (S.Choice value) where
  namedVariable = S.choice

bindInt :: VisualizationBuilder (Bound QueryInt)
bindInt = freshVisualizationValue "view.bind." (Bound P.. queryIntVar)

bindContent :: VisualizationBuilder (Bound ContentValue)
bindContent =
  freshVisualizationValue "view.bind." (Bound P.. ContentBinding P.. Binding)

variable ::
     forall value. VariableValue value
  => VisualizationBuilder (Variable value)
variable =
  freshVisualizationValue "view.var." (Variable P.. namedVariable @value)

variableFrom :: forall value. value -> VisualizationBuilder (Variable value)
variableFrom rhs = emptyVisualizationBuilder (Variable rhs)

choice ::
     forall value. S.ChoiceDomain value
  => VisualizationBuilder (Variable (S.Choice value))
choice = variable @(S.Choice value)
