{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE GADTs                #-}
{-# LANGUAGE LinearTypes          #-}
{-# LANGUAGE RankNTypes           #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

-- | Event projection over the core audit stream. Choreography matching depends
-- on this module to observe lifecycle events without importing the whole core
-- implementation surface.
module LinearTrace.Core.Events
  ( -- * Core event data
    -- | Typed event values derived from core explain tokens. These retain
    -- payload snapshots and facts needed by query/match logic.
    BlockId
  , BlockRef
  , EventBlock(..)
  , TraceEvent(..)
  , EventToken
  , eventTokenFromExplainToken
  , eventTokenEvent
  , EventLog
  , emptyEventLog
  , appendEventToken
  , explainEventLogWith
  , discardEventLog
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
  , -- * Block references
    -- | Block reference helpers used when linking core events to view tags.
    blockRefId
  ) where

import           Control.Functor.Linear    (runState)
import           Data.Kind                 (Type)
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

data TraceEvent act where
  TraceCreate :: EventBlock tag -> TraceEvent (C.Create tag)
  TraceObserve :: EventBlock tag -> TraceEvent (C.Observe tag)
  TraceUse :: EventBlock tag -> TraceEvent (C.Use tag)
  TraceCopy :: EventBlock tag -> EventBlock tag -> TraceEvent (C.Copy tag)
  TraceReplace
    :: EventBlock tag
    -> EventBlock tag
    -> EventBlock tag
    -> TraceEvent (C.Replace tag)
  TraceApply1
    :: EventBlock op
    -> EventBlock arg
    -> EventBlock out
    -> TraceEvent (C.Apply1 op arg out)
  TraceApply2
    :: EventBlock op
    -> EventBlock lhs
    -> EventBlock rhs
    -> EventBlock out
    -> TraceEvent (C.Apply2 op lhs rhs out)
  TraceDestroy :: EventBlock tag -> TraceEvent (C.Destroy tag)
  TraceSeal
    :: EventBlock owner -> EventBlock tag -> TraceEvent (C.Seal owner tag)
  TraceUnseal
    :: EventBlock owner -> EventBlock tag -> TraceEvent (C.Unseal owner tag)

data EventToken act where
  EventToken :: C.AuditStep act -> TraceEvent act -> EventToken act

eventTokenFromExplainToken :: C.ExplainToken act %1 -> Ur (EventToken act)
eventTokenFromExplainToken explainToken =
  case C.explainTokenToAuditStep explainToken of
    Ur step -> Ur (EventToken step (traceEventFromAuditStep step))

eventTokenEvent :: EventToken act -> TraceEvent act
eventTokenEvent token =
  case token of
    EventToken _step event -> event

data EventLog where
  EventLog :: C.Audit acts -> EventLog

emptyEventLog :: EventLog
emptyEventLog = EventLog C.EmptyAudit

appendEventToken :: EventLog -> EventToken act -> EventLog
appendEventToken eventLog token =
  case token of
    EventToken step _event ->
      appendEventLog eventLog (EventLog (step C.:> C.EmptyAudit))

explainEventLogWith ::
     P.String
  -> (forall acts. payload acts)
  -> EventLog
  -> C.TraceBuilderWith payload ()
explainEventLogWith label payload eventLog =
  case eventLog of
    EventLog audit -> C.explainAuditWith label payload audit

discardEventLog :: P.String -> EventLog -> C.TraceBuilderWith payload ()
discardEventLog reason eventLog =
  case eventLog of
    EventLog audit -> C.discardAudit reason audit

emptyTraceBuilderState :: TraceBuilderState payload
emptyTraceBuilderState = C.TraceBuilderState (Ur 0) (Ur []) (Ur [])

runTraceBuilderWithState ::
     C.TraceBuilderWith payload a
     %1 -> TraceBuilderState payload
     %1 -> (a, TraceBuilderState payload)
runTraceBuilderWithState = runState

traceBuilderStateGraph :: TraceBuilderState payload -> TraceGraphWith payload
traceBuilderStateGraph state =
  case state of
    C.TraceBuilderState (Ur _nextBlockId) (Ur blocks) (Ur steps) ->
      C.TraceGraph blocks steps

traceGraphSteps :: TraceGraphWith payload -> [TraceStepWith payload]
traceGraphSteps graph =
  case graph of
    C.TraceGraph _blocks steps -> steps

data TraceStepOutput payload where
  ExplainedTraceStep
    :: P.String -> payload acts -> TraceStep -> TraceStepOutput payload
  DiscardedTraceStep :: P.String -> TraceStep -> TraceStepOutput payload

traceStepOutput :: TraceStepWith payload -> TraceStepOutput payload
traceStepOutput step =
  case step of
    C.ExplainedStep label payload audit ->
      ExplainedTraceStep
        label
        payload
        (C.ExplainedStep label C.NoStepPayload audit)
    C.DiscardedStep reason audit ->
      DiscardedTraceStep reason (C.DiscardedStep reason audit)

blockRefId :: BlockRef tag -> BlockId
blockRefId ref =
  case ref of
    C.BlockRef blockId -> blockId

traceEventFromAuditStep :: C.AuditStep act -> TraceEvent act
traceEventFromAuditStep step =
  case step of
    C.CreateStep snapshot -> TraceCreate (eventBlockFromSnapshot snapshot)
    C.ObserveStep snapshot -> TraceObserve (eventBlockFromSnapshot snapshot)
    C.UseStep snapshot -> TraceUse (eventBlockFromSnapshot snapshot)
    C.CopyStep original copy' ->
      TraceCopy (eventBlockFromSnapshot original) (eventBlockFromSnapshot copy')
    C.ReplaceStep old incoming output ->
      TraceReplace
        (eventBlockFromSnapshot old)
        (eventBlockFromSnapshot incoming)
        (eventBlockFromSnapshot output)
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

type family Append (lhs :: [Type]) (rhs :: [Type]) :: [Type] where
  Append '[] rhs = rhs
  Append (act : acts) rhs = act : Append acts rhs

appendEventLog :: EventLog -> EventLog -> EventLog
appendEventLog lhs rhs =
  case lhs of
    EventLog lhsAudit ->
      case rhs of
        EventLog rhsAudit -> EventLog (appendAudit lhsAudit rhsAudit)

appendAudit :: C.Audit lhs -> C.Audit rhs -> C.Audit (Append lhs rhs)
appendAudit lhs rhs =
  case lhs of
    C.EmptyAudit   -> rhs
    step C.:> rest -> step C.:> appendAudit rest rhs
