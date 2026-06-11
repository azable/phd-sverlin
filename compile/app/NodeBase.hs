{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LinearTypes #-}
{-# LANGUAGE QuantifiedConstraints #-}
{-# LANGUAGE RebindableSyntax #-}

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

    -- * Linear evidence
    Seen,
    Evidence (Evidence),

    -- * Lifecycle/evidence primitives
    create,
    observe,
    use,
    copy,
    destroy,

    -- * Contextual descriptions
    describe1,
    describe2,
    describe3,
    describe4,
    describe5,

    -- * Running builders
    buildGraph,
  )
where

import Control.Functor.Linear
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

data Event content desc where
  Event ::
    desc ->
    [SomeObservation content] ->
    Event content desc

instance
  ( forall tag. P.Show (content tag),
    P.Show desc
  ) =>
  P.Show (Event content desc)
  where
  show (Event desc observations) =
    padRight 14 (P.show desc)
      P.++ joinWith ", " (P.map P.show observations)

data G content desc = G
  { graphNodes :: [NRecord content],
    graphEvents :: [Event content desc]
  }

instance
  ( forall tag. P.Show (content tag),
    P.Show desc
  ) =>
  P.Show (G content desc)
  where
  show (G ns es) =
    "Nodes:\n"
      P.++ P.concat (P.map (\n -> "  " P.++ P.show n P.++ "\n") ns)
      P.++ "Events:\n"
      P.++ P.concat (P.map (\e -> "  " P.++ P.show e P.++ "\n") es)

data GBuilderState content desc = GBuilderState
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

-- | Linear evidence token.
--
-- It is intentionally opaque and has no Consumable instance.
-- It must be discharged through describe1/describe2/etc.
data Seen content tag where
  Seen ::
    Ur (Observation content tag) %1 ->
    Seen content tag

-- | Public evidence package:
--
--   * Observation is unrestricted metadata, useful for reading content.
--   * Seen is the linear token that must be consumed by a description.
data Evidence content tag where
  Evidence ::
    Observation content tag ->
    Seen content tag %1 ->
    Evidence content tag

mkEvidence ::
  NRef content ->
  content tag ->
  Evidence content tag
mkEvidence r content' =
  let obs =
        Observation r content'
   in Evidence obs (Seen (Ur obs))

seenToObservation ::
  Seen content tag %1 ->
  Ur (SomeObservation content)
seenToObservation (Seen obs) =
  case obs of
    Ur obs' ->
      Ur (SomeObservation obs')

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
  GBuilder content desc (N content tag, Evidence content tag)
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
  GBuilder content desc (N content tag, Evidence content tag)
observe (N (Ur nid) (Ur nodeContent')) =
  return
    ( N (Ur nid) (Ur nodeContent'),
      mkEvidence (NRef nid) nodeContent'
    )

use ::
  N content tag %1 ->
  GBuilder content desc (Evidence content tag)
use (N (Ur nid) (Ur nodeContent')) =
  return (mkEvidence (NRef nid) nodeContent')

copy ::
  N content tag %1 ->
  GBuilder
    content
    desc
    ( N content tag,
      Evidence content tag,
      N content tag,
      Evidence content tag
    )
copy (N (Ur nid) (Ur nodeContent')) = do
  (copyNode, copyEvidence) <-
    create nodeContent'

  return
    ( N (Ur nid) (Ur nodeContent'),
      mkEvidence (NRef nid) nodeContent',
      copyNode,
      copyEvidence
    )

destroy ::
  N content tag %1 ->
  GBuilder content desc (Evidence content tag)
destroy (N (Ur nid) (Ur nodeContent')) =
  return (mkEvidence (NRef nid) nodeContent')

describe1 ::
  desc ->
  Seen content a %1 ->
  GBuilder content desc ()
describe1 desc s1 =
  case seenToObservation s1 of
    Ur o1 ->
      emitEvent
        ( Event
            desc
            [o1]
        )

describe2 ::
  desc ->
  Seen content a %1 ->
  Seen content b %1 ->
  GBuilder content desc ()
describe2 desc s1 s2 =
  case seenToObservation s1 of
    Ur o1 ->
      case seenToObservation s2 of
        Ur o2 ->
          emitEvent
            ( Event
                desc
                [o1, o2]
            )

describe3 ::
  desc ->
  Seen content a %1 ->
  Seen content b %1 ->
  Seen content c %1 ->
  GBuilder content desc ()
describe3 desc s1 s2 s3 =
  case seenToObservation s1 of
    Ur o1 ->
      case seenToObservation s2 of
        Ur o2 ->
          case seenToObservation s3 of
            Ur o3 ->
              emitEvent
                ( Event
                    desc
                    [o1, o2, o3]
                )

describe4 ::
  desc ->
  Seen content a %1 ->
  Seen content b %1 ->
  Seen content c %1 ->
  Seen content d %1 ->
  GBuilder content desc ()
describe4 desc s1 s2 s3 s4 =
  case seenToObservation s1 of
    Ur o1 ->
      case seenToObservation s2 of
        Ur o2 ->
          case seenToObservation s3 of
            Ur o3 ->
              case seenToObservation s4 of
                Ur o4 ->
                  emitEvent
                    ( Event
                        desc
                        [o1, o2, o3, o4]
                    )

describe5 ::
  desc ->
  Seen content a %1 ->
  Seen content b %1 ->
  Seen content c %1 ->
  Seen content d %1 ->
  Seen content e %1 ->
  GBuilder content desc ()
describe5 desc s1 s2 s3 s4 s5 =
  case seenToObservation s1 of
    Ur o1 ->
      case seenToObservation s2 of
        Ur o2 ->
          case seenToObservation s3 of
            Ur o3 ->
              case seenToObservation s4 of
                Ur o4 ->
                  case seenToObservation s5 of
                    Ur o5 ->
                      emitEvent
                        ( Event
                            desc
                            [o1, o2, o3, o4, o5]
                        )

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