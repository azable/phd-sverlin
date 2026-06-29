{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE FlexibleInstances #-}

module LinearTrace.View.Primitives
  ( FreeDomain
  , LayoutDomain
  , UnitDomain
  , AngleDomain
  , Free
  , Layout
  , Unit
  , Angle
  , Color
  , FreeExpr
  , LayoutExpr
  , UnitExpr
  , AngleExpr
  , ColorExpr
  , Bounds(..)
  , BoundsExpr
  , MaterializedBounds
  , boundsTop
  , boundsLeft
  , boundsWidth
  , boundsHeight
  , HasBounds(..)
  , Hsl(..)
  , MaterializedHsl
  , unitRange
  , angleRange
  ) where

import           Prelude
import           Solver

data FreeDomain

data LayoutDomain

data UnitDomain

data AngleDomain

instance SymbolicType FreeDomain where
  symbolicDomain _ = realDomain "free"

instance SymbolicType LayoutDomain where
  symbolicDomain _ = realDomain "layout"

instance SymbolicType UnitDomain where
  symbolicDomain _ = boundedDomain "unit" unitRange

instance SymbolicType AngleDomain where
  symbolicDomain _ = boundedCyclicDomain "angle" 360 angleRange

type Free = Expr FreeDomain

type Layout = Expr LayoutDomain

type Unit = Expr UnitDomain

type Angle = Expr AngleDomain

type Color = Hsl Angle Unit

type FreeExpr = Free

type LayoutExpr = Layout

type UnitExpr = Unit

type AngleExpr = Angle

type ColorExpr = Color

unitRange :: Range
unitRange = Range 0 1

angleRange :: Range
angleRange = Range 0 360

data Bounds a =
  Bounds a a a a
  deriving (Eq, Show, Functor, Foldable, Traversable)

type BoundsExpr = Bounds Layout

type MaterializedBounds = Bounds Double

boundsTop :: Bounds a -> a
boundsTop bounds =
  case bounds of
    Bounds t _ _ _ -> t

boundsLeft :: Bounds a -> a
boundsLeft bounds =
  case bounds of
    Bounds _ l _ _ -> l

boundsWidth :: Bounds a -> a
boundsWidth bounds =
  case bounds of
    Bounds _ _ w _ -> w

boundsHeight :: Bounds a -> a
boundsHeight bounds =
  case bounds of
    Bounds _ _ _ h -> h

instance ConstrainEq a => ConstrainEq (Bounds a) where
  constrainEqual lhs rhs =
    case (lhs, rhs) of
      (Bounds at al aw ah, Bounds bt bl bw bh) ->
        allOf [at @==@ bt, al @==@ bl, aw @==@ bw, ah @==@ bh]

class HasBounds a where
  top :: a -> Layout
  left :: a -> Layout
  width :: a -> Layout
  height :: a -> Layout
  right :: a -> Layout
  right x = left x @+@ width x
  bottom :: a -> Layout
  bottom x = top x @+@ height x
  centerX :: a -> Layout
  centerX x = left x @+@ (width x @/@ num 2)
  centerY :: a -> Layout
  centerY x = top x @+@ (height x @/@ num 2)
  center :: a -> Vec2 Layout
  center x = Vec2 (centerX x) (centerY x)
  position :: a -> Vec2 Layout
  position x = Vec2 (left x) (top x)
  size :: a -> Vec2 Layout
  size x = Vec2 (width x) (height x)

instance HasBounds BoundsExpr where
  top = boundsTop
  left = boundsLeft
  width = boundsWidth
  height = boundsHeight

data Hsl hue unit = Hsl
  { hue        :: hue
  , saturation :: unit
  , lightness  :: unit
  } deriving (Eq, Show, Functor, Foldable, Traversable)

type MaterializedHsl = Hsl Double Double
