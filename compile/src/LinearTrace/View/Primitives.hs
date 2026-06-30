{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE FlexibleInstances #-}

-- | Solver-backed primitive domains for the view layer. Style, graph, access,
-- and choreography DSL code depend on these aliases instead of depending on
-- raw solver domains directly.
module LinearTrace.View.Primitives
  ( -- * View domains
    -- | Numeric domains used by layout/style expressions. Unit and angle
    -- domains carry native bounds into the solver.
    FreeDomain
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
  , -- * Geometry
    -- | Bounds and geometry helpers used by graph nodes, patches, build
    -- constraints, and concrete materialization.
    Bounds(..)
  , BoundsExpr
  , ConcreteBounds
  , boundsTop
  , boundsLeft
  , boundsWidth
  , boundsHeight
  , HasBounds(..)
  , -- * Colour
    -- | Symbolic and concrete HSL colour values shared by style access,
    -- materialization, and CSS compilation.
    Hsl(..)
  , ConcreteHsl
  , unitRange
  , angleRange
  , -- * Constructors
    -- | Convenience constructors re-exported through the view and choreography
    -- facades for DSL expressions.
    global
  , num
  , absExpr
  ) where

import           Prelude
import qualified Solver  as S
import           Solver  hiding (absExpr, num)

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

num :: SymbolicType ty => Double -> Expr ty
num = S.num

global :: SymbolicType ty => String -> Expr ty
global name = S.var ("global." ++ name)

absExpr :: Expr ty -> Expr ty
absExpr = S.absExpr

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

type ConcreteBounds = Bounds Double

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

type ConcreteHsl = Hsl Double Double
