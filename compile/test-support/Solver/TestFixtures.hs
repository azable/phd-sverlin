module Solver.TestFixtures
  ( SolverFixture(..)
  , availableFixtures
  , defaultBenchmarkSeeds
  , fixtureByName
  , solveFixture
  , validateFixtureSolution
  ) where

import           Data.Maybe (catMaybes)
import           Solver

data FixtureLayout

data FixtureAngle

instance SymbolicType FixtureLayout where
  symbolicDomain _ = realDomain "fixture-layout"

instance SymbolicType FixtureAngle where
  symbolicDomain _ = cyclicDomain "fixture-angle" 360

data SolverFixture = SolverFixture
  { fixtureName        :: String
  , fixtureDescription :: String
  , fixtureConstraints :: [Constraint]
  }

availableFixtures :: [SolverFixture]
availableFixtures = [boundedRowFixture, cyclicHueFixture]

defaultBenchmarkSeeds :: [RandomSeed]
defaultBenchmarkSeeds =
  map RandomSeed [1, 320994595, -1988735004, 1731275846, 1999326623]

fixtureByName :: String -> Maybe SolverFixture
fixtureByName name =
  case filter ((== name) . fixtureName) availableFixtures of
    fixture:_ -> Just fixture
    []        -> Nothing

solveFixture :: SolverFixture -> RandomSeed -> IO Solution
solveFixture fixture seed =
  solve (withInitialSeed seed defaultSolveConfig) (fixtureConstraints fixture)

validateFixtureSolution :: SolverFixture -> Solution -> [String]
validateFixtureSolution fixture solution =
  case fixtureName fixture of
    "bounded-row" -> validateBoundedRow solution
    "cyclic-hue"  -> validateCyclicHue solution
    _             -> []

boundedRowFixture :: SolverFixture
boundedRowFixture =
  SolverFixture
    { fixtureName = "bounded-row"
    , fixtureDescription =
        "A fixed row of layout boxes with native bounds, bridge equalities, and soft size preferences."
    , fixtureConstraints =
        nativeBoundsConstraints ++ rowConstraints ++ sizePreferenceConstraints
    }

rowItemCount :: Int
rowItemCount = 12

rowIndices :: [Int]
rowIndices = [0 .. rowItemCount - 1]

rowGapIndices :: [Int]
rowGapIndices = [0 .. rowItemCount - 2]

rowLeft :: Int -> Expr FixtureLayout
rowLeft i = var ("fixture.row." ++ show i ++ ".left")

rowTop :: Int -> Expr FixtureLayout
rowTop i = var ("fixture.row." ++ show i ++ ".top")

rowWidth :: Int -> Expr FixtureLayout
rowWidth i = var ("fixture.row." ++ show i ++ ".width")

rowHeight :: Int -> Expr FixtureLayout
rowHeight i = var ("fixture.row." ++ show i ++ ".height")

rowGap :: Int -> Expr FixtureLayout
rowGap i = var ("fixture.row.gap." ++ show i)

nativeBoundsConstraints :: [Constraint]
nativeBoundsConstraints =
  concat
    [ [ within (rowLeft i) (Range 0 760)
      , within (rowTop i) (Range 0 560)
      , within (rowWidth i) (Range 24 44)
      , within (rowHeight i) (Range 24 44)
      ]
    | i <- rowIndices
    ]
    ++ [within (rowGap i) (Range 6 16) | i <- rowGapIndices]

rowConstraints :: [Constraint]
rowConstraints =
  [rowLeft 0 @==@ num 32, rowTop 0 @==@ num 96]
    ++ concat
         [ [ rowLeft next @==@ rowLeft i @+@ rowWidth i @+@ rowGap i
           , rowTop next @==@ rowTop 0
           ]
         | i <- rowGapIndices
         , let next = i + 1
         ]
    ++ [rowHeight i @==@ rowWidth i | i <- rowIndices]

sizePreferenceConstraints :: [Constraint]
sizePreferenceConstraints =
  [soften (rowWidth i @==@ num 34) | i <- rowIndices]
    ++ [soften (rowGap i @==@ num 10) | i <- rowGapIndices]

validateBoundedRow :: Solution -> [String]
validateBoundedRow solution =
  catMaybes
    [ if solutionEnergy solution < 1e-4
        then Nothing
        else Just
               ("expected hard energy < 1e-4, got "
                  ++ show (solutionEnergy solution))
    ]
    ++ concatMap validateItem rowIndices
    ++ concatMap validateGap rowGapIndices
    ++ concatMap validateAdjacent rowGapIndices
  where
    validateItem i =
      concat
        [ expectRange ("left " ++ show i) 0 760 (rowLeft i)
        , expectRange ("top " ++ show i) 0 560 (rowTop i)
        , expectRange ("width " ++ show i) 24 44 (rowWidth i)
        , expectRange ("height " ++ show i) 24 44 (rowHeight i)
        , expectNear ("square " ++ show i) (rowHeight i) (rowWidth i)
        ]
    validateGap i = expectRange ("gap " ++ show i) 6 16 (rowGap i)
    validateAdjacent i =
      expectNear
        ("adjacent " ++ show i)
        (rowLeft (i + 1))
        (rowLeft i @+@ rowWidth i @+@ rowGap i)
    expectRange label lower upper expr =
      case evalExpr solution expr of
        Nothing -> ["missing " ++ label]
        Just value
          | not (finite value) -> [label ++ " is not finite: " ++ show value]
          | value < lower - 1e-3 ->
            [label ++ " below lower bound: " ++ show value]
          | value > upper + 1e-3 ->
            [label ++ " above upper bound: " ++ show value]
          | otherwise -> []
    expectNear label lhs rhs =
      case (evalExpr solution lhs, evalExpr solution rhs) of
        (Just lhsValue, Just rhsValue)
          | abs (lhsValue - rhsValue) <= 1e-3 -> []
          | otherwise ->
            [label ++ " mismatch: " ++ show lhsValue ++ " vs " ++ show rhsValue]
        _ -> ["missing " ++ label]

finite :: Double -> Bool
finite value = not (isNaN value) && not (isInfinite value)

cyclicHueFixture :: SolverFixture
cyclicHueFixture =
  SolverFixture
    { fixtureName = "cyclic-hue"
    , fixtureDescription =
        "A pair of cyclic hue variables with native range bounds and modular equality."
    , fixtureConstraints =
        [ within hueA (Range 0 360)
        , within hueB (Range 0 360)
        , hueA @==@ (num 10 :: Expr FixtureAngle)
        , hueB @==@ (num 10 :: Expr FixtureAngle)
        , hueA @==@ hueB
        ]
    }

hueA :: Expr FixtureAngle
hueA = var "fixture.hue.a"

hueB :: Expr FixtureAngle
hueB = var "fixture.hue.b"

validateCyclicHue :: Solution -> [String]
validateCyclicHue solution =
  catMaybes
    [ if solutionEnergy solution < 1e-4
        then Nothing
        else Just
               ("expected cyclic hard energy < 1e-4, got "
                  ++ show (solutionEnergy solution))
    ]
    ++ expectNear "hue a" 10 hueA
    ++ expectNear "hue b" 10 hueB
  where
    expectNear label expected expr =
      case evalExpr solution expr of
        Nothing -> ["missing " ++ label]
        Just value
          | abs (value - expected) <= 1e-3 -> []
          | otherwise ->
            [label ++ " expected " ++ show expected ++ ", got " ++ show value]
