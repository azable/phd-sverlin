{-# LANGUAGE TypeFamilies #-}

-- | Stable facade for the linear trace core. It re-exports the direct trace
-- builder API from 'LinearTrace.Core.Internal' while hiding internal graph state
-- constructors that only event projection and diagnostics should need.
module LinearTrace.Core
  ( -- * Core public API data
    -- | Direct trace graph and payload vocabulary. Choreography depends on
    -- this layer for typed payload handles and trace lifecycle operations.
    TraceGraph
  , TraceGraphWith
  , TraceBuilder
  , TraceBuilderWith
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
  , PayloadView(..)
  , payloadText
  , Traceable
  , -- * Trusted linear payloads
    -- | Built-in payload wrappers used by examples/tests and by the
    -- choreography DSL's public payload vocabulary.
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
    -- | Type-level action tags recorded by the core builder. Event projection
    -- and printing consume these constructors through 'LinearTrace.Core.Events'
    -- and 'LinearTrace.Print'.
    ActionKind(..)
  , Action
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
    -- | Linear lifecycle operations. Block-producing operations produce
    -- pending obligations that must be materialized before use.
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
    OneUse(..)
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
  , (<$>)
  , (<*>)
  , -- * Graph building
    -- | Final core graph builders. 'LinearTrace.Choreography' uses the same
    -- core state but attaches view output alongside it.
    checkpoint
  , checkpointWith
  , discardPending
  , buildGraph
  ) where

import           LinearTrace.Core.Internal
import           Prelude                   ()
