{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LinearTypes #-}
{-# LANGUAGE QuantifiedConstraints #-}
{-# LANGUAGE RebindableSyntax #-}
{-# LANGUAGE TypeOperators #-}

module NodeBase
  ( -- * Public graph
    G (..),
    GBuilder,
    GBuilderState (..),
    NRecord (..),
    Event (..),
    Some (..),
    SomeObservation (..),

    -- * Node handles and references
    NId,
    N,
    NRef,
    Observation (..),

    -- * Lifecycle modes
    Created,
    Observed,
    Used,
    Destroyed,
    CopiedFrom,
    CopiedTo,
    ReplacedFrom,
    ReplacedTo,

    -- * Lifecycle protocol items
    Create,
    Observe,
    Use,
    Destroy,
    Copy,
    Replace,

    -- * Linear evidence
    Seen,
    Evidence (Evidence),
    Ev (..),
    EvList (..),

    -- * Lifecycle/evidence primitives
    create,
    observe,
    use,
    copy,
    replace,
    destroy,

    -- * Contextual descriptions
    emitDesc,

    -- * Running builders
    buildGraph,
  )
where

import Control.Functor.Linear
import Data.Kind (Type)
import Prelude.Linear
import Prelude qualified as P

type NId = Int

data Some content where
  Some :: content tag -> Some content

instance (forall tag. P.Show (content tag)) => P.Show (Some content) where
  show (Some content') =
    P.show content'

data NRecord content = NRecord
  { nodeId :: NId,
    nodeContent :: Some content
  }

instance (forall tag. P.Show (content tag)) => P.Show (NRecord content) where
  show (NRecord nid nodeContent') =
    padRight 10 ("[N" P.++ P.show nid P.++ "]")
      P.++ P.show nodeContent'

data N content tag where
  N ::
    Ur NId %1 ->
    Ur (content tag) %1 ->
    N content tag

instance Consumable (N content tag) where
  consume (N nid nodeContent') =
    consume nid `lseq` consume nodeContent'

data NRef content where
  NRef :: NId -> NRef content

instance P.Show (NRef content) where
  show (NRef nid) =
    "[N" P.++ P.show nid P.++ "]"

data Observation content tag = Observation
  { ref :: NRef content,
    content :: content tag
  }

instance (P.Show (content tag)) => P.Show (Observation content tag) where
  show (Observation r content') =
    P.show r P.++ " " P.++ P.show content'

data SomeObservation content where
  SomeObservation ::
    Observation content tag ->
    SomeObservation content

instance (forall tag. P.Show (content tag)) => P.Show (SomeObservation content) where
  show (SomeObservation obs) =
    P.show obs

-- Lifecycle modes.
data Created

data Observed

data Used

data Destroyed

data CopiedFrom

data CopiedTo

data ReplacedFrom

data ReplacedTo

-- Lifecycle protocol items.
--
-- Copy tag and Replace tag are intentionally binary protocol items.
-- They each expand to two observations, both with the same tag.
data Create tag

data Observe tag

data Use tag

data Destroy tag

data Copy tag

data Replace tag

data Event content (desc :: [Type] -> Type) where
  Event ::
    desc acts ->
    [SomeObservation content] ->
    Event content desc

instance
  ( forall tag. P.Show (content tag),
    forall acts. P.Show (desc acts)
  ) =>
  P.Show (Event content desc)
  where
  show (Event desc observations) =
    padRight 14 (P.show desc)
      P.++ joinWith ", " (P.map P.show observations)

data G content (desc :: [Type] -> Type) = G
  { graphNodes :: [NRecord content],
    graphEvents :: [Event content desc]
  }

instance
  ( forall tag. P.Show (content tag),
    forall acts. P.Show (desc acts)
  ) =>
  P.Show (G content desc)
  where
  show (G ns es) =
    "Nodes:\n"
      P.++ P.concat (P.map (\n -> "  " P.++ P.show n P.++ "\n") ns)
      P.++ "Events:\n"
      P.++ P.concat (P.map (\e -> "  " P.++ P.show e P.++ "\n") es)

data GBuilderState content (desc :: [Type] -> Type) = GBuilderState
  { nextId :: Ur NId,
    nodes :: Ur [NRecord content],
    events :: Ur [Event content desc]
  }

instance Consumable (GBuilderState content desc) where
  consume (GBuilderState next ns es) =
    consume next `lseq` consume ns `lseq` consume es

instance Dupable (GBuilderState content desc) where
  dup2 (GBuilderState next ns es) =
    case dup2 next of
      (next1, next2) ->
        case dup2 ns of
          (ns1, ns2) ->
            case dup2 es of
              (es1, es2) ->
                ( GBuilderState next1 ns1 es1,
                  GBuilderState next2 ns2 es2
                )

type GBuilder content desc =
  State (GBuilderState content desc)

data Seen content mode tag where
  Seen ::
    Ur (Observation content tag) %1 ->
    Seen content mode tag

data Evidence content mode tag where
  Evidence ::
    Observation content tag ->
    Seen content mode tag %1 ->
    Evidence content mode tag

mkEvidence ::
  NRef content ->
  content tag ->
  Evidence content mode tag
mkEvidence r content' =
  let obs =
        Observation r content'
   in Evidence obs (Seen (Ur obs))

seenToObservation ::
  Seen content mode tag %1 ->
  Ur (SomeObservation content)
seenToObservation (Seen obs) =
  case obs of
    Ur obs' ->
      Ur (SomeObservation obs')

-- | Evidence for a single protocol item.
--
-- Composite protocol items such as Copy and Replace consume two evidence
-- tokens, but still expose one declarative action at the description level.
data Ev content item where
  EvCreate ::
    Seen content Created tag %1 ->
    Ev content (Create tag)
  EvObserve ::
    Seen content Observed tag %1 ->
    Ev content (Observe tag)
  EvUse ::
    Seen content Used tag %1 ->
    Ev content (Use tag)
  EvDestroy ::
    Seen content Destroyed tag %1 ->
    Ev content (Destroy tag)
  EvCopy ::
    Seen content CopiedFrom tag %1 ->
    Seen content CopiedTo tag %1 ->
    Ev content (Copy tag)
  EvReplace ::
    Seen content ReplacedFrom tag %1 ->
    Seen content ReplacedTo tag %1 ->
    Ev content (Replace tag)

data EvList content items where
  ENil ::
    EvList content '[]
  (:~) ::
    Ev content item %1 ->
    EvList content items %1 ->
    EvList content (item ': items)

infixr 5 :~

evToObservations ::
  Ev content item %1 ->
  Ur [SomeObservation content]
evToObservations (EvCreate seen) =
  case seenToObservation seen of
    Ur obs ->
      Ur [obs]
evToObservations (EvObserve seen) =
  case seenToObservation seen of
    Ur obs ->
      Ur [obs]
evToObservations (EvUse seen) =
  case seenToObservation seen of
    Ur obs ->
      Ur [obs]
evToObservations (EvDestroy seen) =
  case seenToObservation seen of
    Ur obs ->
      Ur [obs]
evToObservations (EvCopy fromSeen toSeen) =
  case seenToObservation fromSeen of
    Ur fromObs ->
      case seenToObservation toSeen of
        Ur toObs ->
          Ur [fromObs, toObs]
evToObservations (EvReplace fromSeen toSeen) =
  case seenToObservation fromSeen of
    Ur fromObs ->
      case seenToObservation toSeen of
        Ur toObs ->
          Ur [fromObs, toObs]

evListToObservations ::
  EvList content items %1 ->
  Ur [SomeObservation content]
evListToObservations ENil =
  Ur []
evListToObservations (ev :~ rest) =
  case evToObservations ev of
    Ur obs ->
      case evListToObservations rest of
        Ur restObs ->
          Ur (obs P.++ restObs)

emitDesc ::
  desc acts ->
  EvList content acts %1 ->
  GBuilder content desc ()
emitDesc desc evs =
  case evListToObservations evs of
    Ur observations ->
      emitEvent
        (Event desc observations)

makeNRecord ::
  content tag ->
  GBuilder content desc (Ur NId)
makeNRecord nodeContent' = do
  GBuilderState (Ur oldNextId) (Ur oldNodes) oldEvents <- get

  let newId =
        oldNextId

      newNode =
        NRecord newId (Some nodeContent')

  put
    ( GBuilderState
        (Ur (newId + 1))
        (Ur (oldNodes P.++ [newNode]))
        oldEvents
    )

  return (Ur newId)

emitEvent ::
  Event content desc ->
  GBuilder content desc ()
emitEvent event = do
  GBuilderState oldNext oldNodes (Ur oldEvents) <- get

  put
    ( GBuilderState
        oldNext
        oldNodes
        (Ur (oldEvents P.++ [event]))
    )

create ::
  content tag ->
  GBuilder content desc (N content tag, Evidence content Created tag)
create nodeContent' = do
  Ur nid <-
    makeNRecord nodeContent'

  let r =
        NRef nid

  return
    ( N (Ur nid) (Ur nodeContent'),
      mkEvidence r nodeContent'
    )

observe ::
  N content tag %1 ->
  GBuilder content desc (N content tag, Evidence content Observed tag)
observe (N (Ur nid) (Ur nodeContent')) =
  return
    ( N (Ur nid) (Ur nodeContent'),
      mkEvidence (NRef nid) nodeContent'
    )

use ::
  N content tag %1 ->
  GBuilder content desc (Evidence content Used tag)
use (N (Ur nid) (Ur nodeContent')) =
  return
    (mkEvidence (NRef nid) nodeContent')

copy ::
  N content tag %1 ->
  GBuilder
    content
    desc
    ( N content tag,
      Evidence content CopiedFrom tag,
      N content tag,
      Evidence content CopiedTo tag
    )
copy (N (Ur nid) (Ur nodeContent')) = do
  Ur copyId <-
    makeNRecord nodeContent'

  let originalRef =
        NRef nid

      copyRef =
        NRef copyId

  return
    ( N (Ur nid) (Ur nodeContent'),
      mkEvidence originalRef nodeContent',
      N (Ur copyId) (Ur nodeContent'),
      mkEvidence copyRef nodeContent'
    )

replace ::
  N content tag %1 ->
  N content tag %1 ->
  GBuilder
    content
    desc
    ( N content tag,
      Evidence content ReplacedFrom tag,
      Evidence content ReplacedTo tag
    )
replace oldNode newNode =
  case oldNode of
    N (Ur oldId) (Ur oldContent) ->
      case newNode of
        N (Ur newId) (Ur newContent) ->
          return
            ( N (Ur newId) (Ur newContent),
              mkEvidence (NRef oldId) oldContent,
              mkEvidence (NRef newId) newContent
            )

destroy ::
  N content tag %1 ->
  GBuilder content desc (Evidence content Destroyed tag)
destroy (N (Ur nid) (Ur nodeContent')) =
  return
    (mkEvidence (NRef nid) nodeContent')

buildGraph ::
  GBuilder content desc tag ->
  G content desc
buildGraph builder =
  let (_, finalState) =
        runState
          builder
          (GBuilderState (Ur 0) (Ur []) (Ur []))

      GBuilderState (Ur _) (Ur finalNodes) (Ur finalEvents) =
        finalState
   in G finalNodes finalEvents

padRight :: Int -> String -> String
padRight n s =
  s P.++ P.replicate (n P.- P.length s) ' '

joinWith :: String -> [String] -> String
joinWith _ [] =
  ""
joinWith _ [x] =
  x
joinWith sep (x : xs) =
  x P.++ sep P.++ joinWith sep xs
