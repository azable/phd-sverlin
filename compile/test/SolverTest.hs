{-# LANGUAGE ScopedTypeVariables #-}

module Main where

import           Control.Exception   (ErrorCall, evaluate, try)
import qualified Data.List           as List
import qualified Data.Map.Strict     as Map
import           Solver
import           Solver.TestFixtures
import           Test.Tasty
import           Test.Tasty.HUnit

data TestLayout

data TestAngle

data TestUnit

data TestBoundedAngle

data TestProbe

instance SymbolicType TestLayout where
  symbolicDomain _ = realDomain "test-length"

instance SymbolicType TestAngle where
  symbolicDomain _ = cyclicDomain "test-angle" 360

instance SymbolicType TestUnit where
  symbolicDomain _ = boundedDomain "test-unit" (Range 0 1)

instance SymbolicType TestBoundedAngle where
  symbolicDomain _ = boundedCyclicDomain "test-bounded-angle" 360 (Range 0 360)

instance CategoricalType TestProbe where
  categoricalDomain _ = [category "match", category "no-match"]

main :: IO ()
main =
  defaultMain
    (testGroup
       "solver"
       [ nativeBoundsTests
       , componentTests
       , cyclicDomainTests
       , categoricalTests
       , seededFixtureTests
       , problemInspectionTests
       ])

nativeBoundsTests :: TestTree
nativeBoundsTests =
  testGroup
    "native bounds"
    [ testCase "native bounds constrain soft optima" $ do
        let x = var "test.native.x" :: Expr TestLayout
            constraints = [within x (Range 10 20), soften (x @==@ num 100)]
        solution <-
          solve (withInitialSeed (RandomSeed 7) defaultSolveConfig) constraints
        assertBool
          ("hard energy should be near zero, got "
             ++ show (solutionEnergy solution))
          (solutionEnergy solution <= 1e-6)
        assertEvalRange "x" 10 20 solution x
    , testCase "within on a direct variable becomes native bounds" $ do
        let x = var "test.inspect.x" :: Expr TestLayout
            inspected =
              inspectConstraints defaultSolveConfig [within x (Range 10 20)]
        inspectedNativeBoundNames inspected @?= ["test.inspect.x"]
        inspectedNativeBoundCount inspected @?= 1
    , testCase "bounded domains supply native bounds" $ do
        let x = var "test.domain.unit" :: Expr TestUnit
            inspected = inspectConstraints defaultSolveConfig [x @==@ num 0.5]
        inspectedNativeBoundNames inspected @?= ["test.domain.unit"]
        inspectedNativeBoundCount inspected @?= 1
    , testCase "bounded cyclic domains supply native bounds" $ do
        let x = var "test.domain.angle" :: Expr TestBoundedAngle
            inspected = inspectConstraints defaultSolveConfig [x @==@ num 180]
        inspectedNativeBoundNames inspected @?= ["test.domain.angle"]
        inspectedNativeBoundCount inspected @?= 1
    , testCase "within on a compound expression remains an energy constraint" $ do
        let x = var "test.inspect.x" :: Expr TestLayout
            y = var "test.inspect.y" :: Expr TestLayout
            inspected =
              inspectConstraints
                defaultSolveConfig
                [within (x @+@ y) (Range 10 20)]
        inspectedNativeBoundCount inspected @?= 0
        inspectedEnergyTermCount inspected @?= 2
    , testCase "within on a scaled variable becomes native bounds" $ do
        let x = var "test.scaled.x" :: Expr TestLayout
            inspected =
              inspectConstraints
                defaultSolveConfig
                [within (x @*@ num 2) (Range 10 20)]
        inspectedNativeBoundNames inspected @?= ["test.scaled.x"]
        inspectedNativeBoundCount inspected @?= 1
        inspectedEnergyTermCount inspected @?= 0
        solution <-
          solve
            (withInitialSeed (RandomSeed 5) defaultSolveConfig)
            [within (x @*@ num 2) (Range 10 20), soften (x @==@ num 100)]
        assertEvalRange "x" 5 10 solution x
    , testCase "linear inequalities implied by bounds are eliminated" $ do
        let x = var "test.implied.x" :: Expr TestLayout
            y = var "test.implied.y" :: Expr TestLayout
            inspected =
              inspectConstraints
                defaultSolveConfig
                [ within x (Range 0 10)
                , within y (Range 0 10)
                , (num 0 :: Expr TestLayout) @<=@ x @+@ y
                ]
        inspectedNativeBoundCount inspected @?= 2
        inspectedEnergyTermCount inspected @?= 0
    , testCase "linear inequalities not implied by bounds remain in energy" $ do
        let x = var "test.coupled.x" :: Expr TestLayout
            y = var "test.coupled.y" :: Expr TestLayout
            inspected =
              inspectConstraints
                defaultSolveConfig
                [ within x (Range 0 10)
                , within y (Range 0 10)
                , x @+@ y @<=@ num 10
                ]
        inspectedNativeBoundCount inspected @?= 2
        inspectedEnergyTermCount inspected @?= 1
    , testCase "overlapping repeated ranges merge into native bounds" $ do
        let x = var "test.range.x" :: Expr TestLayout
            inspected =
              inspectConstraints
                defaultSolveConfig
                [within x (Range 0 20), within x (Range 15 30)]
        inspectedNativeBoundNames inspected @?= ["test.range.x"]
        inspectedNativeBoundCount inspected @?= 1
        inspectedEnergyTermCount inspected @?= 0
        solution <-
          solve
            (withInitialSeed (RandomSeed 3) defaultSolveConfig)
            [within x (Range 0 20), within x (Range 15 30)]
        assertEvalRange "x" 15 20 solution x
    , testCase "conflicting ranges fail during native bound preparation" $ do
        let x = var "test.range.conflict" :: Expr TestLayout
        assertErrorContains
          "conflicting range"
          "inconsistent native bounds"
          (evaluate
             (inspectedVariableCount
                (compiledInspection
                   (compileProblem
                      defaultSolveConfig
                      (solverProblem
                         [within x (Range 0 10), within x (Range 20 30)])))))
    ]

componentTests :: TestTree
componentTests =
  testGroup
    "components"
    [ testCase "relates equal components" $ do
        let x = var "term.equal.x" :: Expr TestLayout
            y = var "term.equal.y" :: Expr TestLayout
        relateComponents ComponentEqual [exprComponent x] [exprComponent y]
          @?= [x @==@ y]
    , testCase "relates ordered components with side constraints" $ do
        let x = var "term.ordered.x" :: Expr TestLayout
            y = var "term.ordered.y" :: Expr TestLayout
            side = within x (Range 1 10)
        relateComponents
          ComponentLessOrEqual
          [component x [side]]
          [exprComponent y]
          @?= [side, x @<=@ y]
    , testCase "relates directed bridge components" $ do
        let lhs = var "term.bridge.lhs" :: Expr TestLayout
            gap = var "term.bridge.gap" :: Expr TestLayout
            rhs = var "term.bridge.rhs" :: Expr TestLayout
        directedBridgeComponents
          [exprComponent lhs]
          [exprComponent gap]
          [exprComponent rhs]
          @?= [lhs @+@ gap @==@ rhs]
    , testCase "relates symmetric bridge components" $ do
        let lhs = var "term.symmetric.lhs" :: Expr TestLayout
            delta = var "term.symmetric.delta" :: Expr TestLayout
            rhs = var "term.symmetric.rhs" :: Expr TestLayout
        symmetricBridgeComponents
          [exprComponent lhs]
          [exprComponent delta]
          [exprComponent rhs]
          @?= [absExpr (lhs @-@ rhs) @==@ delta]
    , testCase "rejects mismatched component counts" $ do
        let x = var "term.count.x" :: Expr TestLayout
            y = var "term.count.y" :: Expr TestLayout
        assertErrorContains
          "different component counts"
          "different component counts"
          (evaluate
             (length
                (show
                   (relateComponents
                      ComponentEqual
                      [exprComponent x]
                      [exprComponent y, exprComponent y]))))
    , testCase "rejects mismatched component types" $ do
        let x = var "term.type.x" :: Expr TestLayout
            hueValue = var "term.type.hue" :: Expr TestAngle
        assertErrorContains
          "different scalar types"
          "test-length and test-angle"
          (evaluate
             (length
                (show
                   (relateComponents
                      ComponentEqual
                      [exprComponent x]
                      [exprComponent hueValue]))))
    ]

cyclicDomainTests :: TestTree
cyclicDomainTests =
  testGroup
    "cyclic domains"
    [ testCase "cyclic equality normalizes solved values" $ do
        let hueValue = var "test.cyclic.hue" :: Expr TestAngle
            constraints =
              [ within hueValue (Range 0 360)
              , hueValue @==@ (num 370 :: Expr TestAngle)
              ]
            config =
              withInitialOverrides
                (Map.singleton "test.cyclic.hue" 10)
                (withInitialSeed (RandomSeed 11) defaultSolveConfig)
        constraintCount [num 10 @==@ (num 370 :: Expr TestAngle)] @?= 0
        solution <- solve config constraints
        assertBool
          ("hard energy should be near zero, got "
             ++ show (solutionEnergy solution))
          (solutionEnergy solution <= 1e-6)
        assertEvalNear "hue" 10 solution hueValue
    ]

categoricalTests :: TestTree
categoricalTests =
  testGroup
    "categorical choices"
    [ testCase "solves direct category choices" $ do
        let probe = choice "test.choice.probe" :: Choice TestProbe
            problem =
              solverProblemWithChoices [] [choose probe (category "match")]
        solution <- solveProblem defaultSolveConfig problem
        evalChoice solution probe @?= Just (category "match")
    , testCase "solves same-choice relations" $ do
        let lhs = choice "test.choice.lhs" :: Choice TestProbe
            rhs = choice "test.choice.rhs" :: Choice TestProbe
            problem =
              solverProblemWithChoices
                []
                [sameChoice lhs rhs, choose lhs (category "no-match")]
        solution <- solveProblem defaultSolveConfig problem
        evalChoice solution lhs @?= Just (category "no-match")
        evalChoice solution rhs @?= Just (category "no-match")
    , testCase "solves free category choices" $ do
        let probe = choice "test.choice.free" :: Choice TestProbe
            problem = solverProblemWithChoices [] [freeChoice probe]
            inspected =
              compiledInspection (compileProblem defaultSolveConfig problem)
        inspectedChoiceCount inspected @?= 1
        inspectedChoiceBranchCount inspected @?= 2
        solution <- solveProblem defaultSolveConfig problem
        assertBool
          "expected a sampled category from the probe domain"
          (evalChoice solution probe
             `elem` [Just (category "match"), Just (category "no-match")])
    , testCase "enforces categorical branch limit" $ do
        let lhs = choice "test.choice.limit.lhs" :: Choice TestProbe
            rhs = choice "test.choice.limit.rhs" :: Choice TestProbe
            problem = solverProblemWithChoices [] [differentChoice lhs rhs]
            config = withMaxCategoricalBranches 1 defaultSolveConfig
        assertErrorContains
          "branch limit"
          "exceeds configured limit"
          (evaluate
             (inspectedChoiceBranchCount
                (compiledInspection (compileProblem config problem))))
    ]

seededFixtureTests :: TestTree
seededFixtureTests =
  testGroup
    "fixture solving"
    [ testCase "fixed fixture is deterministic" $ do
        let seed = RandomSeed 320994595
            fixture = defaultFixture
        first <- solveFixture fixture seed
        second <- solveFixture fixture seed
        Map.keys (solutionValues first) @?= Map.keys (solutionValues second)
        mapM_
          (\(name, lhsValue) ->
             case Map.lookup name (solutionValues second) of
               Nothing -> assertFailure ("missing " ++ name)
               Just rhsValue ->
                 assertBool
                   (name ++ " changed between identical seeded solves")
                   (abs (lhsValue - rhsValue) <= epsilon))
          (Map.toAscList (solutionValues first))
    , testCase "fixed fixture satisfies hard constraints" $ do
        solution <- solveFixture defaultFixture (RandomSeed (-1988735004))
        validateFixtureSolution defaultFixture solution @?= []
    ]

problemInspectionTests :: TestTree
problemInspectionTests =
  testGroup
    "problem inspection"
    [ testCase "fixture exposes native bounds without initial vars" $ do
        let inspected =
              inspectConstraints
                defaultSolveConfig
                (fixtureConstraints defaultFixture)
        inspectedVariableCount inspected @?= 59
        assertBool
          "expected direct fixture bounds to lower to native bounds"
          (inspectedNativeBoundCount inspected >= 59)
    , testCase "compiled problem exposes inspection through public facade" $ do
        let x = var "test.compiled.x" :: Expr TestLayout
            problem = solverProblem [within x (Range 10 20)]
            inspected =
              compiledInspection (compileProblem defaultSolveConfig problem)
        inspectedNativeBoundNames inspected @?= ["test.compiled.x"]
        inspectedNativeBoundCount inspected @?= 1
        inspectedRawCount inspected @?= 2
        inspectedCanonicalCount inspected @?= 2
    , testCase "inspection reports eliminated duplicate equalities" $ do
        let x = var "test.canonical.x" :: Expr TestLayout
            y = var "test.canonical.y" :: Expr TestLayout
            inspected =
              inspectConstraints defaultSolveConfig [x @==@ y, y @==@ x]
        inspectedFlattenedCount inspected @?= 1
        inspectedEliminatedCount inspected @?= 1
    ]

defaultFixture :: SolverFixture
defaultFixture =
  case fixtureByName "bounded-row" of
    Just fixture -> fixture
    Nothing      -> error "missing bounded-row fixture"

assertEvalRange ::
     String -> Double -> Double -> Solution -> Expr ty -> Assertion
assertEvalRange label lower upper solution expr =
  case evalExpr solution expr of
    Nothing -> assertFailure ("missing " ++ label)
    Just value -> do
      assertBool
        (label ++ " below " ++ show lower ++ ": " ++ show value)
        (value >= lower - epsilon)
      assertBool
        (label ++ " above " ++ show upper ++ ": " ++ show value)
        (value <= upper + epsilon)

assertEvalNear :: String -> Double -> Solution -> Expr ty -> Assertion
assertEvalNear label expected solution expr =
  case evalExpr solution expr of
    Nothing -> assertFailure ("missing " ++ label)
    Just value ->
      assertBool
        (label ++ " expected " ++ show expected ++ ", got " ++ show value)
        (abs (value - expected) <= 1e-3)

assertErrorContains :: String -> String -> IO a -> Assertion
assertErrorContains label expected action = do
  result <- try action
  case result of
    Left (err :: ErrorCall) ->
      assertBool
        (label ++ " error did not contain " ++ show expected ++ ": " ++ show err)
        (expected `List.isInfixOf` show err)
    Right _ -> assertFailure (label ++ " did not throw an error")

epsilon :: Double
epsilon = 1e-6
