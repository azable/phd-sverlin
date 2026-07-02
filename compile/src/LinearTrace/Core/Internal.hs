{-# LANGUAGE ConstraintKinds         #-}
{-# LANGUAGE DataKinds               #-}
{-# LANGUAGE FlexibleContexts        #-}
{-# LANGUAGE FlexibleInstances       #-}
{-# LANGUAGE FunctionalDependencies  #-}
{-# LANGUAGE GADTs                   #-}
{-# LANGUAGE LinearTypes             #-}
{-# LANGUAGE RankNTypes              #-}
{-# LANGUAGE RebindableSyntax        #-}
{-# LANGUAGE ScopedTypeVariables     #-}
{-# LANGUAGE TypeFamilyDependencies  #-}
{-# LANGUAGE TypeOperators           #-}
{-# LANGUAGE UndecidableInstances    #-}
{-# LANGUAGE UndecidableSuperClasses #-}

-- | Implementation surface for the linear trace core. This module is package
-- internal in Cabal; it is imported by the stable 'LinearTrace.Core' facade,
-- the event projection layer, and diagnostic printing where the full graph
-- state is required.
module LinearTrace.Core.Internal
  ( -- * Core public API data
    -- | Trace graph, builder, payload, fact, and traceable definitions. The
    -- public 'LinearTrace.Core' module re-exports the stable subset of these.
    TraceGraph
  , TraceGraphWith(..)
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
    -- | Built-in linearly tracked payload wrappers shared by core,
    -- choreography, examples, and tests.
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
    -- | Type-level action vocabulary used to type audit steps and event
    -- projection. The constructors are consumed by 'LinearTrace.Core.Events'.
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
    -- | Primitive linear operations that update core builder state and produce
    -- pending block obligations. Higher layers call these through the public
    -- core facade.
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
  , -- * Auditing operations
    -- | Result wrappers and linear one-use payload helpers.
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
  , -- * Public graph/step data
    -- | Full graph state and step records needed by event projection and
    -- printers. These remain internal to the package-level public API.
    BlockId
  , BlockRef(..)
  , BlockSnapshot(..)
  , BlockRecord(..)
  , TraceBuilderState(..)
  , NoStepPayload(..)
  , TraceStep
  , TraceStepWith(..)
  , PendingAudit(..)
  , emptyPendingAudit
  , -- * Public trace event data
    -- | Trace event step data. 'LinearTrace.Core.Events' maps this into typed
    -- event values for choreography matching.
    TraceEventStep(..)
  , Audit(..)
  , -- * Runner
    -- | Core runners and graph builders. The choreography layer uses related
    -- stateful machinery to build core and view output together.
    checkpoint
  , checkpointWith
  , explainAuditWith
  , discardAudit
  , discardPending
  , buildGraph
  ) where

import           Control.Functor.Linear hiding (ask, (<$>), (<*>))
import           Data.Kind              (Type)
import           Data.Proxy             (Proxy (..))
import           Data.Typeable          (Typeable, typeRep)
import qualified Prelude                as P
import           Prelude.Linear

infixl 4 <$>
infixl 4 <*>
infixr 5 :>
type BlockId = Int

type family Payload tag = payload | payload -> tag

newtype PayloadView = PayloadView
  { payloadKind :: P.String
  }

data FactValue
  = FactAtom
  | FactSymbol P.String
  | FactInt Int
  deriving (P.Eq, P.Ord, P.Show)

data Fact =
  Fact P.String FactValue
  deriving (P.Eq, P.Ord, P.Show)

newtype Facts =
  Facts [Fact]
  deriving (P.Eq, P.Ord, P.Show)

emptyFacts :: Facts
emptyFacts = Facts []

factAtom :: P.String -> Fact
factAtom name = Fact name FactAtom

factSymbol :: P.String -> P.String -> Fact
factSymbol name value = Fact name (FactSymbol value)

factInt :: P.String -> Int -> Fact
factInt name value = Fact name (FactInt value)

factsUnion :: Facts -> Facts -> Facts
factsUnion lhs rhs =
  case lhs of
    Facts leftFacts ->
      case rhs of
        Facts rightFacts -> Facts (dedupeFacts (leftFacts P.++ rightFacts))

factsToList :: Facts -> [Fact]
factsToList facts =
  case facts of
    Facts values -> values

dedupeFacts :: [Fact] -> [Fact]
dedupeFacts facts =
  case facts of
    [] -> []
    fact:rest ->
      case fact `P.elem` rest of
        True  -> dedupeFacts rest
        False -> fact : dedupeFacts rest

-- Deliberately not exported.
--
-- Downstream DSLs can use LinearTrace-approved payload wrappers, but cannot
-- define new approved payload classes of their own. Core payloads are trusted
-- value payloads that may be persisted into blocks and audit snapshots.
class CorePayload payload where
  corePayloadText :: payload -> P.String
  persistCorePayload :: payload %1 -> Ur payload

data LUnit tag where
  LUnit :: LUnit tag

data LInt tag where
  LInt :: Int %1 -> LInt tag

data LBool tag where
  LBool :: Bool %1 -> LBool tag

data LDouble tag where
  LDouble :: Double %1 -> LDouble tag

data LString tag where
  LString :: P.String %1 -> LString tag

data LOperator operator tag where
  LOperator :: operator %1 -> LOperator operator tag

class CoreOperator operator where
  operatorPayloadText :: operator -> P.String
  persistOperatorPayload :: operator %1 -> Ur operator

class LinearPayload payload value | payload -> value where
  withPayload :: payload %1 -> (value %1 -> result) %1 -> result
  buildPayload :: value %1 -> payload

applyLinear1 ::
     LinearPayload payload value => (value %1 -> output) -> payload %1 -> output
applyLinear1 f payload = withPayload payload f

applyLinear1Into ::
     (LinearPayload input inputValue, LinearPayload output outputValue)
  => (inputValue %1 -> outputValue)
  -> input
     %1 -> output
applyLinear1Into f = applyLinear1 (linearBuild1 f)

linearBuild1 ::
     LinearPayload output outputValue
  => (inputValue %1 -> outputValue)
  -> inputValue
     %1 -> output
linearBuild1 f value = buildPayload (f value)

applyLinear2 ::
     (LinearPayload lhs lhsValue, LinearPayload rhs rhsValue)
  => (lhsValue %1 -> rhsValue %1 -> output)
  -> lhs
     %1 -> rhs
     %1 -> output
applyLinear2 f lhs rhs = withPayload lhs (applyLinear2Right f rhs)

applyLinear2Right ::
     LinearPayload rhs rhsValue
  => (lhsValue %1 -> rhsValue %1 -> output)
  -> rhs
     %1 -> lhsValue
     %1 -> output
applyLinear2Right f rhs lhsValue = withPayload rhs (f lhsValue)

applyLinear2Into ::
     ( LinearPayload lhs lhsValue
     , LinearPayload rhs rhsValue
     , LinearPayload output outputValue
     )
  => (lhsValue %1 -> rhsValue %1 -> outputValue)
  -> lhs
     %1 -> rhs
     %1 -> output
applyLinear2Into f = applyLinear2 (linearBuild2 f)

linearBuild2 ::
     LinearPayload output outputValue
  => (lhsValue %1 -> rhsValue %1 -> outputValue)
  -> lhsValue
     %1 -> rhsValue
     %1 -> output
linearBuild2 f lhsValue rhsValue = buildPayload (f lhsValue rhsValue)

instance CorePayload (LUnit tag) where
  corePayloadText LUnit = "()"
  persistCorePayload LUnit = Ur LUnit

instance CorePayload (LBool tag) where
  corePayloadText (LBool value) = P.show value
  persistCorePayload (LBool value) =
    case move value of
      Ur moved -> Ur (LBool moved)

instance CorePayload (LInt tag) where
  corePayloadText (LInt value) = P.show value
  persistCorePayload (LInt value) =
    case move value of
      Ur moved -> Ur (LInt moved)

instance CorePayload (LDouble tag) where
  corePayloadText (LDouble value) = P.show value
  persistCorePayload (LDouble value) =
    case move value of
      Ur moved -> Ur (LDouble moved)

instance CorePayload (LString tag) where
  corePayloadText (LString value) = value
  persistCorePayload (LString value) =
    case move value of
      Ur moved -> Ur (LString moved)

instance CoreOperator operator => CorePayload (LOperator operator tag) where
  corePayloadText (LOperator operator) = operatorPayloadText operator
  persistCorePayload (LOperator operator) =
    case persistOperatorPayload operator of
      Ur moved -> Ur (LOperator moved)

instance LinearPayload (LUnit tag) () where
  withPayload LUnit k = k ()
  buildPayload () = LUnit

instance LinearPayload (LBool tag) Bool where
  withPayload (LBool value) k = k value
  buildPayload = LBool

instance LinearPayload (LInt tag) Int where
  withPayload (LInt value) k = k value
  buildPayload = LInt

instance LinearPayload (LDouble tag) Double where
  withPayload (LDouble value) k = k value
  buildPayload = LDouble

instance LinearPayload (LString tag) P.String where
  withPayload (LString value) k = k value
  buildPayload = LString

instance LinearPayload (LOperator operator tag) operator where
  withPayload (LOperator operator) k = k operator
  buildPayload = LOperator

class (CorePayload (Payload tag), Typeable tag) =>
      Traceable tag

instance (CorePayload (Payload tag), Typeable tag) => Traceable tag

payloadView :: Traceable tag => Proxy tag -> PayloadView
payloadView tagProxy = PayloadView {payloadKind = P.show (typeRep tagProxy)}

payloadText :: Traceable tag => Payload tag -> P.String
payloadText = corePayloadText

class Applicable1 op arg where
  type Apply1Result op arg :: Type
  applyPayload1 ::
       Payload op %1 -> Payload arg %1 -> Payload (Apply1Result op arg)

class Applicable2 op lhs rhs where
  type Apply2Result op lhs rhs :: Type
  applyPayload2 ::
       Payload op
       %1 -> Payload lhs
       %1 -> Payload rhs
       %1 -> Payload (Apply2Result op lhs rhs)

data OneUse a where
  OneUse :: a %1 -> OneUse a

(<$>) :: (a %1 -> b) %1 -> OneUse a %1 -> OneUse b
f <$> OneUse x = OneUse (f x)

(<*>) :: OneUse (a %1 -> b) %1 -> OneUse a %1 -> OneUse b
OneUse f <*> OneUse x = OneUse (f x)

data BlockRef tag where
  BlockRef :: BlockId -> BlockRef tag

data Block tag where
  Block :: Ur BlockId %1 -> Ur (Payload tag) %1 -> Ur Facts %1 -> Block tag

-- | A sealed block of type @tag@ owned by an owner type @owner@.
--
-- The constructor is intentionally not exported. Users can hold slots, but
-- cannot extract the hidden block except through 'unseal'.
data Slot owner tag where
  Slot :: Block tag %1 -> Slot owner tag

data BlockSnapshot tag where
  BlockSnapshot
    :: Traceable tag=> BlockRef tag
    -> Payload tag
    -> PayloadView
    -> Facts
    -> BlockSnapshot tag

data BlockRecord where
  BlockRecord :: BlockSnapshot tag -> BlockRecord

--------------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------------
data ActionKind
  = ActionCreate
  | ActionObserve
  | ActionUse
  | ActionCopy
  | ActionReplace
  | ActionApply1
  | ActionApply2
  | ActionDestroy
  | ActionSeal
  | ActionUnseal

data Action (kind :: ActionKind) tag

data Apply1Tag op arg out

data Apply2Tag op lhs rhs out

data SealTag owner tag

data UnsealTag owner tag

type Create tag = Action 'ActionCreate tag

type Observe tag = Action 'ActionObserve tag

type Use tag = Action 'ActionUse tag

type Copy tag = Action 'ActionCopy tag

type Replace tag = Action 'ActionReplace tag

type Apply1 op arg out = Action 'ActionApply1 (Apply1Tag op arg out)

type Apply2 op lhs rhs out = Action 'ActionApply2 (Apply2Tag op lhs rhs out)

type Destroy tag = Action 'ActionDestroy tag

type Seal owner tag = Action 'ActionSeal (SealTag owner tag)

type Unseal owner tag = Action 'ActionUnseal (UnsealTag owner tag)

--------------------------------------------------------------------------------
-- Primitive operation result types
--------------------------------------------------------------------------------
data Pending tag where
  PendingCreate :: PendingFacts tag %1 -> Payload tag %1 -> Pending tag
  PendingCopy
    :: BlockSnapshot tag -> PendingFacts tag %1 -> Payload tag %1 -> Pending tag
  PendingReplace
    :: BlockSnapshot tag -> PendingFacts tag %1 -> Payload tag %1 -> Pending tag
  PendingApply1
    :: BlockSnapshot op
    -> BlockSnapshot arg
    -> PendingFacts out
       %1 -> Payload out
       %1 -> Pending out
  PendingApply2
    :: BlockSnapshot op
    -> BlockSnapshot lhs
    -> BlockSnapshot rhs
    -> PendingFacts out
       %1 -> Payload out
       %1 -> Pending out

data PendingFacts tag where
  PendingFacts :: Facts -> (Payload tag -> Facts) -> PendingFacts tag

data Materialization tag where
  Materialization :: Facts -> (Payload tag -> Facts) -> Materialization tag

commitMaterialization :: Materialization tag
commitMaterialization = Materialization emptyFacts (P.const emptyFacts)

taggedMaterialization :: Facts -> Materialization tag
taggedMaterialization facts = Materialization facts (P.const emptyFacts)

selectedMaterialization ::
     Facts -> (Payload tag -> Facts) -> Materialization tag
selectedMaterialization = Materialization

data Created tag where
  Created :: Pending tag %1 -> Created tag

data Observed tag where
  Observed :: Block tag %1 -> Observed tag

data Used tag where
  Used :: OneUse (Payload tag) %1 -> Used tag

data Copied tag where
  Copied :: Block tag %1 -> Pending tag %1 -> Copied tag

data Replaced tag where
  Replaced :: Pending tag %1 -> Replaced tag

data Applied1 op arg where
  Applied1 :: Pending (Apply1Result op arg) %1 -> Applied1 op arg

data Applied2 op lhs rhs where
  Applied2 :: Pending (Apply2Result op lhs rhs) %1 -> Applied2 op lhs rhs

data Destroyed tag where
  Destroyed :: Destroyed tag

data Sealed owner tag where
  Sealed :: Block owner %1 -> Slot owner tag %1 -> Sealed owner tag

data Unsealed owner tag where
  Unsealed :: Block owner %1 -> Block tag %1 -> Unsealed owner tag

--------------------------------------------------------------------------------
-- Trace event data
--------------------------------------------------------------------------------
data TraceEventStep act where
  CreateStep :: BlockSnapshot tag -> TraceEventStep (Create tag)
  ObserveStep :: BlockSnapshot tag -> TraceEventStep (Observe tag)
  UseStep :: BlockSnapshot tag -> TraceEventStep (Use tag)
  CopyStep
    :: BlockSnapshot tag -> BlockSnapshot tag -> TraceEventStep (Copy tag)
  ReplaceStep
    :: BlockSnapshot tag -> BlockSnapshot tag -> TraceEventStep (Replace tag)
  Apply1Step
    :: BlockSnapshot op
    -> BlockSnapshot arg
    -> BlockSnapshot out
    -> TraceEventStep (Apply1 op arg out)
  Apply2Step
    :: BlockSnapshot op
    -> BlockSnapshot lhs
    -> BlockSnapshot rhs
    -> BlockSnapshot out
    -> TraceEventStep (Apply2 op lhs rhs out)
  DestroyStep :: BlockSnapshot tag -> TraceEventStep (Destroy tag)
  SealStep
    :: BlockSnapshot owner
    -> BlockSnapshot tag
    -> TraceEventStep (Seal owner tag)
  UnsealStep
    :: BlockSnapshot owner
    -> BlockSnapshot tag
    -> TraceEventStep (Unseal owner tag)

data Audit acts where
  EmptyAudit :: Audit '[]
  (:>) :: TraceEventStep act -> Audit acts -> Audit (act : acts)

--------------------------------------------------------------------------------
-- Trace step layer
--------------------------------------------------------------------------------
data NoStepPayload (acts :: [Type]) =
  NoStepPayload

data TraceStepWith (payload :: [Type] -> Type) where
  ExplainedStep
    :: P.String -> payload acts -> Audit acts -> TraceStepWith payload
  DiscardedStep :: P.String -> Audit acts -> TraceStepWith payload

type TraceStep = TraceStepWith NoStepPayload

data TraceGraphWith (payload :: [Type] -> Type) =
  TraceGraph [BlockRecord] [TraceStepWith payload]

type TraceGraph = TraceGraphWith NoStepPayload

data PendingAudit where
  PendingAudit :: Audit acts -> PendingAudit

emptyPendingAudit :: PendingAudit
emptyPendingAudit = PendingAudit EmptyAudit

data TraceBuilderState payload = TraceBuilderState
  { _nextBlockId :: Ur BlockId
  , _blocks      :: Ur [BlockRecord]
  , _pending     :: Ur PendingAudit
  , _steps       :: Ur [TraceStepWith payload]
  }

type TraceBuilderWith payload a = State (TraceBuilderState payload) a

type TraceBuilder a = TraceBuilderWith NoStepPayload a

instance Consumable (TraceBuilderState payload) where
  consume (TraceBuilderState next blocks pending steps) =
    consume next
      `lseq` consume blocks
      `lseq` consume pending
      `lseq` consume steps

instance Dupable (TraceBuilderState payload) where
  dup2 (TraceBuilderState next blocks pending steps) =
    case dup2 next of
      (next1, next2) ->
        case dup2 blocks of
          (blocks1, blocks2) ->
            case dup2 pending of
              (pending1, pending2) ->
                case dup2 steps of
                  (steps1, steps2) ->
                    ( TraceBuilderState next1 blocks1 pending1 steps1
                    , TraceBuilderState next2 blocks2 pending2 steps2)

--------------------------------------------------------------------------------
-- Internal helpers
--------------------------------------------------------------------------------
makeBlockRef :: Proxy tag -> BlockId -> BlockRef tag
makeBlockRef _ = BlockRef

makeSnapshot ::
     forall tag. Traceable tag
  => Proxy tag
  -> BlockRef tag
  -> Payload tag
  -> Facts
  -> BlockSnapshot tag
makeSnapshot tagProxy ref payload =
  BlockSnapshot ref payload (payloadView tagProxy)

makeTraceEventStep1 ::
     Traceable tag
  => (BlockSnapshot tag -> TraceEventStep act)
  -> Proxy tag
  -> BlockRef tag
  -> Payload tag
  -> Facts
  -> TraceEventStep act
makeTraceEventStep1 ctor tagProxy ref payload facts =
  ctor (makeSnapshot tagProxy ref payload facts)

makeTraceEventStep2Hetero ::
     (Traceable left, Traceable right)
  => (BlockSnapshot left -> BlockSnapshot right -> TraceEventStep act)
  -> Proxy left
  -> BlockRef left
  -> Payload left
  -> Facts
  -> Proxy right
  -> BlockRef right
  -> Payload right
  -> Facts
  -> TraceEventStep act
makeTraceEventStep2Hetero ctor leftProxy leftRef leftPayload leftFacts rightProxy rightRef rightPayload rightFacts =
  ctor
    (makeSnapshot leftProxy leftRef leftPayload leftFacts)
    (makeSnapshot rightProxy rightRef rightPayload rightFacts)

allocatePersistedBlock ::
     forall payload tag. Traceable tag
  => Proxy tag
  -> Facts
  -> Payload tag
  -> TraceBuilderWith payload (Ur BlockId, Ur (Payload tag))
allocatePersistedBlock tagProxy facts payload = do
  TraceBuilderState (Ur oldNextBlockId) (Ur oldBlocks) oldPending oldSteps <-
    get
  let blockId = oldNextBlockId
  let ref' = makeBlockRef tagProxy blockId
  let snapshot = makeSnapshot tagProxy ref' payload facts
  let blockRecord = BlockRecord snapshot
  put
    (TraceBuilderState
       (Ur (blockId + 1))
       (Ur (oldBlocks P.++ [blockRecord]))
       oldPending
       oldSteps)
  return (Ur blockId, Ur payload)

emitStep :: TraceStepWith payload -> TraceBuilderWith payload ()
emitStep step = do
  TraceBuilderState oldNext oldBlocks oldPending (Ur oldSteps) <- get
  put
    (TraceBuilderState oldNext oldBlocks oldPending (Ur (oldSteps P.++ [step])))

appendPendingTraceEventStep :: TraceEventStep act -> TraceBuilderWith payload ()
appendPendingTraceEventStep step = do
  TraceBuilderState oldNext oldBlocks (Ur oldPending) oldSteps <- get
  put
    (TraceBuilderState
       oldNext
       oldBlocks
       (Ur (appendPendingAudit oldPending step))
       oldSteps)

appendPendingAudit :: PendingAudit -> TraceEventStep act -> PendingAudit
appendPendingAudit pending step =
  case pending of
    PendingAudit audit -> PendingAudit (appendAudit audit (step :> EmptyAudit))

type family Append (lhs :: [Type]) (rhs :: [Type]) :: [Type] where
  Append '[] rhs = rhs
  Append (act : acts) rhs = act : Append acts rhs

appendAudit :: Audit lhs -> Audit rhs -> Audit (Append lhs rhs)
appendAudit lhs rhs =
  case lhs of
    EmptyAudit   -> rhs
    step :> rest -> step :> appendAudit rest rhs

checkpoint :: P.String -> TraceBuilder ()
checkpoint label = checkpointWith label NoStepPayload

checkpointWith ::
     P.String -> (forall acts. payload acts) -> TraceBuilderWith payload ()
checkpointWith label payload = do
  TraceBuilderState oldNext oldBlocks (Ur pending) (Ur oldSteps) <- get
  case pending of
    PendingAudit EmptyAudit ->
      put
        (TraceBuilderState
           oldNext
           oldBlocks
           (Ur emptyPendingAudit)
           (Ur oldSteps))
    PendingAudit audit ->
      put
        (TraceBuilderState
           oldNext
           oldBlocks
           (Ur emptyPendingAudit)
           (Ur (oldSteps P.++ [ExplainedStep label payload audit])))

explainAuditWith ::
     P.String -> payload acts -> Audit acts -> TraceBuilderWith payload ()
explainAuditWith label payload audit =
  emitStep (ExplainedStep label payload audit)

discardAudit :: P.String -> Audit acts -> TraceBuilderWith payload ()
discardAudit reason audit = emitStep (DiscardedStep reason audit)

discardPending :: P.String -> TraceBuilderWith payload ()
discardPending reason = do
  TraceBuilderState oldNext oldBlocks (Ur pending) (Ur oldSteps) <- get
  case pending of
    PendingAudit EmptyAudit ->
      put
        (TraceBuilderState
           oldNext
           oldBlocks
           (Ur emptyPendingAudit)
           (Ur oldSteps))
    PendingAudit audit ->
      put
        (TraceBuilderState
           oldNext
           oldBlocks
           (Ur emptyPendingAudit)
           (Ur (oldSteps P.++ [DiscardedStep reason audit])))

--------------------------------------------------------------------------------
-- Primitive operations
--------------------------------------------------------------------------------
data SnapshottedBlock tag where
  SnapshottedBlock :: Block tag %1 -> BlockSnapshot tag -> SnapshottedBlock tag

snapshotBlock ::
     forall tag. Traceable tag
  => Block tag
     %1 -> SnapshottedBlock tag
snapshotBlock (Block (Ur blockId) (Ur payload) (Ur facts)) =
  let ref' = makeBlockRef (Proxy :: Proxy tag) blockId
      snapshot = makeSnapshot (Proxy :: Proxy tag) ref' payload facts
   in SnapshottedBlock (Block (Ur blockId) (Ur payload) (Ur facts)) snapshot

data PendingPayload tag where
  PendingPayload :: PendingFacts tag %1 -> Payload tag %1 -> PendingPayload tag

pendingPayload :: Pending tag %1 -> PendingPayload tag
pendingPayload pending =
  case pending of
    PendingCreate pendingFacts payload -> PendingPayload pendingFacts payload
    PendingCopy _source pendingFacts payload ->
      PendingPayload pendingFacts payload
    PendingReplace _old pendingFacts payload ->
      PendingPayload pendingFacts payload
    PendingApply1 _op _arg pendingFacts payload ->
      PendingPayload pendingFacts payload
    PendingApply2 _op _lhs _rhs pendingFacts payload ->
      PendingPayload pendingFacts payload

pendingFactsOnly :: Facts -> PendingFacts tag
pendingFactsOnly facts = PendingFacts facts (P.const emptyFacts)

combinedMaterializationFactsFrom ::
     Facts
  -> (Payload tag -> Facts)
  -> Facts
  -> (Payload tag -> Facts)
  -> Payload tag
  -> Facts
combinedMaterializationFactsFrom materialFacts materialSelect pendingBase pendingSelect payload =
  factsUnion
    pendingBase
    (factsUnion
       (pendingSelect payload)
       (factsUnion materialFacts (materialSelect payload)))

materializeOutput ::
     forall payload tag act. Traceable tag
  => Materialization tag
  -> PendingFacts tag
     %1 -> Payload tag
     %1 -> (BlockSnapshot tag -> TraceEventStep act)
  -> TraceBuilderWith payload (Block tag)
materializeOutput materialization pendingFacts payload0 makeStep =
  case materialization of
    Materialization materialFacts materialSelect ->
      case pendingFacts of
        PendingFacts pendingBase pendingSelect ->
          case persistCorePayload payload0 of
            Ur outputPayload -> do
              let outputFacts =
                    combinedMaterializationFactsFrom
                      materialFacts
                      materialSelect
                      pendingBase
                      pendingSelect
                      outputPayload
              (Ur outputId, Ur persistedOutput) <-
                allocatePersistedBlock
                  (Proxy :: Proxy tag)
                  outputFacts
                  outputPayload
              let outputRef = makeBlockRef (Proxy :: Proxy tag) outputId
              let outputSnapshot =
                    makeSnapshot
                      (Proxy :: Proxy tag)
                      outputRef
                      persistedOutput
                      outputFacts
              appendPendingTraceEventStep (makeStep outputSnapshot)
              return (Block (Ur outputId) (Ur persistedOutput) (Ur outputFacts))

materializeWith ::
     forall payload tag. Traceable tag
  => Materialization tag
  -> Pending tag
     %1 -> TraceBuilderWith payload (Block tag)
materializeWith materialization pending =
  case pending of
    PendingCreate pendingFacts payload ->
      materializeOutput materialization pendingFacts payload CreateStep
    PendingCopy source pendingFacts payload ->
      materializeOutput materialization pendingFacts payload (CopyStep source)
    PendingReplace old pendingFacts payload ->
      materializeOutput materialization pendingFacts payload (ReplaceStep old)
    PendingApply1 op arg pendingFacts payload ->
      materializeOutput materialization pendingFacts payload (Apply1Step op arg)
    PendingApply2 op lhs rhs pendingFacts payload ->
      materializeOutput
        materialization
        pendingFacts
        payload
        (Apply2Step op lhs rhs)

materialize ::
     forall payload tag. Traceable tag
  => Pending tag
     %1 -> TraceBuilderWith payload (Block tag)
materialize = materializeWith commitMaterialization

commit ::
     forall payload tag. Traceable tag
  => Pending tag
     %1 -> TraceBuilderWith payload (Block tag)
commit = materialize

materializeTagged ::
     forall payload tag. Traceable tag
  => Facts
  -> Pending tag
     %1 -> TraceBuilderWith payload (Block tag)
materializeTagged facts = materializeWith (taggedMaterialization facts)

materializeTaggedWith ::
     forall payload tag. Traceable tag
  => Facts
  -> (Payload tag -> Facts)
  -> Pending tag
     %1 -> TraceBuilderWith payload (Block tag)
materializeTaggedWith baseFacts selectFacts =
  materializeWith (selectedMaterialization baseFacts selectFacts)

create ::
     forall payload tag. Traceable tag
  => Payload tag
     %1 -> TraceBuilderWith payload (Created tag)
create = createTagged emptyFacts

createTagged ::
     forall payload tag. Traceable tag
  => Facts
  -> Payload tag
     %1 -> TraceBuilderWith payload (Created tag)
createTagged facts payload0 =
  return (Created (PendingCreate (pendingFactsOnly facts) payload0))

observe ::
     forall payload tag. Traceable tag
  => Block tag
     %1 -> TraceBuilderWith payload (Observed tag)
observe block =
  case snapshotBlock block of
    SnapshottedBlock nextBlock snapshot -> do
      appendPendingTraceEventStep (ObserveStep snapshot)
      return (Observed nextBlock)

use ::
     forall payload tag. Traceable tag
  => Block tag
     %1 -> TraceBuilderWith payload (Used tag)
use (Block (Ur blockId) (Ur payload) (Ur facts)) = do
  let ref' = makeBlockRef (Proxy :: Proxy tag) blockId
  appendPendingTraceEventStep
    (makeTraceEventStep1 UseStep (Proxy :: Proxy tag) ref' payload facts)
  return (Used (OneUse payload))

copy ::
     forall payload tag. Traceable tag
  => Block tag
     %1 -> TraceBuilderWith payload (Copied tag)
copy = copyTagged emptyFacts

copyTagged ::
     forall payload tag. Traceable tag
  => Facts
  -> Block tag
     %1 -> TraceBuilderWith payload (Copied tag)
copyTagged copyFacts block =
  case snapshotBlock block of
    SnapshottedBlock original snapshot ->
      case original of
        Block (Ur originalId) (Ur payload) (Ur sourceFacts) ->
          return
            (Copied
               (Block (Ur originalId) (Ur payload) (Ur sourceFacts))
               (PendingCopy snapshot (pendingFactsOnly copyFacts) payload))

replace ::
     forall payload tag. Traceable tag
  => Block tag
     %1 -> Pending tag
     %1 -> TraceBuilderWith payload (Replaced tag)
replace (Block (Ur oldId) (Ur oldPayload) (Ur oldFacts)) incomingPending =
  let oldRef = makeBlockRef (Proxy :: Proxy tag) oldId
      oldSnapshot = makeSnapshot (Proxy :: Proxy tag) oldRef oldPayload oldFacts
   in case pendingPayload incomingPending of
        PendingPayload pendingFacts payload ->
          return (Replaced (PendingReplace oldSnapshot pendingFacts payload))

apply1 ::
     forall payload op arg.
     ( Applicable1 op arg
     , Traceable op
     , Traceable arg
     , Traceable (Apply1Result op arg)
     )
  => Block op
     %1 -> Block arg
     %1 -> TraceBuilderWith payload (Applied1 op arg)
apply1 = apply1Tagged emptyFacts

apply1Tagged ::
     forall payload op arg.
     ( Applicable1 op arg
     , Traceable op
     , Traceable arg
     , Traceable (Apply1Result op arg)
     )
  => Facts
  -> Block op
     %1 -> Block arg
     %1 -> TraceBuilderWith payload (Applied1 op arg)
apply1Tagged facts = apply1TaggedWith facts (P.const emptyFacts)

apply1TaggedWith ::
     forall payload op arg.
     ( Applicable1 op arg
     , Traceable op
     , Traceable arg
     , Traceable (Apply1Result op arg)
     )
  => Facts
  -> (Payload (Apply1Result op arg) -> Facts)
  -> Block op
     %1 -> Block arg
     %1 -> TraceBuilderWith payload (Applied1 op arg)
apply1TaggedWith baseFacts selectFacts opBlock argBlock =
  case opBlock of
    Block (Ur opId) (Ur opPayload) (Ur opFacts) ->
      case argBlock of
        Block (Ur argId) (Ur argPayload) (Ur argFacts) ->
          let opRef = makeBlockRef (Proxy :: Proxy op) opId
              argRef = makeBlockRef (Proxy :: Proxy arg) argId
              opSnapshot =
                makeSnapshot (Proxy :: Proxy op) opRef opPayload opFacts
              argSnapshot =
                makeSnapshot (Proxy :: Proxy arg) argRef argPayload argFacts
              outputPayload = applyPayload1 opPayload argPayload
           in return
                (Applied1
                   (PendingApply1
                      opSnapshot
                      argSnapshot
                      (PendingFacts baseFacts selectFacts)
                      outputPayload))

apply2 ::
     forall payload op lhs rhs.
     ( Applicable2 op lhs rhs
     , Traceable op
     , Traceable lhs
     , Traceable rhs
     , Traceable (Apply2Result op lhs rhs)
     )
  => Block op
     %1 -> Block lhs
     %1 -> Block rhs
     %1 -> TraceBuilderWith payload (Applied2 op lhs rhs)
apply2 = apply2Tagged emptyFacts

apply2Tagged ::
     forall payload op lhs rhs.
     ( Applicable2 op lhs rhs
     , Traceable op
     , Traceable lhs
     , Traceable rhs
     , Traceable (Apply2Result op lhs rhs)
     )
  => Facts
  -> Block op
     %1 -> Block lhs
     %1 -> Block rhs
     %1 -> TraceBuilderWith payload (Applied2 op lhs rhs)
apply2Tagged facts = apply2TaggedWith facts (P.const emptyFacts)

apply2TaggedWith ::
     forall payload op lhs rhs.
     ( Applicable2 op lhs rhs
     , Traceable op
     , Traceable lhs
     , Traceable rhs
     , Traceable (Apply2Result op lhs rhs)
     )
  => Facts
  -> (Payload (Apply2Result op lhs rhs) -> Facts)
  -> Block op
     %1 -> Block lhs
     %1 -> Block rhs
     %1 -> TraceBuilderWith payload (Applied2 op lhs rhs)
apply2TaggedWith baseFacts selectFacts opBlock lhsBlock rhsBlock =
  case opBlock of
    Block (Ur opId) (Ur opPayload) (Ur opFacts) ->
      case lhsBlock of
        Block (Ur lhsId) (Ur lhsPayload) (Ur lhsFacts) ->
          case rhsBlock of
            Block (Ur rhsId) (Ur rhsPayload) (Ur rhsFacts) ->
              let opRef = makeBlockRef (Proxy :: Proxy op) opId
                  lhsRef = makeBlockRef (Proxy :: Proxy lhs) lhsId
                  rhsRef = makeBlockRef (Proxy :: Proxy rhs) rhsId
                  opSnapshot =
                    makeSnapshot (Proxy :: Proxy op) opRef opPayload opFacts
                  lhsSnapshot =
                    makeSnapshot (Proxy :: Proxy lhs) lhsRef lhsPayload lhsFacts
                  rhsSnapshot =
                    makeSnapshot (Proxy :: Proxy rhs) rhsRef rhsPayload rhsFacts
                  outputPayload = applyPayload2 opPayload lhsPayload rhsPayload
               in return
                    (Applied2
                       (PendingApply2
                          opSnapshot
                          lhsSnapshot
                          rhsSnapshot
                          (PendingFacts baseFacts selectFacts)
                          outputPayload))

destroy ::
     forall payload tag. Traceable tag
  => Block tag
     %1 -> TraceBuilderWith payload (Destroyed tag)
destroy (Block (Ur blockId) (Ur payload) (Ur facts)) = do
  let ref' = makeBlockRef (Proxy :: Proxy tag) blockId
  appendPendingTraceEventStep
    (makeTraceEventStep1 DestroyStep (Proxy :: Proxy tag) ref' payload facts)
  return Destroyed

seal ::
     forall payload owner tag. (Traceable owner, Traceable tag)
  => Block owner
     %1 -> Block tag
     %1 -> TraceBuilderWith payload (Sealed owner tag)
seal ownerBlock childBlock =
  case ownerBlock of
    Block (Ur ownerId) (Ur ownerPayload) (Ur ownerFacts) ->
      case childBlock of
        Block (Ur childId) (Ur childPayload) (Ur childFacts) -> do
          let ownerRef = makeBlockRef (Proxy :: Proxy owner) ownerId
          let childRef = makeBlockRef (Proxy :: Proxy tag) childId
          appendPendingTraceEventStep
            (makeTraceEventStep2Hetero
               SealStep
               (Proxy :: Proxy owner)
               ownerRef
               ownerPayload
               ownerFacts
               (Proxy :: Proxy tag)
               childRef
               childPayload
               childFacts)
          return
            (Sealed
               (Block (Ur ownerId) (Ur ownerPayload) (Ur ownerFacts))
               (Slot (Block (Ur childId) (Ur childPayload) (Ur childFacts))))

unseal ::
     forall payload owner tag. (Traceable owner, Traceable tag)
  => Block owner
     %1 -> Slot owner tag
     %1 -> TraceBuilderWith payload (Unsealed owner tag)
unseal ownerBlock slot =
  case ownerBlock of
    Block (Ur ownerId) (Ur ownerPayload) (Ur ownerFacts) ->
      case slot of
        Slot childBlock ->
          case childBlock of
            Block (Ur childId) (Ur childPayload) (Ur childFacts) -> do
              let ownerRef = makeBlockRef (Proxy :: Proxy owner) ownerId
              let childRef = makeBlockRef (Proxy :: Proxy tag) childId
              appendPendingTraceEventStep
                (makeTraceEventStep2Hetero
                   UnsealStep
                   (Proxy :: Proxy owner)
                   ownerRef
                   ownerPayload
                   ownerFacts
                   (Proxy :: Proxy tag)
                   childRef
                   childPayload
                   childFacts)
              return
                (Unsealed
                   (Block (Ur ownerId) (Ur ownerPayload) (Ur ownerFacts))
                   (Block (Ur childId) (Ur childPayload) (Ur childFacts)))

--------------------------------------------------------------------------------
-- Runner
--------------------------------------------------------------------------------
buildGraph :: TraceBuilderWith payload () -> TraceGraphWith payload
buildGraph builder =
  let (_, finalState) =
        runState
          builder
          (TraceBuilderState (Ur 0) (Ur []) (Ur emptyPendingAudit) (Ur []))
      TraceBuilderState (Ur _) (Ur finalBlocks) _pending (Ur finalSteps) =
        finalState
   in TraceGraph finalBlocks finalSteps
