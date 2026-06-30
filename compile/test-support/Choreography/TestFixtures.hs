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
    style item $ do
      width (by 80)
      height (by 80)

groupSpec :: MatchSpec
groupSpec =
  visualize $ do
    Selected item <- select @TestValue #item
    style item $ do
      width (by 80)
      height (by 80)
    Selected group <- node item
    style group $ do
      padding (by 8)

selectedColorSpec :: MatchSpec
selectedColorSpec =
  visualize $ do
    Selected item <- select @TestValue #item
    style item $ do
      width (by 80)
      height (by 80)
    ensure $ fill item .==. Hsl (120 :: Angle) (0.4 :: Unit) (0.7 :: Unit)

selectedScalarSpec :: MatchSpec
selectedScalarSpec =
  visualize $ do
    Selected item <- select @TestValue #item
    style item $ do
      width (by 80)
      height (by 80)
    ensure $ padding item .==. by 6

categoricalStyleSpec :: MatchSpec
categoricalStyleSpec =
  visualize $ do
    Selected item <- select @TestValue #item
    Variable family <- variable @FontFamily
    style item $ do
      width (by 80)
      height (by 80)
      fontFamily family
    ensure $ family .==. FontMono

categoricalRelationSpec :: MatchSpec
categoricalRelationSpec =
  visualize $ do
    Selected item <- select @TestValue #item
    style item $ do
      width (by 80)
      height (by 80)
    ensure $ fontFamily item .==. FontInter

styledSpec :: MatchSpec
styledSpec =
  visualize $ do
    Selected item <- select @TestValue #item
    style item $ do
      width (by 80)
      height (by 80)
      padding (by 4)
      fontFamily FontInter
      fontWeight FontWeightBold
      fill (Hsl (120 :: Angle) (0.4 :: Unit) (0.7 :: Unit))
