{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Reusable implementations for common style field shapes. Concrete field
-- definitions choose one of these helpers from 'LinearTrace.View.Style'.
module LinearTrace.View.Style.FieldSpec
  ( -- * Scalar fields
    scalarValue
  , scalarLeaves
  , scalarConstraints
  , materializeScalar
  , noConstraints
  , nonNegativeConstraints
  , -- * Colour fields
    colorValue
  , colorLeaves
  , mapColorExprs
  , colorConstraints
  , materializeColor
  , -- * Choice fields
    choiceValue
  , choiceChoices
  , materializeChoice
  , mapChoiceValue
  ) where

import           Data.Kind                    (Type)
import           Data.Proxy                   (Proxy)
import           LinearTrace.View.Primitives
import           LinearTrace.View.Style.Model
import           Prelude
import           Solver                       hiding (num)

scalarValue ::
     forall field (ty :: Type). (StyleField field, SymbolicType ty)
  => Proxy field
  -> StyleValueVars
  -> Expr ty
scalarValue proxy vars = styleExprVar vars [] (styleFieldName proxy)

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

choiceValue ::
     forall value field. (StyleField field, ChoiceDomain value)
  => Proxy field
  -> StyleValueVars
  -> ChoiceValue value
choiceValue proxy vars = Variable (styleChoiceVar vars (styleFieldName proxy))

choiceChoices :: ChoiceValue value -> [ChoiceConstraint]
choiceChoices value =
  case value of
    Fixed _           -> []
    Variable selected -> [freeChoice selected]

materializeChoice ::
     ChoiceDomain value
  => Proxy field
  -> Solution
  -> ChoiceValue value
  -> Either String ConcreteStyleValue
materializeChoice _ solution value =
  ConcreteToken . choiceToken
    <$> case value of
          Fixed fixed -> Right fixed
          Variable selected ->
            maybe
              (Left
                 "could not materialize a style choice from the solver solution")
              Right
              (evalChoice solution selected)

mapChoiceValue :: ChoiceValue value -> ChoiceValue value
mapChoiceValue = id

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
