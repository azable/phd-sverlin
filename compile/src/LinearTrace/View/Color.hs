{-# LANGUAGE DeriveTraversable #-}

module LinearTrace.View.Color
  ( Hsl(..)
  , ColorExpr
  , HslExpr
  , MaterializedColor
  , MaterializedHsl
  ) where

import           LinearTrace.View.Numeric
import           Prelude

data Hsl hue unit = Hsl
  { hue        :: hue
  , saturation :: unit
  , lightness  :: unit
  } deriving (Eq, Show, Functor, Foldable, Traversable)

type ColorExpr = Hsl AngleExpr UnitExpr

type HslExpr = ColorExpr

type MaterializedColor = Hsl Double Double

type MaterializedHsl = MaterializedColor
