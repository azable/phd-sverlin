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
import           Prelude.Linear           hiding (fromInteger, fromRational,
                                           (*), (+), (-), (/), (/=), (<>))

data TestValue

type instance Payload TestValue = LInt TestValue

instance Traceable TestValue

payloadMatchedStats :: (Int, Int, Int, Int)
payloadMatchedStats = fixtureStats payloadMatchedSpec

groupStats :: (Int, Int, Int, Int)
groupStats = fixtureStats groupSpec

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
buildGraph spec = buildViewGraph (runProgramWith spec fixture)

fixture :: Program ()
fixture = do
  first <- create @TestValue #item (LInt 7)
  second <- create @TestValue #item (LInt 8)
  checkpoint "created"
  destroy first
  destroy second
  checkpoint "destroyed"

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
