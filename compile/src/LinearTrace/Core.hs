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
  , BlockId
  , BlockRef
  , blockRefId
  , BlockSnapshot
  , blockSnapshotRef
  , blockSnapshotPayload
  , blockSnapshotPayloadView
  , blockSnapshotFacts
  , withBlockSnapshot
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
  , -- * Primitive operations
    -- | Linear lifecycle operations. Block-producing operations produce
    -- pending obligations that must be materialized before use.
    Pending
  , create
  , observe
  , use
  , copy
  , replace
  , apply1
  , apply2
  , materialize
  , materializeTagged
  , materializeTaggedWith
  , commit
  , destroy
  , seal
  , unseal
  , -- * Operation results
    -- | Public wrappers around linear operation results.
    OneUse(..)
  , Create(..)
  , Observe(..)
  , Use(..)
  , Copy(..)
  , Replace(..)
  , Apply1(..)
  , Apply2(..)
  , Destroy(..)
  , Seal(..)
  , Unseal(..)
  , (<$>)
  , (<*>)
  , -- * Trace events and steps
    -- | Event and checkpoint views over built graphs. These are the direct
    -- core interface used by visualization layers and diagnostics.
    TraceEvent(..)
  , TraceEvents
  , emptyTraceEvents
  , foldTraceEvents
  , NoStepPayload
  , TraceStep
  , TraceStepWith
  , traceGraphPendingEvents
  , traceGraphSteps
  , traceStepEvents
  , foldTraceStep
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
