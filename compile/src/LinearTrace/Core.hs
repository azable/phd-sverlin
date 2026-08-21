{-# LANGUAGE TypeFamilies #-}

-- | Stable facade for the linear trace core. It re-exports the direct trace
-- builder API from 'LinearTrace.Core.Internal' while hiding internal graph state
-- constructors that only event projection should need.
module LinearTrace.Core
  ( -- * Core public API data
    -- | Direct trace graph and payload vocabulary. Choreography depends on
    -- this layer for typed payload handles and trace lifecycle operations.
    TraceGraph
  , TraceBuilder
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
  , -- * Query and tag matching
    -- | Neutral query language over core facts and payload snapshots.
    Query(..)
  , QueryTerm(..)
  , QueryValue(..)
  , QueryInt(..)
  , QueryBindings
  , emptyQuery
  , queryAtom
  , queryInt
  , queryAppend
  , queryKey
  , queryFacts
  , queryMatches
  , queryIntConst
  , queryIntVar
  , queryIntAdd
  , queryBindingValue
  , bindQueryInt
  , MatchBinding(..)
  , MatchBindings
  , matchBinding
  , matchBindingValue
  , queryMatchBindings
  , PayloadPattern
  , payloadPatternMatches
  , anyPayloadPattern
  , payloadBindingPattern
  , payloadBoolPattern
  , payloadIntPattern
  , payloadDoublePattern
  , payloadStringPattern
  , payloadUnitPattern
  , labelName
  , safeKey
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
    -- core interface used by visualization layers.
    TraceEvent(..)
  , TraceEvents
  , emptyTraceEvents
  , foldTraceEvents
  , TraceStep
  , traceGraphPendingEvents
  , traceGraphSteps
  , traceStepEvents
  , foldTraceStep
  , -- * Graph building
    -- | Final core graph builders. 'LinearTrace.Choreography' uses the same
    -- core state but attaches view output alongside it.
    checkpoint
  , buildGraph
  ) where

import           LinearTrace.Core.Internal
import           LinearTrace.Core.Query
import           Prelude                   ()
