{-# LANGUAGE ConstraintKinds         #-}
{-# LANGUAGE DataKinds               #-}
{-# LANGUAGE FlexibleContexts        #-}
{-# LANGUAGE FlexibleInstances       #-}
{-# LANGUAGE GADTs                   #-}
{-# LANGUAGE LinearTypes             #-}
{-# LANGUAGE MultiParamTypeClasses   #-}
{-# LANGUAGE RebindableSyntax        #-}
{-# LANGUAGE ScopedTypeVariables     #-}
{-# LANGUAGE TypeFamilyDependencies  #-}
{-# LANGUAGE TypeOperators           #-}
{-# LANGUAGE UndecidableInstances    #-}
{-# LANGUAGE UndecidableSuperClasses #-}

module LinearTrace.Core.Internal
  ( -- * Core public API data
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
  , Traceable(..)
  , -- * Trusted linear payloads
    LUnit(..)
  , LBool(..)
  , LInt(..)
  , LDouble(..)
  , LString(..)
  , -- * Action vocabulary
    ActionKind(..)
  , Action
  , type Create
  , type Observe
  , type Use
  , type Copy
  , type Replace
  , type Compute
  , type Destroy
  , type Seal
  , type Unseal
  , type Decide
  , -- * Primitive operations
    create
  , createTagged
  , observe
  , use
  , copy
  , replace
  , compute
  , computeTagged
  , destroy
  , seal
  , unseal
  , decide
  , -- * Auditing operations
    OneUse(..)
  , ExplainToken
  , ExplainTokens(..)
  , Created(..)
  , Observed(..)
  , Used(..)
  , Copied(..)
  , Replaced(..)
  , Computed(..)
  , Destroyed(..)
  , Sealed(..)
  , Unsealed(..)
  , Decided(..)
  , (<$>)
  , (<*>)
  , -- * Public graph/step data
    BlockId
  , BlockRef(..)
  , BlockSnapshot(..)
  , BlockRecord(..)
  , TraceBuilderState(..)
  , NoStepPayload(..)
  , TraceStep
  , TraceStepWith(..)
  , -- * Public audit data
    AuditStep(..)
  , Audit(..)
  , explainTokenToAuditStep
  , -- * Runner
    explainAuditWith
  , explainWith
  , discardAudit
  , discard
  , buildGraph
  ) where

import           Control.Functor.Linear hiding (ask, (<$>), (<*>))
import           Data.Kind              (Type)
import           Data.Proxy             (Proxy (..))
import           Data.Typeable          (Typeable, typeRep)
import qualified Prelude                as P
import           Prelude.Linear
import qualified Unsafe.Coerce          as Unsafe

infixl 4 <$>
infixl 4 <*>
infixr 5 :~
infixr 5 :>
type BlockId = Int

type family Payload tag = payload | payload -> tag

data PayloadView = PayloadView
  { payloadKind    :: P.String
  , payloadContent :: P.String
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
-- define new approved payload classes of their own.
class LinearPayload payload where
  payloadDebugContent :: payload -> P.String

data LUnit tag =
  LUnit

newtype LInt tag =
  LInt Int

newtype LBool tag =
  LBool Bool

newtype LDouble tag =
  LDouble Double

newtype LString tag =
  LString P.String

instance LinearPayload (LUnit tag) where
  payloadDebugContent LUnit = "()"

instance LinearPayload (LBool tag) where
  payloadDebugContent (LBool value) = P.show value

instance LinearPayload (LInt tag) where
  payloadDebugContent (LInt value) = P.show value

instance LinearPayload (LDouble tag) where
  payloadDebugContent (LDouble value) = P.show value

instance LinearPayload (LString tag) where
  payloadDebugContent (LString value) = value

class (LinearPayload (Payload tag), Typeable tag) =>
      Traceable tag
  where
  payloadView :: Proxy tag -> Payload tag -> PayloadView
  payloadView tagProxy payload =
    PayloadView
      { payloadKind = P.show (typeRep tagProxy)
      , payloadContent = payloadDebugContent payload
      }

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
    :: BlockRef tag -> Payload tag -> PayloadView -> Facts -> BlockSnapshot tag

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
  | ActionCompute
  | ActionDestroy
  | ActionSeal
  | ActionUnseal
  | ActionDecide

data Action (kind :: ActionKind) tag

data SealTag owner tag

data UnsealTag owner tag

type Create tag = Action 'ActionCreate tag

type Observe tag = Action 'ActionObserve tag

type Use tag = Action 'ActionUse tag

type Copy tag = Action 'ActionCopy tag

type Replace tag = Action 'ActionReplace tag

type Compute tag = Action 'ActionCompute tag

type Destroy tag = Action 'ActionDestroy tag

type Seal owner tag = Action 'ActionSeal (SealTag owner tag)

type Unseal owner tag = Action 'ActionUnseal (UnsealTag owner tag)

type Decide tag = Action 'ActionDecide tag

--------------------------------------------------------------------------------
-- Primitive operation result types
--------------------------------------------------------------------------------
data Created tag where
  Created :: Block tag %1 -> ExplainToken (Create tag) %1 -> Created tag

data Observed tag where
  Observed :: Block tag %1 -> ExplainToken (Observe tag) %1 -> Observed tag

data Used tag where
  Used :: OneUse (Payload tag) %1 -> ExplainToken (Use tag) %1 -> Used tag

data Copied tag where
  Copied
    :: Block tag %1 -> Block tag %1 -> ExplainToken (Copy tag) %1 -> Copied tag

data Replaced tag where
  Replaced :: Block tag %1 -> ExplainToken (Replace tag) %1 -> Replaced tag

data Computed tag where
  Computed :: Block tag %1 -> ExplainToken (Compute tag) %1 -> Computed tag

data Destroyed tag where
  Destroyed :: ExplainToken (Destroy tag) %1 -> Destroyed tag

data Sealed owner tag where
  Sealed
    :: Block owner
       %1 -> Slot owner tag
       %1 -> ExplainToken (Seal owner tag)
       %1 -> Sealed owner tag

data Unsealed owner tag where
  Unsealed
    :: Block owner
       %1 -> Block tag
       %1 -> ExplainToken (Unseal owner tag)
       %1 -> Unsealed owner tag

data Decided tag where
  DecidedTrue :: ExplainToken (Decide tag) %1 -> Decided tag
  DecidedFalse :: ExplainToken (Decide tag) %1 -> Decided tag

--------------------------------------------------------------------------------
-- Audit data
--------------------------------------------------------------------------------
data AuditStep act where
  CreateStep :: BlockSnapshot tag -> AuditStep (Create tag)
  ObserveStep :: BlockSnapshot tag -> AuditStep (Observe tag)
  UseStep :: BlockSnapshot tag -> AuditStep (Use tag)
  CopyStep :: BlockSnapshot tag -> BlockSnapshot tag -> AuditStep (Copy tag)
  ReplaceStep
    :: BlockSnapshot tag
    -> BlockSnapshot tag
    -> BlockSnapshot tag
    -> AuditStep (Replace tag)
  ComputeStep :: BlockSnapshot tag -> AuditStep (Compute tag)
  DestroyStep :: BlockSnapshot tag -> AuditStep (Destroy tag)
  SealStep
    :: BlockSnapshot owner -> BlockSnapshot tag -> AuditStep (Seal owner tag)
  UnsealStep
    :: BlockSnapshot owner -> BlockSnapshot tag -> AuditStep (Unseal owner tag)
  DecideStep :: BlockSnapshot tag -> AuditStep (Decide tag)

data Audit acts where
  EmptyAudit :: Audit '[]
  (:>) :: AuditStep act -> Audit acts -> Audit (act : acts)

data ExplainToken act where
  ExplainToken :: Ur (AuditStep act) %1 -> ExplainToken act

data ExplainTokens acts where
  Done :: ExplainTokens '[]
  (:~)
    :: ExplainToken act
       %1 -> ExplainTokens acts
       %1 -> ExplainTokens (act : acts)

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

data TraceBuilderState payload = TraceBuilderState
  { _nextBlockId :: Ur BlockId
  , _blocks      :: Ur [BlockRecord]
  , _steps       :: Ur [TraceStepWith payload]
  }

type TraceBuilderWith payload a = State (TraceBuilderState payload) a

type TraceBuilder a = TraceBuilderWith NoStepPayload a

instance Consumable (TraceBuilderState payload) where
  consume (TraceBuilderState next blocks steps) =
    consume next `lseq` consume blocks `lseq` consume steps

instance Dupable (TraceBuilderState payload) where
  dup2 (TraceBuilderState next blocks steps) =
    case dup2 next of
      (next1, next2) ->
        case dup2 blocks of
          (blocks1, blocks2) ->
            case dup2 steps of
              (steps1, steps2) ->
                ( TraceBuilderState next1 blocks1 steps1
                , TraceBuilderState next2 blocks2 steps2)

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
  BlockSnapshot ref payload (payloadView tagProxy payload)

makeAuditStep1 ::
     Traceable tag
  => (BlockSnapshot tag -> AuditStep act)
  -> Proxy tag
  -> BlockRef tag
  -> Payload tag
  -> Facts
  -> ExplainToken act
makeAuditStep1 ctor tagProxy ref payload facts =
  ExplainToken (Ur (ctor (makeSnapshot tagProxy ref payload facts)))

makeAuditStep2 ::
     Traceable tag
  => (BlockSnapshot tag -> BlockSnapshot tag -> AuditStep act)
  -> Proxy tag
  -> BlockRef tag
  -> Payload tag
  -> Facts
  -> BlockRef tag
  -> Payload tag
  -> Facts
  -> ExplainToken act
makeAuditStep2 ctor tagProxy ref1 payload1 facts1 ref2 payload2 facts2 =
  ExplainToken
    (Ur
       (ctor
          (makeSnapshot tagProxy ref1 payload1 facts1)
          (makeSnapshot tagProxy ref2 payload2 facts2)))

makeAuditStep3 ::
     Traceable tag
  => (BlockSnapshot tag -> BlockSnapshot tag -> BlockSnapshot tag -> AuditStep
                                                                       act)
  -> Proxy tag
  -> BlockRef tag
  -> Payload tag
  -> Facts
  -> BlockRef tag
  -> Payload tag
  -> Facts
  -> BlockRef tag
  -> Payload tag
  -> Facts
  -> ExplainToken act
makeAuditStep3 ctor tagProxy ref1 payload1 facts1 ref2 payload2 facts2 ref3 payload3 facts3 =
  ExplainToken
    (Ur
       (ctor
          (makeSnapshot tagProxy ref1 payload1 facts1)
          (makeSnapshot tagProxy ref2 payload2 facts2)
          (makeSnapshot tagProxy ref3 payload3 facts3)))

makeAuditStep2Hetero ::
     (Traceable left, Traceable right)
  => (BlockSnapshot left -> BlockSnapshot right -> AuditStep act)
  -> Proxy left
  -> BlockRef left
  -> Payload left
  -> Facts
  -> Proxy right
  -> BlockRef right
  -> Payload right
  -> Facts
  -> ExplainToken act
makeAuditStep2Hetero ctor leftProxy leftRef leftPayload leftFacts rightProxy rightRef rightPayload rightFacts =
  ExplainToken
    (Ur
       (ctor
          (makeSnapshot leftProxy leftRef leftPayload leftFacts)
          (makeSnapshot rightProxy rightRef rightPayload rightFacts)))

explainTokenToAuditStep :: ExplainToken act %1 -> Ur (AuditStep act)
explainTokenToAuditStep (ExplainToken step) = step

explainTokensToAudit :: ExplainTokens acts %1 -> Ur (Audit acts)
explainTokensToAudit Done = Ur EmptyAudit
explainTokensToAudit (explainToken :~ rest) =
  case explainTokenToAuditStep explainToken of
    Ur step ->
      case explainTokensToAudit rest of
        Ur audit -> Ur (step :> audit)

unsafeUr :: forall a. a %1 -> Ur a
unsafeUr = Unsafe.unsafeCoerce (Ur :: a -> Ur a)

allocateBlock ::
     forall payload tag. Traceable tag
  => Proxy tag
  -> Facts
  -> Payload tag
     %1 -> TraceBuilderWith payload (Ur BlockId, Ur (Payload tag))
allocateBlock tagProxy facts payload0 =
  case unsafeUr payload0 of
    Ur payload -> do
      TraceBuilderState (Ur oldNextBlockId) (Ur oldBlocks) oldSteps <- get
      let blockId = oldNextBlockId
      let ref' = makeBlockRef tagProxy blockId
      let snapshot = makeSnapshot tagProxy ref' payload facts
      let blockRecord = BlockRecord snapshot
      put
        (TraceBuilderState
           (Ur (blockId + 1))
           (Ur (oldBlocks P.++ [blockRecord]))
           oldSteps)
      return (Ur blockId, Ur payload)

emitStep :: TraceStepWith payload -> TraceBuilderWith payload ()
emitStep step = do
  TraceBuilderState oldNext oldBlocks (Ur oldSteps) <- get
  put (TraceBuilderState oldNext oldBlocks (Ur (oldSteps P.++ [step])))

explainWith ::
     P.String
  -> payload acts
  -> ExplainTokens acts
     %1 -> TraceBuilderWith payload ()
explainWith label payload explainTokens =
  case explainTokensToAudit explainTokens of
    Ur audit -> explainAuditWith label payload audit

explainAuditWith ::
     P.String -> payload acts -> Audit acts -> TraceBuilderWith payload ()
explainAuditWith label payload audit =
  emitStep (ExplainedStep label payload audit)

discardAudit :: P.String -> Audit acts -> TraceBuilderWith payload ()
discardAudit reason audit = emitStep (DiscardedStep reason audit)

discard :: P.String -> ExplainTokens acts %1 -> TraceBuilderWith payload ()
discard reason explainTokens =
  case explainTokensToAudit explainTokens of
    Ur audit -> discardAudit reason audit

--------------------------------------------------------------------------------
-- Primitive operations
--------------------------------------------------------------------------------
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
createTagged facts payload0 = do
  (Ur blockId, Ur payload) <- allocateBlock (Proxy :: Proxy tag) facts payload0
  let ref' = makeBlockRef (Proxy :: Proxy tag) blockId
  return
    (Created
       (Block (Ur blockId) (Ur payload) (Ur facts))
       (makeAuditStep1 CreateStep (Proxy :: Proxy tag) ref' payload facts))

observe ::
     forall payload tag. Traceable tag
  => Block tag
     %1 -> TraceBuilderWith payload (Observed tag)
observe (Block (Ur blockId) (Ur payload) (Ur facts)) = do
  let ref' = makeBlockRef (Proxy :: Proxy tag) blockId
  return
    (Observed
       (Block (Ur blockId) (Ur payload) (Ur facts))
       (makeAuditStep1 ObserveStep (Proxy :: Proxy tag) ref' payload facts))

use ::
     forall payload tag. Traceable tag
  => Block tag
     %1 -> TraceBuilderWith payload (Used tag)
use (Block (Ur blockId) (Ur payload) (Ur facts)) = do
  let ref' = makeBlockRef (Proxy :: Proxy tag) blockId
  return
    (Used
       (OneUse payload)
       (makeAuditStep1 UseStep (Proxy :: Proxy tag) ref' payload facts))

copy ::
     forall payload tag. Traceable tag
  => Block tag
     %1 -> TraceBuilderWith payload (Copied tag)
copy (Block (Ur originalId) (Ur payload) (Ur facts)) = do
  (Ur copyId, Ur copiedPayload) <-
    allocateBlock (Proxy :: Proxy tag) facts payload
  let originalRef = makeBlockRef (Proxy :: Proxy tag) originalId
  let copyRef = makeBlockRef (Proxy :: Proxy tag) copyId
  return
    (Copied
       (Block (Ur originalId) (Ur payload) (Ur facts))
       (Block (Ur copyId) (Ur copiedPayload) (Ur facts))
       (makeAuditStep2
          CopyStep
          (Proxy :: Proxy tag)
          originalRef
          payload
          facts
          copyRef
          copiedPayload
          facts))

replace ::
     forall payload tag. Traceable tag
  => Block tag
     %1 -> Block tag
     %1 -> TraceBuilderWith payload (Replaced tag)
replace oldBlock incomingBlock =
  case oldBlock of
    Block (Ur oldId) (Ur oldPayload) (Ur oldFacts) ->
      case incomingBlock of
        Block (Ur incomingId) (Ur incomingPayload) (Ur incomingFacts) -> do
          (Ur outputId, Ur outputPayload) <-
            allocateBlock (Proxy :: Proxy tag) incomingFacts incomingPayload
          let oldRef = makeBlockRef (Proxy :: Proxy tag) oldId
          let incomingRef = makeBlockRef (Proxy :: Proxy tag) incomingId
          let outputRef = makeBlockRef (Proxy :: Proxy tag) outputId
          return
            (Replaced
               (Block (Ur outputId) (Ur outputPayload) (Ur incomingFacts))
               (makeAuditStep3
                  ReplaceStep
                  (Proxy :: Proxy tag)
                  oldRef
                  oldPayload
                  oldFacts
                  incomingRef
                  incomingPayload
                  incomingFacts
                  outputRef
                  outputPayload
                  incomingFacts))

compute ::
     forall payload tag. Traceable tag
  => OneUse (Payload tag)
     %1 -> TraceBuilderWith payload (Computed tag)
compute = computeTagged emptyFacts

computeTagged ::
     forall payload tag. Traceable tag
  => Facts
  -> OneUse (Payload tag)
     %1 -> TraceBuilderWith payload (Computed tag)
computeTagged facts (OneUse payload0) = do
  (Ur blockId, Ur payload) <- allocateBlock (Proxy :: Proxy tag) facts payload0
  let ref' = makeBlockRef (Proxy :: Proxy tag) blockId
  return
    (Computed
       (Block (Ur blockId) (Ur payload) (Ur facts))
       (makeAuditStep1 ComputeStep (Proxy :: Proxy tag) ref' payload facts))

destroy ::
     forall payload tag. Traceable tag
  => Block tag
     %1 -> TraceBuilderWith payload (Destroyed tag)
destroy (Block (Ur blockId) (Ur payload) (Ur facts)) = do
  let ref' = makeBlockRef (Proxy :: Proxy tag) blockId
  return
    (Destroyed
       (makeAuditStep1 DestroyStep (Proxy :: Proxy tag) ref' payload facts))

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
          return
            (Sealed
               (Block (Ur ownerId) (Ur ownerPayload) (Ur ownerFacts))
               (Slot (Block (Ur childId) (Ur childPayload) (Ur childFacts)))
               (makeAuditStep2Hetero
                  SealStep
                  (Proxy :: Proxy owner)
                  ownerRef
                  ownerPayload
                  ownerFacts
                  (Proxy :: Proxy tag)
                  childRef
                  childPayload
                  childFacts))

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
              return
                (Unsealed
                   (Block (Ur ownerId) (Ur ownerPayload) (Ur ownerFacts))
                   (Block (Ur childId) (Ur childPayload) (Ur childFacts))
                   (makeAuditStep2Hetero
                      UnsealStep
                      (Proxy :: Proxy owner)
                      ownerRef
                      ownerPayload
                      ownerFacts
                      (Proxy :: Proxy tag)
                      childRef
                      childPayload
                      childFacts))

decide ::
     forall payload tag. Traceable tag
  => (Payload tag %1 -> Bool)
  -> Block tag
     %1 -> TraceBuilderWith payload (Decided tag)
decide predicate (Block (Ur blockId) (Ur payload) (Ur facts)) = do
  let ref' = makeBlockRef (Proxy :: Proxy tag) blockId
  let explainToken =
        makeAuditStep1 DecideStep (Proxy :: Proxy tag) ref' payload facts
  {- HLINT ignore "Use if" -}
  case predicate payload of
    True  -> return (DecidedTrue explainToken)
    False -> return (DecidedFalse explainToken)

--------------------------------------------------------------------------------
-- Runner
--------------------------------------------------------------------------------
buildGraph :: TraceBuilderWith payload () -> TraceGraphWith payload
buildGraph builder =
  let (_, finalState) =
        runState builder (TraceBuilderState (Ur 0) (Ur []) (Ur []))
      TraceBuilderState (Ur _) (Ur finalBlocks) (Ur finalSteps) = finalState
   in TraceGraph finalBlocks finalSteps
