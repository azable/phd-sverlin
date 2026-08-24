{-# LANGUAGE FlexibleContexts       #-}
{-# LANGUAGE FlexibleInstances      #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE NoImplicitPrelude      #-}
{-# LANGUAGE RebindableSyntax       #-}
{-# LANGUAGE TypeFamilies           #-}
{-# LANGUAGE UndecidableInstances   #-}

-- | Layout values, arithmetic, and geometry accessors for choreography.
module LinearTrace.Choreography.Layout
  ( NumExpr(..)
  , IntegerLiteral(..)
  , RationalLiteral(..)
  , fromInteger
  , fromRational
  , QueryField
  , (@:)
  , at
  , by
  , shift
  , asScalar
  , asCoord
  , asSpan
  , AddExpr(..)
  , SubExpr(..)
  , MulExpr(..)
  , DivExpr(..)
  , (+)
  , (-)
  , (*)
  , (/)
  , (|+|)
  , Left(..)
  , Top(..)
  , Right(..)
  , Bottom(..)
  , Width(..)
  , Height(..)
  , X(..)
  , Y(..)
  , Center(..)
  , size
  , bounds
  , mkCoord
  , mkSpan
  , mkOffset
  , mkScalar
  ) where

import           Control.Functor.Linear         hiding ((<$>), (<&>), (<*>))
import           Data.Proxy                     (Proxy (..))
import           GHC.OverloadedLabels           (IsLabel (fromLabel))
import           GHC.TypeLits                   (KnownSymbol)
import qualified LinearTrace.Choreography.Match as Match
import           LinearTrace.Choreography.Node  (Coord, LayoutValue (..),
                                                 Offset, Scalar, Selected (..),
                                                 Span, VisualExpr (..),
                                                 VisualizationBuilder,
                                                 coordConstraints, coordExpr,
                                                 coordPin, editCurrentNode,
                                                 offsetConstraints, offsetExpr,
                                                 scalarConstraints, scalarExpr,
                                                 selectedVisualExpr,
                                                 spanConstraints, spanExpr,
                                                 spanPin)
import           LinearTrace.Core               (Query, QueryInt (..),
                                                 labelName, queryInt,
                                                 queryIntAdd)
import           LinearTrace.View.Access        (LayoutAttr (..),
                                                 layoutValueAccess)
import           LinearTrace.View.Primitives    (Bounds (..), BoundsExpr,
                                                 LayoutExpr)
import qualified LinearTrace.View.Primitives    as V
import qualified LinearTrace.View.Template      as VT
import qualified Prelude                        as P
import           Prelude.Linear                 hiding (fromInteger,
                                                 fromRational, (*), (+), (-),
                                                 (/), (<>))
import qualified Solver                         as S
import           Solver                         (Vec2 (..), vec2)

nonNegative :: LayoutExpr -> S.Constraint
nonNegative expr = (S.num 0 :: LayoutExpr) S.@<=@ expr

mkCoord :: LayoutExpr -> [S.Constraint] -> Coord
mkCoord expr constraints =
  LayoutValue expr (constraints P.++ [nonNegative expr])

mkSpan :: LayoutExpr -> [S.Constraint] -> Span
mkSpan expr constraints = LayoutValue expr (constraints P.++ [nonNegative expr])

mkOffset :: LayoutExpr -> [S.Constraint] -> Offset
mkOffset = LayoutValue

mkScalar :: LayoutExpr -> [S.Constraint] -> Scalar
mkScalar = LayoutValue

class NumExpr a where
  num :: P.Double -> a

class IntegerLiteral a where
  integerLiteral :: P.Integer -> a

class RationalLiteral a where
  rationalLiteral :: P.Rational -> a

fromInteger :: IntegerLiteral a => P.Integer -> a
fromInteger = integerLiteral

fromRational :: RationalLiteral a => P.Rational -> a
fromRational = rationalLiteral

instance S.SymbolicType ty => NumExpr (S.Expr ty) where
  num = S.num

instance S.SymbolicType ty => IntegerLiteral (S.Expr ty) where
  integerLiteral value = S.num (P.fromInteger value)

instance S.SymbolicType ty => RationalLiteral (S.Expr ty) where
  rationalLiteral value = S.num (P.fromRational value)

instance IntegerLiteral P.Int where
  integerLiteral = P.fromInteger

instance IntegerLiteral P.Integer where
  integerLiteral = P.fromInteger

instance IntegerLiteral P.Double where
  integerLiteral = P.fromInteger

instance IntegerLiteral QueryInt where
  integerLiteral = QueryIntConst P.. P.fromInteger

instance RationalLiteral P.Double where
  rationalLiteral = P.fromRational

instance NumExpr Coord where
  num value = mkCoord (S.num value :: LayoutExpr) []

instance IntegerLiteral Coord where
  integerLiteral value = num (P.fromInteger value)

instance RationalLiteral Coord where
  rationalLiteral value = num (P.fromRational value)

instance NumExpr Span where
  num value = mkSpan (S.num value :: LayoutExpr) []

instance IntegerLiteral Span where
  integerLiteral value = num (P.fromInteger value)

instance RationalLiteral Span where
  rationalLiteral value = num (P.fromRational value)

instance NumExpr Offset where
  num value = mkOffset (S.num value :: LayoutExpr) []

instance IntegerLiteral Offset where
  integerLiteral value = num (P.fromInteger value)

instance RationalLiteral Offset where
  rationalLiteral value = num (P.fromRational value)

instance NumExpr Scalar where
  num value = mkScalar (S.num value :: LayoutExpr) []

instance IntegerLiteral Scalar where
  integerLiteral value = num (P.fromInteger value)

instance RationalLiteral Scalar where
  rationalLiteral value = num (P.fromRational value)

newtype QueryField =
  QueryField P.String

instance KnownSymbol name => IsLabel name QueryField where
  fromLabel = QueryField (labelName (Proxy @name))

(@:) :: QueryField -> QueryInt -> Query
QueryField name @: value = queryInt name value

at :: P.Double -> Coord
at = num

by :: P.Double -> Span
by = num

shift :: P.Double -> Offset
shift = num

queryIntExpr :: S.SymbolicType ty => QueryInt -> S.Expr ty
queryIntExpr queryIntValue =
  case queryIntValue of
    QueryIntConst value -> S.num (P.fromIntegral value)
    QueryIntVar name -> V.global name
    QueryIntAdd base offset ->
      queryIntExpr base S.@+@ S.num (P.fromIntegral offset)

asScalar :: QueryInt -> Scalar
asScalar value = mkScalar (queryIntExpr value) []

asCoord :: Offset -> Coord
asCoord value = mkCoord (offsetExpr value) (offsetConstraints value)

asSpan :: Offset -> Span
asSpan value = mkSpan (offsetExpr value) (offsetConstraints value)

rawVisualExpr :: LayoutValue valueRole -> VisualExpr valueRole
rawVisualExpr (LayoutValue expression constraints) =
  VisualExpr (Match.rawValueExpr (S.component expression constraints))

addVisualExpr :: VisualExpr lhs -> VisualExpr rhs -> VisualExpr result
addVisualExpr (VisualExpr lhs) (VisualExpr rhs) =
  VisualExpr (Match.addValueExpr lhs rhs)

subtractVisualExpr :: VisualExpr lhs -> VisualExpr rhs -> VisualExpr result
subtractVisualExpr (VisualExpr lhs) (VisualExpr rhs) =
  VisualExpr (Match.subtractValueExpr lhs rhs)

scaleVisualExpr :: VisualExpr value -> Scalar -> VisualExpr value
scaleVisualExpr (VisualExpr expression) scalar =
  VisualExpr
    (Match.scaleValueExpr
       expression
       (S.component (scalarExpr scalar) (scalarConstraints scalar)))

divideVisualExpr :: VisualExpr value -> Scalar -> VisualExpr value
divideVisualExpr (VisualExpr expression) scalar =
  VisualExpr
    (Match.divideValueExpr
       expression
       (S.component (scalarExpr scalar) (scalarConstraints scalar)))

class AddExpr lhs rhs result | lhs rhs -> result where
  addExpr :: lhs -> rhs -> result

instance S.SymbolicType ty => AddExpr (S.Expr ty) (S.Expr ty) (S.Expr ty) where
  addExpr = (S.@+@)

instance AddExpr P.Int P.Int P.Int where
  addExpr = (P.+)

instance AddExpr P.Integer P.Integer P.Integer where
  addExpr = (P.+)

instance AddExpr P.Double P.Double P.Double where
  addExpr = (P.+)

instance AddExpr QueryInt P.Int QueryInt where
  addExpr = queryIntAdd

instance AddExpr Coord Span Coord where
  addExpr lhs rhs =
    mkCoord
      (coordExpr lhs S.@+@ spanExpr rhs)
      (coordConstraints lhs P.++ spanConstraints rhs)

instance AddExpr Coord Offset Coord where
  addExpr lhs rhs =
    mkCoord
      (coordExpr lhs S.@+@ offsetExpr rhs)
      (coordConstraints lhs P.++ offsetConstraints rhs)

instance AddExpr Span Span Span where
  addExpr lhs rhs =
    mkSpan
      (spanExpr lhs S.@+@ spanExpr rhs)
      (spanConstraints lhs P.++ spanConstraints rhs)

instance AddExpr Offset Span Offset where
  addExpr lhs rhs =
    mkOffset
      (offsetExpr lhs S.@+@ spanExpr rhs)
      (offsetConstraints lhs P.++ spanConstraints rhs)

instance AddExpr Offset Offset Offset where
  addExpr lhs rhs =
    mkOffset
      (offsetExpr lhs S.@+@ offsetExpr rhs)
      (offsetConstraints lhs P.++ offsetConstraints rhs)

instance AddExpr (VisualExpr Coord) (VisualExpr Span) (VisualExpr Coord) where
  addExpr = addVisualExpr

instance AddExpr (VisualExpr Coord) (VisualExpr Offset) (VisualExpr Coord) where
  addExpr = addVisualExpr

instance AddExpr (VisualExpr Span) (VisualExpr Span) (VisualExpr Span) where
  addExpr = addVisualExpr

instance AddExpr (VisualExpr Offset) (VisualExpr Span) (VisualExpr Offset) where
  addExpr = addVisualExpr

instance AddExpr (VisualExpr Offset) (VisualExpr Offset) (VisualExpr Offset) where
  addExpr = addVisualExpr

instance AddExpr (VisualExpr Coord) Span (VisualExpr Coord) where
  addExpr lhs rhs = addVisualExpr lhs (rawVisualExpr rhs)

instance AddExpr (VisualExpr Coord) Offset (VisualExpr Coord) where
  addExpr lhs rhs = addVisualExpr lhs (rawVisualExpr rhs)

instance AddExpr Coord (VisualExpr Span) (VisualExpr Coord) where
  addExpr lhs = addVisualExpr (rawVisualExpr lhs)

instance AddExpr Coord (VisualExpr Offset) (VisualExpr Coord) where
  addExpr lhs = addVisualExpr (rawVisualExpr lhs)

class SubExpr lhs rhs result | lhs rhs -> result where
  subExpr :: lhs -> rhs -> result

instance S.SymbolicType ty => SubExpr (S.Expr ty) (S.Expr ty) (S.Expr ty) where
  subExpr = (S.@-@)

instance SubExpr P.Int P.Int P.Int where
  subExpr = (P.-)

instance SubExpr P.Integer P.Integer P.Integer where
  subExpr = (P.-)

instance SubExpr P.Double P.Double P.Double where
  subExpr = (P.-)

instance SubExpr Coord Span Coord where
  subExpr lhs rhs =
    mkCoord
      (coordExpr lhs S.@-@ spanExpr rhs)
      (coordConstraints lhs P.++ spanConstraints rhs)

instance SubExpr Coord Offset Coord where
  subExpr lhs rhs =
    mkCoord
      (coordExpr lhs S.@-@ offsetExpr rhs)
      (coordConstraints lhs P.++ offsetConstraints rhs)

instance SubExpr Coord Coord Offset where
  subExpr lhs rhs =
    mkOffset
      (coordExpr lhs S.@-@ coordExpr rhs)
      (coordConstraints lhs P.++ coordConstraints rhs)

instance SubExpr Span Span Offset where
  subExpr lhs rhs =
    mkOffset
      (spanExpr lhs S.@-@ spanExpr rhs)
      (spanConstraints lhs P.++ spanConstraints rhs)

instance SubExpr Offset Span Offset where
  subExpr lhs rhs =
    mkOffset
      (offsetExpr lhs S.@-@ spanExpr rhs)
      (offsetConstraints lhs P.++ spanConstraints rhs)

instance SubExpr Offset Offset Offset where
  subExpr lhs rhs =
    mkOffset
      (offsetExpr lhs S.@-@ offsetExpr rhs)
      (offsetConstraints lhs P.++ offsetConstraints rhs)

instance SubExpr (VisualExpr Coord) (VisualExpr Coord) (VisualExpr Offset) where
  subExpr = subtractVisualExpr

instance SubExpr (VisualExpr Coord) (VisualExpr Span) (VisualExpr Coord) where
  subExpr = subtractVisualExpr

instance SubExpr (VisualExpr Coord) (VisualExpr Offset) (VisualExpr Coord) where
  subExpr = subtractVisualExpr

instance SubExpr (VisualExpr Span) (VisualExpr Span) (VisualExpr Offset) where
  subExpr = subtractVisualExpr

instance SubExpr (VisualExpr Offset) (VisualExpr Span) (VisualExpr Offset) where
  subExpr = subtractVisualExpr

instance SubExpr (VisualExpr Offset) (VisualExpr Offset) (VisualExpr Offset) where
  subExpr = subtractVisualExpr

instance SubExpr (VisualExpr Coord) Coord (VisualExpr Offset) where
  subExpr lhs rhs = subtractVisualExpr lhs (rawVisualExpr rhs)

instance SubExpr Coord (VisualExpr Coord) (VisualExpr Offset) where
  subExpr lhs = subtractVisualExpr (rawVisualExpr lhs)

class MulExpr lhs rhs result | lhs rhs -> result where
  mulExpr :: lhs -> rhs -> result

instance S.SymbolicType ty => MulExpr (S.Expr ty) (S.Expr ty) (S.Expr ty) where
  mulExpr = (S.@*@)

instance MulExpr P.Int P.Int P.Int where
  mulExpr = (P.*)

instance MulExpr P.Integer P.Integer P.Integer where
  mulExpr = (P.*)

instance MulExpr P.Double P.Double P.Double where
  mulExpr = (P.*)

instance MulExpr Span Scalar Span where
  mulExpr lhs rhs =
    mkSpan
      (spanExpr lhs S.@*@ scalarExpr rhs)
      (spanConstraints lhs P.++ scalarConstraints rhs)

instance MulExpr Offset Scalar Offset where
  mulExpr lhs rhs =
    mkOffset
      (offsetExpr lhs S.@*@ scalarExpr rhs)
      (offsetConstraints lhs P.++ scalarConstraints rhs)

instance MulExpr Scalar Span Span where
  mulExpr lhs rhs = mulExpr rhs lhs

instance MulExpr Scalar Offset Offset where
  mulExpr lhs rhs = mulExpr rhs lhs

instance MulExpr (VisualExpr Span) Scalar (VisualExpr Span) where
  mulExpr = scaleVisualExpr

instance MulExpr (VisualExpr Offset) Scalar (VisualExpr Offset) where
  mulExpr = scaleVisualExpr

instance MulExpr Scalar (VisualExpr Span) (VisualExpr Span) where
  mulExpr scalar value = scaleVisualExpr value scalar

instance MulExpr Scalar (VisualExpr Offset) (VisualExpr Offset) where
  mulExpr scalar value = scaleVisualExpr value scalar

instance MulExpr Scalar Scalar Scalar where
  mulExpr lhs rhs =
    mkScalar
      (scalarExpr lhs S.@*@ scalarExpr rhs)
      (scalarConstraints lhs P.++ scalarConstraints rhs)

class DivExpr lhs rhs result | lhs rhs -> result, lhs -> rhs result where
  divExpr :: lhs -> rhs -> result

instance S.SymbolicType ty => DivExpr (S.Expr ty) (S.Expr ty) (S.Expr ty) where
  divExpr = (S.@/@)

instance DivExpr P.Double P.Double P.Double where
  divExpr = (P./)

instance DivExpr Span Scalar Span where
  divExpr lhs rhs =
    mkSpan
      (spanExpr lhs S.@/@ scalarExpr rhs)
      (spanConstraints lhs P.++ scalarConstraints rhs)

instance DivExpr Offset Scalar Offset where
  divExpr lhs rhs =
    mkOffset
      (offsetExpr lhs S.@/@ scalarExpr rhs)
      (offsetConstraints lhs P.++ scalarConstraints rhs)

instance DivExpr (VisualExpr Span) Scalar (VisualExpr Span) where
  divExpr = divideVisualExpr

instance DivExpr (VisualExpr Offset) Scalar (VisualExpr Offset) where
  divExpr = divideVisualExpr

instance DivExpr Scalar Scalar Scalar where
  divExpr lhs rhs =
    mkScalar
      (scalarExpr lhs S.@/@ scalarExpr rhs)
      (scalarConstraints lhs P.++ scalarConstraints rhs)

infixl 6 +
infixl 6 -
infixl 6 |+|
infixl 7 *
infixl 7 /
(+) :: AddExpr lhs rhs result => lhs -> rhs -> result
(+) = addExpr

(-) :: SubExpr lhs rhs result => lhs -> rhs -> result
(-) = subExpr

(*) :: MulExpr lhs rhs result => lhs -> rhs -> result
(*) = mulExpr

(/) :: DivExpr lhs rhs result => lhs -> rhs -> result
(/) = divExpr

(|+|) :: Span -> Span -> Span
lhs |+| rhs =
  mkSpan
    (spanExpr lhs S.@+@ spanExpr rhs)
    (spanConstraints lhs P.++ spanConstraints rhs)

class Left input output | input -> output where
  left :: input -> output

class Top input output | input -> output where
  top :: input -> output

class Width input output | input -> output where
  width :: input -> output

class Height input output | input -> output where
  height :: input -> output

class Right input output | input -> output where
  right :: input -> output

class Bottom input output | input -> output where
  bottom :: input -> output

class X input output | input -> output where
  x :: input -> output

class Y input output | input -> output where
  y :: input -> output

class Center input where
  type CenterOutput input
  center :: input -> CenterOutput input

instance Left Coord (VisualizationBuilder ()) where
  left =
    setPin "left" coordPin (\spec maybePin -> spec {VT.templateLeft = maybePin})

instance Top Coord (VisualizationBuilder ()) where
  top =
    setPin "top" coordPin (\spec maybePin -> spec {VT.templateTop = maybePin})

instance Width Span (VisualizationBuilder ()) where
  width =
    setPin
      "width"
      spanPin
      (\spec maybePin -> spec {VT.templateWidth = maybePin})

instance Height Span (VisualizationBuilder ()) where
  height =
    setPin
      "height"
      spanPin
      (\spec maybePin -> spec {VT.templateHeight = maybePin})

instance Right Coord (VisualizationBuilder ()) where
  right =
    setPin
      "right"
      coordPin
      (\spec maybePin -> spec {VT.templateRight = maybePin})

instance Bottom Coord (VisualizationBuilder ()) where
  bottom =
    setPin
      "bottom"
      coordPin
      (\spec maybePin -> spec {VT.templateBottom = maybePin})

instance Left (Selected tag) (VisualExpr Coord) where
  left selection = selectedVisualExpr selection (layoutValueAccess AttrLeft)

instance Top (Selected tag) (VisualExpr Coord) where
  top selection = selectedVisualExpr selection (layoutValueAccess AttrTop)

instance Width (Selected tag) (VisualExpr Span) where
  width selection = selectedVisualExpr selection (layoutValueAccess AttrWidth)

instance Height (Selected tag) (VisualExpr Span) where
  height selection = selectedVisualExpr selection (layoutValueAccess AttrHeight)

instance Right (Selected tag) (VisualExpr Coord) where
  right selection = selectedVisualExpr selection (layoutValueAccess AttrRight)

instance Bottom (Selected tag) (VisualExpr Coord) where
  bottom selection = selectedVisualExpr selection (layoutValueAccess AttrBottom)

instance X Coord (VisualizationBuilder ()) where
  x = setPin "x" coordPin (\spec maybePin -> spec {VT.templateX = maybePin})

instance Y Coord (VisualizationBuilder ()) where
  y = setPin "y" coordPin (\spec maybePin -> spec {VT.templateY = maybePin})

instance X (Selected tag) (VisualExpr Coord) where
  x selection = selectedVisualExpr selection (layoutValueAccess AttrCenterX)

instance Y (Selected tag) (VisualExpr Coord) where
  y selection = selectedVisualExpr selection (layoutValueAccess AttrCenterY)

instance Center (Selected tag) where
  type CenterOutput (Selected tag) = Vec2 (VisualExpr Coord)
  center selection = vec2 (x selection) (y selection)

sequenceNodeActions :: [VisualizationBuilder ()] -> VisualizationBuilder ()
sequenceNodeActions actions =
  case actions of
    [] -> pure ()
    headAction:tailActions ->
      liftA2 (\() () -> ()) headAction (sequenceNodeActions tailActions)

instance Center (Vec2 Coord) where
  type CenterOutput (Vec2 Coord) = VisualizationBuilder ()
  center (Vec2 valueX valueY) = sequenceNodeActions [x valueX, y valueY]

size :: (Width input value, Height input value) => input -> Vec2 value
size selection = vec2 (width selection) (height selection)

bounds :: BoundsExpr -> VisualizationBuilder ()
bounds (Bounds topExpr leftExpr widthExpr heightExpr) =
  sequenceNodeActions
    [ top (mkCoord topExpr [])
    , left (mkCoord leftExpr [])
    , width (mkSpan widthExpr [])
    , height (mkSpan heightExpr [])
    ]

setPin ::
     P.String
  -> (value -> VT.LayoutPin)
  -> (VT.NodeTemplate -> Maybe VT.LayoutPin -> VT.NodeTemplate)
  -> value
  -> VisualizationBuilder ()
setPin property toPin setField value =
  editCurrentNode
    property
    (\_bindings template -> setField template (P.pure (toPin value)))
