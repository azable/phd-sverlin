{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE GADTs                #-}
{-# LANGUAGE LinearTypes          #-}
{-# LANGUAGE RankNTypes           #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module LinearTrace.Core.Events
  ( -- * Core event data
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
    TraceBuilderState
  , emptyTraceBuilderState
  , runTraceBuilderWithState
  , traceBuilderStateGraph
  , -- * Trace graphs and steps
    TraceGraphWith
  , TraceStep
  , TraceStepWith
  , TraceStepOutput(..)
  , traceGraphSteps
  , traceStepOutput
  , -- * Block references
    blockRefId
  , syntheticBlockRef
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

data EventBlock tag = EventBlock
  { eventBlockRef         :: BlockRef tag
  , eventBlockPayload     :: C.Payload tag
  , eventBlockPayloadView :: C.PayloadView
  , eventBlockFacts       :: C.Facts
  }

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
  TraceCompute :: EventBlock tag -> TraceEvent (C.Compute tag)
  TraceDestroy :: EventBlock tag -> TraceEvent (C.Destroy tag)
  TraceSeal
    :: EventBlock owner -> EventBlock tag -> TraceEvent (C.Seal owner tag)
  TraceUnseal
    :: EventBlock owner -> EventBlock tag -> TraceEvent (C.Unseal owner tag)
  TraceDecide :: EventBlock tag -> TraceEvent (C.Decide tag)

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

syntheticBlockRef :: BlockId -> BlockRef tag
syntheticBlockRef = C.BlockRef

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
    C.ComputeStep snapshot -> TraceCompute (eventBlockFromSnapshot snapshot)
    C.DestroyStep snapshot -> TraceDestroy (eventBlockFromSnapshot snapshot)
    C.SealStep owner child ->
      TraceSeal (eventBlockFromSnapshot owner) (eventBlockFromSnapshot child)
    C.UnsealStep owner child ->
      TraceUnseal (eventBlockFromSnapshot owner) (eventBlockFromSnapshot child)
    C.DecideStep snapshot -> TraceDecide (eventBlockFromSnapshot snapshot)

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
