{-# LANGUAGE DeriveTraversable   #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Solver.Expr
  ( Range(..)
  , ScalarType(..)
  , InitialBounds(..)
  , SymbolicType(..)
  , Free
  , Layout
  , Unit
  , Angle
  , unboundedInitialBounds
  , rangeToInitialBounds
  , typeInitialBounds
  , mergeInitialBounds
  , addInitialLower
  , addInitialUpper
  , Var(..)
  , varName
  , Expr(..)
  , RawExpr(..)
  , var
  , substituteExprVars
  , substituteRawExprVars
  , labelName
  , num
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

data ScalarType = ScalarType
  { typeName           :: String
  , typeRange          :: Maybe Range
  , typeCircularPeriod :: Maybe Double
  } deriving (Eq, Ord, Show)

-- Finite initial bounds are also passed to the optimizer as native bounds.
data InitialBounds = InitialBounds
  { initialLower :: Maybe Double
  , initialUpper :: Maybe Double
  } deriving (Eq, Show)

class SymbolicType ty where
  symbolicType :: Proxy ty -> ScalarType

data Free

data Layout

data Unit

data Angle

instance SymbolicType Free where
  symbolicType _ =
    ScalarType
      {typeName = "free", typeRange = Nothing, typeCircularPeriod = Nothing}

instance SymbolicType Layout where
  symbolicType _ =
    ScalarType
      {typeName = "length", typeRange = Nothing, typeCircularPeriod = Nothing}

instance SymbolicType Unit where
  symbolicType _ =
    ScalarType
      { typeName = "unit"
      , typeRange = Just (Range 0 1)
      , typeCircularPeriod = Nothing
      }

instance SymbolicType Angle where
  symbolicType _ =
    ScalarType
      { typeName = "angle"
      , typeRange = Just (Range 0 360)
      , typeCircularPeriod = Just 360
      }

unboundedInitialBounds :: InitialBounds
unboundedInitialBounds =
  InitialBounds {initialLower = Nothing, initialUpper = Nothing}

rangeToInitialBounds :: Range -> InitialBounds
rangeToInitialBounds range =
  InitialBounds
    { initialLower = Just (rangeLower range)
    , initialUpper = Just (rangeUpper range)
    }

typeInitialBounds :: ScalarType -> InitialBounds
typeInitialBounds ty =
  maybe unboundedInitialBounds rangeToInitialBounds (typeRange ty)

mergeInitialBounds :: InitialBounds -> InitialBounds -> InitialBounds
mergeInitialBounds a b =
  InitialBounds
    { initialLower = mergeLower (initialLower a) (initialLower b)
    , initialUpper = mergeUpper (initialUpper a) (initialUpper b)
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

addInitialLower :: Double -> InitialBounds -> InitialBounds
addInitialLower lo bounds =
  bounds
    { initialLower =
        case initialLower bounds of
          Nothing  -> Just lo
          Just old -> Just (max old lo)
    }

addInitialUpper :: Double -> InitialBounds -> InitialBounds
addInitialUpper hi bounds =
  bounds
    { initialUpper =
        case initialUpper bounds of
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
  = EVar ScalarType Var
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
  { exprType :: ScalarType
  , exprRaw  :: RawExpr
  } deriving (Eq, Ord, Show)

var ::
     forall ty. SymbolicType ty
  => String
  -> Expr ty
var name = Expr ty (EVar ty (Var name))
  where
    ty = symbolicType (Proxy :: Proxy ty)

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
num value = Expr ty (ELit value)
  where
    ty = symbolicType (Proxy :: Proxy ty)

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
