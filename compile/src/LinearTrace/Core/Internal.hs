{-# LANGUAGE ConstraintKinds         #-}
{-# LANGUAGE DataKinds               #-}
{-# LANGUAGE FlexibleContexts        #-}
{-# LANGUAGE FlexibleInstances       #-}
{-# LANGUAGE FunctionalDependencies  #-}
{-# LANGUAGE GADTs                   #-}
{-# LANGUAGE LinearTypes             #-}
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
    -- explain tokens. Higher layers call these through the public core facade.
    create
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
  , destroy
  , seal
  , unseal
  , -- * Auditing operations
    -- | Explain structure for assembling typed audit chains before they become
    -- graph steps or event logs.
    OneUse(..)
  , Explain
  , ExplainTokens(..)
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
  , -- * Public audit data
    -- | Audited action sequence data. 'LinearTrace.Core.Events' maps this into
    -- typed event values for choreography matching.
    AuditStep(..)
  , Audit(..)
  , explainToAuditStep
  , -- * Runner
    -- | Core runners and graph builders. The choreography layer uses related
    -- stateful machinery to build core and view output together.
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

infixl 4 <$>
infixl 4 <*>
infixr 5 :~
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
data Created tag where
  Created :: Block tag %1 -> Explain (Create tag) %1 -> Created tag

data Observed tag where
  Observed :: Block tag %1 -> Explain (Observe tag) %1 -> Observed tag

data Used tag where
  Used :: OneUse (Payload tag) %1 -> Explain (Use tag) %1 -> Used tag

data Copied tag where
  Copied :: Block tag %1 -> Block tag %1 -> Explain (Copy tag) %1 -> Copied tag

data Replaced tag where
  Replaced :: Block tag %1 -> Explain (Replace tag) %1 -> Replaced tag

data Applied1 op arg where
  Applied1
    :: Block (Apply1Result op arg)
       %1 -> Explain (Apply1 op arg (Apply1Result op arg))
       %1 -> Applied1 op arg

data Applied2 op lhs rhs where
  Applied2
    :: Block (Apply2Result op lhs rhs)
       %1 -> Explain (Apply2 op lhs rhs (Apply2Result op lhs rhs))
       %1 -> Applied2 op lhs rhs

data Destroyed tag where
  Destroyed :: Explain (Destroy tag) %1 -> Destroyed tag

data Sealed owner tag where
  Sealed
    :: Block owner
       %1 -> Slot owner tag
       %1 -> Explain (Seal owner tag)
       %1 -> Sealed owner tag

data Unsealed owner tag where
  Unsealed
    :: Block owner
       %1 -> Block tag
       %1 -> Explain (Unseal owner tag)
       %1 -> Unsealed owner tag

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
  Apply1Step
    :: BlockSnapshot op
    -> BlockSnapshot arg
    -> BlockSnapshot out
    -> AuditStep (Apply1 op arg out)
  Apply2Step
    :: BlockSnapshot op
    -> BlockSnapshot lhs
    -> BlockSnapshot rhs
    -> BlockSnapshot out
    -> AuditStep (Apply2 op lhs rhs out)
  DestroyStep :: BlockSnapshot tag -> AuditStep (Destroy tag)
  SealStep
    :: BlockSnapshot owner -> BlockSnapshot tag -> AuditStep (Seal owner tag)
  UnsealStep
    :: BlockSnapshot owner -> BlockSnapshot tag -> AuditStep (Unseal owner tag)

data Audit acts where
  EmptyAudit :: Audit '[]
  (:>) :: AuditStep act -> Audit acts -> Audit (act : acts)

data Explain act where
  Explain :: Ur (AuditStep act) %1 -> Explain act

data ExplainTokens acts where
  Done :: ExplainTokens '[]
  (:~) :: Explain act %1 -> ExplainTokens acts %1 -> ExplainTokens (act : acts)

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
  BlockSnapshot ref payload (payloadView tagProxy)

makeAuditStep1 ::
     Traceable tag
  => (BlockSnapshot tag -> AuditStep act)
  -> Proxy tag
  -> BlockRef tag
  -> Payload tag
  -> Facts
  -> Explain act
makeAuditStep1 ctor tagProxy ref payload facts =
  Explain (Ur (ctor (makeSnapshot tagProxy ref payload facts)))

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
  -> Explain act
makeAuditStep2 ctor tagProxy ref1 payload1 facts1 ref2 payload2 facts2 =
  Explain
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
  -> Explain act
makeAuditStep3 ctor tagProxy ref1 payload1 facts1 ref2 payload2 facts2 ref3 payload3 facts3 =
  Explain
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
  -> Explain act
makeAuditStep2Hetero ctor leftProxy leftRef leftPayload leftFacts rightProxy rightRef rightPayload rightFacts =
  Explain
    (Ur
       (ctor
          (makeSnapshot leftProxy leftRef leftPayload leftFacts)
          (makeSnapshot rightProxy rightRef rightPayload rightFacts)))

makeAuditStep3Hetero ::
     (Traceable first, Traceable second, Traceable third)
  => (BlockSnapshot first -> BlockSnapshot second -> BlockSnapshot third -> AuditStep
                                                                              act)
  -> Proxy first
  -> BlockRef first
  -> Payload first
  -> Facts
  -> Proxy second
  -> BlockRef second
  -> Payload second
  -> Facts
  -> Proxy third
  -> BlockRef third
  -> Payload third
  -> Facts
  -> Explain act
makeAuditStep3Hetero ctor firstProxy firstRef firstPayload firstFacts secondProxy secondRef secondPayload secondFacts thirdProxy thirdRef thirdPayload thirdFacts =
  Explain
    (Ur
       (ctor
          (makeSnapshot firstProxy firstRef firstPayload firstFacts)
          (makeSnapshot secondProxy secondRef secondPayload secondFacts)
          (makeSnapshot thirdProxy thirdRef thirdPayload thirdFacts)))

makeAuditStep4Hetero ::
     (Traceable first, Traceable second, Traceable third, Traceable fourth)
  => (BlockSnapshot first -> BlockSnapshot second -> BlockSnapshot third -> BlockSnapshot
                                                                              fourth -> AuditStep
                                                                                          act)
  -> Proxy first
  -> BlockRef first
  -> Payload first
  -> Facts
  -> Proxy second
  -> BlockRef second
  -> Payload second
  -> Facts
  -> Proxy third
  -> BlockRef third
  -> Payload third
  -> Facts
  -> Proxy fourth
  -> BlockRef fourth
  -> Payload fourth
  -> Facts
  -> Explain act
makeAuditStep4Hetero ctor firstProxy firstRef firstPayload firstFacts secondProxy secondRef secondPayload secondFacts thirdProxy thirdRef thirdPayload thirdFacts fourthProxy fourthRef fourthPayload fourthFacts =
  Explain
    (Ur
       (ctor
          (makeSnapshot firstProxy firstRef firstPayload firstFacts)
          (makeSnapshot secondProxy secondRef secondPayload secondFacts)
          (makeSnapshot thirdProxy thirdRef thirdPayload thirdFacts)
          (makeSnapshot fourthProxy fourthRef fourthPayload fourthFacts)))

explainToAuditStep :: Explain act %1 -> Ur (AuditStep act)
explainToAuditStep (Explain step) = step

explainTokensToAudit :: ExplainTokens acts %1 -> Ur (Audit acts)
explainTokensToAudit Done = Ur EmptyAudit
explainTokensToAudit (explain :~ rest) =
  case explainToAuditStep explain of
    Ur step ->
      case explainTokensToAudit rest of
        Ur audit -> Ur (step :> audit)

allocateBlock ::
     forall payload tag. Traceable tag
  => Proxy tag
  -> Facts
  -> Payload tag
     %1 -> TraceBuilderWith payload (Ur BlockId, Ur (Payload tag))
allocateBlock tagProxy facts payload0 =
  case persistCorePayload payload0 of
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

copyTagged ::
     forall payload tag. Traceable tag
  => Facts
  -> Block tag
     %1 -> TraceBuilderWith payload (Copied tag)
copyTagged copyFacts (Block (Ur originalId) (Ur payload) (Ur sourceFacts)) = do
  (Ur copyId, Ur copiedPayload) <-
    allocateBlock (Proxy :: Proxy tag) copyFacts payload
  let originalRef = makeBlockRef (Proxy :: Proxy tag) originalId
  let copyRef = makeBlockRef (Proxy :: Proxy tag) copyId
  return
    (Copied
       (Block (Ur originalId) (Ur payload) (Ur sourceFacts))
       (Block (Ur copyId) (Ur copiedPayload) (Ur copyFacts))
       (makeAuditStep2
          CopyStep
          (Proxy :: Proxy tag)
          originalRef
          payload
          sourceFacts
          copyRef
          copiedPayload
          copyFacts))

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
          case persistCorePayload (applyPayload1 opPayload argPayload) of
            Ur outputPayload0 -> do
              let facts = factsUnion baseFacts (selectFacts outputPayload0)
              (Ur outputId, Ur outputPayload) <-
                allocateBlock
                  (Proxy :: Proxy (Apply1Result op arg))
                  facts
                  outputPayload0
              let opRef = makeBlockRef (Proxy :: Proxy op) opId
              let argRef = makeBlockRef (Proxy :: Proxy arg) argId
              let outputRef =
                    makeBlockRef (Proxy :: Proxy (Apply1Result op arg)) outputId
              return
                (Applied1
                   (Block (Ur outputId) (Ur outputPayload) (Ur facts))
                   (makeAuditStep3Hetero
                      Apply1Step
                      (Proxy :: Proxy op)
                      opRef
                      opPayload
                      opFacts
                      (Proxy :: Proxy arg)
                      argRef
                      argPayload
                      argFacts
                      (Proxy :: Proxy (Apply1Result op arg))
                      outputRef
                      outputPayload
                      facts))

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
              case persistCorePayload
                     (applyPayload2 opPayload lhsPayload rhsPayload) of
                Ur outputPayload0 -> do
                  let facts = factsUnion baseFacts (selectFacts outputPayload0)
                  (Ur outputId, Ur outputPayload) <-
                    allocateBlock
                      (Proxy :: Proxy (Apply2Result op lhs rhs))
                      facts
                      outputPayload0
                  let opRef = makeBlockRef (Proxy :: Proxy op) opId
                  let lhsRef = makeBlockRef (Proxy :: Proxy lhs) lhsId
                  let rhsRef = makeBlockRef (Proxy :: Proxy rhs) rhsId
                  let outputRef =
                        makeBlockRef
                          (Proxy :: Proxy (Apply2Result op lhs rhs))
                          outputId
                  return
                    (Applied2
                       (Block (Ur outputId) (Ur outputPayload) (Ur facts))
                       (makeAuditStep4Hetero
                          Apply2Step
                          (Proxy :: Proxy op)
                          opRef
                          opPayload
                          opFacts
                          (Proxy :: Proxy lhs)
                          lhsRef
                          lhsPayload
                          lhsFacts
                          (Proxy :: Proxy rhs)
                          rhsRef
                          rhsPayload
                          rhsFacts
                          (Proxy :: Proxy (Apply2Result op lhs rhs))
                          outputRef
                          outputPayload
                          facts))

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

--------------------------------------------------------------------------------
-- Runner
--------------------------------------------------------------------------------
buildGraph :: TraceBuilderWith payload () -> TraceGraphWith payload
buildGraph builder =
  let (_, finalState) =
        runState builder (TraceBuilderState (Ur 0) (Ur []) (Ur []))
      TraceBuilderState (Ur _) (Ur finalBlocks) (Ur finalSteps) = finalState
   in TraceGraph finalBlocks finalSteps
