{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE LinearTypes         #-}
{-# LANGUAGE QualifiedDo         #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}

-- | Focused characterization for the target Domain/Program semantic engine.
module SemanticTest
  ( tests
  ) where

import           Control.Exception                   (ErrorCall, evaluate, try)
import           Data.List                           (sortOn)
import qualified Prelude.Linear                      as Linear
import           Sverlin.Internal.Semantic           (Applicable2 (..),
                                                      Apply2 (..), Block,
                                                      BlockId (..), Copy (..),
                                                      Create (..), Destroy (..),
                                                      Domain, Generator, Kind,
                                                      LInt (..), LOperator (..),
                                                      LUnit (..),
                                                      MaterializationOrigin (..),
                                                      Program, Relate (..),
                                                      RelationDirection (..),
                                                      RelationKind,
                                                      Replace (..), Seal (..),
                                                      SemanticTrace (..), Slot,
                                                      StepOccurrence (..),
                                                      TraceBlock (..),
                                                      TraceEvent (..),
                                                      TraceMarker (..),
                                                      TraceOccupancy (..),
                                                      TraceRelation (..),
                                                      Traceable (..),
                                                      Unseal (..), Use (..),
                                                      VariableTranscript (..),
                                                      apply2, between, copy,
                                                      create, declareKind,
                                                      declareRelation,
                                                      declareSteps, destroy,
                                                      kind, listOf, materialize,
                                                      orderedRelation, relate,
                                                      replace,
                                                      runSemanticScenario, seal,
                                                      step, symmetricRelation,
                                                      unseal, use, variable,
                                                      weighted)
import qualified Sverlin.Internal.Semantic.Generator as Generator
import qualified Sverlin.Syntax                      as Syntax
import           Test.Tasty                          (TestTree, testGroup)
import           Test.Tasty.HUnit                    (Assertion, assertBool,
                                                      assertFailure, testCase,
                                                      (@?=))

data Number

instance Traceable Number where
  type Payload Number = LInt Number

data Cell

instance Traceable Cell where
  type Payload Cell = LUnit Cell

data OtherCell

instance Traceable OtherCell where
  type Payload OtherCell = LUnit OtherCell

data Add

instance Traceable Add where
  type Payload Add = LOperator Add

instance Applicable2 Add Number Number where
  type Apply2Result Add Number Number = Number
  applyPayload2 LOperator (LInt leftValue) (LInt rightValue) =
    LInt (leftValue Linear.+ rightValue)

data NumberKind

data CellKind

data OtherCellKind

data AddKind

data Adjacent

data NextCell

data ValueA

data ValueB

data OuterStep

data InnerStep

numberKind :: Kind Number
numberKind = kind @NumberKind

cellKind :: Kind Cell
cellKind = kind @CellKind

adjacent :: RelationKind Cell Cell
adjacent = symmetricRelation @Adjacent

nextCell :: RelationKind Cell Cell
nextCell = orderedRelation @NextCell

wrongNextCell :: RelationKind OtherCell Cell
wrongNextCell = orderedRelation @NextCell

otherCellKind :: Kind OtherCell
otherCellKind = kind @OtherCellKind

addKind :: Kind Add
addKind = kind @AddKind

data Initial where
  Initial
    :: Block Cell
       %1 -> Slot Cell Number
       %1 -> Block Cell
       %1 -> Slot Cell Number
       %1 -> Initial

data Inputs where
  Inputs :: Int %1 -> Int %1 -> Inputs

tests :: TestTree
tests =
  testGroup
    "target semantic engine"
    [ testCase "Domain construction and Program share one ordered trace" $ do
        let trace = runSemanticScenario 19 lifecycleDomain lifecycleProgram
        length (semanticTraceBlocks trace) @?= 4
        length (semanticTraceEvents trace) @?= 13
        map stepOccurrencePath (semanticTraceSteps trace) @?= [[0], [0, 0]]
        case semanticTraceRelations trace of
          [relationRecord] -> do
            traceRelationDirection relationRecord @?= SymmetricRelation
            traceRelationStart relationRecord @?= 6
            traceRelationEnd relationRecord @?= Just 9
          _ -> assertFailure "expected exactly one relation"
    , testCase "variable sub-seeds do not depend on declaration order" $ do
        let first = variableTrace orderedVariables
            second = variableTrace reversedVariables
            stable = traceMarkerType . variableTranscriptMarker
        sortOn stable (semanticTraceVariables first)
          @?= sortOn stable (semanticTraceVariables second)
    , testCase "fixed and generated branches retain a replay transcript" $ do
        let generator =
              weighted (1, pure [1, 2, 3]) [(2, listOf 2 4 (between 0 9))]
        case Generator.runGenerator 23 generator of
          Left problem -> assertFailure (show problem)
          Right (_values, decisions) ->
            assertBool "expected a weighted decision" (not (null decisions))
    , testCase "invalid generator bounds are diagnosed" $ do
        Generator.runGenerator 1 (between 4 3)
          @?= Left
                (Generator.GeneratorFailure
                   "between requires its lower bound to be no greater than its upper bound")
    , testCase "a duplicate relation is rejected independent of sampling"
        $ assertSemanticFailure
            "duplicate active relation"
            duplicateRelationTrace
    , testCase
        "a symmetric duplicate is rejected when its endpoints are reversed"
        $ assertSemanticFailure
            "duplicate active relation"
            reverseDuplicateRelationTrace
    , testCase "ordered relations retain distinct endpoint roles" $ do
        let trace = runSemanticScenario 7 orderedRelationDomain lifecycleProgram
        map
          (\relationRecord ->
             ( traceRelationSource relationRecord
             , traceRelationTarget relationRecord))
          (semanticTraceRelations trace)
          @?= [(BlockId 0, BlockId 2), (BlockId 2, BlockId 0)]
    , testCase "a relation survives occupant replacement and resealing" $ do
        let trace = runSemanticScenario 7 lifecycleDomain resealProgram
        case semanticTraceRelations trace of
          [relationRecord] -> traceRelationEnd relationRecord @?= Just 12
          _                -> assertFailure "expected exactly one relation"
        case filter ((== BlockId 0) . traceBlockId) (semanticTraceBlocks trace) of
          [owner] ->
            traceBlockOccupancies owner
              @?= [ TraceOccupancy (BlockId 1) 2 (Just 7)
                  , TraceOccupancy (BlockId 4) 9 (Just 10)
                  ]
          _ -> assertFailure "expected the stable left owner"
    , testCase
        "a relation handle cannot reuse its marker with different endpoint types"
        $ assertSemanticFailure "not RelationKind" wrongEndpointRelationTrace
    , testCase
        "operator application records its consumed inputs and output lineage" $ do
        let trace = runSemanticScenario 3 applyDomain applyProgram
        map traceBlockEnded (semanticTraceBlocks trace)
          @?= [Just 3, Just 3, Just 3, Just 4]
        let appliedOrigins =
              [ origin
              | TraceMaterialized _ _ origin <- semanticTraceEvents trace
              , case origin of
                  Applied2Origin {} -> True
                  _                 -> False
              ]
        appliedOrigins @?= [Applied2Origin (BlockId 0) (BlockId 1) (BlockId 2)]
    , testCase
        "copy retains the source lifetime and gives the fork its provenance" $ do
        let trace = runSemanticScenario 3 copyDomain copyProgram
        map traceBlockEnded (semanticTraceBlocks trace) @?= [Just 2, Just 3]
        let origins =
              [ origin
              | TraceMaterialized _ _ origin <- semanticTraceEvents trace
              ]
        origins @?= [CreatedOrigin, CopiedOrigin (BlockId 0)]
    , testCase "use exposes a linear payload that can construct its successor" $ do
        let trace = runSemanticScenario 3 copyDomain useProgram
        map traceBlockEnded (semanticTraceBlocks trace) @?= [Just 1, Just 3]
        map traceBlockPayloadText (semanticTraceBlocks trace) @?= ["5", "6"]
    ]

lifecycleDomain :: Domain Initial
lifecycleDomain = Syntax.do
  declareKind numberKind
  declareKind cellKind
  declareRelation adjacent
  declareSteps @'[ OuterStep, InnerStep]
  leftValue <- variable @ValueA (between 1 9)
  rightValue <- variable @ValueB (between 10 19)
  Create leftCellPending <- create LUnit
  leftCell <- materialize cellKind leftCellPending
  Create leftValuePending <- create (LInt leftValue)
  leftBlock <- materialize numberKind leftValuePending
  Seal leftOwner leftSlot <- seal leftCell leftBlock
  Create rightCellPending <- create LUnit
  rightCell <- materialize cellKind rightCellPending
  Create rightValuePending <- create (LInt rightValue)
  rightBlock <- materialize numberKind rightValuePending
  Seal rightOwner rightSlot <- seal rightCell rightBlock
  Relate leftSlot1 rightSlot1 <- relate adjacent leftSlot rightSlot
  Syntax.pure (Initial leftOwner leftSlot1 rightOwner rightSlot1)

lifecycleProgram :: Initial %1 -> Program ()
lifecycleProgram (Initial leftOwner leftSlot rightOwner rightSlot) =
  step @OuterStep
    (Syntax.do
       step @InnerStep
         (Syntax.do
            Unseal leftOwner1 leftValue <- unseal leftOwner leftSlot
            Destroy <- destroy leftValue
            Destroy <- destroy leftOwner1
            Syntax.pure ())
       Unseal rightOwner1 rightValue <- unseal rightOwner rightSlot
       Destroy <- destroy rightValue
       Destroy <- destroy rightOwner1
       Syntax.pure ())

orderedVariables :: Domain Inputs
orderedVariables = Syntax.do
  declareKind numberKind
  first <- variable @ValueA (between 0 100)
  second <- variable @ValueB (listOf 2 2 (between 0 9) >>= sumGenerator)
  Syntax.pure (Inputs first second)

reversedVariables :: Domain Inputs
reversedVariables = Syntax.do
  declareKind numberKind
  second <- variable @ValueB (listOf 2 2 (between 0 9) >>= sumGenerator)
  first <- variable @ValueA (between 0 100)
  Syntax.pure (Inputs first second)

sumGenerator :: [Int] -> Generator Int
sumGenerator values = pure (sum values)

variableTrace :: Domain Inputs %1 -> SemanticTrace
variableTrace domain = runSemanticScenario 41 domain consumeInputs

consumeInputs :: Inputs %1 -> Program ()
consumeInputs (Inputs first second) = Syntax.do
  Create firstPending <- create (LInt first)
  firstBlock <- materialize numberKind firstPending
  Create secondPending <- create (LInt second)
  secondBlock <- materialize numberKind secondPending
  Destroy <- destroy firstBlock
  Destroy <- destroy secondBlock
  Syntax.pure ()

duplicateRelationTrace :: SemanticTrace
duplicateRelationTrace =
  runSemanticScenario 7 duplicateRelationDomain lifecycleProgram

reverseDuplicateRelationTrace :: SemanticTrace
reverseDuplicateRelationTrace =
  runSemanticScenario 7 reverseDuplicateRelationDomain lifecycleProgram

orderedRelationDomain :: Domain Initial
orderedRelationDomain = Syntax.do
  declareKind numberKind
  declareKind cellKind
  declareRelation nextCell
  declareSteps @'[ OuterStep, InnerStep]
  Create leftCellPending <- create LUnit
  leftCell <- materialize cellKind leftCellPending
  Create leftValuePending <- create (LInt 1)
  leftValue <- materialize numberKind leftValuePending
  Seal leftOwner leftSlot <- seal leftCell leftValue
  Create rightCellPending <- create LUnit
  rightCell <- materialize cellKind rightCellPending
  Create rightValuePending <- create (LInt 2)
  rightValue <- materialize numberKind rightValuePending
  Seal rightOwner rightSlot <- seal rightCell rightValue
  Relate leftSlot1 rightSlot1 <- relate nextCell leftSlot rightSlot
  Relate rightSlot2 leftSlot2 <- relate nextCell rightSlot1 leftSlot1
  Syntax.pure (Initial leftOwner leftSlot2 rightOwner rightSlot2)

duplicateRelationDomain :: Domain Initial
duplicateRelationDomain = Syntax.do
  declareKind numberKind
  declareKind cellKind
  declareRelation adjacent
  declareSteps @'[ OuterStep, InnerStep]
  Create leftCellPending <- create LUnit
  leftCell <- materialize cellKind leftCellPending
  Create leftValuePending <- create (LInt 1)
  leftValue <- materialize numberKind leftValuePending
  Seal leftOwner leftSlot <- seal leftCell leftValue
  Create rightCellPending <- create LUnit
  rightCell <- materialize cellKind rightCellPending
  Create rightValuePending <- create (LInt 2)
  rightValue <- materialize numberKind rightValuePending
  Seal rightOwner rightSlot <- seal rightCell rightValue
  Relate leftSlot1 rightSlot1 <- relate adjacent leftSlot rightSlot
  Relate leftSlot2 rightSlot2 <- relate adjacent leftSlot1 rightSlot1
  Syntax.pure (Initial leftOwner leftSlot2 rightOwner rightSlot2)

reverseDuplicateRelationDomain :: Domain Initial
reverseDuplicateRelationDomain = Syntax.do
  declareKind numberKind
  declareKind cellKind
  declareRelation adjacent
  declareSteps @'[ OuterStep, InnerStep]
  Create leftCellPending <- create LUnit
  leftCell <- materialize cellKind leftCellPending
  Create leftValuePending <- create (LInt 1)
  leftValue <- materialize numberKind leftValuePending
  Seal leftOwner leftSlot <- seal leftCell leftValue
  Create rightCellPending <- create LUnit
  rightCell <- materialize cellKind rightCellPending
  Create rightValuePending <- create (LInt 2)
  rightValue <- materialize numberKind rightValuePending
  Seal rightOwner rightSlot <- seal rightCell rightValue
  Relate leftSlot1 rightSlot1 <- relate adjacent leftSlot rightSlot
  Relate rightSlot2 leftSlot2 <- relate adjacent rightSlot1 leftSlot1
  Syntax.pure (Initial leftOwner leftSlot2 rightOwner rightSlot2)

resealProgram :: Initial %1 -> Program ()
resealProgram (Initial leftOwner leftSlot rightOwner rightSlot) = Syntax.do
  Unseal leftOwner1 leftValue <- unseal leftOwner leftSlot
  Create replacementPending <- create (LInt 99)
  Replace successorPending <- replace leftValue replacementPending
  successor <- materialize numberKind successorPending
  Seal leftOwner2 leftSlot1 <- seal leftOwner1 successor
  Unseal leftOwner3 successor1 <- unseal leftOwner2 leftSlot1
  Destroy <- destroy successor1
  Destroy <- destroy leftOwner3
  Unseal rightOwner1 rightValue <- unseal rightOwner rightSlot
  Destroy <- destroy rightValue
  Destroy <- destroy rightOwner1
  Syntax.pure ()

data InvalidInitial where
  InvalidInitial
    :: Block OtherCell
       %1 -> Slot OtherCell Number
       %1 -> Block Cell
       %1 -> Slot Cell Number
       %1 -> InvalidInitial

wrongEndpointRelationTrace :: SemanticTrace
wrongEndpointRelationTrace =
  runSemanticScenario 7 wrongEndpointRelationDomain consumeInvalidInitial

wrongEndpointRelationDomain :: Domain InvalidInitial
wrongEndpointRelationDomain = Syntax.do
  declareKind numberKind
  declareKind cellKind
  declareKind otherCellKind
  declareRelation nextCell
  Create sourceOwnerPending <- create LUnit
  sourceOwner <- materialize otherCellKind sourceOwnerPending
  Create sourceValuePending <- create (LInt 1)
  sourceValue <- materialize numberKind sourceValuePending
  Seal sourceOwner1 sourceSlot <- seal sourceOwner sourceValue
  Create targetOwnerPending <- create LUnit
  targetOwner <- materialize cellKind targetOwnerPending
  Create targetValuePending <- create (LInt 2)
  targetValue <- materialize numberKind targetValuePending
  Seal targetOwner1 targetSlot <- seal targetOwner targetValue
  Relate sourceSlot1 targetSlot1 <- relate wrongNextCell sourceSlot targetSlot
  Syntax.pure (InvalidInitial sourceOwner1 sourceSlot1 targetOwner1 targetSlot1)

consumeInvalidInitial :: InvalidInitial %1 -> Program ()
consumeInvalidInitial (InvalidInitial sourceOwner sourceSlot targetOwner targetSlot) = Syntax.do
  Unseal sourceOwner1 sourceValue <- unseal sourceOwner sourceSlot
  Destroy <- destroy sourceValue
  Destroy <- destroy sourceOwner1
  Unseal targetOwner1 targetValue <- unseal targetOwner targetSlot
  Destroy <- destroy targetValue
  Destroy <- destroy targetOwner1
  Syntax.pure ()

data ApplyInputs where
  ApplyInputs
    :: Block Add %1 -> Block Number %1 -> Block Number %1 -> ApplyInputs

applyDomain :: Domain ApplyInputs
applyDomain = Syntax.do
  declareKind addKind
  declareKind numberKind
  Create addPending <- create @Add LOperator
  addBlock <- materialize addKind addPending
  Create leftPending <- create (LInt 3)
  leftBlock <- materialize numberKind leftPending
  Create rightPending <- create (LInt 4)
  rightBlock <- materialize numberKind rightPending
  Syntax.pure (ApplyInputs addBlock leftBlock rightBlock)

applyProgram :: ApplyInputs %1 -> Program ()
applyProgram (ApplyInputs addBlock leftBlock rightBlock) = Syntax.do
  Apply2 resultPending <- apply2 addBlock leftBlock rightBlock
  result <- materialize numberKind resultPending
  Destroy <- destroy result
  Syntax.pure ()

data CopyInput where
  CopyInput :: Block Number %1 -> CopyInput

copyDomain :: Domain CopyInput
copyDomain = Syntax.do
  declareKind numberKind
  Create pending <- create (LInt 5)
  block <- materialize numberKind pending
  Syntax.pure (CopyInput block)

copyProgram :: CopyInput %1 -> Program ()
copyProgram (CopyInput block) = Syntax.do
  Copy source forkPending <- copy block
  fork <- materialize numberKind forkPending
  Destroy <- destroy source
  Destroy <- destroy fork
  Syntax.pure ()

useProgram :: CopyInput %1 -> Program ()
useProgram (CopyInput block) = Syntax.do
  Use (LInt value) <- use block
  Create pending <- create (LInt (value Linear.+ 1))
  successor <- materialize numberKind pending
  Destroy <- destroy successor
  Syntax.pure ()

assertSemanticFailure :: String -> SemanticTrace -> Assertion
assertSemanticFailure expected trace = do
  result <- try @ErrorCall (evaluate (length (semanticTraceEvents trace)))
  case result of
    Left failure ->
      assertBool
        ("unexpected semantic failure: " ++ show failure)
        (expected `isInfixOf` show failure)
    Right _ -> assertFailure "expected semantic execution to fail"

isInfixOf :: Eq value => [value] -> [value] -> Bool
isInfixOf needle haystack = any (needle `isPrefixOf`) (tails haystack)

isPrefixOf :: Eq value => [value] -> [value] -> Bool
isPrefixOf prefix values = take (length prefix) values == prefix

tails :: [value] -> [[value]]
tails values =
  values
    : case values of
        []     -> []
        _:rest -> tails rest
