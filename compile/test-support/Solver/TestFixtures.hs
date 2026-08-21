-- | Stable solver fixtures shared by tests and benchmarks. These intentionally
-- avoid depending on the editable app example so solver performance and
-- behavior checks remain repeatable.
module Solver.TestFixtures
  ( -- * Fixture model
    -- | Named constraint fixture plus fixture lookup and benchmark seed set.
    SolverFixture(..)
  , availableFixtures
  , defaultBenchmarkSeeds
  , fixtureByName
  , -- * Fixture execution
    -- | Helpers for solving and validating fixture-specific invariants.
    solveFixture
  , validateFixtureSolution
  ) where

import           Data.Maybe (catMaybes)
import           Solver

data FixtureLayout

data FixtureAngle

data FixtureUnit

instance SymbolicType FixtureLayout where
  symbolicDomain _ = realDomain "fixture-layout"

instance SymbolicType FixtureAngle where
  symbolicDomain _ = cyclicDomain "fixture-angle" 360

instance SymbolicType FixtureUnit where
  symbolicDomain _ = realDomain "fixture-unit"

data SolverFixture = SolverFixture
  { fixtureName        :: String
  , fixtureDescription :: String
  , fixtureConstraints :: [Constraint]
  }

availableFixtures :: [SolverFixture]
availableFixtures =
  [boundedRowFixture, cyclicHueFixture, appShapedFixture, nestedExtremaFixture]

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
    "bounded-row"    -> validateBoundedRow solution
    "cyclic-hue"     -> validateCyclicHue solution
    "app-shaped"     -> validateAppShaped solution
    "nested-extrema" -> validateNestedExtrema solution
    _                -> []

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

appShapedFixture :: SolverFixture
appShapedFixture =
  SolverFixture
    { fixtureName = "app-shaped"
    , fixtureDescription =
        "A visualization-like grid with layout, colour variables, native bounds, bridge equalities, and soft style preferences."
    , fixtureConstraints =
        appNativeBoundsConstraints
          ++ appGridConstraints
          ++ appStylePreferenceConstraints
    }

appColumns :: Int
appColumns = 4

appRows :: Int
appRows = 3

appNodeCount :: Int
appNodeCount = appColumns * appRows

appIndices :: [Int]
appIndices = [0 .. appNodeCount - 1]

appRowIndices :: [Int]
appRowIndices = [0 .. appRows - 1]

appHorizontalGapIndices :: [(Int, Int)]
appHorizontalGapIndices =
  [(row, col) | row <- appRowIndices, col <- [0 .. appColumns - 2]]

appVerticalGapIndices :: [Int]
appVerticalGapIndices = [0 .. appRows - 2]

appIndex :: Int -> Int -> Int
appIndex row col = row * appColumns + col

appLeft :: Int -> Expr FixtureLayout
appLeft i = var ("fixture.app." ++ show i ++ ".left")

appTop :: Int -> Expr FixtureLayout
appTop i = var ("fixture.app." ++ show i ++ ".top")

appWidth :: Int -> Expr FixtureLayout
appWidth i = var ("fixture.app." ++ show i ++ ".width")

appHeight :: Int -> Expr FixtureLayout
appHeight i = var ("fixture.app." ++ show i ++ ".height")

appHue :: Int -> Expr FixtureAngle
appHue i = var ("fixture.app." ++ show i ++ ".hue")

appSaturation :: Int -> Expr FixtureUnit
appSaturation i = var ("fixture.app." ++ show i ++ ".saturation")

appLightness :: Int -> Expr FixtureUnit
appLightness i = var ("fixture.app." ++ show i ++ ".lightness")

appHorizontalGap :: Int -> Int -> Expr FixtureLayout
appHorizontalGap row col =
  var ("fixture.app.gap.x." ++ show row ++ "." ++ show col)

appVerticalGap :: Int -> Expr FixtureLayout
appVerticalGap row = var ("fixture.app.gap.y." ++ show row)

appNativeBoundsConstraints :: [Constraint]
appNativeBoundsConstraints =
  concat
    [ [ within (appLeft i) (Range 0 760)
      , within (appTop i) (Range 0 560)
      , within (appWidth i) (Range 24 90)
      , within (appHeight i) (Range 20 72)
      , within (appHue i) (Range 0 360)
      , within (appSaturation i) (Range 0.35 0.75)
      , within (appLightness i) (Range 0.35 0.75)
      ]
    | i <- appIndices
    ]
    ++ [ within (appHorizontalGap row col) (Range 8 28)
       | (row, col) <- appHorizontalGapIndices
       ]
    ++ [ within (appVerticalGap row) (Range 12 36)
       | row <- appVerticalGapIndices
       ]

appGridConstraints :: [Constraint]
appGridConstraints =
  [appLeft 0 @==@ num 32, appTop 0 @==@ num 64]
    ++ concatMap appRowConstraints appRowIndices
    ++ concatMap appNextRowConstraints [0 .. appRows - 2]
    ++ [appHeight i @==@ appWidth i @*@ num 0.72 | i <- appIndices]

appRowConstraints :: Int -> [Constraint]
appRowConstraints row =
  concat
    [ [ appLeft next
          @==@ appLeft current
          @+@ appWidth current
          @+@ appHorizontalGap row col
      , appTop next @==@ appTop current
      ]
    | col <- [0 .. appColumns - 2]
    , let current = appIndex row col
    , let next = appIndex row (col + 1)
    ]

appNextRowConstraints :: Int -> [Constraint]
appNextRowConstraints row =
  [ appLeft nextFirst @==@ appLeft 0
  , appTop nextFirst
      @==@ appTop currentFirst
      @+@ appHeight currentFirst
      @+@ appVerticalGap row
  ]
  where
    currentFirst = appIndex row 0
    nextFirst = appIndex (row + 1) 0

appStylePreferenceConstraints :: [Constraint]
appStylePreferenceConstraints =
  [soften (appWidth i @==@ num 48) | i <- appIndices]
    ++ [ soften (appHue i @==@ num (fromIntegral ((i * 23 + 20) `mod` 360)))
       | i <- appIndices
       ]
    ++ [soften (appSaturation i @==@ num 0.58) | i <- appIndices]
    ++ [soften (appLightness i @==@ num 0.52) | i <- appIndices]
    ++ [ soften (appHorizontalGap row col @==@ num 14)
       | (row, col) <- appHorizontalGapIndices
       ]
    ++ [soften (appVerticalGap row @==@ num 20) | row <- appVerticalGapIndices]

validateAppShaped :: Solution -> [String]
validateAppShaped solution =
  catMaybes
    [ if solutionEnergy solution < 1e-4
        then Nothing
        else Just
               ("expected app hard energy < 1e-4, got "
                  ++ show (solutionEnergy solution))
    ]
    ++ concatMap validateNode appIndices
    ++ concatMap validateHorizontal appHorizontalGapIndices
    ++ concatMap validateVertical appVerticalGapIndices
  where
    validateNode i =
      concat
        [ expectRange ("app left " ++ show i) 0 760 (appLeft i)
        , expectRange ("app top " ++ show i) 0 560 (appTop i)
        , expectRange ("app width " ++ show i) 24 90 (appWidth i)
        , expectRange ("app height " ++ show i) 20 72 (appHeight i)
        , expectRange ("app hue " ++ show i) 0 360 (appHue i)
        , expectRange ("app saturation " ++ show i) 0.35 0.75 (appSaturation i)
        , expectRange ("app lightness " ++ show i) 0.35 0.75 (appLightness i)
        , expectNear
            ("app aspect " ++ show i)
            (appHeight i)
            (appWidth i @*@ num 0.72)
        ]
    validateHorizontal (row, col) =
      let current = appIndex row col
          next = appIndex row (col + 1)
       in expectNear
            ("app horizontal " ++ show row ++ "." ++ show col)
            (appLeft next)
            (appLeft current @+@ appWidth current @+@ appHorizontalGap row col)
    validateVertical row =
      let currentFirst = appIndex row 0
          nextFirst = appIndex (row + 1) 0
       in expectNear
            ("app vertical " ++ show row)
            (appTop nextFirst)
            (appTop currentFirst
               @+@ appHeight currentFirst
               @+@ appVerticalGap row)
    expectRange :: String -> Double -> Double -> Expr tag -> [String]
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

nestedExtremaFixture :: SolverFixture
nestedExtremaFixture =
  SolverFixture
    { fixtureName = "nested-extrema"
    , fixtureDescription =
        "Deeply nested minimum and maximum expressions that guard against duplicated backend evaluation."
    , fixtureConstraints =
        [ within value (Range 0 (fromIntegral nestedExtremaCount + 1))
        | value <- nestedExtremaValues
        ]
          ++ [ nestedMinimum @==@ num 1
             , nestedMaximum @==@ num (fromIntegral nestedExtremaCount)
             ]
    }

nestedExtremaCount :: Int
nestedExtremaCount = 18

nestedExtremaValues :: [Expr FixtureLayout]
nestedExtremaValues =
  [var ("fixture.extrema." ++ show index) | index <- [1 .. nestedExtremaCount]]

nestedMinimum :: Expr FixtureLayout
nestedMinimum = foldNestedExtrema minExpr

nestedMaximum :: Expr FixtureLayout
nestedMaximum = foldNestedExtrema maxExpr

foldNestedExtrema ::
     (Expr FixtureLayout -> Expr FixtureLayout -> Expr FixtureLayout)
  -> Expr FixtureLayout
foldNestedExtrema combine =
  case nestedExtremaValues of
    []         -> error "nested extrema fixture requires at least one value"
    value:rest -> foldl combine value rest

validateNestedExtrema :: Solution -> [String]
validateNestedExtrema solution =
  catMaybes
    [ if solutionEnergy solution < 1e-4
        then Nothing
        else Just
               ("expected nested extrema hard energy < 1e-4, got "
                  ++ show (solutionEnergy solution))
    , expectNear "minimum" 1 nestedMinimum
    , expectNear "maximum" (fromIntegral nestedExtremaCount) nestedMaximum
    ]
  where
    expectNear label expected expr =
      case evalExpr solution expr of
        Nothing -> Just ("missing nested extrema " ++ label)
        Just value
          | abs (value - expected) <= 1e-3 -> Nothing
          | otherwise ->
            Just
              ("nested extrema "
                 ++ label
                 ++ " expected "
                 ++ show expected
                 ++ ", got "
                 ++ show value)
