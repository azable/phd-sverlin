{-# LANGUAGE ScopedTypeVariables #-}

module Main where

import           Control.Exception   (ErrorCall, evaluate, try)
import qualified Data.List           as List
import qualified Data.Map.Strict     as Map
import           Solver
import           Solver.TestFixtures
import           Test.Tasty
import           Test.Tasty.HUnit

main :: IO ()
main =
  defaultMain
    (testGroup
       "solver"
       [ nativeBoundsTests
       , componentTests
       , seededFixtureTests
       , problemInspectionTests
       ])

nativeBoundsTests :: TestTree
nativeBoundsTests =
  testGroup
    "native bounds"
    [ testCase "native bounds constrain soft optima" $ do
        let x = var "test.native.x" :: Expr Layout
            constraints = [within x (Range 10 20), soften (x @==@ num 100)]
        solution <-
          solve defaultSolveConfig {initialSeed = RandomSeed 7} constraints
        assertBool
          ("hard energy should be near zero, got "
             ++ show (solutionEnergy solution))
          (solutionEnergy solution <= 1e-6)
        assertEvalRange "x" 10 20 solution x
    , testCase "within on a direct variable becomes native bounds" $ do
        let x = var "test.inspect.x" :: Expr Layout
            inspected =
              inspectConstraints defaultSolveConfig [within x (Range 10 20)]
        inspectedNativeBoundNames inspected @?= ["test.inspect.x"]
        inspectedNativeBoundCount inspected @?= 1
    , testCase "within on a compound expression remains an energy constraint" $ do
        let x = var "test.inspect.x" :: Expr Layout
            y = var "test.inspect.y" :: Expr Layout
            inspected =
              inspectConstraints
                defaultSolveConfig
                [within (x @+@ y) (Range 10 20)]
        inspectedNativeBoundCount inspected @?= 0
        inspectedEnergyTermCount inspected @?= 2
    ]

componentTests :: TestTree
componentTests =
  testGroup
    "components"
    [ testCase "relates equal components" $ do
        let x = var "term.equal.x" :: Expr Layout
            y = var "term.equal.y" :: Expr Layout
        relateComponents ComponentEqual [exprComponent x] [exprComponent y]
          @?= [x @==@ y]
    , testCase "relates ordered components with side constraints" $ do
        let x = var "term.ordered.x" :: Expr Layout
            y = var "term.ordered.y" :: Expr Layout
            side = within x (Range 1 10)
        relateComponents
          ComponentLessOrEqual
          [component x [side]]
          [exprComponent y]
          @?= [side, x @<=@ y]
    , testCase "relates directed bridge components" $ do
        let lhs = var "term.bridge.lhs" :: Expr Layout
            gap = var "term.bridge.gap" :: Expr Layout
            rhs = var "term.bridge.rhs" :: Expr Layout
        directedBridgeComponents
          [exprComponent lhs]
          [exprComponent gap]
          [exprComponent rhs]
          @?= [lhs @+@ gap @==@ rhs]
    , testCase "relates symmetric bridge components" $ do
        let lhs = var "term.symmetric.lhs" :: Expr Layout
            delta = var "term.symmetric.delta" :: Expr Layout
            rhs = var "term.symmetric.rhs" :: Expr Layout
        symmetricBridgeComponents
          [exprComponent lhs]
          [exprComponent delta]
          [exprComponent rhs]
          @?= [absExpr (lhs @-@ rhs) @==@ delta]
    , testCase "rejects mismatched component counts" $ do
        let x = var "term.count.x" :: Expr Layout
            y = var "term.count.y" :: Expr Layout
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
        let x = var "term.type.x" :: Expr Layout
            hueValue = var "term.type.hue" :: Expr Angle
        assertErrorContains
          "different scalar types"
          "length and angle"
          (evaluate
             (length
                (show
                   (relateComponents
                      ComponentEqual
                      [exprComponent x]
                      [exprComponent hueValue]))))
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
        let x = var "test.compiled.x" :: Expr Layout
            problem =
              SolverProblem
                { solverConstraints = [within x (Range 10 20)]
                , solverInitialOverrides = Map.empty
                }
            inspected =
              compiledInspection (compileProblem defaultSolveConfig problem)
        inspectedNativeBoundNames inspected @?= ["test.compiled.x"]
        inspectedNativeBoundCount inspected @?= 1
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
