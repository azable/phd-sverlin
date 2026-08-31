{-# LANGUAGE AllowAmbiguousTypes     #-}
{-# LANGUAGE DataKinds               #-}
{-# LANGUAGE FlexibleContexts        #-}
{-# LANGUAGE FlexibleInstances       #-}
{-# LANGUAGE GADTs                   #-}
{-# LANGUAGE LinearTypes             #-}
{-# LANGUAGE MultiParamTypeClasses   #-}
{-# LANGUAGE NoImplicitPrelude       #-}
{-# LANGUAGE RebindableSyntax        #-}
{-# LANGUAGE ScopedTypeVariables     #-}
{-# LANGUAGE TypeApplications        #-}
{-# LANGUAGE TypeFamilyDependencies  #-}
{-# LANGUAGE TypeOperators           #-}
{-# LANGUAGE UndecidableInstances    #-}
{-# LANGUAGE UndecidableSuperClasses #-}

-- | Private semantic implementation behind the authored @Sverlin@ facade.
--
-- Domain and Program share one trace state, but their distinct wrappers and
-- closed construction instances keep algorithm-only operations out of Domain.
-- Render consumes the immutable 'SemanticTrace'; it never observes the old
-- fact/query representation.
module Sverlin.Internal.Semantic
  ( -- * Builders and managed binding
    Domain
  , Program
  , domainBind
  , domainPure
  , domainFail
  , programBind
  , programPure
  , programFail
  , -- * Typed vocabulary
    Kind
  , kind
  , kindIdentity
  , kindTypeIdentity
  , declareKind
  , RelationKind
  , orderedRelation
  , symmetricRelation
  , relationIdentity
  , relationSourceTypeIdentity
  , relationTargetTypeIdentity
  , relationDirection
  , declareRelation
  , declareSteps
  , -- * Scenario generation
    Generator
  , GeneratorDecision(..)
  , between
  , elementOf
  , weighted
  , listOf
  , shuffle
  , variable
  , -- * Payloads and operators
    Traceable(Payload)
  , LUnit(..)
  , LBool(..)
  , LInt(..)
  , LDouble(..)
  , LString(..)
  , LOperator(..)
  , Applicable1(..)
  , Applicable2(..)
  , -- * Linear resources and results
    Block
  , Pending
  , Slot
  , Create(..)
  , Use(..)
  , Copy(..)
  , Replace(..)
  , Apply1(..)
  , Apply2(..)
  , Destroy(..)
  , Seal(..)
  , Unseal(..)
  , Relate(..)
  , create
  , materialize
  , seal
  , relate
  , copy
  , use
  , apply1
  , apply2
  , replace
  , destroy
  , unseal
  , step
  , -- * Compiler execution and projection
    runSemanticScenario
  , SemanticTrace(..)
  , TraceMarker(..)
  , BlockId(..)
  , TraceBlock(..)
  , TraceOccupancy(..)
  , RelationDirection(..)
  , TraceRelation(..)
  , StepOccurrence(..)
  , TraceEvent(..)
  , MaterializationOrigin(..)
  , VariableTranscript(..)
  ) where

import           Control.Functor.Linear              hiding ((<$>), (<*>))
import           Data.Char                           (ord)
import           Data.Kind                           (Type)
import qualified Data.Map.Strict                     as Map
import           Data.Maybe                          (isNothing)
import           Data.Proxy                          (Proxy (..))
import           Data.Typeable                       (Typeable)
import           GHC.Exts                            (Multiplicity (One))
import qualified Prelude                             as P
import           Prelude.Linear
import           Sverlin.Internal.Semantic.Generator (Generator,
                                                      GeneratorDecision (..),
                                                      GeneratorFailure (..),
                                                      between, elementOf,
                                                      listOf, runGenerator,
                                                      shuffle, weighted)
import qualified Sverlin.Syntax                      as Syntax
import           Type.Reflection                     (SomeTypeRep, someTypeRep)

--------------------------------------------------------------------------------
-- Stable typed markers and declarations
--------------------------------------------------------------------------------
newtype MarkerKey =
  MarkerKey SomeTypeRep
  deriving (P.Eq, P.Ord)

newtype TraceMarker = TraceMarker
  { traceMarkerType :: P.String
  } deriving (P.Eq, P.Ord, P.Show)

markerKey ::
     forall marker. Typeable marker
  => MarkerKey
markerKey = MarkerKey (someTypeRep (Proxy @marker))

markerView :: MarkerKey -> TraceMarker
markerView (MarkerKey representation) =
  TraceMarker {traceMarkerType = P.show representation}

data Kind tag where
  Kind :: Traceable tag => MarkerKey -> MarkerKey -> Kind tag

kind ::
     forall identity tag. (Typeable identity, Traceable tag)
  => Kind tag
kind = Kind (markerKey @identity) (markerKey @tag)

kindIdentity :: Kind tag -> P.String
kindIdentity (Kind identity _) = traceMarkerType (markerView identity)

kindTypeIdentity :: Kind tag -> P.String
kindTypeIdentity (Kind _ tagType) = traceMarkerType (markerView tagType)

data RelationDirection
  = OrderedRelation
  | SymmetricRelation
  deriving (P.Eq, P.Ord, P.Show)

data RelationKind source target where
  RelationKind
    :: (Traceable source, Traceable target)=> MarkerKey
    -> MarkerKey
    -> MarkerKey
    -> RelationDirection
    -> RelationKind source target

orderedRelation ::
     forall identity source target.
     (Typeable identity, Traceable source, Traceable target)
  => RelationKind source target
orderedRelation =
  RelationKind
    (markerKey @identity)
    (markerKey @source)
    (markerKey @target)
    OrderedRelation

symmetricRelation ::
     forall identity node. (Typeable identity, Traceable node)
  => RelationKind node node
symmetricRelation =
  RelationKind
    (markerKey @identity)
    (markerKey @node)
    (markerKey @node)
    SymmetricRelation

relationIdentity :: RelationKind source target -> P.String
relationIdentity (RelationKind identity _ _ _) =
  traceMarkerType (markerView identity)

relationSourceTypeIdentity :: RelationKind source target -> P.String
relationSourceTypeIdentity (RelationKind _ sourceType _ _) =
  traceMarkerType (markerView sourceType)

relationTargetTypeIdentity :: RelationKind source target -> P.String
relationTargetTypeIdentity (RelationKind _ _ targetType _) =
  traceMarkerType (markerView targetType)

relationDirection :: RelationKind source target -> RelationDirection
relationDirection (RelationKind _ _ _ direction) = direction

data DeclarationCategory
  = KindCategory TraceMarker
  | RelationCategory TraceMarker TraceMarker RelationDirection
  | VariableCategory
  | StepCategory
  deriving (P.Eq, P.Show)

class StepList (steps :: [Type]) where
  stepMarkerKeys :: Proxy steps -> [MarkerKey]

instance StepList '[] where
  stepMarkerKeys _ = []

instance (Typeable stepName, StepList rest) => StepList (stepName : rest) where
  stepMarkerKeys _ = markerKey @stepName : stepMarkerKeys (Proxy @rest)

--------------------------------------------------------------------------------
-- Trusted payload storage
--------------------------------------------------------------------------------
data LUnit tag where
  LUnit :: LUnit tag

data LBool tag where
  LBool :: P.Bool %1 -> LBool tag

data LInt tag where
  LInt :: P.Int %1 -> LInt tag

data LDouble tag where
  LDouble :: P.Double %1 -> LDouble tag

data LString tag where
  LString :: P.String %1 -> LString tag

data LOperator tag where
  LOperator :: LOperator tag

class PersistablePayload payload where
  persistPayload :: payload %1 -> Ur payload
  describePayload :: payload -> (P.String, P.Maybe P.Double)

instance PersistablePayload (LUnit tag) where
  persistPayload LUnit = Ur LUnit
  describePayload LUnit = ("()", P.Nothing)

instance PersistablePayload (LBool tag) where
  persistPayload (LBool value) =
    case move value of
      Ur moved -> Ur (LBool moved)
  describePayload (LBool value) = (P.show value, P.Nothing)

instance PersistablePayload (LInt tag) where
  persistPayload (LInt value) =
    case move value of
      Ur moved -> Ur (LInt moved)
  describePayload (LInt value) = (P.show value, P.Just (P.fromIntegral value))

instance PersistablePayload (LDouble tag) where
  persistPayload (LDouble value) =
    case move value of
      Ur moved ->
        case P.isNaN moved P.|| P.isInfinite moved of
          P.True  -> semanticError "LDouble payloads must be finite"
          P.False -> Ur (LDouble moved)
  describePayload (LDouble value) = (P.show value, P.Just value)

instance PersistablePayload (LString tag) where
  persistPayload (LString value) =
    case move value of
      Ur moved -> Ur (LString moved)
  describePayload (LString value) = (value, P.Nothing)

instance PersistablePayload (LOperator tag) where
  persistPayload LOperator = Ur LOperator
  describePayload LOperator = ("operator", P.Nothing)

class (Typeable tag, PersistablePayload (Payload tag)) =>
      Traceable tag
  where
  type Payload tag = payload | payload -> tag

class Applicable1 operator argument where
  type Apply1Result operator argument
  applyPayload1 ::
       Payload operator
       %1 -> Payload argument
       %1 -> Payload (Apply1Result operator argument)

class Applicable2 operator left right where
  type Apply2Result operator left right
  applyPayload2 ::
       Payload operator
       %1 -> Payload left
       %1 -> Payload right
       %1 -> Payload (Apply2Result operator left right)

--------------------------------------------------------------------------------
-- Immutable compiler projection
--------------------------------------------------------------------------------
newtype BlockId = BlockId
  { blockIdInt :: P.Int
  } deriving (P.Eq, P.Ord, P.Show)

data TraceOccupancy = TraceOccupancy
  { traceOccupant       :: BlockId
  , traceOccupancyStart :: P.Int
  , traceOccupancyEnd   :: P.Maybe P.Int
  } deriving (P.Eq, P.Show)

data TraceBlock = TraceBlock
  { traceBlockId            :: BlockId
  , traceBlockKind          :: TraceMarker
  , traceBlockType          :: TraceMarker
  , traceBlockPayloadText   :: P.String
  , traceBlockPayloadScalar :: P.Maybe P.Double
  , traceBlockBorn          :: P.Int
  , traceBlockEnded         :: P.Maybe P.Int
  , traceBlockOccupancies   :: [TraceOccupancy]
  } deriving (P.Eq, P.Show)

data MaterializationOrigin
  = CreatedOrigin
  | CopiedOrigin BlockId
  | ReplacedOrigin BlockId
  | Applied1Origin BlockId BlockId
  | Applied2Origin BlockId BlockId BlockId
  deriving (P.Eq, P.Show)

data TraceEvent
  = TraceMaterialized P.Int BlockId MaterializationOrigin
  | TraceUsed P.Int BlockId
  | TraceDestroyed P.Int BlockId
  | TraceSealed P.Int BlockId BlockId
  | TraceUnsealed P.Int BlockId BlockId
  | TraceRelated P.Int P.Int
  deriving (P.Eq, P.Show)

data TraceRelation = TraceRelation
  { traceRelationId        :: P.Int
  , traceRelationKind      :: TraceMarker
  , traceRelationDirection :: RelationDirection
  , traceRelationSource    :: BlockId
  , traceRelationTarget    :: BlockId
  , traceRelationStart     :: P.Int
  , traceRelationEnd       :: P.Maybe P.Int
  } deriving (P.Eq, P.Show)

data StepOccurrence = StepOccurrence
  { stepOccurrenceDefinition :: TraceMarker
  , stepOccurrencePath       :: [P.Int]
  , stepOccurrenceStart      :: P.Int
  , stepOccurrenceEnd        :: P.Int
  } deriving (P.Eq, P.Show)

data VariableTranscript = VariableTranscript
  { variableTranscriptMarker    :: TraceMarker
  , variableTranscriptSubseed   :: P.Int
  , variableTranscriptDecisions :: [GeneratorDecision]
  } deriving (P.Eq, P.Show)

data SemanticTrace = SemanticTrace
  { semanticTraceScenarioSeed :: P.Int
  , semanticTraceDeclarations :: [(TraceMarker, P.String)]
  , semanticTraceVariables    :: [VariableTranscript]
  , semanticTraceBlocks       :: [TraceBlock]
  , semanticTraceRelations    :: [TraceRelation]
  , semanticTraceSteps        :: [StepOccurrence]
  , semanticTraceEvents       :: [TraceEvent]
  } deriving (P.Eq, P.Show)

--------------------------------------------------------------------------------
-- Linear authored resources
--------------------------------------------------------------------------------
data Block tag where
  Block
    :: Ur BlockId
       %1 -> Ur MarkerKey
       %1 -> Ur MarkerKey
       %1 -> Ur (Payload tag)
       %1 -> Block tag

data Pending tag where
  Pending :: Payload tag %1 -> Ur MaterializationOrigin %1 -> Pending tag

data Slot owner value where
  Slot :: Ur BlockId %1 -> Block value %1 -> Slot owner value

data Create tag where
  Create :: Pending tag %1 -> Create tag

data Use tag where
  Use :: Payload tag %1 -> Use tag

data Copy tag where
  Copy :: Block tag %1 -> Pending tag %1 -> Copy tag

data Replace tag where
  Replace :: Pending tag %1 -> Replace tag

data Apply1 operator argument where
  Apply1
    :: Pending (Apply1Result operator argument) %1 -> Apply1 operator argument

data Apply2 operator left right where
  Apply2
    :: Pending (Apply2Result operator left right)
       %1 -> Apply2 operator left right

data Destroy tag where
  Destroy :: Destroy tag

data Seal owner value where
  Seal :: Block owner %1 -> Slot owner value %1 -> Seal owner value

data Unseal owner value where
  Unseal :: Block owner %1 -> Block value %1 -> Unseal owner value

data Relate source sourceValue target targetValue where
  Relate
    :: Slot source sourceValue
       %1 -> Slot target targetValue
       %1 -> Relate source sourceValue target targetValue

--------------------------------------------------------------------------------
-- Shared builder state
--------------------------------------------------------------------------------
data RelationKey =
  RelationKey MarkerKey BlockId BlockId
  deriving (P.Eq, P.Ord)

data OpenStep = OpenStep
  { openStepPath      :: [P.Int]
  , openStepNextChild :: P.Int
  }

data SemanticStore = SemanticStore
  { storeScenarioSeed    :: P.Int
  , storeNextBlock       :: P.Int
  , storeNextEvent       :: P.Int
  , storeNextRelation    :: P.Int
  , storeRegistry        :: Map.Map MarkerKey DeclarationCategory
  , storeVariables       :: [VariableTranscript]
  , storeBlocks          :: Map.Map BlockId TraceBlock
  , storeSlots           :: Map.Map BlockId BlockId
  , storeActiveRelations :: Map.Map RelationKey P.Int
  , storeRelations       :: Map.Map P.Int TraceRelation
  , storeOpenSteps       :: [OpenStep]
  , storeRootNextStep    :: P.Int
  , storeSteps           :: [StepOccurrence]
  , storeEvents          :: [TraceEvent]
  }

newtype SemanticState =
  SemanticState (Ur SemanticStore)

instance Consumable SemanticState where
  consume (SemanticState store) = consume store

instance Dupable SemanticState where
  dup2 (SemanticState store) =
    case dup2 store of
      (left, right) -> (SemanticState left, SemanticState right)

data Domain value where
  Domain :: State SemanticState value %1 -> Domain value

data Program value where
  Program :: State SemanticState value %1 -> Program value

domainBind :: Domain value %1 -> (value %1 -> Domain result) %1 -> Domain result
domainBind (Domain action) continue =
  Domain
    (action
       >>= (\value ->
              case continue value of
                Domain next -> next))

domainPure :: value %1 -> Domain value
domainPure value = Domain (return value)

domainFail :: P.String -> Domain value
domainFail = semanticError

programBind ::
     Program value %1 -> (value %1 -> Program result) %1 -> Program result
programBind (Program action) continue =
  Program
    (action
       >>= (\value ->
              case continue value of
                Program next -> next))

programPure :: value %1 -> Program value
programPure value = Program (return value)

programFail :: P.String -> Program value
programFail = semanticError

instance Syntax.Rebind 'One Domain where
  rebind = domainBind
  repure = domainPure
  refail = domainFail

instance Syntax.Rebind 'One Program where
  rebind = programBind
  repure = programPure
  refail = programFail

--------------------------------------------------------------------------------
-- Domain declarations and generation
--------------------------------------------------------------------------------
declareKind :: Kind tag -> Domain ()
declareKind (Kind identity tagType) =
  Domain (registerMarker identity (KindCategory (markerView tagType)))

declareRelation :: RelationKind source target -> Domain ()
declareRelation (RelationKind identity sourceType targetType direction) =
  Domain
    (registerMarker
       identity
       (RelationCategory
          (markerView sourceType)
          (markerView targetType)
          direction))

declareSteps ::
     forall steps. StepList steps
  => Domain ()
declareSteps = Domain (registerStepMarkers (stepMarkerKeys (Proxy @steps)))

variable ::
     forall identity value. Typeable identity
  => Generator value
  -> Domain value
variable generator =
  Domain $ do
    SemanticState (Ur store) <- get
    let identity = markerKey @identity
    assertState (ensureMarkerUnused identity (storeRegistry store))
    let subseed = markerSubseed (storeScenarioSeed store) identity
    case runGenerator subseed generator of
      P.Left (GeneratorFailure message) ->
        semanticError
          ("generator "
             P.++ traceMarkerType (markerView identity)
             P.++ " is invalid: "
             P.++ message)
      P.Right (value, decisions) -> do
        let transcript =
              VariableTranscript
                { variableTranscriptMarker = markerView identity
                , variableTranscriptSubseed = subseed
                , variableTranscriptDecisions = decisions
                }
            updated =
              store
                { storeRegistry =
                    Map.insert identity VariableCategory (storeRegistry store)
                , storeVariables = storeVariables store P.++ [transcript]
                }
        put (SemanticState (Ur updated))
        return value

registerStepMarkers :: [MarkerKey] -> State SemanticState ()
registerStepMarkers markers =
  case markers of
    [] -> return ()
    current:rest -> do
      registerMarker current StepCategory
      registerStepMarkers rest

registerMarker :: MarkerKey -> DeclarationCategory -> State SemanticState ()
registerMarker identity category = do
  SemanticState (Ur store) <- get
  assertState (ensureMarkerUnused identity (storeRegistry store))
  put
    (SemanticState
       (Ur
          store
            {storeRegistry = Map.insert identity category (storeRegistry store)}))

assertState :: () -> State SemanticState ()
assertState checked = checked `lseq` return ()

ensureMarkerUnused :: MarkerKey -> Map.Map MarkerKey DeclarationCategory -> ()
ensureMarkerUnused identity registry =
  case Map.lookup identity registry of
    P.Nothing -> ()
    P.Just category ->
      semanticError
        ("marker "
           P.++ traceMarkerType (markerView identity)
           P.++ " is already declared as "
           P.++ declarationCategoryName category)

ensureDeclared ::
     MarkerKey
  -> (DeclarationCategory -> P.Bool)
  -> P.String
  -> Map.Map MarkerKey DeclarationCategory
  -> ()
ensureDeclared identity accepts expected registry =
  case Map.lookup identity registry of
    P.Nothing ->
      semanticError
        ("undeclared "
           P.++ expected
           P.++ " marker "
           P.++ traceMarkerType (markerView identity))
    P.Just category ->
      case accepts category of
        P.True -> ()
        P.False ->
          semanticError
            ("marker "
               P.++ traceMarkerType (markerView identity)
               P.++ " is declared as "
               P.++ declarationCategoryName category
               P.++ ", not "
               P.++ expected)

declarationCategoryName :: DeclarationCategory -> P.String
declarationCategoryName category =
  case category of
    KindCategory _      -> "a Kind"
    RelationCategory {} -> "a RelationKind"
    VariableCategory    -> "a Domain variable"
    StepCategory        -> "a step"

markerSubseed :: P.Int -> MarkerKey -> P.Int
markerSubseed scenarioSeed identity =
  P.fromInteger
    (P.foldl
       mix
       (P.toInteger scenarioSeed `P.mod` modulus)
       (traceMarkerType (markerView identity)))
  where
    modulus = 2147483647
    mix hash character =
      (hash P.* 16777619 P.+ P.toInteger (ord character)) `P.mod` modulus

--------------------------------------------------------------------------------
-- Shared construction and Program lifecycle
--------------------------------------------------------------------------------
class Construct builder where
  constructCreate :: Payload tag %1 -> builder (Create tag)
  constructMaterialize :: Kind tag -> Pending tag %1 -> builder (Block tag)
  constructSeal ::
       Block owner %1 -> Block value %1 -> builder (Seal owner value)
  constructRelate ::
       RelationKind source target
    -> Slot source sourceValue
       %1 -> Slot target targetValue
       %1 -> builder (Relate source sourceValue target targetValue)

instance Construct Domain where
  constructCreate payload = Domain (createState payload)
  constructMaterialize handle pending = Domain (materializeState handle pending)
  constructSeal owner value = Domain (sealState owner value)
  constructRelate relationKind source target =
    Domain (relateState relationKind source target)

instance Construct Program where
  constructCreate payload = Program (createState payload)
  constructMaterialize handle pending =
    Program (materializeState handle pending)
  constructSeal owner value = Program (sealState owner value)
  constructRelate relationKind source target =
    Program (relateState relationKind source target)

create ::
     forall tag builder. Construct builder
  => Payload tag
     %1 -> builder (Create tag)
create = constructCreate

materialize ::
     forall tag builder. Construct builder
  => Kind tag
  -> Pending tag
     %1 -> builder (Block tag)
materialize = constructMaterialize

seal ::
     forall owner value builder. Construct builder
  => Block owner
     %1 -> Block value
     %1 -> builder (Seal owner value)
seal = constructSeal

relate ::
     forall source target sourceValue targetValue builder. Construct builder
  => RelationKind source target
  -> Slot source sourceValue
     %1 -> Slot target targetValue
     %1 -> builder (Relate source sourceValue target targetValue)
relate = constructRelate

createState :: Payload tag %1 -> State SemanticState (Create tag)
createState payload = return (Create (Pending payload (Ur CreatedOrigin)))

materializeState ::
     forall tag. Kind tag -> Pending tag %1 -> State SemanticState (Block tag)
materializeState (Kind kindIdentity' tagType) (Pending payload (Ur origin)) =
  case persistPayload payload of
    Ur persisted -> do
      SemanticState (Ur store) <- get
      assertState
        (ensureDeclared kindIdentity' isKind "Kind" (storeRegistry store))
      let blockId = BlockId (storeNextBlock store)
          offset = storeNextEvent store
          (payloadText, payloadScalar) = describePayload persisted
          traceBlock =
            TraceBlock
              { traceBlockId = blockId
              , traceBlockKind = markerView kindIdentity'
              , traceBlockType = markerView tagType
              , traceBlockPayloadText = payloadText
              , traceBlockPayloadScalar = payloadScalar
              , traceBlockBorn = offset
              , traceBlockEnded = P.Nothing
              , traceBlockOccupancies = []
              }
          event = TraceMaterialized offset blockId origin
          updated =
            store
              { storeNextBlock = storeNextBlock store P.+ 1
              , storeNextEvent = offset P.+ 1
              , storeBlocks = Map.insert blockId traceBlock (storeBlocks store)
              , storeEvents = event : storeEvents store
              }
      put (SemanticState (Ur updated))
      return (Block (Ur blockId) (Ur kindIdentity') (Ur tagType) (Ur persisted))
  where
    isKind category =
      case category of
        KindCategory declaredType -> declaredType P.== markerView tagType
        _                         -> P.False

copy :: forall tag. Block tag %1 -> Program (Copy tag)
copy (Block (Ur blockId) (Ur kindIdentity') (Ur tagType) (Ur payload)) =
  Program
    (return
       (Copy
          (Block (Ur blockId) (Ur kindIdentity') (Ur tagType) (Ur payload))
          (Pending payload (Ur (CopiedOrigin blockId)))))

use :: forall tag. Block tag %1 -> Program (Use tag)
use (Block (Ur blockId) (Ur _kindIdentity) (Ur _tagType) (Ur payload)) =
  Program $ do
    terminalEvent blockId TraceUsed
    return (Use payload)

replace :: forall tag. Block tag %1 -> Pending tag %1 -> Program (Replace tag)
replace (Block (Ur oldId) (Ur _kindIdentity) (Ur _tagType) (Ur _oldPayload)) (Pending payload (Ur _origin)) =
  Program $ do
    terminalInputs [oldId]
    return (Replace (Pending payload (Ur (ReplacedOrigin oldId))))

apply1 ::
     forall operator argument. Applicable1 operator argument
  => Block operator
     %1 -> Block argument
     %1 -> Program (Apply1 operator argument)
apply1 (Block (Ur operatorId) (Ur _operatorKind) (Ur _operatorType) (Ur operatorPayload)) (Block (Ur argumentId) (Ur _argumentKind) (Ur _argumentType) (Ur argumentPayload)) =
  let output = applyPayload1 operatorPayload argumentPayload
   in Program $ do
        terminalInputs [operatorId, argumentId]
        return
          (Apply1 (Pending output (Ur (Applied1Origin operatorId argumentId))))

apply2 ::
     forall operator left right. Applicable2 operator left right
  => Block operator
     %1 -> Block left
     %1 -> Block right
     %1 -> Program (Apply2 operator left right)
apply2 (Block (Ur operatorId) (Ur _operatorKind) (Ur _operatorType) (Ur operatorPayload)) (Block (Ur leftId) (Ur _leftKind) (Ur _leftType) (Ur leftPayload)) (Block (Ur rightId) (Ur _rightKind) (Ur _rightType) (Ur rightPayload)) =
  let output = applyPayload2 operatorPayload leftPayload rightPayload
   in Program $ do
        terminalInputs [operatorId, leftId, rightId]
        return
          (Apply2
             (Pending output (Ur (Applied2Origin operatorId leftId rightId))))

destroy :: forall tag. Block tag %1 -> Program (Destroy tag)
destroy (Block (Ur blockId) (Ur _kindIdentity) (Ur _tagType) (Ur _payload)) =
  Program $ do
    terminalEvent blockId TraceDestroyed
    return Destroy

sealState ::
     forall owner value.
     Block owner %1 -> Block value %1 -> State SemanticState (Seal owner value)
sealState (Block (Ur ownerId) (Ur ownerKind) (Ur ownerType) (Ur ownerPayload)) (Block (Ur valueId) (Ur valueKind) (Ur valueType) (Ur valuePayload)) = do
  SemanticState (Ur store) <- get
  case Map.lookup ownerId (storeSlots store) of
    P.Just _ -> semanticError "an owner may have at most one active Slot"
    P.Nothing -> do
      let offset = storeNextEvent store
          blocks' = openOccupancy ownerId valueId offset (storeBlocks store)
          updated =
            store
              { storeNextEvent = offset P.+ 1
              , storeSlots = Map.insert ownerId valueId (storeSlots store)
              , storeBlocks = blocks'
              , storeEvents =
                  TraceSealed offset ownerId valueId : storeEvents store
              }
      put (SemanticState (Ur updated))
      return
        (Seal
           (Block (Ur ownerId) (Ur ownerKind) (Ur ownerType) (Ur ownerPayload))
           (Slot
              (Ur ownerId)
              (Block
                 (Ur valueId)
                 (Ur valueKind)
                 (Ur valueType)
                 (Ur valuePayload))))

unseal ::
     forall owner value.
     Block owner %1 -> Slot owner value %1 -> Program (Unseal owner value)
unseal (Block (Ur ownerId) (Ur ownerKind) (Ur ownerType) (Ur ownerPayload)) (Slot (Ur slotOwnerId) (Block (Ur valueId) (Ur valueKind) (Ur valueType) (Ur valuePayload))) =
  Program $ do
    SemanticState (Ur store) <- get
    case ownerId P.== slotOwnerId
           P.&& Map.lookup ownerId (storeSlots store) P.== P.Just valueId of
      P.False ->
        semanticError "unseal received an owner and Slot that do not match"
      P.True -> do
        let offset = storeNextEvent store
            blocks' = closeOccupancy ownerId valueId offset (storeBlocks store)
            updated =
              store
                { storeNextEvent = offset P.+ 1
                , storeSlots = Map.delete ownerId (storeSlots store)
                , storeBlocks = blocks'
                , storeEvents =
                    TraceUnsealed offset ownerId valueId : storeEvents store
                }
        put (SemanticState (Ur updated))
        return
          (Unseal
             (Block (Ur ownerId) (Ur ownerKind) (Ur ownerType) (Ur ownerPayload))
             (Block (Ur valueId) (Ur valueKind) (Ur valueType) (Ur valuePayload)))

relateState ::
     forall source target sourceValue targetValue.
     RelationKind source target
  -> Slot source sourceValue
     %1 -> Slot target targetValue
     %1 -> State SemanticState (Relate source sourceValue target targetValue)
relateState relationKind@(RelationKind identity sourceType targetType direction) (Slot (Ur sourceId) (Block (Ur sourceValueId) (Ur sourceValueKind) (Ur sourceValueType) (Ur sourceValuePayload))) (Slot (Ur targetId) (Block (Ur targetValueId) (Ur targetValueKind) (Ur targetValueType) (Ur targetValuePayload))) = do
  SemanticState (Ur store) <- get
  assertState
    (ensureDeclared identity isRelation "RelationKind" (storeRegistry store))
  assertState (ensureActiveSlot sourceId (storeSlots store))
  assertState (ensureActiveSlot targetId (storeSlots store))
  let (keySource, keyTarget) = canonicalEndpoints direction sourceId targetId
      key = RelationKey identity keySource keyTarget
  case Map.lookup key (storeActiveRelations store) of
    P.Just _ ->
      semanticError
        ("duplicate active relation " P.++ relationIdentity relationKind)
    P.Nothing -> do
      let relationId = storeNextRelation store
          offset = storeNextEvent store
          relationRecord =
            TraceRelation
              { traceRelationId = relationId
              , traceRelationKind = markerView identity
              , traceRelationDirection = direction
              , traceRelationSource = sourceId
              , traceRelationTarget = targetId
              , traceRelationStart = offset
              , traceRelationEnd = P.Nothing
              }
          updated =
            store
              { storeNextRelation = relationId P.+ 1
              , storeNextEvent = offset P.+ 1
              , storeActiveRelations =
                  Map.insert key relationId (storeActiveRelations store)
              , storeRelations =
                  Map.insert relationId relationRecord (storeRelations store)
              , storeEvents = TraceRelated offset relationId : storeEvents store
              }
      put (SemanticState (Ur updated))
      return
        (Relate
           (Slot
              (Ur sourceId)
              (Block
                 (Ur sourceValueId)
                 (Ur sourceValueKind)
                 (Ur sourceValueType)
                 (Ur sourceValuePayload)))
           (Slot
              (Ur targetId)
              (Block
                 (Ur targetValueId)
                 (Ur targetValueKind)
                 (Ur targetValueType)
                 (Ur targetValuePayload))))
  where
    isRelation category =
      case category of
        RelationCategory declaredSource declaredTarget declaredDirection ->
          declaredSource P.== markerView sourceType
            P.&& declaredTarget P.== markerView targetType
            P.&& declaredDirection P.== direction
        _ -> P.False

ensureActiveSlot :: BlockId -> Map.Map BlockId BlockId -> ()
ensureActiveSlot ownerId slots =
  case Map.member ownerId slots of
    P.True  -> ()
    P.False -> semanticError "relate requires two active Slot capabilities"

canonicalEndpoints ::
     RelationDirection -> BlockId -> BlockId -> (BlockId, BlockId)
canonicalEndpoints direction source target =
  case direction of
    OrderedRelation -> (source, target)
    SymmetricRelation ->
      case source P.<= target of
        P.True  -> (source, target)
        P.False -> (target, source)

terminalEvent ::
     BlockId -> (P.Int -> BlockId -> TraceEvent) -> State SemanticState ()
terminalEvent blockId makeEvent = do
  SemanticState (Ur store) <- get
  let offset = storeNextEvent store
      ended = endBlocks [blockId] offset store
      updated =
        ended
          { storeNextEvent = offset P.+ 1
          , storeEvents = makeEvent offset blockId : storeEvents ended
          }
  put (SemanticState (Ur updated))

terminalInputs :: [BlockId] -> State SemanticState ()
terminalInputs blockIds = do
  SemanticState (Ur store) <- get
  let offset = storeNextEvent store
      ended = endBlocks blockIds offset store
  put (SemanticState (Ur ended))

endBlocks :: [BlockId] -> P.Int -> SemanticStore -> SemanticStore
endBlocks blockIds offset store = P.foldl (endBlock offset) store blockIds
  where
    endBlock terminalOffset currentStore blockId =
      case Map.lookup blockId (storeSlots currentStore) of
        P.Just _ ->
          semanticError "an owner must be unsealed before its lifetime ends"
        P.Nothing ->
          case Map.lookup blockId (storeBlocks currentStore) of
            P.Nothing ->
              semanticError "unknown Block reached a terminal operation"
            P.Just block ->
              case traceBlockEnded block of
                P.Just _ ->
                  semanticError "a Block lifetime ended more than once"
                P.Nothing ->
                  closeRelationsFor
                    blockId
                    terminalOffset
                    currentStore
                      { storeBlocks =
                          Map.insert
                            blockId
                            block {traceBlockEnded = P.Just terminalOffset}
                            (storeBlocks currentStore)
                      }

closeRelationsFor :: BlockId -> P.Int -> SemanticStore -> SemanticStore
closeRelationsFor blockId offset store =
  let ending =
        [ (key, relationId)
        | (key@(RelationKey _ source target), relationId) <-
            Map.toList (storeActiveRelations store)
        , source P.== blockId P.|| target P.== blockId
        ]
      active' =
        P.foldl
          (\active (key, _) -> Map.delete key active)
          (storeActiveRelations store)
          ending
      relations' =
        P.foldl
          (\relations (_, relationId) ->
             Map.adjust
               (\relationRecord ->
                  relationRecord {traceRelationEnd = P.Just offset})
               relationId
               relations)
          (storeRelations store)
          ending
   in store {storeActiveRelations = active', storeRelations = relations'}

openOccupancy ::
     BlockId
  -> BlockId
  -> P.Int
  -> Map.Map BlockId TraceBlock
  -> Map.Map BlockId TraceBlock
openOccupancy ownerId valueId offset =
  Map.adjust
    (\block ->
       block
         { traceBlockOccupancies =
             traceBlockOccupancies block
               P.++ [TraceOccupancy valueId offset P.Nothing]
         })
    ownerId

closeOccupancy ::
     BlockId
  -> BlockId
  -> P.Int
  -> Map.Map BlockId TraceBlock
  -> Map.Map BlockId TraceBlock
closeOccupancy ownerId valueId offset =
  Map.adjust
    (\block ->
       block {traceBlockOccupancies = closeLatest (traceBlockOccupancies block)})
    ownerId
  where
    closeLatest occupancies =
      case P.reverse occupancies of
        TraceOccupancy occupant start P.Nothing:rest
          | occupant P.== valueId ->
            P.reverse (TraceOccupancy occupant start (P.Just offset) : rest)
        _ -> semanticError "Slot occupancy history does not match unseal"

--------------------------------------------------------------------------------
-- Typed nested steps
--------------------------------------------------------------------------------
data StepToken =
  StepToken MarkerKey [P.Int] P.Int

step ::
     forall name value. Typeable name
  => Program value
     %1 -> Program value
step (Program action) =
  Program $ do
    Ur token <- beginStep (markerKey @name)
    value <- action
    finishStep token
    return value

beginStep :: MarkerKey -> State SemanticState (Ur StepToken)
beginStep identity = do
  SemanticState (Ur store) <- get
  assertState (ensureDeclared identity isStep "step" (storeRegistry store))
  let start = storeNextEvent store
      (path, openSteps', rootNext') = nextStepPath store
      updated =
        store
          { storeOpenSteps = OpenStep path 0 : openSteps'
          , storeRootNextStep = rootNext'
          }
  put (SemanticState (Ur updated))
  return (Ur (StepToken identity path start))
  where
    isStep category =
      case category of
        StepCategory -> P.True
        _            -> P.False

nextStepPath :: SemanticStore -> ([P.Int], [OpenStep], P.Int)
nextStepPath store =
  case storeOpenSteps store of
    [] -> ([storeRootNextStep store], [], storeRootNextStep store P.+ 1)
    parent:rest ->
      let ordinal = openStepNextChild parent
          path = openStepPath parent P.++ [ordinal]
          advanced = parent {openStepNextChild = ordinal P.+ 1}
       in (path, advanced : rest, storeRootNextStep store)

finishStep :: StepToken -> State SemanticState ()
finishStep (StepToken identity path start) = do
  SemanticState (Ur store) <- get
  case storeOpenSteps store of
    OpenStep currentPath _nextChild:rest
      | currentPath P.== path -> do
        let occurrence =
              StepOccurrence
                { stepOccurrenceDefinition = markerView identity
                , stepOccurrencePath = path
                , stepOccurrenceStart = start
                , stepOccurrenceEnd = storeNextEvent store
                }
            updated =
              store
                { storeOpenSteps = rest
                , storeSteps = occurrence : storeSteps store
                }
        put (SemanticState (Ur updated))
    _ -> semanticError "nested step stack became inconsistent"

--------------------------------------------------------------------------------
-- Host execution
--------------------------------------------------------------------------------
runSemanticScenario ::
     P.Int
  -> Domain initial
     %1 -> (initial %1 -> Program ())
     %1 -> SemanticTrace
runSemanticScenario scenarioSeed domain runProgram =
  case domain of
    Domain initialize ->
      case runState initialize (initialSemanticState scenarioSeed) of
        (initial, afterDomain) ->
          case runProgram initial of
            Program execute ->
              case runState execute afterDomain of
                ((), finalState) -> semanticTraceFromState finalState

initialSemanticState :: P.Int -> SemanticState
initialSemanticState scenarioSeed =
  SemanticState
    (Ur
       SemanticStore
         { storeScenarioSeed = scenarioSeed
         , storeNextBlock = 0
         , storeNextEvent = 0
         , storeNextRelation = 0
         , storeRegistry = Map.empty
         , storeVariables = []
         , storeBlocks = Map.empty
         , storeSlots = Map.empty
         , storeActiveRelations = Map.empty
         , storeRelations = Map.empty
         , storeOpenSteps = []
         , storeRootNextStep = 0
         , storeSteps = []
         , storeEvents = []
         })

semanticTraceFromState :: SemanticState %1 -> SemanticTrace
semanticTraceFromState (SemanticState (Ur store)) =
  validateFinishedStore store
    `lseq` SemanticTrace
             { semanticTraceScenarioSeed = storeScenarioSeed store
             , semanticTraceDeclarations =
                 [ (markerView identity, declarationCategoryName category)
                 | (identity, category) <- Map.toAscList (storeRegistry store)
                 ]
             , semanticTraceVariables = storeVariables store
             , semanticTraceBlocks = Map.elems (storeBlocks store)
             , semanticTraceRelations = Map.elems (storeRelations store)
             , semanticTraceSteps = sortOn stepOccurrencePath (storeSteps store)
             , semanticTraceEvents = P.reverse (storeEvents store)
             }

validateFinishedStore :: SemanticStore -> ()
validateFinishedStore store =
  case storeOpenSteps store of
    _:_ -> semanticError "Program ended inside an unfinished step"
    [] ->
      case Map.null (storeSlots store) of
        P.False -> semanticError "Program ended with an active Slot"
        P.True ->
          case [ traceBlockId block
               | block <- Map.elems (storeBlocks store)
               , isNothing (traceBlockEnded block)
               ] of
            blockId:_ ->
              semanticError
                ("Program ended with live Block " P.++ P.show blockId)
            [] -> ()

semanticError :: P.String -> value
semanticError message = P.error ("Sverlin semantic error: " P.++ message)
