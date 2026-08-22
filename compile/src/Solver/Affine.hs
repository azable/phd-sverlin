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
import           Data.Maybe        (fromMaybe)
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
  , affineSoftCount      :: Int
  } deriving (Eq, Show)

-- | Result of deciding whether hit-and-run can solve a constraint set.
data AffineClassification
  = AffineReady AffineProblem
  | AffineFallback String
  | AffineInvalid String
  deriving (Eq, Show)

-- | Compile all hard constraints into affine rows. Soft constraints remain
-- visible to the optimizer fallback but intentionally do not affect sampling.
classifyAffineProblem :: [Constraint] -> AffineClassification
classifyAffineProblem constraints =
  case invalidBounds of
    Just message -> AffineInvalid message
    Nothing ->
      case unboundedNames of
        names@(_:_) ->
          AffineFallback
            ("uniform affine sampling requires finite bounds for: "
               ++ intercalate ", " names)
        [] ->
          case traverse classifyHard hardConstraints of
            Left reason -> AffineFallback reason
            Right rows ->
              case firstInvalid rows of
                Just message -> AffineInvalid message
                Nothing ->
                  AffineReady
                    AffineProblem
                      { affineVariableNames = Map.keys variableTypes
                      , affineVariableBounds = finalBounds
                      , affineEqualities = [row | HardEquality row <- rows]
                      , affineInequalities = [row | HardInequality row <- rows]
                      , affineSoftCount = length softConstraints
                      }
  where
    flatConstraints = flattenConstraints constraints
    hardConstraints = filter hardConstraint flatConstraints
    softConstraints = filter (not . hardConstraint) flatConstraints
    variableTypes = collectConstraintVarTypes flatConstraints
    inferredBounds = inferDomainBounds hardConstraints
    finalBounds =
      Map.mapWithKey
        (\name ty ->
           domainDefaultBounds ty
             `mergeDomainBounds` Map.findWithDefault
                                   unboundedDomainBounds
                                   name
                                   inferredBounds)
        variableTypes
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

hardConstraint :: Constraint -> Bool
hardConstraint constraint =
  case constraint of
    Soft _     -> False
    Minimize _ -> False
    _          -> True

classifyHard :: Constraint -> Either String HardRow
classifyHard constraint =
  case constraint of
    Equals ty lhs rhs ->
      case domainCircularPeriod ty of
        Just _ -> Left "cyclic equality requires the optimizer backend"
        Nothing ->
          maybe
            (Left "non-affine equality requires the optimizer backend")
            (Right . equalityRow)
            (linearRawExpr (ESub lhs rhs))
    LessOrEqual lhs rhs ->
      maybe
        (Left "non-affine inequality requires the optimizer backend")
        (Right . inequalityRow)
        (linearRawExpr (ESub lhs rhs))
    Soft _ -> Right HardSatisfied
    Minimize _ -> Right HardSatisfied
    All _ -> Left "unflattened conjunction reached affine classification"

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

-- | Infer per-variable bounds from direct ranges and affine inequalities whose
-- other variables already have direct finite bounds.
inferDomainBounds :: [Constraint] -> Map String DomainBounds
inferDomainBounds constraints =
  foldl (addAffineConstraint directBounds) directBounds constraints
  where
    directBounds = foldl addDirectConstraint Map.empty constraints

addDirectConstraint ::
     Map String DomainBounds -> Constraint -> Map String DomainBounds
addDirectConstraint bounds constraint =
  case constraint of
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
    _ -> bounds

addAffineConstraint ::
     Map String DomainBounds
  -> Map String DomainBounds
  -> Constraint
  -> Map String DomainBounds
addAffineConstraint known bounds constraint =
  case constraint of
    LessOrEqual lhs rhs -> addLinearUpperBounds known (ESub lhs rhs) bounds
    All nested          -> foldl (addAffineConstraint known) bounds nested
    _                   -> bounds

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
