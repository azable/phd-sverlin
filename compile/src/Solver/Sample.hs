-- | Uniform-ish sampling from bounded affine feasible regions.
--
-- Problems are normalized to a unit box, reduced to the null space of their
-- equalities, projected to feasibility, and sampled with hit-and-run. The
-- feasibility entrypoint is deliberately narrow so a different phase-I
-- implementation (including a MIP-backed one) can be substituted later.
module Solver.Sample
  ( FeasibilityFailure(..)
  , SamplingStatistics(..)
  , VolumeBudget(..)
  , defaultVolumeBudget
  , VolumeEstimate(..)
  , SamplingStrategy(..)
  , DecisionCoverage(..)
  , SamplingProvenance(..)
  , sampleAffineProblem
  , estimateAffineLogVolume
  ) where

import           Control.Monad         (when)
import           Data.Either           (lefts, rights)
import           Data.Map.Strict       (Map)
import qualified Data.Map.Strict       as Map
import           Data.Maybe            (catMaybes)
import qualified Numeric.LinearAlgebra as LA
import           Prelude
import           Solver.Affine
import           Solver.Expr
import           Solver.Random

-- | A deterministic failure to construct or sample a feasible affine region.
newtype FeasibilityFailure =
  FeasibilityFailure String
  deriving (Eq, Show)

-- | Backend-specific work reported alongside a sampled solution.
data SamplingStatistics = SamplingStatistics
  { samplingAmbientDimension :: Int
  , samplingReducedDimension :: Int
  , samplingEqualityCount    :: Int
  , samplingInequalityCount  :: Int
  , samplingBurnInSteps      :: Int
  } deriving (Eq, Show)

-- | Work and uncertainty limits for opt-in geometric branch weighting.
data VolumeBudget = VolumeBudget
  { volumeSamplesPerPhase     :: Int
  , volumeIndependentChains   :: Int
  , volumeTargetRelativeError :: Double
  , volumeMaximumWalkSteps    :: Int
  } deriving (Eq, Show)

defaultVolumeBudget :: VolumeBudget
defaultVolumeBudget =
  VolumeBudget
    { volumeSamplesPerPhase = 1024
    , volumeIndependentChains = 4
    , volumeTargetRelativeError = 0.1
    , volumeMaximumWalkSteps = 1000000
    }

-- | Relative intrinsic-volume estimate. The common unit-ball constant is
-- omitted from 'volumeLogMeasure', which is sufficient when every alternative
-- has the validated common dimension.
data VolumeEstimate = VolumeEstimate
  { volumeDimension     :: Int
  , volumeLogMeasure    :: Double
  , volumeRelativeError :: Double
  , volumeWalkSteps     :: Int
  } deriving (Eq, Show)

-- | Base measure used to propose valid solutions.
data SamplingStrategy
  = BalancedDesignChoices
  | GeometricVolume VolumeBudget
  deriving (Eq, Show)

-- | Whether finite decision assignments were fully enumerated or selected by
-- bounded MIP conditioning.
data DecisionCoverage
  = EnumeratedDecisions
  | MipConditionedDecisions
  deriving (Eq, Show)

-- | Reproducibility metadata retained with every solution.
data SamplingProvenance
  = SampledWith SamplingStrategy DecisionCoverage
  | LegacySampling
  deriving (Eq, Show)

data VariableScale = VariableScale
  { scaledName     :: String
  , scaledMidpoint :: Double
  , scaledRadius   :: Double
  } deriving (Eq, Show)

data NormalizedProblem = NormalizedProblem
  { normalizedVariables    :: [VariableScale]
  , normalizedFixedValues  :: Map String Double
  , normalizedEqualities   :: [DenseRow]
  , normalizedInequalities :: [DenseRow]
  }

data DenseRow = DenseRow
  { denseCoefficients :: LA.Vector Double
  , denseRhs          :: Double
  }

data ReducedProblem = ReducedProblem
  { reducedOrigin       :: LA.Vector Double
  , reducedBasis        :: LA.Matrix Double
  , reducedInequalities :: [DenseRow]
  }

-- | Sample one point from the feasible hard-constraint region. Initial
-- overrides only select the starting hint; burn-in separates them from the
-- returned sample.
sampleAffineProblem ::
     RandomSeed
  -> Map String Double
  -> AffineProblem
  -> Either FeasibilityFailure (Map String Double, SamplingStatistics)
sampleAffineProblem seed overrides problem = do
  normalized <- normalizeProblem problem
  reduced <- reduceEqualities normalized
  start <- findFeasiblePoint (startingHint overrides normalized reduced) reduced
  let dimension = LA.cols (reducedBasis reduced)
      burnIn =
        if dimension == 0
          then 0
          else max 256 (20 * dimension)
  sampled <-
    hitAndRun
      (deriveSeed seed "numeric.hit-and-run")
      burnIn
      start
      (reducedInequalities reduced)
  when
    (maximumViolation (reducedInequalities reduced) sampled
       > 10 * inequalityTolerance)
    (Left
       (FeasibilityFailure
          "hit-and-run finished outside the affine feasible region"))
  values <- reconstruct normalized reduced sampled
  pure
    ( values
    , SamplingStatistics
        { samplingAmbientDimension = length (normalizedVariables normalized)
        , samplingReducedDimension = dimension
        , samplingEqualityCount = length (normalizedEqualities normalized)
        , samplingInequalityCount = length (normalizedInequalities normalized)
        , samplingBurnInSteps = burnIn
        })

-- | Estimate normalized intrinsic volume using nested-ball ratios. This is an
-- explicitly bounded MCMC estimate, not an exact polytope-volume calculation.
estimateAffineLogVolume ::
     VolumeBudget
  -> RandomSeed
  -> AffineProblem
  -> Either FeasibilityFailure VolumeEstimate
estimateAffineLogVolume budget seed problem = do
  normalized <- normalizeProblem problem
  reduced <- reduceEqualities normalized
  let dimension = LA.cols (reducedBasis reduced)
  if dimension == 0
    then pure
           VolumeEstimate
             { volumeDimension = 0
             , volumeLogMeasure = 0
             , volumeRelativeError = 0
             , volumeWalkSteps = 0
             }
    else do
      start <-
        findFeasiblePoint (startingHint Map.empty normalized reduced) reduced
      (center, centerSteps) <-
        findInteriorCenter
          (deriveSeed seed "volume.center")
          start
          (reducedInequalities reduced)
      let innerRadius = inscribedRadius (reducedInequalities reduced) center
          ambientDimension = length (normalizedVariables normalized)
          outerRadius =
            sqrt (fromIntegral ambientDimension)
              + LA.norm_2 (reducedOrigin reduced)
              + LA.norm_2 center
              + 1.0e-9
      when
        (not (finite innerRadius) || innerRadius <= numericalTolerance)
        (Left
           (FeasibilityFailure
              "geometric volume requires a full-dimensional feasible region"))
      estimate <-
        estimateNestedVolume
          budget
          (deriveSeed seed "volume.ratios")
          centerSteps
          dimension
          center
          innerRadius
          (max innerRadius outerRadius)
          (reducedInequalities reduced)
      pure
        estimate
          { volumeLogMeasure =
              volumeLogMeasure estimate
                + intrinsicLogScale
                    (normalizedVariables normalized)
                    (reducedBasis reduced)
          }

intrinsicLogScale :: [VariableScale] -> LA.Matrix Double -> Double
intrinsicLogScale scales basis =
  sum
    [ log singularValue
    | singularValue <-
        LA.toList
          (LA.singularValues
             (LA.diag (LA.fromList (map scaledRadius scales)) LA.<> basis))
    , singularValue > numericalTolerance
    ]

findInteriorCenter ::
     RandomSeed
  -> LA.Vector Double
  -> [DenseRow]
  -> Either FeasibilityFailure (LA.Vector Double, Int)
findInteriorCenter seed start rows = do
  let dimension = LA.size start
      steps = max 256 (24 * dimension)
  candidates <- hitAndRunBallSamples seed 0 1 steps start rows Nothing
  let allCandidates = start : candidates
      center =
        foldl'
          (\best candidate ->
             if inscribedRadius rows candidate > inscribedRadius rows best
               then candidate
               else best)
          start
          allCandidates
  pure (center, steps)

inscribedRadius :: [DenseRow] -> LA.Vector Double -> Double
inscribedRadius rows point =
  minimum
    (positiveInfinity
       : [ (denseRhs row - LA.dot (denseCoefficients row) point)
           / LA.norm_2 (denseCoefficients row)
         | row <- rows
         , LA.norm_2 (denseCoefficients row) > numericalTolerance
         ])

estimateNestedVolume ::
     VolumeBudget
  -> RandomSeed
  -> Int
  -> Int
  -> LA.Vector Double
  -> Double
  -> Double
  -> [DenseRow]
  -> Either FeasibilityFailure VolumeEstimate
estimateNestedVolume budget seed centerSteps dimension center inner outer rows =
  attempt (max 64 (volumeSamplesPerPhase budget))
  where
    phases = volumePhases dimension inner outer
    attempt samplesPerPhase = do
      let estimatedSteps =
            centerSteps
              + sum
                  [ chainSteps samplesPerPhase
                  | _ <- phases
                  , _ <- [1 .. max 1 (volumeIndependentChains budget)]
                  ]
      when
        (estimatedSteps > volumeMaximumWalkSteps budget)
        (Left
           (FeasibilityFailure
              "geometric volume could not meet its uncertainty target within the walk budget"))
      probabilities <-
        traverse
          (estimatePhaseProbability samplesPerPhase)
          (zip [0 :: Int ..] phases)
      let logMeasure =
            fromIntegral dimension * log inner
              - sum [log probability | (probability, _) <- probabilities]
          relativeError = sqrt (sum [variance | (_, variance) <- probabilities])
      if relativeError <= volumeTargetRelativeError budget
        then pure
               VolumeEstimate
                 { volumeDimension = dimension
                 , volumeLogMeasure = logMeasure
                 , volumeRelativeError = relativeError
                 , volumeWalkSteps = estimatedSteps
                 }
        else attempt (samplesPerPhase * 2)
    estimatePhaseProbability samplesPerPhase (phaseIndex, (smaller, larger)) = do
      let chains = max 1 (volumeIndependentChains budget)
          perChain = max 1 ((samplesPerPhase + chains - 1) `div` chains)
      samples <-
        fmap
          concat
          (traverse
             (\chainIndex ->
                hitAndRunBallSamples
                  (deriveSeed
                     seed
                     ("phase."
                        ++ show phaseIndex
                        ++ ".chain."
                        ++ show chainIndex
                        ++ ".samples."
                        ++ show samplesPerPhase))
                  (max 128 (20 * dimension))
                  4
                  perChain
                  center
                  rows
                  (Just (center, larger)))
             [0 .. chains - 1])
      let count = length samples
          inside =
            length
              [() | point <- samples, LA.norm_2 (point - center) <= smaller]
          probability = fromIntegral inside / fromIntegral count
      when
        (inside == 0)
        (Left
           (FeasibilityFailure
              "geometric volume ratio was not resolved by the configured samples"))
      let relativeVariance =
            (1 - probability) / (fromIntegral count * probability)
      pure (probability, relativeVariance)
    chainSteps samplesPerPhase =
      let chains = max 1 (volumeIndependentChains budget)
          perChain = max 1 ((samplesPerPhase + chains - 1) `div` chains)
       in max 128 (20 * dimension) + 4 * perChain

volumePhases :: Int -> Double -> Double -> [(Double, Double)]
volumePhases dimension inner outer
  | inner >= outer * (1 - numericalTolerance) = []
  | otherwise = go inner
  where
    growth = 2 ** (1 / fromIntegral dimension)
    go current =
      let next = min outer (current * growth)
       in (current, next)
            : if next >= outer * (1 - numericalTolerance)
                then []
                else go next

normalizeProblem :: AffineProblem -> Either FeasibilityFailure NormalizedProblem
normalizeProblem problem = do
  scales <- traverse variableScale (affineVariableNames problem)
  let variables = rights scales
      fixedValues = Map.fromList (lefts scales)
  equalities <-
    traverse (normalizeRow variables fixedValues) (affineEqualities problem)
  inequalities <-
    traverse (normalizeRow variables fixedValues) (affineInequalities problem)
  let dimension = length variables
      boxRows = concatMap (unitBoxRows dimension) [0 .. dimension - 1]
  pure
    NormalizedProblem
      { normalizedVariables = variables
      , normalizedFixedValues = fixedValues
      , normalizedEqualities = equalities
      , normalizedInequalities = inequalities ++ boxRows
      }
  where
    variableScale name =
      case Map.lookup name (affineVariableBounds problem) of
        Nothing ->
          Left
            (FeasibilityFailure
               ("missing affine bounds for variable " ++ show name))
        Just bounds ->
          case (domainLowerBound bounds, domainUpperBound bounds) of
            (Just lower, Just upper)
              | not (finite lower && finite upper) ->
                Left
                  (FeasibilityFailure
                     ("non-finite affine bounds for variable " ++ show name))
              | lower > upper ->
                Left
                  (FeasibilityFailure
                     ("inconsistent affine bounds for variable " ++ show name))
              | upper - lower <= numericalTolerance ->
                Right (Left (name, lower))
              | otherwise ->
                Right
                  (Right
                     VariableScale
                       { scaledName = name
                       , scaledMidpoint = (lower + upper) / 2
                       , scaledRadius = (upper - lower) / 2
                       })
            _ ->
              Left
                (FeasibilityFailure
                   ("uniform affine sampling requires finite bounds for "
                      ++ show name))

normalizeRow ::
     [VariableScale]
  -> Map String Double
  -> AffineRow
  -> Either FeasibilityFailure DenseRow
normalizeRow variables fixedValues row =
  if all finite (rhs : coefficients)
    then Right
           DenseRow
             {denseCoefficients = LA.fromList coefficients, denseRhs = rhs}
    else Left (FeasibilityFailure "affine row contains a non-finite value")
  where
    coefficient scale =
      Map.findWithDefault 0 (scaledName scale) (affineRowCoefficients row)
    coefficients = [coefficient scale * scaledRadius scale | scale <- variables]
    midpointContribution =
      sum [coefficient scale * scaledMidpoint scale | scale <- variables]
    fixedContribution =
      sum
        [ Map.findWithDefault 0 name (affineRowCoefficients row) * value
        | (name, value) <- Map.toAscList fixedValues
        ]
    rhs = affineRowRhs row - midpointContribution - fixedContribution

unitBoxRows :: Int -> Int -> [DenseRow]
unitBoxRows dimension index =
  [ DenseRow (basisVector dimension index 1) 1
  , DenseRow (basisVector dimension index (-1)) 1
  ]

basisVector :: Int -> Int -> Double -> LA.Vector Double
basisVector dimension index value =
  LA.fromList
    [ if current == index
      then value
      else 0
    | current <- [0 .. dimension - 1]
    ]

reduceEqualities ::
     NormalizedProblem -> Either FeasibilityFailure ReducedProblem
reduceEqualities problem
  | ambientDimension == 0 = do
    validateConstantRows (normalizedEqualities problem) True
    validateConstantRows (normalizedInequalities problem) False
    pure
      ReducedProblem
        { reducedOrigin = LA.fromList []
        , reducedBasis = (LA.><) 0 0 []
        , reducedInequalities = []
        }
  | null equalities =
    pure
      ReducedProblem
        { reducedOrigin = LA.konst 0 ambientDimension
        , reducedBasis = LA.ident ambientDimension
        , reducedInequalities = inequalities
        }
  | otherwise = do
    let equalityMatrix = LA.fromRows (map denseCoefficients equalities)
        equalityValues = LA.fromList (map denseRhs equalities)
        origin =
          LA.flatten
            (LA.linearSolveSVD equalityMatrix (LA.asColumn equalityValues))
        residual = equalityMatrix LA.#> origin - equalityValues
    if not (finiteVector origin) || LA.norm_Inf residual > equalityTolerance
      then Left (FeasibilityFailure "affine equalities are inconsistent")
      else do
        let basis = LA.nullspace equalityMatrix
        reducedRows <- traverse (reduceInequality origin basis) inequalities
        pure
          ReducedProblem
            { reducedOrigin = origin
            , reducedBasis = basis
            , reducedInequalities = catMaybes reducedRows
            }
  where
    ambientDimension = length (normalizedVariables problem)
    equalities = normalizedEqualities problem
    inequalities = normalizedInequalities problem

validateConstantRows :: [DenseRow] -> Bool -> Either FeasibilityFailure ()
validateConstantRows rows equality =
  case filter invalid rows of
    [] -> Right ()
    _ ->
      Left
        (FeasibilityFailure
           (if equality
              then "affine equalities are inconsistent"
              else "affine inequalities are infeasible"))
  where
    invalid row
      | equality = abs (denseRhs row) > equalityTolerance
      | otherwise = denseRhs row < -inequalityTolerance

reduceInequality ::
     LA.Vector Double
  -> LA.Matrix Double
  -> DenseRow
  -> Either FeasibilityFailure (Maybe DenseRow)
reduceInequality origin basis row
  | LA.norm_2 coefficients <= numericalTolerance =
    if rhs >= -inequalityTolerance
      then Right Nothing
      else Left (FeasibilityFailure "affine inequalities are infeasible")
  | otherwise =
    Right (Just DenseRow {denseCoefficients = coefficients, denseRhs = rhs})
  where
    coefficients = LA.tr basis LA.#> denseCoefficients row
    rhs = denseRhs row - LA.dot (denseCoefficients row) origin

startingHint ::
     Map String Double
  -> NormalizedProblem
  -> ReducedProblem
  -> LA.Vector Double
startingHint overrides normalized reduced
  | LA.cols (reducedBasis reduced) == 0 = LA.fromList []
  | otherwise =
    LA.tr (reducedBasis reduced) LA.#> (normalizedHint - reducedOrigin reduced)
  where
    normalizedHint =
      LA.fromList
        [ clamp
          (-1)
          1
          ((Map.findWithDefault
              (scaledMidpoint scale)
              (scaledName scale)
              overrides
              - scaledMidpoint scale)
             / scaledRadius scale)
        | scale <- normalizedVariables normalized
        ]

-- | Phase-I feasibility boundary. The current implementation uses Dykstra's
-- cyclic projections; callers do not depend on that choice.
findFeasiblePoint ::
     LA.Vector Double
  -> ReducedProblem
  -> Either FeasibilityFailure (LA.Vector Double)
findFeasiblePoint initial problem
  | LA.size initial == 0 = Right initial
  | otherwise = go 0 initial zeroCorrections
  where
    rows = reducedInequalities problem
    zeroCorrections = map (const (LA.konst 0 (LA.size initial))) rows
    go sweep point corrections
      | maximumViolation rows point <= inequalityTolerance = Right point
      | sweep >= maximumProjectionSweeps =
        Left
          (FeasibilityFailure
             "could not find a feasible point for bounded affine constraints")
      | otherwise =
        let (nextPoint, nextCorrections) =
              projectionSweep point corrections rows
         in go (sweep + 1) nextPoint nextCorrections

projectionSweep ::
     LA.Vector Double
  -> [LA.Vector Double]
  -> [DenseRow]
  -> (LA.Vector Double, [LA.Vector Double])
projectionSweep initial corrections rows =
  let (point, correctionRev) =
        foldl' projectOne (initial, []) (zip rows corrections)
   in (point, reverse correctionRev)
  where
    projectOne (point, correctionRev) (row, correction) =
      let corrected = point + correction
          coefficients = denseCoefficients row
          violation = LA.dot coefficients corrected - denseRhs row
          denominator = LA.dot coefficients coefficients
          projected =
            if violation <= 0 || denominator <= numericalTolerance
              then corrected
              else corrected - LA.scale (violation / denominator) coefficients
          nextCorrection = corrected - projected
       in (projected, nextCorrection : correctionRev)

maximumViolation :: [DenseRow] -> LA.Vector Double -> Double
maximumViolation rows point =
  maximum
    (0 : [LA.dot (denseCoefficients row) point - denseRhs row | row <- rows])

hitAndRun ::
     RandomSeed
  -> Int
  -> LA.Vector Double
  -> [DenseRow]
  -> Either FeasibilityFailure (LA.Vector Double)
hitAndRun _ 0 point _ = Right point
hitAndRun seed steps initial rows = go steps initial randomValues
  where
    randomValues = randomUnitsFromSeed seed
    dimension = LA.size initial
    go remaining point values
      | remaining <= 0 = Right point
      | otherwise = do
        let (direction, afterDirection) = randomDirection dimension values
        (lower, upper) <- chord rows point direction
        case afterDirection of
          [] -> Left (FeasibilityFailure "seeded random stream ended")
          unit:rest ->
            let distance = lower + openUnit unit * (upper - lower)
                next = point + LA.scale distance direction
             in if finiteVector next
                  then go (remaining - 1) next rest
                  else Left
                         (FeasibilityFailure
                            "hit-and-run produced a non-finite sample")

hitAndRunBallSamples ::
     RandomSeed
  -> Int
  -> Int
  -> Int
  -> LA.Vector Double
  -> [DenseRow]
  -> Maybe (LA.Vector Double, Double)
  -> Either FeasibilityFailure [LA.Vector Double]
hitAndRunBallSamples seed burnIn thinning sampleCount initial rows ball =
  fmap reverse (go 0 initial randomValues [])
  where
    randomValues = randomUnitsFromSeed seed
    dimension = LA.size initial
    thin = max 1 thinning
    totalSteps = max 0 burnIn + thin * max 0 sampleCount
    go step point values samples
      | step >= totalSteps = Right samples
      | otherwise = do
        let (direction, afterDirection) = randomDirection dimension values
        (lower, upper) <- chordWithBall rows ball point direction
        case afterDirection of
          [] -> Left (FeasibilityFailure "seeded random stream ended")
          unit:rest ->
            let distance = lower + openUnit unit * (upper - lower)
                next = point + LA.scale distance direction
                nextStep = step + 1
                retain =
                  nextStep > burnIn && (nextStep - burnIn) `mod` thin == 0
                nextSamples =
                  if retain
                    then next : samples
                    else samples
             in if finiteVector next
                  then go nextStep next rest nextSamples
                  else Left
                         (FeasibilityFailure
                            "hit-and-run produced a non-finite sample")

randomDirection :: Int -> [Double] -> (LA.Vector Double, [Double])
randomDirection dimension values =
  let (components, rest) = normalValues dimension values
      vector = LA.fromList components
      magnitude = LA.norm_2 vector
   in if magnitude <= numericalTolerance
        then randomDirection dimension rest
        else (LA.scale (1 / magnitude) vector, rest)

normalValues :: Int -> [Double] -> ([Double], [Double])
normalValues count values
  | count <= 0 = ([], values)
normalValues _ [] = error "seeded random stream ended"
normalValues _ [_] = error "seeded random stream ended"
normalValues count (first:second:rest) =
  let radius = sqrt (-(2 * log (openUnit first)))
      angle = 2 * pi * second
      pair = [radius * cos angle, radius * sin angle]
      takeCount = min 2 count
      (remaining, after) = normalValues (count - takeCount) rest
   in (take takeCount pair ++ remaining, after)

chord ::
     [DenseRow]
  -> LA.Vector Double
  -> LA.Vector Double
  -> Either FeasibilityFailure (Double, Double)
chord rows point direction = do
  (lower, upper) <-
    foldl' intersect (Right (negativeInfinity, positiveInfinity)) rows
  if not (finite lower && finite upper) || lower > upper + inequalityTolerance
    then Left
           (FeasibilityFailure "bounded affine sampling found no finite chord")
    else Right (lower, upper)
  where
    intersect interval row = do
      (lower, upper) <- interval
      let offset = denseRhs row - LA.dot (denseCoefficients row) point
          slope = LA.dot (denseCoefficients row) direction
      if abs slope <= numericalTolerance
        then if offset >= -inequalityTolerance
               then Right (lower, upper)
               else Left
                      (FeasibilityFailure
                         "sample point left the feasible region")
        else let boundary = offset / slope
              in if slope > 0
                   then Right (lower, min upper boundary)
                   else Right (max lower boundary, upper)

chordWithBall ::
     [DenseRow]
  -> Maybe (LA.Vector Double, Double)
  -> LA.Vector Double
  -> LA.Vector Double
  -> Either FeasibilityFailure (Double, Double)
chordWithBall rows ball point direction = do
  linearInterval <- chord rows point direction
  case ball of
    Nothing -> Right linearInterval
    Just (center, radius) -> do
      let delta = point - center
          projection = LA.dot delta direction
          discriminant =
            projection * projection - (LA.dot delta delta - radius * radius)
      if discriminant < -inequalityTolerance
        then Left (FeasibilityFailure "sample point left the volume ball")
        else do
          let root = sqrt (max 0 discriminant)
              ballInterval = (-projection - root, -projection + root)
              interval = intersectIntervals linearInterval ballInterval
          if fst interval > snd interval + inequalityTolerance
            then Left (FeasibilityFailure "volume ball has no sampling chord")
            else Right interval

intersectIntervals :: (Double, Double) -> (Double, Double) -> (Double, Double)
intersectIntervals (firstLower, firstUpper) (secondLower, secondUpper) =
  (max firstLower secondLower, min firstUpper secondUpper)

reconstruct ::
     NormalizedProblem
  -> ReducedProblem
  -> LA.Vector Double
  -> Either FeasibilityFailure (Map String Double)
reconstruct normalized reduced sampled =
  if finiteVector normalizedValues
    then Right
           (Map.union
              (normalizedFixedValues normalized)
              (Map.fromList
                 [ (scaledName scale, value)
                 | (scale, unitValue) <-
                     zip
                       (normalizedVariables normalized)
                       (LA.toList normalizedValues)
                 , let value =
                         scaledMidpoint scale + scaledRadius scale * unitValue
                 ]))
    else Left (FeasibilityFailure "affine reconstruction was non-finite")
  where
    normalizedValues =
      reducedOrigin reduced + (reducedBasis reduced LA.#> sampled)

finiteVector :: LA.Vector Double -> Bool
finiteVector = all finite . LA.toList

finite :: Double -> Bool
finite value = not (isNaN value || isInfinite value)

clamp :: Double -> Double -> Double -> Double
clamp lower upper = min upper . max lower

openUnit :: Double -> Double
openUnit = clamp 1.0e-12 (1 - 1.0e-12)

numericalTolerance :: Double
numericalTolerance = 1.0e-12

equalityTolerance :: Double
equalityTolerance = 1.0e-8

inequalityTolerance :: Double
inequalityTolerance = 1.0e-8

maximumProjectionSweeps :: Int
maximumProjectionSweeps = 2000

positiveInfinity :: Double
positiveInfinity = 1 / 0

negativeInfinity :: Double
negativeInfinity = -positiveInfinity
