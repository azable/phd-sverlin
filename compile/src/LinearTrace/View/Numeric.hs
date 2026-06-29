module LinearTrace.View.Numeric
  ( -- * Solver domains
    FreeDomain
  , LayoutDomain
  , UnitDomain
  , AngleDomain
  , Free
  , Layout
  , Unit
  , Angle
  , -- * Expression aliases
    FreeExpr
  , LayoutExpr
  , UnitExpr
  , AngleExpr
  , Hue
  , HueExpr
  , -- * Semantic ranges
    unitRange
  , angleRange
  , unitConstraints
  , angleConstraints
  ) where

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
  symbolicDomain _ = realDomain "unit"

instance SymbolicType AngleDomain where
  symbolicDomain _ = cyclicDomain "angle" 360

type Free = FreeDomain

type Layout = LayoutDomain

type Unit = UnitDomain

type Angle = AngleDomain

type FreeExpr = Expr FreeDomain

type LayoutExpr = Expr LayoutDomain

type UnitExpr = Expr UnitDomain

type AngleExpr = Expr AngleDomain

type Hue = AngleExpr

type HueExpr = AngleExpr

unitRange :: Range
unitRange = Range 0 1

angleRange :: Range
angleRange = Range 0 360

unitConstraints :: UnitExpr -> [Constraint]
unitConstraints expr = [within expr unitRange]

angleConstraints :: AngleExpr -> [Constraint]
angleConstraints expr = [within expr angleRange]
