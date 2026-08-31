-- | Recognition and lowering of bounded affine hard-constraint problems.
module Solver.Affine
  ( AffineRow(..)
  , AffineProblem(..)
  , AffineClassification(..)
  , classifyAffineProblem
  , collectConstraintVarTypes
  , collectRawExprVarTypes
  , inferDomainBounds
  , linearRawExpr
  ) where

import           Data.List         (intercalate)
import           Data.Map.Strict   (Map)
import qualified Data.Map.Strict   as Map
import           Data.Maybe        (fromMaybe, isNothing)
import           Prelude
import           Solver.Constraint
import           Solver.Expr

-- | A normalized symbolic affine row, represented as @coefficients * x <= rhs@
-- or @coefficients * x == rhs@ according to where it is stored.
data AffineRow = AffineRow
  { affineRowCoefficients :: Map String Double
  , affineRowRhs          :: Double
  } deriving (Eq, Show)

-- | A bounded affine problem before dense matrix preparation.
data AffineProblem = AffineProblem
  { affineVariableNames  :: [String]
  , affineVariableBounds :: Map String DomainBounds
  , affineEqualities     :: [AffineRow]
  , affineInequalities   :: [AffineRow]
  } deriving (Eq, Show)

-- | Result of validating and lowering a constraint set for affine sampling.
data AffineClassification
  = AffineReady AffineProblem
  | AffineUnsupported String
  | AffineInvalid String
  deriving (Eq, Show)

-- | Compile every constraint into affine rows. Unsupported expressions and
-- objectives are rejected; there is no secondary numeric backend.
classifyAffineProblem :: [Constraint] -> AffineClassification
classifyAffineProblem constraints =
  case firstUnsupported flatConstraints of
    Just message -> AffineUnsupported message
    Nothing ->
      case invalidBounds of
        Just message -> AffineInvalid message
        Nothing ->
          case unboundedNames of
            names@(_:_) ->
              AffineUnsupported
                ("affine sampling requires finite lower and upper bounds for: "
                   ++ intercalate ", " names)
            [] ->
              case traverse classifyHard flatConstraints of
                Left reason -> AffineUnsupported reason
                Right rows ->
                  case firstInvalid rows of
                    Just message -> AffineInvalid message
                    Nothing ->
                      AffineReady
                        AffineProblem
                          { affineVariableNames = Map.keys variableTypes
                          , affineVariableBounds = finalBounds
                          , affineEqualities = [row | HardEquality row <- rows]
                          , affineInequalities =
                              [row | HardInequality row <- rows]
                          }
  where
    flatConstraints = flattenConstraints constraints
    variableTypes = collectConstraintVarTypes flatConstraints
    inferredBounds = inferDomainBounds flatConstraints
    finalBounds =
      Map.map
        canonicalizeBounds
        (Map.mapWithKey
           (\name ty ->
              domainDefaultBounds ty
                `mergeDomainBounds` Map.findWithDefault
                                      unboundedDomainBounds
                                      name
                                      inferredBounds)
           variableTypes)
    invalidBounds = firstInvalidBound (Map.toAscList finalBounds)
    unboundedNames =
      [ name
      | (name, bounds) <- Map.toAscList finalBounds
      , not (boundedOnBothSides bounds)
      ]

data HardRow
  = HardEquality AffineRow
  | HardInequality AffineRow
  | HardSatisfied

firstUnsupported :: [Constraint] -> Maybe String
firstUnsupported constraints = firstJust (map unsupported constraints)
  where
    unsupported constraint =
      case constraint of
        Soft _ ->
          Just "soft constraints are unsupported in affine design spaces"
        Minimize _ ->
          Just "numeric objectives are unsupported in affine design spaces"
        _ -> Nothing

classifyHard :: Constraint -> Either String HardRow
classifyHard constraint =
  case constraint of
    Equals ty lhs rhs ->
      case domainCircularPeriod ty of
        Just _ -> Left "cyclic equality is not affine"
        Nothing ->
          maybe
            (Left "non-affine equality is unsupported")
            (Right . equalityRow)
            (linearRawExpr (ESub lhs rhs))
    LessOrEqual lhs rhs ->
      maybe
        (Left "non-affine inequality is unsupported")
        (Right . inequalityRow)
        (linearRawExpr (ESub lhs rhs))
    Soft _ -> Right HardSatisfied
    Minimize _ -> Right HardSatisfied
    All _ -> Left "unflattened conjunction reached affine classification"
    Cases _ -> Left "finite disjunction requires the design-space sampler"

equalityRow :: (Map String Double, Double) -> HardRow
equalityRow (coefficients, constant) =
  HardEquality (AffineRow (cleanCoefficients coefficients) (-constant))

inequalityRow :: (Map String Double, Double) -> HardRow
inequalityRow (coefficients, constant) =
  HardInequality (AffineRow (cleanCoefficients coefficients) (-constant))

cleanCoefficients :: Map String Double -> Map String Double
cleanCoefficients = Map.filter ((> equalityEpsilon) . abs)

firstInvalid :: [HardRow] -> Maybe String
firstInvalid rows = firstJust (map invalidRow rows)
  where
    invalidRow row =
      case row of
        HardEquality affine
          | Map.null (affineRowCoefficients affine)
          , abs (affineRowRhs affine) > equalityEpsilon ->
            Just "inconsistent constant affine equality"
        HardInequality affine
          | Map.null (affineRowCoefficients affine)
          , affineRowRhs affine < -equalityEpsilon ->
            Just "inconsistent constant affine inequality"
        _ -> Nothing

firstInvalidBound :: [(String, DomainBounds)] -> Maybe String
firstInvalidBound entries =
  firstJust
    [ case (domainLowerBound bounds, domainUpperBound bounds) of
      (Just lower, Just upper)
        | lower > upper ->
          Just
            ("inconsistent bounds for solver variable "
               ++ show name
               ++ ": lower "
               ++ show lower
               ++ " is greater than upper "
               ++ show upper)
      _ -> Nothing
    | (name, bounds) <- entries
    ]

firstJust :: [Maybe a] -> Maybe a
firstJust values =
  case values of
    []           -> Nothing
    Just value:_ -> Just value
    Nothing:rest -> firstJust rest

boundedOnBothSides :: DomainBounds -> Bool
boundedOnBothSides bounds =
  case (domainLowerBound bounds, domainUpperBound bounds) of
    (Just _, Just _) -> True
    _                -> False

-- Affine propagation may derive the same exact endpoint through differently
-- ordered floating-point arithmetic. Collapse a tolerance-sized crossed range
-- to its midpoint so a valid equality is not rejected as contradictory.
canonicalizeBounds :: DomainBounds -> DomainBounds
canonicalizeBounds bounds =
  case (domainLowerBound bounds, domainUpperBound bounds) of
    (Just lower, Just upper)
      | lower > upper
      , lower - upper <= equalityEpsilon ->
        let endpoint = (lower + upper) / 2
         in DomainBounds
              { domainLowerBound = Just endpoint
              , domainUpperBound = Just endpoint
              }
    _ -> bounds

-- | Collect and validate the symbolic domain used for every variable.
collectConstraintVarTypes :: [Constraint] -> Map String Domain
collectConstraintVarTypes = foldMap collectOne
  where
    collectOne constraint =
      case constraint of
        Equals _ lhs rhs ->
          mergeVarTypeMaps
            (collectRawExprVarTypes lhs)
            (collectRawExprVarTypes rhs)
        LessOrEqual lhs rhs ->
          mergeVarTypeMaps
            (collectRawExprVarTypes lhs)
            (collectRawExprVarTypes rhs)
        Minimize objective -> collectRawExprVarTypes objective
        Soft inner -> collectConstraintVarTypes [inner]
        All nested -> collectConstraintVarTypes nested
        Cases spec ->
          foldMap
            (collectConstraintVarTypes . snd)
            (decisionSpecAlternatives spec)

collectRawExprVarTypes :: RawExpr -> Map String Domain
collectRawExprVarTypes expr =
  case expr of
    EVar ty variable -> Map.singleton (varName variable) ty
    ELit _           -> Map.empty
    EAdd lhs rhs     -> both lhs rhs
    ESub lhs rhs     -> both lhs rhs
    EMul lhs rhs     -> both lhs rhs
    EDiv lhs rhs     -> both lhs rhs
    ENeg inner       -> collectRawExprVarTypes inner
    EAbs inner       -> collectRawExprVarTypes inner
    ESignum inner    -> collectRawExprVarTypes inner
    EPow lhs rhs     -> both lhs rhs
    EMin lhs rhs     -> both lhs rhs
    EMax lhs rhs     -> both lhs rhs
  where
    both lhs rhs =
      mergeVarTypeMaps (collectRawExprVarTypes lhs) (collectRawExprVarTypes rhs)

mergeVarTypeMaps :: Map String Domain -> Map String Domain -> Map String Domain
mergeVarTypeMaps = Map.unionWith mergeVarTypes

mergeVarTypes :: Domain -> Domain -> Domain
mergeVarTypes lhs rhs
  | lhs == rhs = lhs
  | otherwise =
    error
      ("solver variable used with incompatible symbolic types: "
         ++ show lhs
         ++ " and "
         ++ show rhs)

-- | Infer finite outer bounds from domains, direct ranges, and affine
-- relationships. Equality propagation is repeated only until no new bound
-- side becomes available; further numeric tightening is unnecessary because
-- every original affine row remains in the sampled problem.
inferDomainBounds :: [Constraint] -> Map String DomainBounds
inferDomainBounds constraints = inferBoundsFrom domainBounds constraints
  where
    domainBounds =
      Map.map domainDefaultBounds (collectConstraintVarTypes constraints)

inferBoundsFrom ::
     Map String DomainBounds -> [Constraint] -> Map String DomainBounds
inferBoundsFrom initial originalConstraints = propagate directBounds
  where
    constraints = mergeParallelCases originalConstraints
    directBounds = foldl addDirectConstraint domainBounds constraints
    domainBounds = initial
    propagate known =
      let next = foldl (addAffineConstraint known) known constraints
       in if boundAvailability next == boundAvailability known
            then next
            else propagate next

-- Several constraints may be guarded by the same finite decision.  Bound
-- inference must consider their conjunction per token: inspecting each Cases
-- node separately would miss complementary arms such as "omit fixes size to
-- zero" and "include derives size from content".  Decisions with different
-- names remain independent, so this does not construct a Cartesian product.
mergeParallelCases :: [Constraint] -> [Constraint]
mergeParallelCases original = ordinary ++ map Cases (Map.elems grouped)
  where
    normalized = concatMap normalize original
    ordinary = [constraint | constraint <- normalized, notCase constraint]
    grouped =
      Map.fromListWith
        mergeSpecs
        [(specKey spec, spec) | Cases spec <- normalized]
    normalize constraint =
      case constraint of
        All nested -> mergeParallelCases nested
        Cases spec ->
          [ Cases
              spec
                { decisionSpecAlternatives =
                    [ (token, mergeParallelCases nested)
                    | (token, nested) <- decisionSpecAlternatives spec
                    ]
                }
          ]
        _ -> [constraint]
    notCase constraint =
      case constraint of
        Cases _ -> False
        _       -> True
    specKey spec =
      ( decisionSpecName spec
      , decisionSpecOrigin spec
      , map fst (decisionSpecAlternatives spec))
    mergeSpecs newer older =
      older
        { decisionSpecAlternatives =
            zipWith
              (\(token, oldConstraints) (_, newConstraints) ->
                 (token, oldConstraints ++ newConstraints))
              (decisionSpecAlternatives older)
              (decisionSpecAlternatives newer)
        }

boundAvailability :: Map String DomainBounds -> Map String (Bool, Bool)
boundAvailability =
  Map.map
    (\bounds ->
       (hasBound (domainLowerBound bounds), hasBound (domainUpperBound bounds)))
  where
    hasBound maybeBound =
      case maybeBound of
        Nothing -> False
        Just _  -> True

addDirectConstraint ::
     Map String DomainBounds -> Constraint -> Map String DomainBounds
addDirectConstraint bounds constraint =
  case constraint of
    Equals domain (EVar _ variable) (ELit value)
      | isNothing (domainCircularPeriod domain) ->
        addFixedBound variable value bounds
    Equals domain (ELit value) (EVar _ variable)
      | isNothing (domainCircularPeriod domain) ->
        addFixedBound variable value bounds
    LessOrEqual (ELit lower) (EVar _ variable) ->
      Map.alter
        (Just . addDomainLower lower . fromMaybe unboundedDomainBounds)
        (varName variable)
        bounds
    LessOrEqual (EVar _ variable) (ELit upper) ->
      Map.alter
        (Just . addDomainUpper upper . fromMaybe unboundedDomainBounds)
        (varName variable)
        bounds
    All nested -> foldl addDirectConstraint bounds nested
    Cases _ -> bounds
    _ -> bounds

addFixedBound ::
     Var -> Double -> Map String DomainBounds -> Map String DomainBounds
addFixedBound variable value =
  Map.alter
    (Just
       . addDomainUpper value
       . addDomainLower value
       . fromMaybe unboundedDomainBounds)
    (varName variable)

addAffineConstraint ::
     Map String DomainBounds
  -> Map String DomainBounds
  -> Constraint
  -> Map String DomainBounds
addAffineConstraint known bounds constraint =
  case constraint of
    Equals domain lhs rhs
      | isNothing (domainCircularPeriod domain) ->
        let difference = ESub lhs rhs
         in addLinearUpperBounds
              known
              (ENeg difference)
              (addLinearUpperBounds known difference bounds)
    LessOrEqual lhs rhs -> addLinearUpperBounds known (ESub lhs rhs) bounds
    All nested -> foldl (addAffineConstraint known) bounds nested
    Cases spec ->
      Map.unionWith
        mergeDomainBounds
        bounds
        (commonAlternativeBounds
           [ inferBoundsFrom known nested
           | (_, nested) <- decisionSpecAlternatives spec
           , not (constraintsDefinitelyInfeasible nested)
           ])
    _ -> bounds

-- Constant contradictions are independent of every numeric bound.  Ignoring
-- those branches is required for guarded constraints: an inactive guard is
-- represented by @0 == 1@, so it cannot weaken the bounds proved by the only
-- feasible alternative.
constraintsDefinitelyInfeasible :: [Constraint] -> Bool
constraintsDefinitelyInfeasible = any constraintDefinitelyInfeasible

constraintDefinitelyInfeasible :: Constraint -> Bool
constraintDefinitelyInfeasible constraint =
  case constraint of
    Equals domain lhs rhs
      | isNothing (domainCircularPeriod domain) ->
        maybe False ((> equalityEpsilon) . abs) (constantDifference lhs rhs)
    LessOrEqual lhs rhs ->
      maybe False (> equalityEpsilon) (constantDifference lhs rhs)
    All nested -> constraintsDefinitelyInfeasible nested
    Cases spec ->
      all
        (constraintsDefinitelyInfeasible . snd)
        (decisionSpecAlternatives spec)
    _ -> False
  where
    constantDifference lhs rhs =
      case linearRawExpr (ESub lhs rhs) of
        Just (coefficients, constant)
          | Map.null coefficients -> Just constant
        _ -> Nothing

commonAlternativeBounds :: [Map String DomainBounds] -> Map String DomainBounds
commonAlternativeBounds alternatives =
  case alternatives of
    [] -> Map.empty
    first:_ ->
      Map.mapWithKey
        (\name _ ->
           DomainBounds
             { domainLowerBound =
                 minimum
                   <$> traverse
                         (\branch -> Map.lookup name branch >>= domainLowerBound)
                         alternatives
             , domainUpperBound =
                 maximum
                   <$> traverse
                         (\branch -> Map.lookup name branch >>= domainUpperBound)
                         alternatives
             })
        first

addLinearUpperBounds ::
     Map String DomainBounds
  -> RawExpr
  -> Map String DomainBounds
  -> Map String DomainBounds
addLinearUpperBounds known expr bounds =
  case linearRawExpr expr of
    Nothing -> bounds
    Just (coefficients, constant) ->
      foldl
        (addLinearBound known coefficients constant)
        bounds
        (Map.toAscList coefficients)

addLinearBound ::
     Map String DomainBounds
  -> Map String Double
  -> Double
  -> Map String DomainBounds
  -> (String, Double)
  -> Map String DomainBounds
addLinearBound known coefficients constant bounds (target, coefficient)
  | abs coefficient <= equalityEpsilon = bounds
  | otherwise =
    case boundFromOtherTerms known target coefficient coefficients constant of
      Nothing -> bounds
      Just value
        | coefficient > 0 ->
          Map.alter
            (Just . addDomainUpper value . fromMaybe unboundedDomainBounds)
            target
            bounds
        | otherwise ->
          Map.alter
            (Just . addDomainLower value . fromMaybe unboundedDomainBounds)
            target
            bounds

boundFromOtherTerms ::
     Map String DomainBounds
  -> String
  -> Double
  -> Map String Double
  -> Double
  -> Maybe Double
boundFromOtherTerms known target coefficient coefficients constant = do
  otherValue <- minOtherTerms known target coefficients
  pure ((-constant - otherValue) / coefficient)

minOtherTerms ::
     Map String DomainBounds -> String -> Map String Double -> Maybe Double
minOtherTerms known target coefficients =
  sum
    <$> traverse
          termMinimum
          [ entry
          | entry@(name, _) <- Map.toAscList coefficients
          , name /= target
          ]
  where
    termMinimum (name, coefficient)
      | coefficient >= 0 = do
        bounds <- Map.lookup name known
        lower <- domainLowerBound bounds
        pure (coefficient * lower)
      | otherwise = do
        bounds <- Map.lookup name known
        upper <- domainUpperBound bounds
        pure (coefficient * upper)

-- | Recognize constants, variables, addition, subtraction, negation, and
-- multiplication or division by a literal as an affine expression.
linearRawExpr :: RawExpr -> Maybe (Map String Double, Double)
linearRawExpr expr =
  case expr of
    EVar _ variable -> Just (Map.singleton (varName variable) 1, 0)
    ELit value -> Just (Map.empty, value)
    EAdd lhs rhs -> addLinear lhs rhs
    ESub lhs rhs -> subtractLinear lhs rhs
    ENeg inner -> scaleLinear (-1) <$> linearRawExpr inner
    EMul (ELit scalar) rhs -> scaleLinear scalar <$> linearRawExpr rhs
    EMul lhs (ELit scalar) -> scaleLinear scalar <$> linearRawExpr lhs
    EDiv lhs (ELit scalar)
      | abs scalar > equalityEpsilon ->
        scaleLinear (1 / scalar) <$> linearRawExpr lhs
    _ -> Nothing

addLinear :: RawExpr -> RawExpr -> Maybe (Map String Double, Double)
addLinear lhs rhs = do
  lhsLinear <- linearRawExpr lhs
  rhsLinear <- linearRawExpr rhs
  pure (addLinearValues lhsLinear rhsLinear)

subtractLinear :: RawExpr -> RawExpr -> Maybe (Map String Double, Double)
subtractLinear lhs rhs = do
  lhsLinear <- linearRawExpr lhs
  rhsLinear <- linearRawExpr rhs
  pure (addLinearValues lhsLinear (scaleLinear (-1) rhsLinear))

addLinearValues ::
     (Map String Double, Double)
  -> (Map String Double, Double)
  -> (Map String Double, Double)
addLinearValues (lhsCoefficients, lhsConstant) (rhsCoefficients, rhsConstant) =
  (Map.unionWith (+) lhsCoefficients rhsCoefficients, lhsConstant + rhsConstant)

scaleLinear ::
     Double -> (Map String Double, Double) -> (Map String Double, Double)
scaleLinear scalar (coefficients, constant) =
  (Map.map (* scalar) coefficients, scalar * constant)
