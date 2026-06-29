{-# LANGUAGE ConstraintKinds     #-}
{-# LANGUAGE DeriveTraversable   #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Solver.Expr
  ( Range(..)
  , Domain
  , domainName
  , domainCircularPeriod
  , domainDefaultBounds
  , realDomain
  , boundedDomain
  , cyclicDomain
  , boundedCyclicDomain
  , DomainBounds(..)
  , NumericType
  , SymbolicType(..)
  , unboundedDomainBounds
  , rangeDomainBounds
  , mergeDomainBounds
  , addDomainLower
  , addDomainUpper
  , Var(..)
  , varName
  , Expr(..)
  , RawExpr(..)
  , ExprView(..)
  , var
  , substituteExprVars
  , substituteRawExprVars
  , labelName
  , num
  , exprView
  , rawExprView
  , (@+@)
  , (@-@)
  , (@*@)
  , (@/@)
  , (@^@)
  , absExpr
  , minExpr
  , maxExpr
  , Vec2(..)
  , Vec3(..)
  , Vec4(..)
  , vec2
  , vec3
  , vec4
  ) where

import           Data.Proxy   (Proxy (..))
import           GHC.TypeLits (KnownSymbol, symbolVal)
import           Prelude

-- Symbolic scalar domains
--------------------------------------------------------------------------------
data Range = Range
  { rangeLower :: Double
  , rangeUpper :: Double
  } deriving (Eq, Ord, Show)

data Domain = Domain
  { domainName           :: String
  , domainCircularPeriod :: Maybe Double
  , domainDefaultBounds  :: DomainBounds
  } deriving (Eq, Ord, Show)

realDomain :: String -> Domain
realDomain name =
  Domain
    { domainName = name
    , domainCircularPeriod = Nothing
    , domainDefaultBounds = unboundedDomainBounds
    }

boundedDomain :: String -> Range -> Domain
boundedDomain name range =
  Domain
    { domainName = name
    , domainCircularPeriod = Nothing
    , domainDefaultBounds = rangeDomainBounds range
    }

cyclicDomain :: String -> Double -> Domain
cyclicDomain name period =
  Domain
    { domainName = name
    , domainCircularPeriod = Just period
    , domainDefaultBounds = unboundedDomainBounds
    }

boundedCyclicDomain :: String -> Double -> Range -> Domain
boundedCyclicDomain name period range =
  Domain
    { domainName = name
    , domainCircularPeriod = Just period
    , domainDefaultBounds = rangeDomainBounds range
    }

-- Finite domain bounds are passed to the optimizer as native bounds.
data DomainBounds = DomainBounds
  { domainLowerBound :: Maybe Double
  , domainUpperBound :: Maybe Double
  } deriving (Eq, Ord, Show)

class SymbolicType ty where
  symbolicDomain :: Proxy ty -> Domain

type NumericType ty = SymbolicType ty

unboundedDomainBounds :: DomainBounds
unboundedDomainBounds =
  DomainBounds {domainLowerBound = Nothing, domainUpperBound = Nothing}

rangeDomainBounds :: Range -> DomainBounds
rangeDomainBounds range =
  DomainBounds
    { domainLowerBound = Just (rangeLower range)
    , domainUpperBound = Just (rangeUpper range)
    }

mergeDomainBounds :: DomainBounds -> DomainBounds -> DomainBounds
mergeDomainBounds a b =
  DomainBounds
    { domainLowerBound = mergeLower (domainLowerBound a) (domainLowerBound b)
    , domainUpperBound = mergeUpper (domainUpperBound a) (domainUpperBound b)
    }

mergeLower :: Maybe Double -> Maybe Double -> Maybe Double
mergeLower a b =
  case (a, b) of
    (Nothing, x)     -> x
    (x, Nothing)     -> x
    (Just x, Just y) -> Just (max x y)

mergeUpper :: Maybe Double -> Maybe Double -> Maybe Double
mergeUpper a b =
  case (a, b) of
    (Nothing, x)     -> x
    (x, Nothing)     -> x
    (Just x, Just y) -> Just (min x y)

addDomainLower :: Double -> DomainBounds -> DomainBounds
addDomainLower lo bounds =
  bounds
    { domainLowerBound =
        case domainLowerBound bounds of
          Nothing  -> Just lo
          Just old -> Just (max old lo)
    }

addDomainUpper :: Double -> DomainBounds -> DomainBounds
addDomainUpper hi bounds =
  bounds
    { domainUpperBound =
        case domainUpperBound bounds of
          Nothing  -> Just hi
          Just old -> Just (min old hi)
    }

--------------------------------------------------------------------------------
-- Symbolic scalar expressions
--------------------------------------------------------------------------------
newtype Var =
  Var String
  deriving (Eq, Ord, Show)

varName :: Var -> String
varName (Var name) = name

data RawExpr
  = EVar Domain Var
  | ELit Double
  | EAdd RawExpr RawExpr
  | ESub RawExpr RawExpr
  | EMul RawExpr RawExpr
  | EDiv RawExpr RawExpr
  | ENeg RawExpr
  | EAbs RawExpr
  | ESignum RawExpr
  | EPow RawExpr RawExpr
  | EMin RawExpr RawExpr
  | EMax RawExpr RawExpr
  deriving (Eq, Ord, Show)

data Expr ty = Expr
  { exprDomain :: Domain
  , exprRaw    :: RawExpr
  } deriving (Eq, Ord, Show)

data ExprView
  = ExprVar Domain String
  | ExprLit Double
  | ExprAdd ExprView ExprView
  | ExprSub ExprView ExprView
  | ExprMul ExprView ExprView
  | ExprDiv ExprView ExprView
  | ExprNeg ExprView
  | ExprAbs ExprView
  | ExprSignum ExprView
  | ExprPow ExprView ExprView
  | ExprMin ExprView ExprView
  | ExprMax ExprView ExprView
  deriving (Eq, Show)

var ::
     forall ty. SymbolicType ty
  => String
  -> Expr ty
var name = Expr domain (EVar domain (Var name))
  where
    domain = symbolicDomain (Proxy :: Proxy ty)

labelName :: KnownSymbol name => Proxy name -> String
labelName proxy = dotName (symbolVal proxy)

dotName :: String -> String
dotName name =
  case name of
    []        -> []
    char:rest -> dotChar char : dotName rest

dotChar :: Char -> Char
dotChar char =
  if char == '_'
    then '.'
    else char

num ::
     forall ty. SymbolicType ty
  => Double
  -> Expr ty
num value = Expr domain (ELit value)
  where
    domain = symbolicDomain (Proxy :: Proxy ty)

binaryExpr :: (RawExpr -> RawExpr -> RawExpr) -> Expr ty -> Expr ty -> Expr ty
binaryExpr f (Expr ty lhs) (Expr _ rhs) = Expr ty (f lhs rhs)

unaryExpr :: (RawExpr -> RawExpr) -> Expr ty -> Expr ty
unaryExpr f (Expr ty inner) = Expr ty (f inner)

absExpr :: Expr ty -> Expr ty
absExpr = unaryExpr EAbs

minExpr :: Expr ty -> Expr ty -> Expr ty
minExpr = binaryExpr EMin

maxExpr :: Expr ty -> Expr ty -> Expr ty
maxExpr = binaryExpr EMax

substituteExprVars :: [(String, Double)] -> Expr ty -> Expr ty
substituteExprVars substitutions (Expr ty raw) =
  Expr ty (substituteRawExprVars substitutions raw)

substituteRawExprVars :: [(String, Double)] -> RawExpr -> RawExpr
substituteRawExprVars substitutions expr =
  case expr of
    EVar _ variable -> maybe expr ELit (lookup (varName variable) substitutions)
    ELit _ -> expr
    EAdd lhs rhs ->
      EAdd
        (substituteRawExprVars substitutions lhs)
        (substituteRawExprVars substitutions rhs)
    ESub lhs rhs ->
      ESub
        (substituteRawExprVars substitutions lhs)
        (substituteRawExprVars substitutions rhs)
    EMul lhs rhs ->
      EMul
        (substituteRawExprVars substitutions lhs)
        (substituteRawExprVars substitutions rhs)
    EDiv lhs rhs ->
      EDiv
        (substituteRawExprVars substitutions lhs)
        (substituteRawExprVars substitutions rhs)
    ENeg inner -> ENeg (substituteRawExprVars substitutions inner)
    EAbs inner -> EAbs (substituteRawExprVars substitutions inner)
    ESignum inner -> ESignum (substituteRawExprVars substitutions inner)
    EPow base to ->
      EPow
        (substituteRawExprVars substitutions base)
        (substituteRawExprVars substitutions to)
    EMin lhs rhs ->
      EMin
        (substituteRawExprVars substitutions lhs)
        (substituteRawExprVars substitutions rhs)
    EMax lhs rhs ->
      EMax
        (substituteRawExprVars substitutions lhs)
        (substituteRawExprVars substitutions rhs)

exprView :: Expr ty -> ExprView
exprView = rawExprView . exprRaw

rawExprView :: RawExpr -> ExprView
rawExprView expr =
  case expr of
    EVar domain variable -> ExprVar domain (varName variable)
    ELit value           -> ExprLit value
    EAdd lhs rhs         -> ExprAdd (rawExprView lhs) (rawExprView rhs)
    ESub lhs rhs         -> ExprSub (rawExprView lhs) (rawExprView rhs)
    EMul lhs rhs         -> ExprMul (rawExprView lhs) (rawExprView rhs)
    EDiv lhs rhs         -> ExprDiv (rawExprView lhs) (rawExprView rhs)
    ENeg inner           -> ExprNeg (rawExprView inner)
    EAbs inner           -> ExprAbs (rawExprView inner)
    ESignum inner        -> ExprSignum (rawExprView inner)
    EPow base to         -> ExprPow (rawExprView base) (rawExprView to)
    EMin lhs rhs         -> ExprMin (rawExprView lhs) (rawExprView rhs)
    EMax lhs rhs         -> ExprMax (rawExprView lhs) (rawExprView rhs)

infixl 6 @+@
infixl 6 @-@
infixl 7 @*@
infixl 7 @/@
infixr 8 @^@
(@+@) :: Expr ty -> Expr ty -> Expr ty
(@+@) = binaryExpr EAdd

(@-@) :: Expr ty -> Expr ty -> Expr ty
(@-@) = binaryExpr ESub

(@*@) :: Expr ty -> Expr ty -> Expr ty
(@*@) = binaryExpr EMul

(@/@) :: Expr ty -> Expr ty -> Expr ty
(@/@) = binaryExpr EDiv

(@^@) :: Expr ty -> Expr ty -> Expr ty
(@^@) = binaryExpr EPow

instance SymbolicType ty => Num (Expr ty) where
  (+) = (@+@)
  (-) = (@-@)
  (*) = (@*@)
  negate = unaryExpr ENeg
  abs = unaryExpr EAbs
  signum = unaryExpr ESignum
  fromInteger = num . fromInteger

instance SymbolicType ty => Fractional (Expr ty) where
  (/) = (@/@)
  recip x = num 1 @/@ x
  fromRational = num . fromRational

--------------------------------------------------------------------------------
-- Symbolic vector containers
--------------------------------------------------------------------------------
data Vec2 a =
  Vec2 a a
  deriving (Eq, Show, Functor, Foldable, Traversable)

data Vec3 a =
  Vec3 a a a
  deriving (Eq, Show, Functor, Foldable, Traversable)

data Vec4 a =
  Vec4 a a a a
  deriving (Eq, Show, Functor, Foldable, Traversable)

vec2 :: a -> a -> Vec2 a
vec2 = Vec2

vec3 :: a -> a -> a -> Vec3 a
vec3 = Vec3

vec4 :: a -> a -> a -> a -> Vec4 a
vec4 = Vec4

instance Num a => Num (Vec2 a) where
  Vec2 ax ay + Vec2 bx by = Vec2 (ax + bx) (ay + by)
  Vec2 ax ay - Vec2 bx by = Vec2 (ax - bx) (ay - by)
  Vec2 ax ay * Vec2 bx by = Vec2 (ax * bx) (ay * by)
  negate (Vec2 ax ay) = Vec2 (negate ax) (negate ay)
  abs (Vec2 ax ay) = Vec2 (abs ax) (abs ay)
  signum (Vec2 ax ay) = Vec2 (signum ax) (signum ay)
  fromInteger n = Vec2 (fromInteger n) (fromInteger n)

instance Fractional a => Fractional (Vec2 a) where
  Vec2 ax ay / Vec2 bx by = Vec2 (ax / bx) (ay / by)
  recip (Vec2 ax ay) = Vec2 (recip ax) (recip ay)
  fromRational x = Vec2 (fromRational x) (fromRational x)

instance Num a => Num (Vec3 a) where
  Vec3 ax ay az + Vec3 bx by bz = Vec3 (ax + bx) (ay + by) (az + bz)
  Vec3 ax ay az - Vec3 bx by bz = Vec3 (ax - bx) (ay - by) (az - bz)
  Vec3 ax ay az * Vec3 bx by bz = Vec3 (ax * bx) (ay * by) (az * bz)
  negate (Vec3 ax ay az) = Vec3 (negate ax) (negate ay) (negate az)
  abs (Vec3 ax ay az) = Vec3 (abs ax) (abs ay) (abs az)
  signum (Vec3 ax ay az) = Vec3 (signum ax) (signum ay) (signum az)
  fromInteger n = Vec3 (fromInteger n) (fromInteger n) (fromInteger n)

instance Fractional a => Fractional (Vec3 a) where
  Vec3 ax ay az / Vec3 bx by bz = Vec3 (ax / bx) (ay / by) (az / bz)
  recip (Vec3 ax ay az) = Vec3 (recip ax) (recip ay) (recip az)
  fromRational x = Vec3 (fromRational x) (fromRational x) (fromRational x)

instance Num a => Num (Vec4 a) where
  Vec4 ax ay az aw + Vec4 bx by bz bw =
    Vec4 (ax + bx) (ay + by) (az + bz) (aw + bw)
  Vec4 ax ay az aw - Vec4 bx by bz bw =
    Vec4 (ax - bx) (ay - by) (az - bz) (aw - bw)
  Vec4 ax ay az aw * Vec4 bx by bz bw =
    Vec4 (ax * bx) (ay * by) (az * bz) (aw * bw)
  negate (Vec4 ax ay az aw) =
    Vec4 (negate ax) (negate ay) (negate az) (negate aw)
  abs (Vec4 ax ay az aw) = Vec4 (abs ax) (abs ay) (abs az) (abs aw)
  signum (Vec4 ax ay az aw) =
    Vec4 (signum ax) (signum ay) (signum az) (signum aw)
  fromInteger n =
    Vec4 (fromInteger n) (fromInteger n) (fromInteger n) (fromInteger n)

instance Fractional a => Fractional (Vec4 a) where
  Vec4 ax ay az aw / Vec4 bx by bz bw =
    Vec4 (ax / bx) (ay / by) (az / bz) (aw / bw)
  recip (Vec4 ax ay az aw) = Vec4 (recip ax) (recip ay) (recip az) (recip aw)
  fromRational x =
    Vec4 (fromRational x) (fromRational x) (fromRational x) (fromRational x)
--------------------------------------------------------------------------------
