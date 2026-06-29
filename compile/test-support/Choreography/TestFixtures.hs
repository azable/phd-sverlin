{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE LinearTypes       #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedLabels  #-}
{-# LANGUAGE RebindableSyntax  #-}
{-# LANGUAGE TypeApplications  #-}
{-# LANGUAGE TypeFamilies      #-}

module Choreography.TestFixtures
  ( payloadMatchedStats
  , virtualGroupStats
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

virtualGroupStats :: (Int, Int, Int, Int)
virtualGroupStats = fixtureStats virtualGroupSpec

fixtureStats :: MatchSpec -> (Int, Int, Int, Int)
fixtureStats spec =
  viewGraphStats (buildViewGraph (runProgramWith spec fixture))

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

virtualGroupSpec :: MatchSpec
virtualGroupSpec =
  visualize $ do
    Selected item <- select @TestValue #item
    style item $ do
      width (by 80)
      height (by 80)
    Selected group <- node item
    style group $ do
      padding (by 8)
