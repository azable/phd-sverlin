{-# LANGUAGE GADTs       #-}
{-# LANGUAGE LinearTypes #-}

-- | Event projection over the core trace stream. Choreography matching depends
-- on this module to observe lifecycle events without importing the whole core
-- implementation surface.
module LinearTrace.Core.Events
  ( -- * Core event data
    -- | Event values derived from core trace steps. These retain payload
    -- snapshots and facts needed by query/match logic.
    BlockId
  , BlockRef
  , EventBlock(..)
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
import qualified LinearTrace.Core.Internal as C
import qualified Prelude                   as P
import           Prelude.Linear

type BlockId = C.BlockId

type BlockRef tag = C.BlockRef tag

type TraceBuilderState payload = C.TraceBuilderState payload

type TraceGraphWith payload = C.TraceGraphWith payload

type TraceStep = C.TraceStep

type TraceStepWith payload = C.TraceStepWith payload

data EventBlock tag where
  EventBlock
    :: C.Traceable tag=> { eventBlockRef :: BlockRef tag
                         , eventBlockPayload :: C.Payload tag
                         , eventBlockPayloadView :: C.PayloadView
                         , eventBlockFacts :: C.Facts}
    -> EventBlock tag

data TraceEvent where
  TraceCreate :: EventBlock tag -> TraceEvent
  TraceObserve :: EventBlock tag -> TraceEvent
  TraceUse :: EventBlock tag -> TraceEvent
  TraceCopy :: EventBlock tag -> EventBlock tag -> TraceEvent
  TraceReplace :: EventBlock tag -> EventBlock tag -> TraceEvent
  TraceApply1 :: EventBlock op -> EventBlock arg -> EventBlock out -> TraceEvent
  TraceApply2
    :: EventBlock op
    -> EventBlock lhs
    -> EventBlock rhs
    -> EventBlock out
    -> TraceEvent
  TraceDestroy :: EventBlock tag -> TraceEvent
  TraceSeal :: EventBlock owner -> EventBlock tag -> TraceEvent
  TraceUnseal :: EventBlock owner -> EventBlock tag -> TraceEvent

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
    C.PendingEvents events -> eventLogFromTraceEventSteps events

eventLogFromTraceEventSteps :: C.TraceEventSteps -> EventLog
eventLogFromTraceEventSteps eventSteps =
  case eventSteps of
    C.TraceEventSteps steps ->
      EventLog (P.map traceEventFromTraceEventStep steps)

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
    C.CheckpointStep _label _payload events ->
      eventLogFromTraceEventSteps events
    C.DiscardedStep _reason events -> eventLogFromTraceEventSteps events

blockRefId :: BlockRef tag -> BlockId
blockRefId ref =
  case ref of
    C.BlockRef blockId -> blockId

traceEventFromTraceEventStep :: C.TraceEventStep -> TraceEvent
traceEventFromTraceEventStep step =
  case step of
    C.CreateStep snapshot -> TraceCreate (eventBlockFromSnapshot snapshot)
    C.ObserveStep snapshot -> TraceObserve (eventBlockFromSnapshot snapshot)
    C.UseStep snapshot -> TraceUse (eventBlockFromSnapshot snapshot)
    C.CopyStep original copy' ->
      TraceCopy (eventBlockFromSnapshot original) (eventBlockFromSnapshot copy')
    C.ReplaceStep old output ->
      TraceReplace (eventBlockFromSnapshot old) (eventBlockFromSnapshot output)
    C.Apply1Step op arg output ->
      TraceApply1
        (eventBlockFromSnapshot op)
        (eventBlockFromSnapshot arg)
        (eventBlockFromSnapshot output)
    C.Apply2Step op lhs rhs output ->
      TraceApply2
        (eventBlockFromSnapshot op)
        (eventBlockFromSnapshot lhs)
        (eventBlockFromSnapshot rhs)
        (eventBlockFromSnapshot output)
    C.DestroyStep snapshot -> TraceDestroy (eventBlockFromSnapshot snapshot)
    C.SealStep owner child ->
      TraceSeal (eventBlockFromSnapshot owner) (eventBlockFromSnapshot child)
    C.UnsealStep owner child ->
      TraceUnseal (eventBlockFromSnapshot owner) (eventBlockFromSnapshot child)

eventBlockFromSnapshot :: C.BlockSnapshot tag -> EventBlock tag
eventBlockFromSnapshot snapshot =
  case snapshot of
    C.BlockSnapshot ref payload payloadView facts ->
      EventBlock ref payload payloadView facts
