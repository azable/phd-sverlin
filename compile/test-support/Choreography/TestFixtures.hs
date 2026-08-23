{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE LinearTypes       #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedLabels  #-}
{-# LANGUAGE RebindableSyntax  #-}
{-# LANGUAGE TypeApplications  #-}
{-# LANGUAGE TypeFamilies      #-}

-- | Stable choreography/view fixtures used by solver tests. These exercise the
-- public choreography DSL while keeping assertions independent of the changing
-- app example.
module Choreography.TestFixtures
  ( -- * Graph statistics
    -- | Compact graph stats used by tests for query and hierarchy
    -- behavior.
    payloadMatchedStats
  , nestedNodeStats
  , overlappingDeclarationStats
  , pendingMaterializedStepCount
  , pendingReplaceEventNames
  , pendingTailEventNames
  , conditionalStyleAccessStats
  , forbiddenStyleAccessStats
  , -- * View graphs
    -- | Concrete fixture graphs used by materialization/style tests.
    categoricalRelationGraph
  , categoricalStyleGraph
  , centerGraph
  , codeTypographyGraph
  , invalidCodeEmphasisGraph
  , invisibleCodeEmphasisGraph
  , maximumTypographyGraph
  , conditionalAbsentGraph
  , conditionalPresentGraph
  , disjunctiveGraph
  , explicitFitTypographyGraph
  , fixedLargeTypographyGraph
  , forbiddenStyleGraph
  , generativeGraph
  , generativeParentGraph
  , generativeRequiredStyleGraph
  , hierarchyBoxGraph
  , prunedHierarchyGraph
  , separatedFamiliesGraph
  , selectedColorGraph
  , selectedScalarGraph
  , styledGraph
  , transientGraph
  , typographyGraph
  , uncappedFitTypographyGraph
  , oversizedFitTypographyGraph
  , responsiveDenseTypographyGraph
  , responsiveSparseTypographyGraph
  , wideLeafGraph
  ) where

import           Control.Functor.Linear   hiding ((<$>), (<&>), (<*>))
import           LinearTrace.Choreography
import qualified LinearTrace.Core         as Core
import qualified Prelude                  as P
import           Prelude.Linear           hiding (fromInteger, fromRational,
                                           (*), (+), (-), (/), (/=), (<>))

data TestValue

type instance Payload TestValue = LInt TestValue

data TestTreatment
  = TestPlain
  | TestFilled

instance ChoiceDomain TestTreatment where
  choiceDomain = [TestPlain, TestFilled]
  choiceToken treatment =
    case treatment of
      TestPlain  -> "plain"
      TestFilled -> "filled"

payloadMatchedStats :: (Int, Int, Int)
payloadMatchedStats = fixtureStats payloadMatchedSpec

nestedNodeStats :: (Int, Int, Int)
nestedNodeStats = fixtureStats nestedNodeSpec

overlappingDeclarationStats :: (Int, Int, Int)
overlappingDeclarationStats = fixtureStats overlappingDeclarationSpec

pendingMaterializedStepCount :: Int
pendingMaterializedStepCount =
  P.length (Core.traceGraphSteps pendingMaterializedGraph)

pendingReplaceEventNames :: [P.String]
pendingReplaceEventNames =
  case Core.traceGraphSteps pendingReplaceGraph of
    _created:replaced:_ -> eventNames (Core.traceStepEvents replaced)
    _                   -> []

pendingTailEventNames :: [P.String]
pendingTailEventNames =
  eventNames (Core.traceGraphPendingEvents pendingTailGraph)

conditionalStyleAccessStats :: (Int, Int, Int)
conditionalStyleAccessStats = fixtureStats conditionalStyleAccessSpec

forbiddenStyleAccessStats :: (Int, Int, Int)
forbiddenStyleAccessStats = fixtureStats forbiddenStyleAccessSpec

selectedColorGraph :: ViewGraph
selectedColorGraph = buildGraph selectedColorSpec

selectedScalarGraph :: ViewGraph
selectedScalarGraph = buildGraph selectedScalarSpec

categoricalStyleGraph :: ViewGraph
categoricalStyleGraph = buildGraph categoricalStyleSpec

categoricalRelationGraph :: ViewGraph
categoricalRelationGraph = buildGraph categoricalRelationSpec

centerGraph :: ViewGraph
centerGraph = buildGraph centerSpec

codeTypographyGraph :: ViewGraph
codeTypographyGraph = buildGraph codeTypographySpec

invalidCodeEmphasisGraph :: ViewGraph
invalidCodeEmphasisGraph = buildGraph invalidCodeEmphasisSpec

invisibleCodeEmphasisGraph :: ViewGraph
invisibleCodeEmphasisGraph = buildGraph invisibleCodeEmphasisSpec

conditionalAbsentGraph :: ViewGraph
conditionalAbsentGraph = buildGraph (conditionalStyleSpec TestPlain)

conditionalPresentGraph :: ViewGraph
conditionalPresentGraph = buildGraph (conditionalStyleSpec TestFilled)

disjunctiveGraph :: ViewGraph
disjunctiveGraph = buildGraph disjunctiveSpec

explicitFitTypographyGraph :: ViewGraph
explicitFitTypographyGraph = buildGraph explicitFitTypographySpec

fixedLargeTypographyGraph :: ViewGraph
fixedLargeTypographyGraph = buildGraph fixedLargeTypographySpec

uncappedFitTypographyGraph :: ViewGraph
uncappedFitTypographyGraph = buildGraph uncappedFitTypographySpec

oversizedFitTypographyGraph :: ViewGraph
oversizedFitTypographyGraph = buildGraph oversizedFitTypographySpec

responsiveSparseTypographyGraph :: ViewGraph
responsiveSparseTypographyGraph = buildGraph responsiveSparseTypographySpec

responsiveDenseTypographyGraph :: ViewGraph
responsiveDenseTypographyGraph =
  buildGraphFor responsiveDenseFixture responsiveDenseTypographySpec

forbiddenStyleGraph :: ViewGraph
forbiddenStyleGraph = buildGenerativeGraph forbiddenStyleSpec

generativeGraph :: ViewGraph
generativeGraph = buildGenerativeGraph generativeSpec

generativeParentGraph :: ViewGraph
generativeParentGraph = buildGenerativeGraph generativeParentSpec

generativeRequiredStyleGraph :: ViewGraph
generativeRequiredStyleGraph = buildGenerativeGraph selectedColorSpec

hierarchyBoxGraph :: ViewGraph
hierarchyBoxGraph = buildGraph hierarchyBoxSpec

prunedHierarchyGraph :: ViewGraph
prunedHierarchyGraph = buildGraph prunedHierarchySpec

separatedFamiliesGraph :: ViewGraph
separatedFamiliesGraph = buildGenerativeGraph separatedFamiliesSpec

styledGraph :: ViewGraph
styledGraph = buildGraph styledSpec

transientGraph :: ViewGraph
transientGraph = buildGraphFor transientFixture nestedNodeSpec

typographyGraph :: ViewGraph
typographyGraph = buildGenerativeGraph typographySpec

maximumTypographyGraph :: ViewGraph
maximumTypographyGraph = buildGenerativeGraph maximumTypographySpec

wideLeafGraph :: ViewGraph
wideLeafGraph = buildGraph wideLeafSpec

fixtureStats :: MatchSpec -> (Int, Int, Int)
fixtureStats spec = viewGraphStats (buildGraph spec)

buildGraph :: MatchSpec -> ViewGraph
buildGraph = buildGraphFor fixture

buildGenerativeGraph :: MatchSpec -> ViewGraph
buildGenerativeGraph spec =
  buildViewGraph (runChoreographyWithGenerativeStyles spec fixture)

buildGraphFor :: Choreography () -> MatchSpec -> ViewGraph
buildGraphFor choreography spec =
  buildViewGraph (runChoreographyWith spec choreography)

fixture :: Choreography ()
fixture = do
  Create firstPending <- create @TestValue (LInt 7)
  first <- materialize #item firstPending
  Create secondPending <- create @TestValue (LInt 8)
  second <- materialize #item secondPending
  checkpoint "created"
  checkpoint "unchanged"
  Destroy <- destroy first
  Destroy <- destroy second
  checkpoint "destroyed"

responsiveDenseFixture :: Choreography ()
responsiveDenseFixture = do
  Create pending7 <- create @TestValue (LInt 7)
  value7 <- materialize #item pending7
  Create pending8 <- create @TestValue (LInt 8)
  value8 <- materialize #item pending8
  Create pending9 <- create @TestValue (LInt 9)
  value9 <- materialize #item pending9
  Create pending10 <- create @TestValue (LInt 10)
  value10 <- materialize #item pending10
  Create pending11 <- create @TestValue (LInt 11)
  value11 <- materialize #item pending11
  checkpoint "created"
  Destroy <- destroy value11
  Destroy <- destroy value10
  Destroy <- destroy value9
  Destroy <- destroy value8
  Destroy <- destroy value7
  checkpoint "destroyed"

transientFixture :: Choreography ()
transientFixture = do
  Create pending <- create @TestValue (LInt 7)
  block <- materialize #item pending
  Destroy <- destroy block
  checkpoint "transient"
  checkpoint "after transient"

pendingMaterializedGraph :: Core.TraceGraph
pendingMaterializedGraph =
  Core.buildGraph $ do
    Core.Create pending <- Core.create (LInt 1 :: LInt TestValue)
    block <- Core.materialize pending
    Core.Destroy <- Core.destroy block
    Core.checkpoint "done"

pendingReplaceGraph :: Core.TraceGraph
pendingReplaceGraph =
  Core.buildGraph $ do
    Core.Create pending <- Core.create (LInt 1 :: LInt TestValue)
    block <- Core.materialize pending
    Core.checkpoint "created"
    Core.Copy original copied <- Core.copy block
    Core.Replace replaced <- Core.replace original copied
    next <- Core.materialize replaced
    Core.Destroy <- Core.destroy next
    Core.checkpoint "replaced"

pendingTailGraph :: Core.TraceGraph
pendingTailGraph =
  Core.buildGraph $ do
    Core.Create pending <- Core.create (LInt 1 :: LInt TestValue)
    block <- Core.materialize pending
    Core.checkpoint "created"
    Core.Destroy <- Core.destroy block
    return ()

eventNames :: Core.TraceEvents -> [P.String]
eventNames =
  Core.foldTraceEvents (\names event -> names P.++ [traceEventName event]) []

traceEventName :: Core.TraceEvent -> P.String
traceEventName event =
  case event of
    Core.TraceCreate _    -> "create"
    Core.TraceObserve _   -> "observe"
    Core.TraceUse _       -> "use"
    Core.TraceCopy _ _    -> "copy"
    Core.TraceReplace _ _ -> "replace"
    Core.TraceApply1 {}   -> "apply1"
    Core.TraceApply2 {}   -> "apply2"
    Core.TraceDestroy _   -> "destroy"
    Core.TraceSeal _ _    -> "seal"
    Core.TraceUnseal _ _  -> "unseal"

payloadMatchedSpec :: MatchSpec
payloadMatchedSpec =
  visualize $ do
    Selected item <- select @TestValue (#item <&> payload (7 :: Int))
    node item $ do
      width (by 80)
      height (by 80)

nestedNodeSpec :: MatchSpec
nestedNodeSpec =
  visualize $ do
    Selected item <- select @TestValue #item
    Selected _parent <-
      node $ do
        padding (uniform (by 8))
        node item $ do
          width (by 80)
          height (by 80)
    return ()

overlappingDeclarationSpec :: MatchSpec
overlappingDeclarationSpec =
  visualize $ do
    Selected item <- select @TestValue #item
    node item $ do
      width (by 80)
      height (by 80)
    node item $ do
      width (by 60)
      height (by 60)

generativeSpec :: MatchSpec
generativeSpec =
  visualize $ do
    Selected item <- select @TestValue #item
    node item $ do
      width (by 80)
      height (by 80)

generativeParentSpec :: MatchSpec
generativeParentSpec =
  visualize $ do
    Selected first <- select @TestValue (#item <&> payload (7 :: Int))
    Selected second <- select @TestValue (#item <&> payload (8 :: Int))
    Selected _parent <-
      node $ do
        padding (uniform (by 8))
        node first $ do
          width (by 80)
          height (by 80)
          left (at 80)
          top (at 80)
        node second $ do
          width (by 80)
          height (by 80)
          left (at 200)
          top (at 80)
    return ()

hierarchyBoxSpec :: MatchSpec
hierarchyBoxSpec =
  visualize $ do
    Selected item <- select @TestValue (#item <&> payload (7 :: Int))
    Selected parent <-
      node $ do
        Selected current <- self
        width (by 400)
        height (by 300)
        padding (edges (by 10) (by 20) (by 30) (by 40))
        margin (symmetric (by 5) (by 7))
        contentFit Both Contain
        style @FontFamily (FixedStyle FontSerif)
        ensure $ x current .==. x canvas
        node item $ do
          content (text "7")
          widthOf (percent 50)
          heightOf (percent 40)
          xAt (percent 50)
          yAt (percent 50)
    ensure $ y parent .==. y canvas

prunedHierarchySpec :: MatchSpec
prunedHierarchySpec =
  visualize $ do
    Selected missing <- select @TestValue (#item <&> payload (999 :: Int))
    Selected _parent <-
      node $ do
        node missing $ do
          width (by 80)
          height (by 80)
    return ()

selectedColorSpec :: MatchSpec
selectedColorSpec =
  visualize $ do
    Selected item <- select @TestValue #item
    node item $ do
      width (by 80)
      height (by 80)
    ensure
      $ styleOf @Fill item .==. Hsl (120 :: Angle) (0.4 :: Unit) (0.7 :: Unit)

selectedScalarSpec :: MatchSpec
selectedScalarSpec =
  visualize $ do
    Selected item <- select @TestValue #item
    node item $ do
      width (by 80)
      height (by 80)
    ensure $ styleOf @Radius item .==. by 6

categoricalStyleSpec :: MatchSpec
categoricalStyleSpec =
  visualize $ do
    Selected item <- select @TestValue #item
    Variable family <- choice @FontFamily
    node item $ do
      width (by 80)
      height (by 80)
      style @FontFamily (VariableStyle family)
    ensure $ family .==. FontMono

categoricalRelationSpec :: MatchSpec
categoricalRelationSpec =
  visualize $ do
    Selected item <- select @TestValue #item
    node item $ do
      width (by 80)
      height (by 80)
    ensure $ styleOf @FontFamily item .==. FontInter

centerSpec :: MatchSpec
centerSpec =
  visualize $ do
    Selected first <- select @TestValue (#item <&> payload (7 :: Int))
    Selected second <- select @TestValue (#item <&> payload (8 :: Int))
    node first $ do
      width (by 80)
      height (by 80)
      center (vec2 (at 120) (at 90))
    node second $ do
      width (by 80)
      height (by 80)
    ensure $ center second .==. center first

disjunctiveSpec :: MatchSpec
disjunctiveSpec =
  visualize $ do
    Selected item <- select @TestValue (#item <&> payload (7 :: Int))
    node item $ do
      width (by 80)
      height (by 80)
    oneOf
      "test.visual.position"
      (alternative "left" [left item .==. at 40])
      [alternative "right" [left item .==. at 680]]

conditionalStyleSpec :: TestTreatment -> MatchSpec
conditionalStyleSpec selectedTreatment =
  visualize $ do
    Selected item <- select @TestValue #item
    Variable treatment <- choice @TestTreatment
    node item $ do
      width (by 80)
      height (by 80)
      styleCase @Fill treatment $ \case
        TestPlain -> P.Nothing
        TestFilled -> P.Just (Hsl (210 :: Angle) (0.5 :: Unit) (0.9 :: Unit))
    ensure $ treatment .==. selectedTreatment

conditionalStyleAccessSpec :: MatchSpec
conditionalStyleAccessSpec =
  visualize $ do
    Selected item <- select @TestValue #item
    Variable treatment <- choice @TestTreatment
    node item $ do
      width (by 80)
      height (by 80)
      styleCase @Fill treatment $ \case
        TestPlain -> P.Nothing
        TestFilled -> P.Just (Hsl (210 :: Angle) (0.5 :: Unit) (0.9 :: Unit))
    ensure
      $ styleOf @Fill item .==. Hsl (210 :: Angle) (0.5 :: Unit) (0.9 :: Unit)

forbiddenStyleSpec :: MatchSpec
forbiddenStyleSpec =
  visualize $ do
    Selected item <- select @TestValue #item
    node item $ do
      width (by 80)
      height (by 80)
      withoutStyle @Fill

forbiddenStyleAccessSpec :: MatchSpec
forbiddenStyleAccessSpec =
  visualize $ do
    Selected item <- select @TestValue #item
    node item $ do
      width (by 80)
      height (by 80)
      withoutStyle @Fill
    ensure
      $ styleOf @Fill item .==. Hsl (210 :: Angle) (0.5 :: Unit) (0.9 :: Unit)

separatedFamiliesSpec :: MatchSpec
separatedFamiliesSpec =
  visualize $ do
    Selected first <- select @TestValue (#item <&> payload (7 :: Int))
    Selected second <- select @TestValue (#item <&> payload (8 :: Int))
    node first $ do
      width (by 80)
      height (by 80)
      styleFamily "first"
    node second $ do
      width (by 80)
      height (by 80)
      styleFamily "second"

styledSpec :: MatchSpec
styledSpec =
  visualize $ do
    Selected item <- select @TestValue #item
    node item $ do
      width (by 80)
      height (by 80)
      padding (uniform (by 4))
      style @FontFamily (FixedStyle FontInter)
      style @FontWeight (FixedStyle FontWeightBold)
      style @Fill (Hsl (120 :: Angle) (0.4 :: Unit) (0.7 :: Unit))

wideLeafSpec :: MatchSpec
wideLeafSpec =
  visualize $ do
    Selected item <- select @TestValue #item
    node item $ do
      width (by 620)
      height (by 52)
    ensure $ left item .>=. at 70
    ensure $ right item .<=. at 730

typographySpec :: MatchSpec
typographySpec =
  visualize $ do
    Selected item <- select @TestValue (#item <&> payload (7 :: Int))
    node item $ do
      content
        (text
           "This label is deliberately long enough to exercise deterministic fitting")
      width (by 220)
      height (by 64)
      left (at 40)
      top (at 40)
      style @FontFamily (FixedStyle FontInter)

maximumTypographySpec :: MatchSpec
maximumTypographySpec =
  visualize $ do
    Selected item <- select @TestValue (#item <&> payload (7 :: Int))
    node item $ do
      fitText
        (text
           "This label is deliberately long enough to exercise deterministic fitting")
      width (by 220)
      height (by 64)
      left (at 40)
      top (at 40)
      style @FontFamily (FixedStyle FontInter)

explicitFitTypographySpec :: MatchSpec
explicitFitTypographySpec =
  visualize $ do
    Selected item <- select @TestValue (#item <&> payload (7 :: Int))
    node item $ do
      fitText
        (text
           "This explicitly sized label may be reduced by the compiler when requested")
      width (by 220)
      height (by 64)
      left (at 40)
      top (at 40)
      style @FontFamily (FixedStyle FontInter)
      style @FontSize (by 24)

uncappedFitTypographySpec :: MatchSpec
uncappedFitTypographySpec =
  visualize $ do
    Selected item <- select @TestValue (#item <&> payload (7 :: Int))
    node item $ do
      fitText (text "7")
      width (by 88)
      height (by 68)
      left (at 40)
      top (at 40)
      style @FontFamily (FixedStyle FontMono)
      style @FontWeight (FixedStyle FontWeightBold)
      style @StrokeWidth (by 2)

oversizedFitTypographySpec :: MatchSpec
oversizedFitTypographySpec =
  visualize $ do
    Selected item <- select @TestValue (#item <&> payload (7 :: Int))
    node item $ do
      fitText (text "7")
      width (by 88)
      height (by 68)
      left (at 40)
      top (at 40)
      style @FontFamily (FixedStyle FontMono)
      style @FontWeight (FixedStyle FontWeightBold)
      style @FontSize (by 56)
      style @StrokeWidth (by 2)

fixedLargeTypographySpec :: MatchSpec
fixedLargeTypographySpec =
  visualize $ do
    Selected item <- select @TestValue (#item <&> payload (7 :: Int))
    node item $ do
      content (text "7")
      width (by 120)
      height (by 100)
      left (at 40)
      top (at 40)
      style @FontFamily (FixedStyle FontMono)
      style @FontSize (by 56)

responsiveSparseTypographySpec :: MatchSpec
responsiveSparseTypographySpec =
  visualize $ do
    Selected first <- select @TestValue (#item <&> payload (7 :: Int))
    Selected second <- select @TestValue (#item <&> payload (8 :: Int))
    node first $ do
      fitText (text "7")
      width (by 120)
      height (by 250)
      left (at 340)
      top (at 40)
      style @FontFamily (FixedStyle FontMono)
      style @FontWeight (FixedStyle FontWeightBold)
    node second $ do
      fitText (text "8")
      width (by 120)
      height (by 250)
      left (at 340)
      top (at 310)
      style @FontFamily (FixedStyle FontMono)
      style @FontWeight (FixedStyle FontWeightBold)

responsiveDenseTypographySpec :: MatchSpec
responsiveDenseTypographySpec =
  visualize $ do
    Selected value7 <- select @TestValue (#item <&> payload (7 :: Int))
    Selected value8 <- select @TestValue (#item <&> payload (8 :: Int))
    Selected value9 <- select @TestValue (#item <&> payload (9 :: Int))
    Selected value10 <- select @TestValue (#item <&> payload (10 :: Int))
    Selected value11 <- select @TestValue (#item <&> payload (11 :: Int))
    node value7 $ do
      fitText (text "7")
      width (by 120)
      height (by 88)
      left (at 340)
      top (at 40)
      style @FontFamily (FixedStyle FontMono)
      style @FontWeight (FixedStyle FontWeightBold)
    node value8 $ do
      fitText (text "8")
      width (by 120)
      height (by 88)
      left (at 340)
      top (at 148)
      style @FontFamily (FixedStyle FontMono)
      style @FontWeight (FixedStyle FontWeightBold)
    node value9 $ do
      fitText (text "9")
      width (by 120)
      height (by 88)
      left (at 340)
      top (at 256)
      style @FontFamily (FixedStyle FontMono)
      style @FontWeight (FixedStyle FontWeightBold)
    node value10 $ do
      fitText (text "10")
      width (by 120)
      height (by 88)
      left (at 340)
      top (at 364)
      style @FontFamily (FixedStyle FontMono)
      style @FontWeight (FixedStyle FontWeightBold)
    node value11 $ do
      fitText (text "11")
      width (by 120)
      height (by 88)
      left (at 340)
      top (at 472)
      style @FontFamily (FixedStyle FontMono)
      style @FontWeight (FixedStyle FontWeightBold)

codeTypographySpec :: MatchSpec
codeTypographySpec =
  visualize $ do
    Selected item <- select @TestValue (#item <&> payload (7 :: Int))
    node item $ do
      emphasizeCode
        "created"
        [codeRange 4 10, codeRange 8 12]
        (emphasizeCode
           "unchanged"
           [codeRange 51 58]
           (highlightCode
              "haskell"
              (codeWrap
                 (codeContent
                    (text
                       "let greeting = \"λ deliberately long value\"\n-- this comment is deliberately long as well\nin greeting")))))
      width (by 250)
      height (by 110)
      left (at 40)
      top (at 40)
      style @FontSize (by 14)
      style @TextAlign (FixedStyle TextAlignLeft)

invalidCodeEmphasisSpec :: MatchSpec
invalidCodeEmphasisSpec =
  visualize $ do
    Selected item <- select @TestValue (#item <&> payload (7 :: Int))
    node item $ do
      emphasizeCode
        "created"
        [codeRange 0 100]
        (codeContent (text "let value = 1"))
      width (by 250)
      height (by 64)
      left (at 40)
      top (at 40)

invisibleCodeEmphasisSpec :: MatchSpec
invisibleCodeEmphasisSpec =
  visualize $ do
    Selected item <- select @TestValue (#item <&> payload (7 :: Int))
    node item $ do
      emphasizeCode
        "missing"
        [codeRange 0 3]
        (codeContent (text "let value = 1"))
      width (by 250)
      height (by 64)
      left (at 40)
      top (at 40)
