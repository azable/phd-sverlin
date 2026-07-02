{-# LANGUAGE LinearTypes #-}
{-# LANGUAGE RankNTypes  #-}

-- | Event projection over the core trace stream. Choreography matching depends
-- on this module to observe lifecycle events without importing the whole core
-- implementation surface.
module LinearTrace.Core.Events
  ( -- * Core event data
    -- | Event values derived from core trace steps. These retain payload
    -- snapshots and facts needed by query/match logic.
    BlockId
  , BlockRef
  , EventBlock
  , eventBlockRef
  , eventBlockPayload
  , eventBlockPayloadView
  , eventBlockFacts
  , withEventBlock
  , TraceEvent(..)
  , EventLog
  , emptyEventLog
  , foldEventLog
  , traceBuilderPendingEventLog
  , traceGraphPendingEventLog
  , checkpointEventLogWith
  , -- * Trace builder state
    -- | Thin state aliases over 'LinearTrace.Core.Internal'. Exposed here so
    -- choreography can run core actions and collect event logs in one pass.
    TraceBuilderState
  , emptyTraceBuilderState
  , runTraceBuilderWithState
  , traceBuilderStateGraph
  , -- * Trace graphs and steps
    -- | Core graph and step views consumed by printers and choreography graph
    -- construction.
    TraceGraphWith
  , TraceStep
  , TraceStepWith
  , TraceStepOutput(..)
  , traceGraphSteps
  , traceStepOutput
  , traceStepEventLog
  , -- * Block references
    -- | Block reference helpers used when linking core events to view tags.
    blockRefId
  ) where

import           Control.Functor.Linear    (runState)
import           LinearTrace.Core.Internal (TraceEvent (..))
import qualified LinearTrace.Core.Internal as C
import qualified Prelude                   as P
import           Prelude.Linear

type BlockId = C.BlockId

type BlockRef tag = C.BlockRef tag

type TraceBuilderState payload = C.TraceBuilderState payload

type TraceGraphWith payload = C.TraceGraphWith payload

type TraceStep = C.TraceStep

type TraceStepWith payload = C.TraceStepWith payload

type EventBlock tag = C.BlockSnapshot tag

eventBlockRef :: EventBlock tag -> BlockRef tag
eventBlockRef block =
  case block of
    C.BlockSnapshot ref _payload _payloadView _facts -> ref

eventBlockPayload :: EventBlock tag -> C.Payload tag
eventBlockPayload block =
  case block of
    C.BlockSnapshot _ref payload _payloadView _facts -> payload

eventBlockPayloadView :: EventBlock tag -> C.PayloadView
eventBlockPayloadView block =
  case block of
    C.BlockSnapshot _ref _payload payloadView _facts -> payloadView

eventBlockFacts :: EventBlock tag -> C.Facts
eventBlockFacts block =
  case block of
    C.BlockSnapshot _ref _payload _payloadView facts -> facts

withEventBlock :: EventBlock tag -> (C.Traceable tag => result) -> result
withEventBlock block result =
  case block of
    C.BlockSnapshot {} -> result

newtype EventLog =
  EventLog [TraceEvent]

emptyEventLog :: EventLog
emptyEventLog = EventLog []

foldEventLog ::
     (accumulator -> TraceEvent -> accumulator)
  -> accumulator
  -> EventLog
  -> accumulator
foldEventLog foldEvent initial eventLog =
  case eventLog of
    EventLog events -> P.foldl foldEvent initial events

traceBuilderPendingEventLog :: TraceBuilderState payload -> EventLog
traceBuilderPendingEventLog state =
  case state of
    C.TraceBuilderState _next _blocks (Ur pending) _steps ->
      eventLogFromPendingEvents pending

traceGraphPendingEventLog :: TraceGraphWith payload -> EventLog
traceGraphPendingEventLog graph =
  case graph of
    C.TraceGraph _blocks _steps pending -> eventLogFromPendingEvents pending

eventLogFromPendingEvents :: C.PendingEvents -> EventLog
eventLogFromPendingEvents pending =
  case pending of
    C.PendingEvents events -> eventLogFromTraceEvents events

eventLogFromTraceEvents :: C.TraceEvents -> EventLog
eventLogFromTraceEvents traceEvents =
  case traceEvents of
    C.TraceEvents events -> EventLog events

checkpointEventLogWith :: P.String -> payload -> C.TraceBuilderWith payload ()
checkpointEventLogWith = C.checkpointWith

emptyTraceBuilderState :: TraceBuilderState payload
emptyTraceBuilderState =
  C.TraceBuilderState (Ur 0) (Ur []) (Ur C.emptyPendingEvents) (Ur [])

runTraceBuilderWithState ::
     C.TraceBuilderWith payload a
     %1 -> TraceBuilderState payload
     %1 -> (a, TraceBuilderState payload)
runTraceBuilderWithState = runState

traceBuilderStateGraph :: TraceBuilderState payload -> TraceGraphWith payload
traceBuilderStateGraph state =
  case state of
    C.TraceBuilderState (Ur _nextBlockId) (Ur blocks) (Ur pending) (Ur steps) ->
      C.TraceGraph blocks steps pending

traceGraphSteps :: TraceGraphWith payload -> [TraceStepWith payload]
traceGraphSteps graph =
  case graph of
    C.TraceGraph _blocks steps _pending -> steps

data TraceStepOutput payload where
  ExplainedTraceStep
    :: P.String -> payload -> TraceStep -> TraceStepOutput payload
  DiscardedTraceStep :: P.String -> TraceStep -> TraceStepOutput payload

traceStepOutput :: TraceStepWith payload -> TraceStepOutput payload
traceStepOutput step =
  case step of
    C.CheckpointStep label payload events ->
      ExplainedTraceStep
        label
        payload
        (C.CheckpointStep label C.NoStepPayload events)
    C.DiscardedStep reason events ->
      DiscardedTraceStep reason (C.DiscardedStep reason events)

traceStepEventLog :: TraceStepWith payload -> EventLog
traceStepEventLog step =
  case step of
    C.CheckpointStep _label _payload events -> eventLogFromTraceEvents events
    C.DiscardedStep _reason events          -> eventLogFromTraceEvents events

blockRefId :: BlockRef tag -> BlockId
blockRefId ref =
  case ref of
    C.BlockRef blockId -> blockId
