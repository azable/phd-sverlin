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
  , -- * Query and tag matching
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
  , -- * Primitive operations
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
    OneUse
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
  , checkpoint
  , checkpointWith
  , discardPending
  , (<$>)
  , (<*>)
  , -- * Trace events and steps
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
