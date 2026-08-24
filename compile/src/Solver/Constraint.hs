{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Constraint and component implementation for symbolic expressions. The
-- public 'Solver' facade re-exports the stable constructors and combinators;
-- 'Solver.Problem' imports this module to flatten and canonicalize constraints
-- before backend compilation.
module Solver.Constraint
  ( -- * Constraints
    -- | Raw constraint tree and typeclass operators used by the view and
    -- solver problem layers to express hard and soft numeric relationships.
    Constraint(..)
  , Alternative
  , alternative
  , oneOf
  , caseOf
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
  , DecisionSpec(..)
  , constraintDecisionSpecs
  , hasConstraintDecisions
  , resolveConstraintDecisions
  , -- * Components
    -- | Structured relation API used by choreography matching to bridge
    -- vectors, HSL colours, and scalar fields without exposing raw solver
    -- internals to the DSL.
    Component
  , ComponentRelation(..)
  , component
  , exprComponent
  , componentConstraints
  , addComponentConstraints
  , addComponents
  , subtractComponents
  , scaleComponent
  , substituteComponentVars
  , componentConstantValue
  , substituteConstraintVars
  , relateComponents
  , directedBridgeComponents
  , symmetricBridgeComponents
  ) where

import qualified Data.Set      as Set
import           Prelude
import           Solver.Choice
import           Solver.Expr

-- Constraints
--------------------------------------------------------------------------------
data Constraint
  = Equals Domain RawExpr RawExpr
  | LessOrEqual RawExpr RawExpr
  | Minimize RawExpr
  | Soft Constraint
  | All [Constraint]
  | Cases DecisionSpec
  deriving (Eq, Ord, Show)

-- | One labelled branch of a finite disjunction.
data Alternative =
  Alternative String [Constraint]
  deriving (Eq, Ord, Show)

-- | A stable finite decision and the constraints guarded by each token.
data DecisionSpec = DecisionSpec
  { decisionSpecName         :: String
  , decisionSpecAlternatives :: [(String, [Constraint])]
  } deriving (Eq, Ord, Show)

-- | Label a conjunction of constraints for use with 'oneOf'.
alternative :: String -> [Constraint] -> Alternative
alternative name constraints
  | null name = error "solver alternative names must not be empty"
  | otherwise = Alternative name constraints

-- | Require exactly one labelled alternative. Supplying the first branch as
-- a separate argument makes an empty disjunction unrepresentable.
oneOf :: String -> Alternative -> [Alternative] -> Constraint
oneOf name first rest
  | null name = error "solver decision names must not be empty"
  | hasDuplicates tokens =
    error ("solver decision has duplicate alternative names: " ++ show name)
  | otherwise = Cases (DecisionSpec name alternatives)
  where
    alternatives = map unwrapAlternative (first : rest)
    tokens = map fst alternatives
    unwrapAlternative (Alternative token constraints) = (token, constraints)

-- | Guard constraints by every value of an existing typed finite choice.
caseOf ::
     forall value. ChoiceDomain value
  => Choice value
  -> (value -> [Constraint])
  -> Constraint
caseOf selected constraintsFor =
  Cases
    DecisionSpec
      { decisionSpecName = choiceName selected
      , decisionSpecAlternatives =
          [ (choiceToken value, constraintsFor value)
          | value <- choiceDomain :: [value]
          ]
      }

hasDuplicates :: Ord a => [a] -> Bool
hasDuplicates values = Set.size (Set.fromList values) /= length values

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
    Cases spec      -> [Cases (mapDecisionConstraints flattenConstraints spec)]
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
    Cases spec -> Cases (mapDecisionConstraints (map canonicalConstraint) spec)
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
    Cases _ -> False

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

-- | Collect every finite decision nested in a constraint tree.
constraintDecisionSpecs :: [Constraint] -> [DecisionSpec]
constraintDecisionSpecs = concatMap collect
  where
    collect constraint =
      case constraint of
        Equals {} -> []
        LessOrEqual _ _ -> []
        Minimize _ -> []
        Soft inner -> collect inner
        All constraints -> concatMap collect constraints
        Cases spec ->
          spec
            : concatMap
                (concatMap collect . snd)
                (decisionSpecAlternatives spec)

hasConstraintDecisions :: [Constraint] -> Bool
hasConstraintDecisions = not . null . constraintDecisionSpecs

-- | Select all guarded branches for one complete decision assignment.
resolveConstraintDecisions ::
     [(String, String)] -> [Constraint] -> Either String [Constraint]
resolveConstraintDecisions assignment = fmap concat . traverse resolve
  where
    resolve constraint =
      case constraint of
        Equals {} -> Right [constraint]
        LessOrEqual _ _ -> Right [constraint]
        Minimize _ -> Right [constraint]
        Soft inner -> fmap (map Soft) (resolve inner)
        All constraints -> fmap concat (traverse resolve constraints)
        Cases spec ->
          case lookup (decisionSpecName spec) assignment of
            Nothing ->
              Left
                ("missing solver decision assignment for "
                   ++ show (decisionSpecName spec))
            Just selected ->
              case lookup selected (decisionSpecAlternatives spec) of
                Nothing ->
                  Left
                    ("unknown solver decision alternative "
                       ++ show selected
                       ++ " for "
                       ++ show (decisionSpecName spec))
                Just constraints -> fmap concat (traverse resolve constraints)

mapDecisionConstraints ::
     ([Constraint] -> [Constraint]) -> DecisionSpec -> DecisionSpec
mapDecisionConstraints f spec =
  spec
    { decisionSpecAlternatives =
        [ (token, f constraints)
        | (token, constraints) <- decisionSpecAlternatives spec
        ]
    }

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

addComponentConstraints :: [Constraint] -> Component -> Component
addComponentConstraints additional value =
  case value of
    Component domain raw constraints ->
      Component domain raw (constraints ++ additional)

addComponents :: Component -> Component -> Component
addComponents = combineComponents EAdd

subtractComponents :: Component -> Component -> Component
subtractComponents = combineComponents ESub

combineComponents ::
     (RawExpr -> RawExpr -> RawExpr) -> Component -> Component -> Component
combineComponents combine lhs rhs =
  case (lhs, rhs) of
    (Component lhsType lhsRaw lhsConstraints, Component rhsType rhsRaw rhsConstraints) ->
      if lhsType == rhsType
        then Component
               lhsType
               (combine lhsRaw rhsRaw)
               (lhsConstraints ++ rhsConstraints)
        else error
               ("Cannot combine values with different scalar types: "
                  ++ domainName lhsType
                  ++ " and "
                  ++ domainName rhsType)

scaleComponent :: Double -> Component -> Component
scaleComponent factor value =
  case value of
    Component domain raw constraints ->
      Component domain (EMul raw (ELit factor)) constraints

substituteComponentVars :: [(String, Double)] -> Component -> Component
substituteComponentVars substitutions value =
  case value of
    Component domain raw constraints ->
      Component
        domain
        (substituteRawExprVars substitutions raw)
        (map (substituteConstraintVars substitutions) constraints)

componentConstantValue :: Component -> Maybe Double
componentConstantValue value =
  case value of
    Component _ raw _ -> constantRawExprValue raw

substituteConstraintVars :: [(String, Double)] -> Constraint -> Constraint
substituteConstraintVars substitutions constraint =
  case constraint of
    Equals domain lhs rhs ->
      Equals
        domain
        (substituteRawExprVars substitutions lhs)
        (substituteRawExprVars substitutions rhs)
    LessOrEqual lhs rhs ->
      LessOrEqual
        (substituteRawExprVars substitutions lhs)
        (substituteRawExprVars substitutions rhs)
    Minimize expr -> Minimize (substituteRawExprVars substitutions expr)
    Soft inner -> Soft (substituteConstraintVars substitutions inner)
    All constraints ->
      All (map (substituteConstraintVars substitutions) constraints)
    Cases spec ->
      Cases
        (mapDecisionConstraints
           (map (substituteConstraintVars substitutions))
           spec)

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
               ComponentEqual       -> componentEquality lhsType lhsRaw rhsRaw
               ComponentLessOrEqual -> LessOrEqual lhsRaw rhsRaw
        else componentTypeError lhsType rhsType

-- Bounded cyclic visual components have one duplicated endpoint (for example,
-- 0 and 360 degrees are the same hue). Relating their canonical numeric
-- representatives is sufficient and keeps otherwise-affine visual design
-- spaces on the affine backend. Unbounded cyclic domains retain the general
-- modulo equality handled by the optimizer.
componentEquality :: Domain -> RawExpr -> RawExpr -> Constraint
componentEquality domain lhs rhs =
  case canonicalCyclicBounds domain of
    Nothing -> Equals domain lhs rhs
    Just (lower, period) ->
      Equals
        (realDomain (domainName domain))
        (canonicalizeCyclicConstant lower period lhs)
        (canonicalizeCyclicConstant lower period rhs)

canonicalCyclicBounds :: Domain -> Maybe (Double, Double)
canonicalCyclicBounds domain =
  case (domainCircularPeriod domain, domainDefaultBounds domain) of
    (Just period, DomainBounds (Just lower) (Just upper))
      | period > 0 && upper - lower <= period + equalityEpsilon ->
        Just (lower, period)
    _ -> Nothing

canonicalizeCyclicConstant :: Double -> Double -> RawExpr -> RawExpr
canonicalizeCyclicConstant lower period expression =
  case constantRawExprValue expression of
    Nothing -> expression
    Just value ->
      let wrapped =
            value
              - period
                  * fromInteger (floor ((value - lower) / period) :: Integer)
       in ELit
            (if abs (wrapped - (lower + period)) <= equalityEpsilon
               then lower
               else wrapped)

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
