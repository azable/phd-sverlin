{-# LANGUAGE ScopedTypeVariables #-}

module Main where

import           Control.Exception   (ErrorCall, SomeException, evaluate, try)
import qualified Data.List           as List
import qualified Data.Map.Strict     as Map
import           Data.Maybe          (mapMaybe)
import           Solver
import           Solver.TestFixtures
import           System.Timeout      (timeout)
import           Test.Tasty
import           Test.Tasty.HUnit

data TestLayout

data TestAngle

data TestUnit

data TestSignedUnit

data TestBoundedAngle

data TestProbe
  = TestMatch
  | TestNoMatch
  deriving (Eq, Show)

instance SymbolicType TestLayout where
  symbolicDomain _ = realDomain "test-length"

instance SymbolicType TestAngle where
  symbolicDomain _ = cyclicDomain "test-angle" 360

instance SymbolicType TestUnit where
  symbolicDomain _ = boundedDomain "test-unit" (Range 0 1)

instance SymbolicType TestSignedUnit where
  symbolicDomain _ = boundedDomain "test-signed-unit" (Range (-1) 1)

instance SymbolicType TestBoundedAngle where
  symbolicDomain _ = boundedCyclicDomain "test-bounded-angle" 360 (Range 0 360)

instance ChoiceDomain TestProbe where
  choiceDomain = [TestMatch, TestNoMatch]
  choiceToken value =
    case value of
      TestMatch   -> "match"
      TestNoMatch -> "no-match"

main :: IO ()
main =
  defaultMain
    (testGroup
       "solver"
       [ nativeBoundsTests
       , backendDispatchTests
       , componentTests
       , cyclicDomainTests
       , categoricalTests
       , designSpaceTests
       , seededFixtureTests
       , problemInspectionTests
       ])

nativeBoundsTests :: TestTree
nativeBoundsTests =
  testGroup
    "native bounds"
    [ testCase "native bounds constrain sampled values" $ do
        let x = var "test.native.x" :: Expr TestLayout
            constraints = [within x (Range 10 20)]
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
            inspected = inspectConstraints defaultSolveConfig [x @<=@ num 180]
        inspectedNativeBoundNames inspected @?= ["test.domain.angle"]
        inspectedNativeBoundCount inspected @?= 1
    , testCase
        "affine equalities propagate fixed bounds through derived coordinates" $ do
        let widthValue = var "test.derived.width" :: Expr TestLayout
            centerValue = var "test.derived.center" :: Expr TestLayout
            constraints =
              [ widthValue @==@ num 800
              , centerValue @-@ widthValue @/@ num 2 @==@ num 0
              ]
            inspected = inspectConstraints defaultSolveConfig constraints
        inspectedNativeBoundNames inspected
          @?= ["test.derived.center", "test.derived.width"]
        solution <- solve defaultSolveConfig constraints
        assertEvalNear "derived center" 400 solution centerValue
    , testCase
        "within on a compound expression lowers to two affine inequalities" $ do
        let x = var "test.inspect.x" :: Expr TestUnit
            y = var "test.inspect.y" :: Expr TestUnit
            inspected =
              inspectConstraints
                defaultSolveConfig
                [within (x @+@ y) (Range 0.5 1.5)]
        inspectedNativeBoundCount inspected @?= 2
        inspectedAffineInequalityCount inspected @?= 2
    , testCase "within on a scaled variable becomes native bounds" $ do
        let x = var "test.scaled.x" :: Expr TestLayout
            inspected =
              inspectConstraints
                defaultSolveConfig
                [within (x @*@ num 2) (Range 10 20)]
        inspectedNativeBoundNames inspected @?= ["test.scaled.x"]
        inspectedNativeBoundCount inspected @?= 1
        solution <-
          solve
            (withInitialSeed (RandomSeed 5) defaultSolveConfig)
            [within (x @*@ num 2) (Range 10 20)]
        assertEvalRange "x" 5 10 solution x
    , testCase "linear inequalities remain exact affine rows" $ do
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
        inspectedAffineInequalityCount inspected @?= 5
    , testCase "coupled linear inequalities remain exact affine rows" $ do
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
        inspectedAffineInequalityCount inspected @?= 5
    , testCase "overlapping repeated ranges merge into native bounds" $ do
        let x = var "test.range.x" :: Expr TestLayout
            inspected =
              inspectConstraints
                defaultSolveConfig
                [within x (Range 0 20), within x (Range 15 30)]
        inspectedNativeBoundNames inspected @?= ["test.range.x"]
        inspectedNativeBoundCount inspected @?= 1
        solution <-
          solve
            (withInitialSeed (RandomSeed 3) defaultSolveConfig)
            [within x (Range 0 20), within x (Range 15 30)]
        assertEvalRange "x" 15 20 solution x
    , testCase "conflicting ranges fail during native bound preparation" $ do
        let x = var "test.range.conflict" :: Expr TestLayout
        assertErrorContains
          "conflicting range"
          "inconsistent bounds for solver variable"
          (evaluate
             (inspectedVariableCount
                (compiledInspection
                   (compileProblem
                      defaultSolveConfig
                      (solverProblem
                         [within x (Range 0 10), within x (Range 20 30)])))))
    , testCase
        "rounding-sized crossed bounds do not reject an exact affine value" $ do
        let x = var "test.range.rounding" :: Expr TestLayout
            constraints = [x @==@ num 640, x @<=@ num (640 - 2e-13)]
        solution <- solve defaultSolveConfig constraints
        assertEvalNear "rounding-sized bound" 640 solution x
    , testCase "default tolerance repairs crossed native bounds" $ do
        let x = var "test.range.native-rounding" :: Expr TestLayout
            constraints = [x @>=@ num 400, x @<=@ num 399.99999999999994]
        solution <- solve defaultSolveConfig constraints
        assertEvalNear "normalized native bound" 400 solution x
    , testCase "bound tolerance is configurable" $ do
        let x = var "test.range.configured-rounding" :: Expr TestLayout
            constraints = [x @>=@ num 400, x @<=@ num 399.99999999999994]
            strictConfigs =
              [ withBoundTolerance 0 defaultSolveConfig
              , withBoundTolerance 1e-15 defaultSolveConfig
              ]
        mapM_
          (\strictConfig ->
             assertErrorContains
               "configured bound tolerance"
               "inconsistent bounds for solver variable"
               (evaluate
                  (inspectedVariableCount
                     (inspectConstraints strictConfig constraints))))
          strictConfigs
    , testCase "crossed native bounds above tolerance remain invalid" $ do
        let x = var "test.range.material-conflict" :: Expr TestLayout
            constraints = [x @>=@ num (400 + 1e-6), x @<=@ num 400]
        assertErrorContains
          "materially crossed bounds"
          "inconsistent bounds for solver variable"
          (evaluate
             (inspectedVariableCount
                (inspectConstraints defaultSolveConfig constraints)))
    , testCase "bound tolerance must be finite and non-negative" $ do
        mapM_
          (\invalid ->
             assertErrorContains
               "invalid bound tolerance"
               "solver bound tolerance must be finite and non-negative"
               (evaluate (withBoundTolerance invalid defaultSolveConfig)))
          [-1, 0 / 0, 1 / 0]
    , testCase "disjunction bounds enclose every alternative" $ do
        let x = var "test.range.alternatives" :: Expr TestLayout
            problem =
              solverProblem
                [ oneOf
                    "test.range.alternatives.authored"
                    (alternative "first" [])
                    [alternative "second" []]
                , algebraicOneOf
                    "test.range.alternatives.cell"
                    (alternative
                       "low"
                       [ oneOf
                           "test.range.alternatives.guard"
                           (alternative
                              "omit"
                              [(num 0 :: Expr TestLayout) @==@ num 1])
                           [alternative "include" [x @==@ num 2]]
                       ])
                    [alternative "high" [x @==@ num 7]]
                ]
            config = withMaxCategoricalBranches 2 defaultSolveConfig
        design <- assertDesignCompiled (compileDesignSpace config problem)
        sampled <-
          sampleDesignSpaceBatch
            BalancedDesignChoices
            (map RandomSeed [1 .. 32])
            design
        solutions <- assertDesignSampled sampled
        let values = map (`evalExpr` x) solutions
        assertBool "expected the low disjunct" (Just 2 `elem` values)
        assertBool "expected the high disjunct" (Just 7 `elem` values)
    , testCase "nested disjunction bounds enclose every nested alternative" $ do
        let x = var "test.range.nested-alternatives" :: Expr TestLayout
            problem =
              solverProblem
                [ algebraicOneOf
                    "test.range.nested-alternatives.outer"
                    (alternative
                       "nested"
                       [ algebraicOneOf
                           "test.range.nested-alternatives.inner"
                           (alternative "low" [x @==@ num 1])
                           [alternative "middle" [x @==@ num 4]]
                       ])
                    [alternative "high" [x @==@ num 9]]
                ]
            config = defaultSolveConfig
        design <- assertDesignCompiled (compileDesignSpace config problem)
        sampled <-
          sampleDesignSpaceBatch
            BalancedDesignChoices
            (map RandomSeed [1 .. 48])
            design
        solutions <- assertDesignSampled sampled
        let values = map (`evalExpr` x) solutions
        assertBool "expected the nested low disjunct" (Just 1 `elem` values)
        assertBool "expected the nested middle disjunct" (Just 4 `elem` values)
        assertBool "expected the outer high disjunct" (Just 9 `elem` values)
    , testCase
        "disjunction retains only bound sides proved by every alternative" $ do
        let x = var "test.range.one-sided-alternatives" :: Expr TestLayout
            problem =
              solverProblem
                [ oneOf
                    "test.range.one-sided-alternatives.authored"
                    (alternative "first" [])
                    [alternative "second" []]
                , x @<=@ num 4
                , algebraicOneOf
                    "test.range.one-sided-alternatives.cell"
                    (alternative "bounded" [within x (Range 1 2)])
                    [alternative "lower-only" [num 3 @<=@ x]]
                ]
            config = defaultSolveConfig
        design <- assertDesignCompiled (compileDesignSpace config problem)
        sampled <-
          sampleDesignSpaceBatch
            BalancedDesignChoices
            (map RandomSeed [1 .. 32])
            design
        solutions <- assertDesignSampled sampled
        let values =
              [ value
              | solution <- solutions
              , Just value <- [evalExpr solution x]
              ]
        assertBool "expected the lower disjunct" (any (<= 2 + epsilon) values)
        assertBool
          "expected the lower-only disjunct"
          (any (>= 3 - epsilon) values)
    , testCase "parallel guards infer bounds from their token-wise conjunction" $ do
        let x = var "test.range.parallel-guards" :: Expr TestLayout
            decision = "test.range.parallel-guards.presence"
            problem =
              solverProblem
                [ oneOf
                    decision
                    (alternative "omit" [x @==@ num 0])
                    [alternative "include" []]
                , oneOf
                    decision
                    (alternative "omit" [])
                    [alternative "include" [x @==@ num 1]]
                ]
            config = withMaxCategoricalBranches 1 defaultSolveConfig
        design <- assertDesignCompiled (compileDesignSpace config problem)
        sampled <-
          sampleDesignSpaceBatch
            BalancedDesignChoices
            (map RandomSeed [1 .. 24])
            design
        solutions <- assertDesignSampled sampled
        let values = map (`evalExpr` x) solutions
        assertBool "expected the omitted value" (Just 0 `elem` values)
        assertBool "expected the included value" (Just 1 `elem` values)
    ]

backendDispatchTests :: TestTree
backendDispatchTests =
  testGroup
    "affine solver boundary"
    [ testCase "bounded affine constraints use hit-and-run" $ do
        let x = var "test.sample.x" :: Expr TestUnit
            y = var "test.sample.y" :: Expr TestUnit
            constraints = [x @+@ y @==@ num 1]
        solution <-
          solve (withInitialSeed (RandomSeed 27) defaultSolveConfig) constraints
        solutionBackend solution @?= AffineSampler
        assertEvalNear "affine sum" 1 solution (x @+@ y)
        case solutionBackendStatistics solution of
          AffineSamplingStatistics statistics -> do
            samplingAmbientDimension statistics @?= 2
            samplingReducedDimension statistics @?= 1
            samplingEqualityCount statistics @?= 1
            samplingBurnInSteps statistics @?= 32
    , testCase "opposing inequalities preserve movement along an equality face" $ do
        let x = var "test.sample.implicit-face.x" :: Expr TestUnit
            y = var "test.sample.implicit-face.y" :: Expr TestUnit
            free = var "test.sample.implicit-face.free" :: Expr TestUnit
            total = x @+@ y
            constraints = [total @<=@ num 1, num 1 @<=@ total, free @<=@ num 1]
        solutions <-
          traverse
            (\seed ->
               solve
                 (withInitialSeed (RandomSeed seed) defaultSolveConfig)
                 constraints)
            [1 .. 24]
        mapM_
          (\solution -> assertEvalNear "implicit face" 1 solution total)
          solutions
        let freeValues = mapMaybe (`evalExpr` free) solutions
        length freeValues @?= length solutions
        assertBool
          "expected the unrelated variable to vary across seeds"
          (maximum freeValues - minimum freeValues > 0.25)
        case solutions of
          firstSolution:_ ->
            case solutionBackendStatistics firstSolution of
              AffineSamplingStatistics statistics ->
                samplingReducedDimension statistics @?= 2
          [] -> assertFailure "expected seeded affine solutions"
    , testCase "repeats opposing inequality reduction on exposed faces" $ do
        let x = var "test.sample.iterated-face.x" :: Expr TestSignedUnit
            y = var "test.sample.iterated-face.y" :: Expr TestSignedUnit
            z = var "test.sample.iterated-face.z" :: Expr TestSignedUnit
            firstFace = x @+@ y
            secondFace = x @+@ z
            constraints =
              [ firstFace @<=@ num 0
              , num 0 @<=@ num 2 @*@ firstFace
              , secondFace @<=@ num 0
              , num 2 @*@ (y @-@ z) @<=@ num 0
              ]
        solution <-
          solve (withInitialSeed (RandomSeed 37) defaultSolveConfig) constraints
        assertEvalNear "first exposed face" 0 solution firstFace
        assertEvalNear "second exposed face" 0 solution secondFace
        case solutionBackendStatistics solution of
          AffineSamplingStatistics statistics -> do
            samplingAmbientDimension statistics @?= 3
            samplingReducedDimension statistics @?= 1
    , testCase "does not collapse an opposing band above tolerance" $ do
        let x = var "test.sample.nonzero-band.x" :: Expr TestUnit
            y = var "test.sample.nonzero-band.y" :: Expr TestUnit
            total = x @+@ y
            upper = 1 + 1e-6
            constraints = [total @<=@ num upper, num 1 @<=@ total]
        solution <-
          solve (withInitialSeed (RandomSeed 31) defaultSolveConfig) constraints
        assertEvalRange "nonzero band" 1 upper solution total
        case solutionBackendStatistics solution of
          AffineSamplingStatistics statistics ->
            samplingReducedDimension statistics @?= 2
    , testCase "phase I enters a narrow affine corner before hit-and-run" $ do
        let x = var "test.phase-i-corner.x" :: Expr TestSignedUnit
            y = var "test.phase-i-corner.y" :: Expr TestSignedUnit
            boundary = 7.5e-9
            constraints = [num boundary @<=@ y @+@ x, num boundary @<=@ y @-@ x]
        solution <-
          solve
            (withInitialSeed (RandomSeed 1466279144) defaultSolveConfig)
            constraints
        solutionBackend solution @?= AffineSampler
        assertBool
          "expected a feasible affine sample"
          (solutionSuccess solution)
        assertEvalRange "positive corner face" boundary 2 solution (y @+@ x)
        assertEvalRange "negative corner face" boundary 2 solution (y @-@ x)
    , testCase "nonlinear hard constraints are rejected" $ do
        let x = var "test.reject.nonlinear" :: Expr TestUnit
        assertErrorContains
          "nonlinear constraint"
          "non-affine equality is unsupported"
          (evaluate
             (inspectedVariableCount
                (inspectConstraints defaultSolveConfig [x @*@ x @==@ num 0.25])))
    , testCase "unbounded affine spaces are rejected" $ do
        let x = var "test.reject.unbounded" :: Expr TestLayout
        assertErrorContains
          "unbounded affine space"
          "finite lower and upper bounds"
          (evaluate
             (inspectedVariableCount
                (inspectConstraints defaultSolveConfig [x @<=@ num 1])))
    , testCase "an infeasible affine hard region fails instead of compromising" $ do
        let x = var "test.sample.infeasible" :: Expr TestUnit
        result <-
          try (solve defaultSolveConfig [x @<=@ num (-1)]) :: IO
            (Either SomeException Solution)
        case result of
          Left err ->
            assertBool
              ("unexpected feasibility error: " ++ show err)
              ("feasible" `List.isInfixOf` show err)
          Right solution ->
            assertFailure
              ("expected infeasible constraints to fail, got " ++ show solution)
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
    , testCase
        "canonicalizes bounded cyclic visual components for affine solving" $ do
        let hueValue = var "term.equal.bounded-hue" :: Expr TestBoundedAngle
            constraints =
              relateComponents
                ComponentEqual
                [exprComponent hueValue]
                [exprComponent (num 360 :: Expr TestBoundedAngle)]
        solution <- solve defaultSolveConfig constraints
        solutionBackend solution @?= AffineSampler
        assertEvalNear "canonical hue" 0 solution hueValue
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
    [ testCase "cyclic equality is rejected without a nonlinear backend" $ do
        let hueValue = var "test.cyclic.hue" :: Expr TestAngle
            constraints =
              [ within hueValue (Range 0 360)
              , hueValue @==@ (num 370 :: Expr TestAngle)
              ]
        constraintCount [num 10 @==@ (num 370 :: Expr TestAngle)] @?= 0
        assertErrorContains
          "cyclic equality"
          "cyclic equality is not affine"
          (evaluate
             (inspectedVariableCount
                (inspectConstraints defaultSolveConfig constraints)))
    ]

categoricalTests :: TestTree
categoricalTests =
  testGroup
    "categorical choices"
    [ testCase "solves direct category choices" $ do
        let probe = choice "test.choice.probe" :: Choice TestProbe
            problem = solverProblemWithChoices [] [choose probe TestMatch]
        solution <- solveProblem defaultSolveConfig problem
        evalChoice solution probe @?= Just TestMatch
    , testCase "solves same-choice relations" $ do
        let lhs = choice "test.choice.lhs" :: Choice TestProbe
            rhs = choice "test.choice.rhs" :: Choice TestProbe
            problem =
              solverProblemWithChoices
                []
                [sameChoice lhs rhs, choose lhs TestNoMatch]
        solution <- solveProblem defaultSolveConfig problem
        evalChoice solution lhs @?= Just TestNoMatch
        evalChoice solution rhs @?= Just TestNoMatch
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
          (evalChoice solution probe `elem` [Just TestMatch, Just TestNoMatch])
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
    , testCase "independent choices do not form a global Cartesian product" $ do
        let probes =
              [ choice ("test.choice.independent." ++ show index) :: Choice
                TestProbe
              | index <- [1 .. 12 :: Int]
              ]
            problem = solverProblemWithChoices [] (map freeChoice probes)
            config = withMaxCategoricalBranches 2 defaultSolveConfig
            inspected = compiledInspection (compileProblem config problem)
        inspectedChoiceCount inspected @?= 12
        inspectedChoiceComponentCount inspected @?= 12
        inspectedChoiceBranchCount inspected @?= 24
        inspectedLargestChoiceComponentBranches inspected @?= 2
        solution <- solveProblem config problem
        assertBool
          "expected every independent choice to be sampled"
          (all ((/= Nothing) . evalChoice solution) probes)
    ]

designSpaceTests :: TestTree
designSpaceTests =
  testGroup
    "finite affine design spaces"
    [ testCase "rejects nonlinear branches during design-space compilation" $ do
        let x = var "test.design.reject-nonlinear" :: Expr TestUnit
            problem =
              solverProblem
                [ oneOf
                    "test.design.reject-nonlinear.branch"
                    (alternative "linear" [x @<=@ num 0.5])
                    [alternative "nonlinear" [x @*@ x @<=@ num 0.5]]
                ]
        case compileDesignSpace defaultSolveConfig problem of
          Left (UnsupportedDesignSpace message) ->
            assertBool
              ("unexpected nonlinear diagnostic: " ++ message)
              ("non-affine inequality" `List.isInfixOf` message)
          Left err ->
            assertFailure
              ("expected unsupported design space, received " ++ show err)
          Right _ ->
            assertFailure "expected nonlinear design-space compilation to fail"
    , testCase "balances feasible named alternatives" $ do
        let x = var "test.design.balanced" :: Expr TestUnit
            problem =
              solverProblem
                [ oneOf
                    "test.design.region"
                    (alternative "low" [x @<=@ num 0.2])
                    [alternative "high" [x @>=@ num 0.8]]
                ]
            compiled = compileDesignSpace defaultSolveConfig problem
        design <- assertDesignCompiled compiled
        sampled <-
          sampleDesignSpaceBatch
            BalancedDesignChoices
            (map RandomSeed [1 .. 40])
            design
        solutions <- assertDesignSampled sampled
        let selected =
              map (Map.lookup "test.design.region" . solutionChoices) solutions
        assertBool "expected low alternatives" (Just "low" `elem` selected)
        assertBool "expected high alternatives" (Just "high" `elem` selected)
        mapM_
          (\solution ->
             case ( Map.lookup "test.design.region" (solutionChoices solution)
                  , evalExpr solution x) of
               (Just "low", Just value) ->
                 assertBool
                   "low branch escaped its region"
                   (value <= 0.2 + epsilon)
               (Just "high", Just value) ->
                 assertBool
                   "high branch escaped its region"
                   (value >= 0.8 - epsilon)
               other -> assertFailure ("invalid design sample: " ++ show other))
          solutions
    , testCase "weights nested authored choices in their local scope" $ do
        let x = var "test.design.local-weight" :: Expr TestUnit
            outerName = "test.design.local-weight.outer"
            innerName = "test.design.local-weight.inner"
            problem =
              solverProblem
                [ oneOf
                    outerName
                    (alternative
                       "nested"
                       [ oneOf
                           innerName
                           (alternative "low" [x @<=@ num 0.25])
                           [alternative "high" [x @>=@ num 0.75]]
                       ])
                    [alternative "single" [x @==@ num 0.5]]
                ]
        design <-
          assertDesignCompiled (compileDesignSpace defaultSolveConfig problem)
        sampled <-
          sampleDesignSpaceBatch
            BalancedDesignChoices
            (map RandomSeed [1 .. 256])
            design
        solutions <- assertDesignSampled sampled
        let nestedCount =
              length
                [ ()
                | solution <- solutions
                , Map.lookup outerName (solutionChoices solution)
                    == Just "nested"
                ]
        assertBool
          ("expected the outer choice to remain near 50/50, selected nested "
             ++ show nestedCount
             ++ " of 256")
          (nestedCount >= 96 && nestedCount <= 160)
    , testCase "weights algebraic cells by their feasible size" $ do
        let x = var "test.design.algebraic-weight" :: Expr TestUnit
            splitName = "test.design.algebraic-weight.cell"
            problem =
              solverProblem
                [ algebraicOneOf
                    splitName
                    (alternative "narrow" [x @<=@ num 0.2])
                    [alternative "wide" [x @>=@ num 0.2]]
                ]
        design <-
          assertDesignCompiled (compileDesignSpace defaultSolveConfig problem)
        sampled <-
          sampleDesignSpaceBatch
            BalancedDesignChoices
            (map (RandomSeed . (* 104729)) [1 .. 80])
            design
        solutions <- assertDesignSampled sampled
        let wideCount =
              length
                [ ()
                | solution <- solutions
                , maybe False (>= 0.2 - epsilon) (evalExpr solution x)
                ]
        assertBool
          ("expected algebraic volume to favor the wide cell, selected "
             ++ show wideCount
             ++ " of 80")
          (wideCount >= 48)
        mapM_
          (\solution ->
             Map.lookup splitName (solutionChoices solution) @?= Nothing)
          solutions
    , testCase "oversized algebraic completion is seeded and deterministic" $ do
        let x = var "test.design.algebraic-overflow" :: Expr TestUnit
            problem =
              solverProblem
                [ algebraicOneOf
                    "test.design.algebraic-overflow.cell"
                    (alternative "low" [x @<=@ num 0.4])
                    [alternative "high" [x @>=@ num 0.6]]
                ]
            config = withMaxCategoricalBranches 1 defaultSolveConfig
        design <- assertDesignCompiled (compileDesignSpace config problem)
        repeatedA <-
          sampleDesignSpace BalancedDesignChoices (RandomSeed 17) design
        repeatedB <-
          sampleDesignSpace BalancedDesignChoices (RandomSeed 17) design
        first <- assertSingleDesignSample repeatedA
        second <- assertSingleDesignSample repeatedB
        solutionValues first @?= solutionValues second
        sampled <-
          sampleDesignSpaceBatch
            BalancedDesignChoices
            (map RandomSeed [1 .. 24])
            design
        solutions <- assertDesignSampled sampled
        let values =
              [ value
              | solution <- solutions
              , Just value <- [evalExpr solution x]
              ]
        assertBool
          "expected the low seeded algebraic completion"
          (any (<= 0.4 + epsilon) values)
        assertBool
          "expected the high seeded algebraic completion"
          (any (>= 0.6 - epsilon) values)
        mapM_
          (\solution ->
             Map.lookup
               "test.design.algebraic-overflow.cell"
               (solutionChoices solution)
               @?= Nothing)
          solutions
    , testCase "MIP conditioning tolerates rounding-sized crossed bounds" $ do
        let x = var "test.design.mip-rounding" :: Expr TestLayout
            problem =
              solverProblem
                [ x @>=@ num (490.4 + 5e-14)
                , x @<=@ num 490.4
                , oneOf
                    "test.design.mip-rounding.branch"
                    (alternative "first" [])
                    [alternative "second" []]
                ]
            config = withMaxCategoricalBranches 1 defaultSolveConfig
        design <- assertDesignCompiled (compileDesignSpace config problem)
        sampled <- sampleDesignSpace BalancedDesignChoices (RandomSeed 5) design
        solution <- assertSingleDesignSample sampled
        assertEvalNear "MIP rounding-sized bound" 490.4 solution x
    , testCase "conditioned MIP corners still produce varied samples" $ do
        let names =
              [ "test.design.mip-hint." ++ show index
              | index <- [0 :: Int .. 15]
              ]
            variables = [var name :: Expr TestUnit | name <- names]
            problem =
              solverProblem
                (oneOf
                   "test.design.mip-hint.branch"
                   (alternative "first" [])
                   [alternative "second" []]
                   : [value @>=@ num 0 | value <- variables])
            config =
              withInitialOverrides
                (Map.fromList [(name, 0.5) | name <- names])
                (withMaxCategoricalBranches 1 defaultSolveConfig)
        design <- assertDesignCompiled (compileDesignSpace config problem)
        sampled <- sampleDesignSpace BalancedDesignChoices (RandomSeed 7) design
        solution <- assertSingleDesignSample sampled
        let values = mapMaybe (evalExpr solution) variables
        length values @?= length variables
        assertBool
          "hit-and-run should move away from the feasible MIP corner"
          (maximum values > 0.1)
    , testCase "materializes and varies choices beyond the balanced prefix" $ do
        let decisionNames =
              ["test.design.deferred." ++ show index | index <- [0 :: Int .. 9]]
            decision name =
              oneOf name (alternative "first" []) [alternative "second" []]
            problem = solverProblem (map decision decisionNames)
            config = withMaxCategoricalBranches 1 defaultSolveConfig
            seed = RandomSeed 29
        design <- assertDesignCompiled (compileDesignSpace config problem)
        repeatedA <-
          assertSingleDesignSample
            =<< sampleDesignSpace BalancedDesignChoices seed design
        repeatedB <-
          assertSingleDesignSample
            =<< sampleDesignSpace BalancedDesignChoices seed design
        solutionChoices repeatedA @?= solutionChoices repeatedB
        sampled <-
          sampleDesignSpaceBatch
            BalancedDesignChoices
            (map RandomSeed [1 .. 12])
            design
        solutions <- assertDesignSampled sampled
        mapM_
          (\solution ->
             mapM_
               (\name ->
                  assertBool
                    ("missing visible deferred choice " ++ show name)
                    (Map.member name (solutionChoices solution)))
               decisionNames)
          solutions
        let selected name = map (Map.lookup name . solutionChoices) solutions
            prefixValues = selected "test.design.deferred.0"
            deferredValues = selected "test.design.deferred.9"
        assertBool
          "expected both values from the locally balanced prefix"
          (Just "first" `elem` prefixValues && Just "second" `elem` prefixValues)
        assertBool
          "expected seeded variation after the locally balanced prefix"
          (Just "first" `elem` deferredValues
             && Just "second" `elem` deferredValues)
    , testCase "uses a feasible completion for oversized Hug-shaped partitions" $ do
        let edges = [0 :: Int .. 5]
            parent index =
              var ("test.design.hug.parent." ++ show index) :: Expr TestUnit
            leading index =
              var ("test.design.hug.leading." ++ show index) :: Expr TestUnit
            trailing index =
              var ("test.design.hug.trailing." ++ show index) :: Expr TestUnit
            edgeConstraints index =
              [ leading index @==@ num 0.25
              , trailing index @==@ num 0.75
              , parent index @<=@ leading index
              , parent index @<=@ trailing index
              , algebraicOneOf
                  ("test.design.hug.edge." ++ show index)
                  (alternative "leading" [parent index @==@ leading index])
                  [alternative "trailing" [parent index @==@ trailing index]]
              ]
            problem = solverProblem (concatMap edgeConstraints edges)
            config = withMaxCategoricalBranches 2 defaultSolveConfig
        design <- assertDesignCompiled (compileDesignSpace config problem)
        sampled <-
          sampleDesignSpace BalancedDesignChoices (RandomSeed 19) design
        solution <- assertSingleDesignSample sampled
        mapM_ (\index -> evalExpr solution (parent index) @?= Just 0.25) edges
        mapM_
          (\index ->
             Map.lookup
               ("test.design.hug.edge." ++ show index)
               (solutionChoices solution)
               @?= Nothing)
          edges
    , testCase "rejects conflicting decision provenance" $ do
        let authored =
              oneOf
                "test.design.provenance"
                (alternative "left" [])
                [alternative "right" []]
            algebraic =
              algebraicOneOf
                "test.design.provenance"
                (alternative "left" [])
                [alternative "right" []]
        case compileDesignSpace
               defaultSolveConfig
               (solverProblem [authored, algebraic]) of
          Left (InvalidDecision message) ->
            assertBool
              ("unexpected provenance diagnostic: " ++ message)
              ("both authored and algebraic" `List.isInfixOf` message)
          Left err ->
            assertFailure
              ("expected conflicting provenance, received " ++ show err)
          Right _ ->
            assertFailure
              "expected conflicting provenance, but compilation succeeded"
    , testCase "typed choice cases resolve exhaustively" $ do
        let x = var "test.design.typed" :: Expr TestUnit
            probe = choice "test.design.probe" :: Choice TestProbe
            constraints = [caseOf probe constraintsFor]
            constraintsFor TestMatch   = [x @<=@ num 0.25]
            constraintsFor TestNoMatch = [x @>=@ num 0.75]
        design <-
          assertDesignCompiled
            (compileDesignSpace defaultSolveConfig (solverProblem constraints))
        sampled <- sampleDesignSpace BalancedDesignChoices (RandomSeed 9) design
        solution <- assertSingleDesignSample sampled
        case (evalChoice solution probe, evalExpr solution x) of
          (Just TestMatch, Just value) ->
            assertBool "match case escaped its region" (value <= 0.25 + epsilon)
          (Just TestNoMatch, Just value) ->
            assertBool
              "no-match case escaped its region"
              (value >= 0.75 - epsilon)
          other -> assertFailure ("invalid typed case sample: " ++ show other)
    , testCase "removes infeasible alternatives before balanced sampling" $ do
        let x = var "test.design.feasible" :: Expr TestUnit
            problem =
              solverProblem
                [ oneOf
                    "test.design.feasibility"
                    (alternative "impossible" [x @<=@ num (-1)])
                    [alternative "possible" [x @>=@ num 0.5]]
                ]
        design <-
          assertDesignCompiled (compileDesignSpace defaultSolveConfig problem)
        sampled <-
          sampleDesignSpaceBatch
            BalancedDesignChoices
            (map RandomSeed [1 .. 8])
            design
        solutions <- assertDesignSampled sampled
        mapM_
          (\solution ->
             Map.lookup "test.design.feasibility" (solutionChoices solution)
               @?= Just "possible")
          solutions
    , testCase "geometric sampling favors larger feasible regions" $ do
        let x = var "test.design.volume" :: Expr TestUnit
            problem =
              solverProblem
                [ oneOf
                    "test.design.volume-region"
                    (alternative "narrow" [x @<=@ num 0.2])
                    [alternative "wide" [x @>=@ num 0.2]]
                ]
            budget =
              defaultVolumeBudget
                { volumeSamplesPerPhase = 512
                , volumeTargetRelativeError = 0.25
                , volumeMaximumWalkSteps = 200000
                }
        design <-
          assertDesignCompiled (compileDesignSpace defaultSolveConfig problem)
        sampled <-
          sampleDesignSpaceBatch
            (GeometricVolume budget)
            (map (RandomSeed . (* 104729)) [1 .. 80])
            design
        solutions <- assertDesignSampled sampled
        let selected =
              map
                (Map.lookup "test.design.volume-region" . solutionChoices)
                solutions
            wideCount = length (filter (== Just "wide") selected)
        assertBool
          ("expected geometric weighting to favor the wide branch, selected "
             ++ show wideCount
             ++ " of 80")
          (wideCount >= 48)
    , testCase "conditions oversized decision spaces with HiGHS" $ do
        let x = var "test.design.mip" :: Expr TestSignedUnit
            decisionName = "test.design.mip-region"
            problem =
              solverProblem
                [ oneOf
                    decisionName
                    (alternative "low" [x @<=@ num (-0.6)])
                    [alternative "high" [x @>=@ num 0.6]]
                ]
            config = withMaxCategoricalBranches 1 defaultSolveConfig
            seed = RandomSeed 7
        design <- assertDesignCompiled (compileDesignSpace config problem)
        first <-
          assertSingleDesignSample
            =<< sampleDesignSpace BalancedDesignChoices seed design
        second <-
          assertSingleDesignSample
            =<< sampleDesignSpace BalancedDesignChoices seed design
        solutionChoices first @?= solutionChoices second
        evalExpr first x @?= evalExpr second x
        solutionSampling first
          @?= SampledWith BalancedDesignChoices MipConditionedDecisions
        sampled <-
          sampleDesignSpaceBatch
            BalancedDesignChoices
            (map RandomSeed [1 .. 16])
            design
        solutions <- assertDesignSampled sampled
        let selected = map (Map.lookup decisionName . solutionChoices) solutions
        assertBool "expected low MIP assignments" (Just "low" `elem` selected)
        assertBool "expected high MIP assignments" (Just "high" `elem` selected)
        mapM_
          (\solution -> do
             solutionSampling solution
               @?= SampledWith BalancedDesignChoices MipConditionedDecisions
             case ( Map.lookup decisionName (solutionChoices solution)
                  , evalExpr solution x) of
               (Just "low", Just value) ->
                 assertBool
                   "low MIP branch escaped its region"
                   (value <= -0.6 + epsilon)
               (Just "high", Just value) ->
                 assertBool
                   "high MIP branch escaped its region"
                   (value >= 0.6 - epsilon)
               other ->
                 assertFailure ("invalid MIP design sample: " ++ show other))
          solutions
    , testCase "conditions oversized categorical components with HiGHS" $ do
        let lhs = choice "test.design.mip-choice.lhs" :: Choice TestProbe
            rhs = choice "test.design.mip-choice.rhs" :: Choice TestProbe
            problem = solverProblemWithChoices [] [differentChoice lhs rhs]
            config = withMaxCategoricalBranches 1 defaultSolveConfig
        design <- assertDesignCompiled (compileDesignSpace config problem)
        repeatedA <-
          assertSingleDesignSample
            =<< sampleDesignSpace BalancedDesignChoices (RandomSeed 23) design
        repeatedB <-
          assertSingleDesignSample
            =<< sampleDesignSpace BalancedDesignChoices (RandomSeed 23) design
        (evalChoice repeatedA lhs, evalChoice repeatedA rhs)
          @?= (evalChoice repeatedB lhs, evalChoice repeatedB rhs)
        sampled <-
          sampleDesignSpaceBatch
            BalancedDesignChoices
            (map RandomSeed [1 .. 8])
            design
        solutions <- assertDesignSampled sampled
        let pairs =
              map
                (\solution -> (evalChoice solution lhs, evalChoice solution rhs))
                solutions
        assertBool
          "expected both locally feasible categorical assignments"
          ((Just TestMatch, Just TestNoMatch) `elem` pairs
             && (Just TestNoMatch, Just TestMatch) `elem` pairs)
        mapM_
          (\solution ->
             assertBool
               "expected different categorical values"
               (evalChoice solution lhs /= evalChoice solution rhs))
          solutions
    , testCase "decodes an original zero endpoint from HiGHS" $ do
        let x = var "test.design.mip-zero" :: Expr TestUnit
            probe = choice "test.design.mip-zero-choice" :: Choice TestProbe
            problem = solverProblemWithChoices [x @==@ num 0] [freeChoice probe]
            config = withMaxCategoricalBranches 1 defaultSolveConfig
        design <- assertDesignCompiled (compileDesignSpace config problem)
        solution <-
          assertSingleDesignSample
            =<< sampleDesignSpace BalancedDesignChoices (RandomSeed 29) design
        solutionSampling solution
          @?= SampledWith BalancedDesignChoices MipConditionedDecisions
        evalExpr solution x @?= Just 0
    , testCase "reports impossible guarded MIP branches without retrying" $ do
        let x = var "test.design.mip-infeasible" :: Expr TestUnit
            problem =
              solverProblem
                [ oneOf
                    "test.design.mip-infeasible-region"
                    (alternative "below" [x @<=@ num (-1)])
                    [alternative "above" [x @>=@ num 2]]
                ]
            config = withMaxCategoricalBranches 1 defaultSolveConfig
        design <- assertDesignCompiled (compileDesignSpace config problem)
        completed <-
          timeout
            (5 * 1000 * 1000)
            (sampleDesignSpace BalancedDesignChoices (RandomSeed 1) design)
        case completed of
          Nothing ->
            assertFailure "HiGHS infeasibility sampling did not terminate"
          Just (Left (InfeasibleDesignSpace message)) ->
            assertBool
              ("unexpected HiGHS failure: " ++ message)
              ("feasible affine region" `List.isInfixOf` message)
          Just other ->
            assertFailure
              ("expected a typed infeasible-design result, received "
                 ++ show other)
    ]

assertDesignCompiled ::
     Either DesignSpaceError CompiledDesignSpace -> IO CompiledDesignSpace
assertDesignCompiled result =
  case result of
    Left err       -> assertFailure (show err) >> pure (error (show err))
    Right compiled -> pure compiled

assertDesignSampled :: Either DesignSpaceError [Solution] -> IO [Solution]
assertDesignSampled result =
  case result of
    Left err        -> assertFailure (show err) >> pure []
    Right solutions -> pure solutions

assertSingleDesignSample :: Either DesignSpaceError Solution -> IO Solution
assertSingleDesignSample result =
  case result of
    Left err       -> assertFailure (show err) >> pure (error (show err))
    Right solution -> pure solution

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
    , testCase "app-shaped affine fixture satisfies hard constraints" $ do
        let fixture = namedFixture "app-shaped"
        solution <- solveFixture fixture (RandomSeed 1)
        validateFixtureSolution fixture solution @?= []
    , testCase "shared text-family fixture satisfies every peer fit" $ do
        let fixture = namedFixture "fit-family"
        solution <- solveFixture fixture (RandomSeed 1)
        validateFixtureSolution fixture solution @?= []
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
        let x = var "test.canonical.x" :: Expr TestUnit
            y = var "test.canonical.y" :: Expr TestUnit
            inspected =
              inspectConstraints defaultSolveConfig [x @==@ y, y @==@ x]
        inspectedFlattenedCount inspected @?= 1
        inspectedEliminatedCount inspected @?= 1
    ]

defaultFixture :: SolverFixture
defaultFixture = namedFixture "bounded-row"

namedFixture :: String -> SolverFixture
namedFixture name =
  case fixtureByName name of
    Just fixture -> fixture
    Nothing      -> error ("missing solver fixture: " ++ name)

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
