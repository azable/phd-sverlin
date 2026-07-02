{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE FlexibleInstances #-}
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
    -- | Compact graph stats used by tests for query and grouping
    -- behavior.
    payloadMatchedStats
  , groupStats
  , pendingMaterializedStepCount
  , pendingReplaceEventNames
  , -- * View graphs
    -- | Concrete fixture graphs used by materialization/style tests.
    categoricalRelationGraph
  , categoricalStyleGraph
  , centerGraph
  , selectedColorGraph
  , selectedScalarGraph
  , styledGraph
  ) where

import           Control.Functor.Linear   hiding ((<$>), (<&>), (<*>))
import           LinearTrace.Choreography
import qualified LinearTrace.Core         as Core
import qualified LinearTrace.Core.Events  as CoreEvents
import qualified Prelude                  as P
import           Prelude.Linear           hiding (fromInteger, fromRational,
                                           (*), (+), (-), (/), (/=), (<>))

data TestValue

type instance Payload TestValue = LInt TestValue

payloadMatchedStats :: (Int, Int, Int, Int)
payloadMatchedStats = fixtureStats payloadMatchedSpec

groupStats :: (Int, Int, Int, Int)
groupStats = fixtureStats groupSpec

pendingMaterializedStepCount :: Int
pendingMaterializedStepCount =
  P.length (CoreEvents.traceGraphSteps pendingMaterializedGraph)

pendingReplaceEventNames :: [P.String]
pendingReplaceEventNames =
  case CoreEvents.traceGraphSteps pendingReplaceGraph of
    _created:replaced:_ -> eventNames (CoreEvents.traceStepEventLog replaced)
    _                   -> []

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

styledGraph :: ViewGraph
styledGraph = buildGraph styledSpec

fixtureStats :: MatchSpec -> (Int, Int, Int, Int)
fixtureStats spec = viewGraphStats (buildGraph spec)

buildGraph :: MatchSpec -> ViewGraph
buildGraph spec = buildViewGraph (runChoreographyWith spec fixture)

fixture :: Choreography ()
fixture = do
  Created firstPending <- create @TestValue (LInt 7)
  first <- materialize #item firstPending
  Created secondPending <- create @TestValue (LInt 8)
  second <- materialize #item secondPending
  checkpoint "created"
  Destroyed <- destroy first
  Destroyed <- destroy second
  checkpoint "destroyed"

pendingMaterializedGraph :: Core.TraceGraph
pendingMaterializedGraph =
  Core.buildGraph $ do
    Core.Created pending <- Core.create (LInt 1 :: LInt TestValue)
    block <- Core.materialize pending
    Core.Destroyed <- Core.destroy block
    Core.checkpoint "done"

pendingReplaceGraph :: Core.TraceGraph
pendingReplaceGraph =
  Core.buildGraph $ do
    Core.Created pending <- Core.create (LInt 1 :: LInt TestValue)
    block <- Core.materialize pending
    Core.checkpoint "created"
    Core.Copied original copied <- Core.copy block
    Core.Replaced replaced <- Core.replace original copied
    next <- Core.materialize replaced
    Core.Destroyed <- Core.destroy next
    Core.checkpoint "replaced"

eventNames :: CoreEvents.EventLog -> [P.String]
eventNames =
  CoreEvents.foldEventLog (\names event -> names P.++ [traceEventName event]) []

traceEventName :: CoreEvents.TraceEvent act -> P.String
traceEventName event =
  case event of
    CoreEvents.TraceCreate _    -> "create"
    CoreEvents.TraceObserve _   -> "observe"
    CoreEvents.TraceUse _       -> "use"
    CoreEvents.TraceCopy _ _    -> "copy"
    CoreEvents.TraceReplace _ _ -> "replace"
    CoreEvents.TraceApply1 {}   -> "apply1"
    CoreEvents.TraceApply2 {}   -> "apply2"
    CoreEvents.TraceDestroy _   -> "destroy"
    CoreEvents.TraceSeal _ _    -> "seal"
    CoreEvents.TraceUnseal _ _  -> "unseal"

payloadMatchedSpec :: MatchSpec
payloadMatchedSpec =
  visualize $ do
    Selected item <- select @TestValue (#item <&> payload (7 :: Int))
    render item $ do
      width (by 80)
      height (by 80)

groupSpec :: MatchSpec
groupSpec =
  visualize $ do
    Selected item <- select @TestValue #item
    render item $ do
      width (by 80)
      height (by 80)
    Selected group <- node item
    render group $ do
      style @Padding (by 8)

selectedColorSpec :: MatchSpec
selectedColorSpec =
  visualize $ do
    Selected item <- select @TestValue #item
    render item $ do
      width (by 80)
      height (by 80)
    ensure
      $ styleOf @Fill item .==. Hsl (120 :: Angle) (0.4 :: Unit) (0.7 :: Unit)

selectedScalarSpec :: MatchSpec
selectedScalarSpec =
  visualize $ do
    Selected item <- select @TestValue #item
    render item $ do
      width (by 80)
      height (by 80)
    ensure $ styleOf @Padding item .==. by 6

categoricalStyleSpec :: MatchSpec
categoricalStyleSpec =
  visualize $ do
    Selected item <- select @TestValue #item
    Variable family <- choice @FontFamily
    render item $ do
      width (by 80)
      height (by 80)
      style @FontFamily (VariableStyle family)
    ensure $ family .==. FontMono

categoricalRelationSpec :: MatchSpec
categoricalRelationSpec =
  visualize $ do
    Selected item <- select @TestValue #item
    render item $ do
      width (by 80)
      height (by 80)
    ensure $ styleOf @FontFamily item .==. FontInter

centerSpec :: MatchSpec
centerSpec =
  visualize $ do
    Selected first <- select @TestValue (#item <&> payload (7 :: Int))
    Selected second <- select @TestValue (#item <&> payload (8 :: Int))
    render first $ do
      width (by 80)
      height (by 80)
      center (vec2 (at 120) (at 90))
    render second $ do
      width (by 80)
      height (by 80)
    ensure $ center second .==. center first

styledSpec :: MatchSpec
styledSpec =
  visualize $ do
    Selected item <- select @TestValue #item
    render item $ do
      width (by 80)
      height (by 80)
      style @Padding (by 4)
      style @FontFamily (FixedStyle FontInter)
      style @FontWeight (FixedStyle FontWeightBold)
      style @Fill (Hsl (120 :: Angle) (0.4 :: Unit) (0.7 :: Unit))
