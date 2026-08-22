{-# LANGUAGE LinearTypes         #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies        #-}

module Main where

import qualified Choreography.TestFixtures         as ChoreographyFixtures
import           Control.Exception                 (ErrorCall, SomeException,
                                                    evaluate, try)
import qualified Data.List                         as List
import qualified Data.Map.Strict                   as Map
import           Data.Maybe                        (isJust)
import           LinearTrace.Choreography          (Applicable2 (..),
                                                    CoreOperator (..),
                                                    LBool (..), LInt (..),
                                                    LOperator (..), OneUse (..),
                                                    Payload, applyLinear2Into)
import qualified LinearTrace.Choreography          as Choreography
import qualified LinearTrace.Core                  as Core
import qualified LinearTrace.Visualization.Compile as Compile
import qualified LinearTrace.Visualization.IR      as IR
import           Prelude.Linear                    (Ur (..))
import qualified Prelude.Linear                    as Linear
import           Solver
import           Solver.TestFixtures
import           System.Timeout                      (timeout)
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

data ApplyValue

type instance Payload ApplyValue = LInt ApplyValue

data ApplyMatch

type instance Payload ApplyMatch = LBool ApplyMatch

data ApplyEqual =
  ApplyEqual

type instance Payload ApplyEqual = LOperator ApplyEqual ApplyEqual

instance CoreOperator ApplyEqual where
  operatorPayloadText ApplyEqual = "=="
  persistOperatorPayload ApplyEqual = Ur ApplyEqual

instance Applicable2 ApplyEqual ApplyValue ApplyValue where
  type Apply2Result ApplyEqual ApplyValue ApplyValue = ApplyMatch
  applyPayload2 (LOperator ApplyEqual) = applyLinear2Into (Linear.==)

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
       , coreQueryTests
       , choreographyBridgeTests
       , viewMaterializationTests
       ])

coreQueryTests :: TestTree
coreQueryTests =
  testGroup
    "core query"
    [ testCase "query facts preserve concrete atom and int tags" $ do
        let query =
              Core.queryAppend
                (Core.queryAtom "item")
                (Core.queryInt "index" (Core.queryIntConst 3))
        Core.queryFacts query
          @?= Core.Facts [Core.factInt "index" 3, Core.factAtom "item"]
    , testCase "query matching binds integer variables"
        $ Core.queryMatches
            (Core.queryInt "index" (Core.queryIntVar "i"))
            (Core.Facts [Core.factInt "index" 3])
            @?= Just [("i", 3)]
    , testCase "query matching rejects conflicting repeated variables"
        $ Core.queryMatches
            (Core.queryAppend
               (Core.queryInt "index" (Core.queryIntVar "i"))
               (Core.queryInt "row" (Core.queryIntVar "i")))
            (Core.Facts [Core.factInt "index" 3, Core.factInt "row" 4])
            @?= Nothing
    , testCase "payload binding pattern captures payload text"
        $ Core.payloadPatternMatches
            (Core.payloadBindingPattern "value" :: Core.PayloadPattern
               ApplyValue)
            (LInt 12 :: LInt ApplyValue)
            @?= Just [Core.MatchBinding "value" "12"]
    ]

choreographyBridgeTests :: TestTree
choreographyBridgeTests =
  testGroup
    "choreography bridge"
    [ testCase "payload selector controls matched blocks"
        $ let (nodeCount, _constraintCount, _stepCount) =
                ChoreographyFixtures.payloadMatchedStats
           in nodeCount @?= 1
    , testCase "grouping matches neutral view tags"
        $ let (nodeCount, _constraintCount, _stepCount) =
                ChoreographyFixtures.groupStats
           in nodeCount @?= 3
    , testCase "apply2 payload operators consume built-in wrappers linearly" $ do
        oneUseBool
          (OneUse
             (applyPayload2
                (LOperator ApplyEqual :: LOperator ApplyEqual ApplyEqual)
                (LInt 2 :: LInt ApplyValue)
                (LInt 2 :: LInt ApplyValue)))
          @?= True
    , testCase "core materialization buffers events until checkpoint"
        $ ChoreographyFixtures.pendingMaterializedStepCount @?= 1
    , testCase "unmaterialized copy collapses through replace"
        $ ChoreographyFixtures.pendingReplaceEventNames
            @?= ["replace", "destroy"]
    , testCase "tail events remain available for graph diagnostics"
        $ ChoreographyFixtures.pendingTailEventNames @?= ["destroy"]
    , testCase "core retains checkpoints without pending events"
        $ let graph = Core.buildGraph (Core.checkpoint "idle")
              labels =
                map (Core.foldTraceStep const) (Core.traceGraphSteps graph)
           in labels @?= ["idle"]
    ]

oneUseBool :: OneUse (LBool tag) %1 -> Bool
oneUseBool (OneUse (LBool value)) = value

viewMaterializationTests :: TestTree
viewMaterializationTests =
  testGroup
    "view materialization"
    [ testCase "selected color access adds a compiled color style" $ do
        solution <-
          Choreography.solveViewGraphWithSeed
            (RandomSeed 11)
            ChoreographyFixtures.selectedColorGraph
        compiled <-
          assertCompileSolved solution ChoreographyFixtures.selectedColorGraph
        case renderElements compiled of
          element:_ -> do
            assertBool
              "expected selected fill access to compile a concrete fill"
              (isJust (IR.visualFill (IR.elementStyle element)))
            assertTraceVariablesExist
              compiled
              (styleBindingVariables "fill" element)
            let style' = IR.elementStyle element
            IR.visualOpacity style' @?= Nothing
            IR.visualZIndex style' @?= Nothing
            IR.visualPadding style' @?= Nothing
            IR.visualFontSize style' @?= Nothing
            IR.visualRadius style' @?= Nothing
            IR.visualStrokeWidth style' @?= Nothing
          [] -> assertFailure "expected at least one compiled render element"
    , testCase "selected scalar access adds and constrains style" $ do
        solution <-
          Choreography.solveViewGraphWithSeed
            (RandomSeed 15)
            ChoreographyFixtures.selectedScalarGraph
        compiled <-
          assertCompileSolved solution ChoreographyFixtures.selectedScalarGraph
        case renderElements compiled of
          element:_ -> do
            let style' = IR.elementStyle element
            IR.visualPadding style' @?= Just 6
            assertTraceVariablesExist
              compiled
              (styleBindingVariables "padding" element)
            IR.visualFontSize style' @?= Nothing
            IR.visualOpacity style' @?= Nothing
          [] -> assertFailure "expected at least one compiled render element"
    , testCase "center helper reads and writes node centers" $ do
        solution <-
          Choreography.solveViewGraphWithSeed
            (RandomSeed 16)
            ChoreographyFixtures.centerGraph
        compiled <-
          assertCompileSolved solution ChoreographyFixtures.centerGraph
        let assertCentered element = do
              let style' = IR.elementStyle element
              assertNear "left" 80 (IR.visualLeft style')
              assertNear "top" 50 (IR.visualTop style')
              assertNear "width" 80 (IR.visualWidth style')
              assertNear "height" 80 (IR.visualHeight style')
            assertNear label expected actual =
              assertBool
                (label
                   ++ " expected "
                   ++ show expected
                   ++ ", got "
                   ++ show actual)
                (abs (actual - expected) <= 0.01)
        case renderElements compiled of
          []       -> assertFailure "expected centered render elements"
          elements -> mapM_ assertCentered elements
    , testCase "categorical style variables lower to concrete tokens" $ do
        solution <-
          Choreography.solveViewGraphWithSeed
            (RandomSeed 13)
            ChoreographyFixtures.categoricalStyleGraph
        compiled <-
          assertCompileSolved
            solution
            ChoreographyFixtures.categoricalStyleGraph
        case renderElements compiled of
          element:_ -> do
            IR.visualFontFamily (IR.elementStyle element) @?= Just "monospace"
            assertTraceVariablesExist
              compiled
              (styleBindingVariables "fontFamily" element)
          [] -> assertFailure "expected at least one compiled render element"
    , testCase "selected categorical access adds and constrains style" $ do
        solution <-
          Choreography.solveViewGraphWithSeed
            (RandomSeed 14)
            ChoreographyFixtures.categoricalRelationGraph
        compiled <-
          assertCompileSolved
            solution
            ChoreographyFixtures.categoricalRelationGraph
        case renderElements compiled of
          element:_ ->
            IR.visualFontFamily (IR.elementStyle element) @?= Just "Inter"
          [] -> assertFailure "expected at least one compiled render element"
    , testCase
        "compileSolved lowers concrete scalar text choice and color fields" $ do
        solution <-
          Choreography.solveViewGraphWithSeed
            (RandomSeed 12)
            ChoreographyFixtures.styledGraph
        compiled <-
          assertCompileSolved solution ChoreographyFixtures.styledGraph
        case renderElements compiled of
          element:_ -> do
            let style' = IR.elementStyle element
            IR.visualPadding style' @?= Just 4
            IR.visualFontFamily style' @?= Just "Inter"
            IR.visualFontWeight style' @?= Just "bold"
            assertBool "expected concrete fill" (isJust (IR.visualFill style'))
          [] -> assertFailure "expected at least one compiled render element"
    , testCase "checkpoints lower one-to-one to named timeline steps" $ do
        solution <-
          Choreography.solveViewGraphWithSeed
            (RandomSeed 21)
            ChoreographyFixtures.styledGraph
        compiled <-
          assertCompileSolved solution ChoreographyFixtures.styledGraph
        map IR.stepLabel (IR.visualizationSteps compiled)
          @?= ["created", "unchanged", "destroyed"]
        map (length . IR.stepInstances) (IR.visualizationSteps compiled)
          @?= [2, 2, 2]
    , testCase "a checkpoint exposes introductions before silent removals" $ do
        solution <-
          Choreography.solveViewGraphWithSeed
            (RandomSeed 22)
            ChoreographyFixtures.transientGraph
        compiled <-
          assertCompileSolved solution ChoreographyFixtures.transientGraph
        map IR.stepLabel (IR.visualizationSteps compiled)
          @?= ["transient", "after transient"]
        map (length . IR.stepInstances) (IR.visualizationSteps compiled)
          @?= [2, 0]
    , testCase "leaf nodes may use more than half the canvas width" $ do
        solution <-
          Choreography.solveViewGraphWithSeed
            (RandomSeed 23)
            ChoreographyFixtures.wideLeafGraph
        compiled <-
          assertCompileSolved solution ChoreographyFixtures.wideLeafGraph
        case renderElements compiled of
          [] -> assertFailure "expected wide render elements"
          elements ->
            mapM_
              (\element ->
                 assertBool
                   "expected the requested 620px width"
                   (abs (IR.visualWidth (IR.elementStyle element) - 620) <= 0.01))
              elements
    , testCase "visual alternatives compile once and vary across seeds" $ do
        solutions <-
          Choreography.solveViewGraphWithSeeds
            (map RandomSeed [1 .. 24])
            ChoreographyFixtures.disjunctiveGraph
        let positions =
              map
                (Map.lookup "test.visual.position" . solutionChoices)
                solutions
        assertBool
          "expected the left visual alternative"
          (Just "left" `elem` positions)
        assertBool
          "expected the right visual alternative"
          (Just "right" `elem` positions)
    ]

nativeBoundsTests :: TestTree
nativeBoundsTests =
  testGroup
    "native bounds"
    [ testCase "native bounds constrain sampled values" $ do
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

backendDispatchTests :: TestTree
backendDispatchTests =
  testGroup
    "numeric backend dispatch"
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
            assertBool
              "expected hit-and-run burn-in"
              (samplingBurnInSteps statistics >= 256)
          other ->
            assertFailure ("unexpected backend statistics: " ++ show other)
    , testCase "hard-space sampling ignores soft objective attraction" $ do
        let x = var "test.sample.soft" :: Expr TestUnit
            constraints = [soften (x @==@ num 0)]
        solutions <-
          traverse
            (\seed ->
               solve
                 (withInitialSeed (RandomSeed seed) defaultSolveConfig)
                 constraints)
            [1 .. 32]
        let values =
              [ value
              | solution <- solutions
              , Just value <- [evalExpr solution x]
              ]
            average = sum values / fromIntegral (length values)
        length values @?= 32
        assertBool
          "expected samples near the lower range"
          (minimum values < 0.2)
        assertBool
          "expected samples near the upper range"
          (maximum values > 0.8)
        assertBool
          ("expected a broad centered sample, mean was " ++ show average)
          (average > 0.35 && average < 0.65)
    , testCase "nonlinear hard constraints fall back to the optimizer" $ do
        let x = var "test.fallback.nonlinear" :: Expr TestUnit
            inspected =
              inspectConstraints defaultSolveConfig [x @*@ x @==@ num 0.25]
        inspectedBackend inspected @?= PenaltyOptimizer
        assertBool
          "expected a nonlinear fallback diagnostic"
          (isJust (inspectedFallbackReason inspected))
    , testCase "unbounded affine spaces fall back to the optimizer" $ do
        let x = var "test.fallback.unbounded" :: Expr TestLayout
            inspected = inspectConstraints defaultSolveConfig [x @==@ num 1]
        inspectedBackend inspected @?= PenaltyOptimizer
    , testCase "the optimizer can be selected explicitly" $ do
        let x = var "test.force.optimizer" :: Expr TestUnit
            inspected =
              inspectConstraints
                (withNumericBackend PenaltyOptimizer defaultSolveConfig)
                [x @==@ num 0.5]
        inspectedBackend inspected @?= PenaltyOptimizer
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
        solutionBackend solution @?= PenaltyOptimizer
        assertEvalNear "hue" 10 solution hueValue
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
    [ testCase "balances feasible named alternatives" $ do
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
        let selected =
              map (Map.lookup decisionName . solutionChoices) solutions
        assertBool "expected low MIP assignments" (Just "low" `elem` selected)
        assertBool "expected high MIP assignments" (Just "high" `elem` selected)
        mapM_
          (\solution -> do
             solutionSampling solution
               @?= SampledWith
                     BalancedDesignChoices
                     MipConditionedDecisions
             case (Map.lookup decisionName (solutionChoices solution), evalExpr solution x) of
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
            (sampleDesignSpace
               BalancedDesignChoices
               (RandomSeed 1)
               design)
        case completed of
          Nothing -> assertFailure "HiGHS infeasibility sampling did not terminate"
          Just (Left (SamplingFailed message)) ->
            assertBool
              ("unexpected HiGHS failure: " ++ message)
              ("feasible design" `List.isInfixOf` message)
          Just other ->
            assertFailure
              ("expected a typed MIP sampling failure, received " ++ show other)
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
    , testCase "nested extrema fixture satisfies hard constraints" $ do
        let fixture = namedFixture "nested-extrema"
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
        let x = var "test.canonical.x" :: Expr TestLayout
            y = var "test.canonical.y" :: Expr TestLayout
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

assertCompileSolved :: Solution -> Choreography.ViewGraph -> IO IR.Visualization
assertCompileSolved solution graph =
  case Compile.compileSolved "compile/test/SolverTest.hs" solution graph of
    Left err       -> assertFailure err >> pure (error err)
    Right compiled -> pure compiled

renderElements :: IR.Visualization -> [IR.VisualElement]
renderElements = IR.visualizationElements

styleBindingVariables :: String -> IR.VisualElement -> [IR.CspVariableId]
styleBindingVariables field element =
  concat
    [ IR.bindingVariables binding
    | binding <- IR.elementStyleVariables element
    , IR.bindingField binding == field
    ]

assertTraceVariablesExist :: IR.Visualization -> [IR.CspVariableId] -> Assertion
assertTraceVariablesExist compiled referenced = do
  assertBool
    "expected style field to reference at least one CSP variable"
    (not (null referenced))
  let available = map IR.cspVariableId (IR.visualizationVariables compiled)
  mapM_
    (\variableId ->
       assertBool
         ("missing CSP variable " ++ show variableId)
         (variableId `elem` available))
    referenced

epsilon :: Double
epsilon = 1e-6
