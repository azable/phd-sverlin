{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE FlexibleInstances #-}

module LinearTrace.View.Geometry
  ( Bounds(..)
  , BoundsExpr
  , MaterializedBounds
  , boundsTop
  , boundsLeft
  , boundsWidth
  , boundsHeight
  , HasBounds(..)
  ) where

import           LinearTrace.View.Numeric
import           Prelude
import           Solver

data Bounds a =
  Bounds a a a a
  deriving (Eq, Show, Functor, Foldable, Traversable)

type BoundsExpr = Bounds LayoutExpr

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
  top :: a -> LayoutExpr
  left :: a -> LayoutExpr
  width :: a -> LayoutExpr
  height :: a -> LayoutExpr
  right :: a -> LayoutExpr
  right x = left x @+@ width x
  bottom :: a -> LayoutExpr
  bottom x = top x @+@ height x
  centerX :: a -> LayoutExpr
  centerX x = left x @+@ (width x @/@ num 2)
  centerY :: a -> LayoutExpr
  centerY x = top x @+@ (height x @/@ num 2)
  center :: a -> Vec2 LayoutExpr
  center x = Vec2 (centerX x) (centerY x)
  position :: a -> Vec2 LayoutExpr
  position x = Vec2 (left x) (top x)
  size :: a -> Vec2 LayoutExpr
  size x = Vec2 (width x) (height x)

instance HasBounds BoundsExpr where
  top = boundsTop
  left = boundsLeft
  width = boundsWidth
  height = boundsHeight
