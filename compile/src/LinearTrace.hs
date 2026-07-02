{-# LANGUAGE TypeFamilies #-}

-- | Public convenience facade for users that want the core trace DSL plus
-- printing and JSON compilation from one import. This module only re-exports
-- stable APIs from 'LinearTrace.Core', 'LinearTrace.Print', and
-- 'LinearTrace.Compile'; lower-level view/choreography internals stay behind
-- their own modules.
module LinearTrace
  ( -- * Core public API data
    -- | Core graph, payload, fact, and typeclass vocabulary re-exported from
    -- 'LinearTrace.Core'. Use these when building a trace directly.
    TraceGraph
  , TraceGraphWith
  , TraceBuilder
  , TraceBuilderWith
  , Traceable
  , Block
  , Slot
  , Payload
  , FactValue(..)
  , Fact(..)
  , Facts(..)
  , emptyFacts
  , factAtom
  , factSymbol
  , factInt
  , factsUnion
  , factsToList
  , -- * Trusted linear payloads
    -- | Small trusted payload wrappers supplied by the core layer for example
    -- and test programs. User payload types can also provide their own
    -- 'Payload' instances.
    LUnit(..)
  , LBool(..)
  , LInt(..)
  , LDouble(..)
  , LString(..)
  , LOperator(..)
  , CoreOperator(..)
  , LinearPayload(..)
  , applyLinear1
  , applyLinear1Into
  , applyLinear2
  , applyLinear2Into
  , Applicable1(..)
  , Applicable2(..)
  , -- * Action vocabulary
    -- | Linear action tags and operations from the core trace builder. These
    -- are the only constructors the direct core API needs to record lifecycle
    -- events.
    Action
  , type Create
  , type Observe
  , type Use
  , type Copy
  , type Replace
  , type Apply1
  , type Apply2
  , type Destroy
  , type Seal
  , type Unseal
  , -- * Primitive operations
    Pending
  , Materialization
  , commitMaterialization
  , taggedMaterialization
  , selectedMaterialization
  , create
  , createTagged
  , observe
  , use
  , copy
  , copyTagged
  , replace
  , apply1
  , apply1Tagged
  , apply1TaggedWith
  , apply2
  , apply2Tagged
  , apply2TaggedWith
  , materialize
  , materializeTagged
  , materializeTaggedWith
  , materializeWith
  , commit
  , destroy
  , seal
  , unseal
  , -- * Operation results
    -- | Public wrappers around linear operation results.
    OneUse
  , Created(..)
  , Observed(..)
  , Used(..)
  , Copied(..)
  , Replaced(..)
  , Applied1(..)
  , Applied2(..)
  , Destroyed(..)
  , Sealed(..)
  , Unsealed(..)
  , checkpoint
  , checkpointWith
  , discardPending
  , (<$>)
  , (<*>)
  , -- * Graph building, rendering and compilation
    -- | Output-facing helpers from 'LinearTrace.Print' and
    -- 'LinearTrace.Compile'. The visualization compiler depends on a solved
    -- view graph supplied by the choreography/view pipeline.
    PayloadView(..)
  , buildGraph
  , printGraph
  , printTrace
  , printSolutionByStep
  , compileSolved
  , printCompiledJSON
  , writeCompiledJSON
  ) where

import           LinearTrace.Compile
import           LinearTrace.Core
import           LinearTrace.Print
import           Prelude             hiding ((<$>), (<*>))
