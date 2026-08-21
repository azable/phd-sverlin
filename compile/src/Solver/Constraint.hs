{-# LANGUAGE FlexibleInstances #-}

-- | Constraint and component implementation for symbolic expressions. The
-- public 'Solver' facade re-exports the stable constructors and combinators;
-- 'Solver.Problem' imports this module to flatten and canonicalize constraints
-- before backend compilation.
module Solver.Constraint
  ( -- * Constraints
    -- | Raw constraint tree and typeclass operators used by the view and
    -- solver problem layers to express hard and soft numeric relationships.
    Constraint(..)
  , ConstrainEq(..)
  , ConstrainOrd(..)
  , (@==@)
  , (@<=@)
  , (@>=@)
  , allOf
  , within
  , minimize
  , soften
  , -- * Canonicalization
    -- | Implementation helpers used by 'Solver.Problem' for deduplication,
    -- inspection, and energy lowering.
    flattenConstraint
  , flattenConstraints
  , constraintCount
  , equalityEpsilon
  , -- * Components
    -- | Structured relation API used by choreography matching to bridge
    -- vectors, HSL colours, and scalar fields without exposing raw solver
    -- internals to the DSL.
    Component
  , ComponentRelation(..)
  , component
  , exprComponent
  , componentConstraints
  , relateComponents
  , directedBridgeComponents
  , symmetricBridgeComponents
  ) where

import qualified Data.Set    as Set
import           Prelude
import           Solver.Expr

-- Constraints
--------------------------------------------------------------------------------
data Constraint
  = Equals Domain RawExpr RawExpr
  | LessOrEqual RawExpr RawExpr
  | Minimize RawExpr
  | Soft Constraint
  | All [Constraint]
  deriving (Eq, Ord, Show)

instance Semigroup Constraint where
  lhs <> rhs = All (flattenConstraint lhs ++ flattenConstraint rhs)

instance Monoid Constraint where
  mempty = All []

class ConstrainEq a where
  constrainEqual :: a -> a -> Constraint

class ConstrainOrd a where
  constrainLessOrEqual :: a -> a -> Constraint

infix 4 @==@
infix 4 @<=@
infix 4 @>=@
(@==@) :: ConstrainEq a => a -> a -> Constraint
(@==@) = constrainEqual

-- The solver lowers inequalities to a non-strict hinge penalty.
(@<=@) :: ConstrainOrd a => a -> a -> Constraint
(@<=@) = constrainLessOrEqual

(@>=@) :: ConstrainOrd a => a -> a -> Constraint
lhs @>=@ rhs = rhs @<=@ lhs

instance ConstrainEq (Expr ty) where
  constrainEqual (Expr domain lhs) (Expr _ rhs) = Equals domain lhs rhs

instance ConstrainOrd (Expr ty) where
  constrainLessOrEqual (Expr _ lhs) (Expr _ rhs) = LessOrEqual lhs rhs

instance ConstrainEq a => ConstrainEq (Vec2 a) where
  constrainEqual lhs rhs =
    case (lhs, rhs) of
      (Vec2 ax ay, Vec2 bx by) -> All [ax @==@ bx, ay @==@ by]

instance ConstrainEq a => ConstrainEq (Vec3 a) where
  constrainEqual lhs rhs =
    case (lhs, rhs) of
      (Vec3 ax ay az, Vec3 bx by bz) -> All [ax @==@ bx, ay @==@ by, az @==@ bz]

instance ConstrainEq a => ConstrainEq (Vec4 a) where
  constrainEqual lhs rhs =
    case (lhs, rhs) of
      (Vec4 ax ay az aw, Vec4 bx by bz bw) ->
        All [ax @==@ bx, ay @==@ by, az @==@ bz, aw @==@ bw]

flattenConstraint :: Constraint -> [Constraint]
flattenConstraint constraint =
  case constraint of
    All constraints -> concatMap flattenConstraint constraints
    Soft inner      -> fmap Soft (flattenConstraint inner)
    _               -> [constraint]

flattenConstraints :: [Constraint] -> [Constraint]
flattenConstraints =
  dedupeConstraints
    . filter (not . redundantConstraint)
    . map canonicalConstraint
    . concatMap flattenConstraint

canonicalConstraint :: Constraint -> Constraint
canonicalConstraint constraint =
  case constraint of
    Equals domain lhs rhs
      | rhs < lhs -> Equals domain rhs lhs
      | otherwise -> constraint
    Soft inner -> Soft (canonicalConstraint inner)
    All constraints -> All (map canonicalConstraint constraints)
    _ -> constraint

allOf :: [Constraint] -> Constraint
allOf = All

constraintCount :: [Constraint] -> Int
constraintCount = length . flattenConstraints

dedupeConstraints :: [Constraint] -> [Constraint]
dedupeConstraints = go Set.empty
  where
    go _ [] = []
    go seen (constraint:rest)
      | Set.member constraint seen = go seen rest
      | otherwise = constraint : go (Set.insert constraint seen) rest

redundantConstraint :: Constraint -> Bool
redundantConstraint constraint =
  case constraint of
    Equals _ lhs rhs
      | lhs == rhs -> True
    LessOrEqual lhs rhs
      | lhs == rhs -> True
    _ -> satisfiedConstantConstraint constraint

satisfiedConstantConstraint :: Constraint -> Bool
satisfiedConstantConstraint constraint =
  case constraint of
    Equals ty lhs rhs ->
      case (constantRawExprValue lhs, constantRawExprValue rhs) of
        (Just lhsValue, Just rhsValue) -> constantEquals ty lhsValue rhsValue
        _                              -> False
    LessOrEqual lhs rhs ->
      case (constantRawExprValue lhs, constantRawExprValue rhs) of
        (Just lhsValue, Just rhsValue) -> lhsValue <= rhsValue + equalityEpsilon
        _                              -> False
    Minimize _ -> False
    Soft inner -> satisfiedConstantConstraint inner
    All _ -> False

constantEquals :: Domain -> Double -> Double -> Bool
constantEquals ty lhs rhs =
  case domainCircularPeriod ty of
    Just period
      | period > 0 ->
        let nearestTurns = fromInteger (round ((lhs - rhs) / period) :: Integer)
         in abs (lhs - rhs - period * nearestTurns) <= equalityEpsilon
    _ -> abs (lhs - rhs) <= equalityEpsilon

equalityEpsilon :: Double
equalityEpsilon = 1e-9

constantRawExprValue :: RawExpr -> Maybe Double
constantRawExprValue expr =
  case expr of
    EVar _ _      -> Nothing
    ELit value    -> Just value
    EAdd lhs rhs  -> binaryConstant (+) lhs rhs
    ESub lhs rhs  -> binaryConstant (-) lhs rhs
    EMul lhs rhs  -> binaryConstant (*) lhs rhs
    EDiv lhs rhs  -> binaryConstant (/) lhs rhs
    ENeg inner    -> negate <$> constantRawExprValue inner
    EAbs inner    -> abs <$> constantRawExprValue inner
    ESignum inner -> signum <$> constantRawExprValue inner
    EPow base to  -> binaryConstant (**) base to
    EMin lhs rhs  -> binaryConstant min lhs rhs
    EMax lhs rhs  -> binaryConstant max lhs rhs

binaryConstant ::
     (Double -> Double -> Double) -> RawExpr -> RawExpr -> Maybe Double
binaryConstant op lhs rhs =
  op <$> constantRawExprValue lhs <*> constantRawExprValue rhs

minimize :: Expr ty -> Constraint
minimize (Expr _ objective) = Minimize objective

within :: SymbolicType ty => Expr ty -> Range -> Constraint
within expr range =
  All [num (rangeLower range) @<=@ expr, expr @<=@ num (rangeUpper range)]

soften :: Constraint -> Constraint
soften constraint =
  case constraint of
    Soft _ -> constraint
    _      -> Soft constraint

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Multi-component constraint helpers
--------------------------------------------------------------------------------
data Component =
  Component Domain RawExpr [Constraint]
  deriving (Eq, Ord, Show)

data ComponentRelation
  = ComponentEqual
  | ComponentLessOrEqual
  deriving (Eq, Ord, Show)

component :: SymbolicType ty => Expr ty -> [Constraint] -> Component
component expr = Component (exprDomain expr) (exprRaw expr)

exprComponent :: SymbolicType ty => Expr ty -> Component
exprComponent expr = component expr []

componentConstraints :: Component -> [Constraint]
componentConstraints value =
  case value of
    Component _ _ constraints -> constraints

relateComponents ::
     ComponentRelation -> [Component] -> [Component] -> [Constraint]
relateComponents relation = zipComponentsWith (componentRelation relation)

directedBridgeComponents ::
     [Component] -> [Component] -> [Component] -> [Constraint]
directedBridgeComponents = zipComponentTriplesWith directedBridgeComponent

symmetricBridgeComponents ::
     [Component] -> [Component] -> [Component] -> [Constraint]
symmetricBridgeComponents = zipComponentTriplesWith symmetricBridgeComponent

zipComponentsWith ::
     (Component -> Component -> Constraint)
  -> [Component]
  -> [Component]
  -> [Constraint]
zipComponentsWith f lhs rhs =
  case (lhs, rhs) of
    ([], []) -> []
    (leftComponent:leftRest, rightComponent:rightRest) ->
      componentConstraints leftComponent
        ++ componentConstraints rightComponent
        ++ [f leftComponent rightComponent]
        ++ zipComponentsWith f leftRest rightRest
    _ -> error "Cannot relate values with different component counts."

zipComponentTriplesWith ::
     (Component -> Component -> Component -> Constraint)
  -> [Component]
  -> [Component]
  -> [Component]
  -> [Constraint]
zipComponentTriplesWith f lhs middle rhs =
  case (lhs, middle, rhs) of
    ([], [], []) -> []
    (leftComponent:leftRest, middleComponent:middleRest, rightComponent:rightRest) ->
      componentConstraints leftComponent
        ++ componentConstraints middleComponent
        ++ componentConstraints rightComponent
        ++ [f leftComponent middleComponent rightComponent]
        ++ zipComponentTriplesWith f leftRest middleRest rightRest
    _ -> error "Cannot relate values with different component counts."

componentRelation :: ComponentRelation -> Component -> Component -> Constraint
componentRelation relation lhs rhs =
  case (lhs, rhs) of
    (Component lhsType lhsRaw _, Component rhsType rhsRaw _) ->
      if lhsType == rhsType
        then case relation of
               ComponentEqual       -> Equals lhsType lhsRaw rhsRaw
               ComponentLessOrEqual -> LessOrEqual lhsRaw rhsRaw
        else componentTypeError lhsType rhsType

directedBridgeComponent :: Component -> Component -> Component -> Constraint
directedBridgeComponent lhs gap rhs =
  case (lhs, gap, rhs) of
    (Component lhsType lhsRaw _, Component gapType gapRaw _, Component rhsType rhsRaw _) ->
      if lhsType == gapType && lhsType == rhsType
        then Equals lhsType (EAdd lhsRaw gapRaw) rhsRaw
        else componentTypeError3 lhsType gapType rhsType

symmetricBridgeComponent :: Component -> Component -> Component -> Constraint
symmetricBridgeComponent lhs delta rhs =
  case (lhs, delta, rhs) of
    (Component lhsType lhsRaw _, Component deltaType deltaRaw _, Component rhsType rhsRaw _) ->
      if lhsType == deltaType && lhsType == rhsType
        then let difference = EAbs (ESub lhsRaw rhsRaw)
              in Equals lhsType difference deltaRaw
        else componentTypeError3 lhsType deltaType rhsType

componentTypeError :: Domain -> Domain -> Constraint
componentTypeError lhs rhs =
  error
    ("Cannot relate values with different scalar types: "
       ++ domainName lhs
       ++ " and "
       ++ domainName rhs)

componentTypeError3 :: Domain -> Domain -> Domain -> Constraint
componentTypeError3 first second third =
  error
    ("Cannot relate values with different scalar types: "
       ++ domainName first
       ++ ", "
       ++ domainName second
       ++ ", and "
       ++ domainName third)
