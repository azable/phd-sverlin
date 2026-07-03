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
  , queryIndex
  , (@:)
  , at
  , by
  , shift
  , asUnit
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

import           Control.Functor.Linear        hiding ((<$>), (<&>), (<*>))
import           LinearTrace.Choreography.Node (Coord, LayoutValue (..),
                                                NodeRecipe, Offset, Scalar,
                                                Selected (..),
                                                SelectionValue (..), Span,
                                                coordConstraints, coordExpr,
                                                coordPin, offsetConstraints,
                                                offsetExpr, scalarConstraints,
                                                scalarExpr, setNodePatch,
                                                spanConstraints, spanExpr,
                                                spanPin,
                                                substituteCoordBindings,
                                                substituteSpanBindings)
import           LinearTrace.Core              (MatchBindings, QueryInt (..),
                                                queryIntAdd, queryIntConst)
import qualified LinearTrace.View              as V
import           LinearTrace.View.Access       (LayoutAttr (..),
                                                layoutValueAccess)
import qualified LinearTrace.View.Patch        as VP
import           LinearTrace.View.Primitives   (Bounds (..), BoundsExpr,
                                                LayoutExpr, Unit)
import qualified Prelude                       as P
import           Prelude.Linear                hiding (fromInteger,
                                                fromRational, (*), (+), (-),
                                                (/), (<>))
import qualified Solver                        as S
import           Solver                        (Vec2 (..), vec2)

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

instance IntegerLiteral QueryInt where
  integerLiteral value = queryIntConst (P.fromInteger value)

queryIndex :: P.Int -> QueryInt
queryIndex = queryIntConst

(@:) :: (QueryInt -> query) -> QueryInt -> query
(@:) buildField = buildField

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

asUnit :: QueryInt -> Unit
asUnit = queryIntExpr

asCoord :: Offset -> Coord
asCoord value = mkCoord (offsetExpr value) (offsetConstraints value)

asSpan :: Offset -> Span
asSpan value = mkSpan (offsetExpr value) (offsetConstraints value)

class AddExpr lhs rhs result
  | lhs rhs -> result
  , lhs result -> rhs
  , result -> lhs rhs
  where
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

instance AddExpr Offset Span Offset where
  addExpr lhs rhs =
    mkOffset
      (offsetExpr lhs S.@+@ spanExpr rhs)
      (offsetConstraints lhs P.++ spanConstraints rhs)

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

instance SubExpr Coord Span Offset where
  subExpr lhs rhs =
    mkOffset
      (coordExpr lhs S.@-@ spanExpr rhs)
      (coordConstraints lhs P.++ spanConstraints rhs)

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

class MulExpr lhs rhs result
  | lhs rhs -> result
  , lhs result -> rhs
  , rhs result -> lhs
  , result -> lhs rhs
  where
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

instance MulExpr Scalar Scalar Scalar where
  mulExpr lhs rhs =
    mkScalar
      (scalarExpr lhs S.@*@ scalarExpr rhs)
      (scalarConstraints lhs P.++ scalarConstraints rhs)

class DivExpr lhs rhs result
  | lhs rhs -> result
  , lhs result -> rhs
  , result -> lhs rhs
  where
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

class Left input output | input -> output, output -> input where
  left :: input -> output

class Top input output | input -> output, output -> input where
  top :: input -> output

class Width input output | input -> output, output -> input where
  width :: input -> output

class Height input output | input -> output, output -> input where
  height :: input -> output

class Right input output | input -> output, output -> input where
  right :: input -> output

class Bottom input output | input -> output, output -> input where
  bottom :: input -> output

class X input output | input -> output, output -> input where
  x :: input -> output

class Y input output | input -> output, output -> input where
  y :: input -> output

class Center input where
  type CenterOutput input
  center :: input -> CenterOutput input

instance Left Coord (NodeRecipe ()) where
  left =
    setPin coordValuePin (\spec maybePin -> spec {VP.nodePatchLeft = maybePin})

instance Top Coord (NodeRecipe ()) where
  top =
    setPin coordValuePin (\spec maybePin -> spec {VP.nodePatchTop = maybePin})

instance Width Span (NodeRecipe ()) where
  width =
    setPin spanValuePin (\spec maybePin -> spec {VP.nodePatchWidth = maybePin})

instance Height Span (NodeRecipe ()) where
  height =
    setPin spanValuePin (\spec maybePin -> spec {VP.nodePatchHeight = maybePin})

instance Right Coord (NodeRecipe ()) where
  right =
    setPin coordValuePin (\spec maybePin -> spec {VP.nodePatchRight = maybePin})

instance Bottom Coord (NodeRecipe ()) where
  bottom =
    setPin
      coordValuePin
      (\spec maybePin -> spec {VP.nodePatchBottom = maybePin})

instance Left (Selected tag) (SelectionValue Coord tag) where
  left selection = SelectionValue selection (layoutValueAccess AttrLeft)

instance Top (Selected tag) (SelectionValue Coord tag) where
  top selection = SelectionValue selection (layoutValueAccess AttrTop)

instance Width (Selected tag) (SelectionValue Span tag) where
  width selection = SelectionValue selection (layoutValueAccess AttrWidth)

instance Height (Selected tag) (SelectionValue Span tag) where
  height selection = SelectionValue selection (layoutValueAccess AttrHeight)

instance Right (Selected tag) (SelectionValue Coord tag) where
  right selection = SelectionValue selection (layoutValueAccess AttrRight)

instance Bottom (Selected tag) (SelectionValue Coord tag) where
  bottom selection = SelectionValue selection (layoutValueAccess AttrBottom)

instance X Coord (NodeRecipe ()) where
  x = setPin coordValuePin (\spec maybePin -> spec {VP.nodePatchX = maybePin})

instance Y Coord (NodeRecipe ()) where
  y = setPin coordValuePin (\spec maybePin -> spec {VP.nodePatchY = maybePin})

instance X (Selected tag) (SelectionValue Coord tag) where
  x selection = SelectionValue selection (layoutValueAccess AttrCenterX)

instance Y (Selected tag) (SelectionValue Coord tag) where
  y selection = SelectionValue selection (layoutValueAccess AttrCenterY)

instance Center (Selected tag) where
  type CenterOutput (Selected tag) = Vec2 (SelectionValue Coord tag)
  center selection = vec2 (x selection) (y selection)

sequenceNodeRecipes :: [NodeRecipe ()] -> NodeRecipe ()
sequenceNodeRecipes recipes =
  case recipes of
    [] -> pure ()
    headRecipe:tailRecipes ->
      liftA2 (\() () -> ()) headRecipe (sequenceNodeRecipes tailRecipes)

instance Center (Vec2 Coord) where
  type CenterOutput (Vec2 Coord) = NodeRecipe ()
  center (Vec2 valueX valueY) = sequenceNodeRecipes [x valueX, y valueY]

size :: (Width input value, Height input value) => input -> Vec2 value
size selection = vec2 (width selection) (height selection)

bounds :: BoundsExpr -> NodeRecipe ()
bounds (Bounds topExpr leftExpr widthExpr heightExpr) =
  sequenceNodeRecipes
    [ top (mkCoord topExpr [])
    , left (mkCoord leftExpr [])
    , width (mkSpan widthExpr [])
    , height (mkSpan heightExpr [])
    ]

coordValuePin :: MatchBindings -> Coord -> VP.LayoutPin
coordValuePin bindings = coordPin P.. substituteCoordBindings bindings

spanValuePin :: MatchBindings -> Span -> VP.LayoutPin
spanValuePin bindings = spanPin P.. substituteSpanBindings bindings

setPin ::
     (MatchBindings -> value -> VP.LayoutPin)
  -> (VP.NodePatch -> Maybe VP.LayoutPin -> VP.NodePatch)
  -> value
  -> NodeRecipe ()
setPin toPin setField value =
  setNodePatch
    (\bindings -> setField VP.emptyNodePatch (P.pure (toPin bindings value)))
