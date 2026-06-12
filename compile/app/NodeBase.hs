{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LinearTypes #-}
{-# LANGUAGE QuantifiedConstraints #-}
{-# LANGUAGE RebindableSyntax #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}

module NodeBase
  ( G (..),
    GBuilder,
    GBuilderState (..),
    NRecord (..),
    Event (..),
    Some (..),
    SomeObservation (..),
    NId,
    N,
    NRef,
    Observation (..),
    OneUse,
    (<$>),
    (<*>),
    Create,
    Observe,
    Use,
    Copy,
    Replace,
    Compute,
    Destroy,
    Seen,
    SeenList (..),
    Created (..),
    Observed (..),
    Used (..),
    Copied (..),
    Replaced (..),
    Computed (..),
    Destroyed (..),
    create,
    observe,
    use,
    copy,
    replace,
    compute,
    destroy,
    emitDesc,
    buildGraph,
  )
where

import Control.Functor.Linear hiding ((<$>), (<*>))
import Data.Kind (Type)
import Prelude.Linear
import Unsafe.Coerce qualified as Unsafe
import Prelude qualified as P

infixl 4 <$>

infixl 4 <*>

type NId = Int

data OneUse a where
  OneUse :: a %1 -> OneUse a

(<$>) ::
  (a %1 -> b) %1 ->
  OneUse a %1 ->
  OneUse b
f <$> OneUse x =
  OneUse (f x)

(<*>) ::
  OneUse (a %1 -> b) %1 ->
  OneUse a %1 ->
  OneUse b
OneUse f <*> OneUse x =
  OneUse (f x)

data Some content where
  Some :: content tag -> Some content

instance (forall tag. P.Show (content tag)) => P.Show (Some content) where
  show (Some content') = P.show content'

data NRecord content = NRecord
  { nodeId :: NId,
    nodeContent :: Some content
  }

instance
  (forall tag. P.Show (content tag)) =>
  P.Show (NRecord content)
  where
  show (NRecord nid content') =
    padRight 10 ("[N" P.++ P.show nid P.++ "]")
      P.++ P.show content'

data N content tag where
  N :: Ur NId %1 -> Ur (content tag) %1 -> N content tag

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
  SomeObservation :: Observation content tag -> SomeObservation content

instance
  (forall tag. P.Show (content tag)) =>
  P.Show (SomeObservation content)
  where
  show (SomeObservation obs) = P.show obs

data Create tag

data Observe tag

data Use tag

data Copy tag

data Replace tag

data Compute tag

data Destroy tag

data Seen content act where
  Seen :: Ur [SomeObservation content] %1 -> Seen content act

data SeenList content acts where
  ENil :: SeenList content '[]
  (:~) ::
    Seen content act %1 ->
    SeenList content acts %1 ->
    SeenList content (act ': acts)

infixr 5 :~

data Created content tag where
  Created ::
    N content tag %1 ->
    Seen content (Create tag) %1 ->
    Created content tag

data Observed content tag where
  Observed ::
    N content tag %1 ->
    Seen content (Observe tag) %1 ->
    Observed content tag

data Used content tag where
  Used ::
    OneUse (content tag) %1 ->
    Seen content (Use tag) %1 ->
    Used content tag

data Copied content tag where
  Copied ::
    N content tag %1 ->
    N content tag %1 ->
    Seen content (Copy tag) %1 ->
    Copied content tag

data Replaced content tag where
  Replaced ::
    N content tag %1 ->
    Seen content (Replace tag) %1 ->
    Replaced content tag

data Computed content tag where
  Computed ::
    N content tag %1 ->
    Seen content (Compute tag) %1 ->
    Computed content tag

data Destroyed content tag where
  Destroyed ::
    Seen content (Destroy tag) %1 ->
    Destroyed content tag

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
      P.++ P.concat (P.map showNode ns)
      P.++ "Events:\n"
      P.++ P.concat (P.map showEvent es)
    where
      showNode n = "  " P.++ P.show n P.++ "\n"
      showEvent e = "  " P.++ P.show e P.++ "\n"

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

type GBuilder content desc = State (GBuilderState content desc)

makeObservation ::
  NRef content ->
  content tag ->
  SomeObservation content
makeObservation r content' =
  SomeObservation (Observation r content')

makeSeen1 ::
  NRef content ->
  content tag ->
  Seen content act
makeSeen1 r content' =
  Seen (Ur [makeObservation r content'])

makeSeen2 ::
  NRef content ->
  content tag ->
  NRef content ->
  content tag ->
  Seen content act
makeSeen2 r1 content1 r2 content2 =
  Seen
    ( Ur
        [ makeObservation r1 content1,
          makeObservation r2 content2
        ]
    )

seenToObservations ::
  Seen content act %1 ->
  Ur [SomeObservation content]
seenToObservations (Seen observations) = observations

seenListToObservations ::
  SeenList content acts %1 ->
  Ur [SomeObservation content]
seenListToObservations ENil = Ur []
seenListToObservations (seen :~ rest) =
  case seenToObservations seen of
    Ur observations ->
      case seenListToObservations rest of
        Ur restObservations ->
          Ur (observations P.++ restObservations)

makeNRecord ::
  content tag ->
  GBuilder content desc (Ur NId)
makeNRecord content' = do
  GBuilderState (Ur oldNextId) (Ur oldNodes) oldEvents <- get

  let newId = oldNextId
  let newNode = NRecord newId (Some content')

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

emitDesc ::
  desc acts ->
  SeenList content acts %1 ->
  GBuilder content desc ()
emitDesc desc seenList =
  case seenListToObservations seenList of
    Ur observations ->
      emitEvent (Event desc observations)

unsafeUr ::
  forall a.
  a %1 ->
  Ur a
unsafeUr =
  Unsafe.unsafeCoerce (Ur :: a -> Ur a)

create ::
  content tag %1 ->
  GBuilder content desc (Created content tag)
create content0 =
  case unsafeUr content0 of
    Ur content' -> do
      Ur nid <- makeNRecord content'

      let r = NRef nid

      return
        ( Created
            (N (Ur nid) (Ur content'))
            (makeSeen1 r content')
        )

observe ::
  N content tag %1 ->
  GBuilder content desc (Observed content tag)
observe (N (Ur nid) (Ur content')) =
  return
    ( Observed
        (N (Ur nid) (Ur content'))
        (makeSeen1 (NRef nid) content')
    )

use ::
  N content tag %1 ->
  GBuilder content desc (Used content tag)
use (N (Ur nid) (Ur content')) =
  return
    ( Used
        (OneUse content')
        (makeSeen1 (NRef nid) content')
    )

copy ::
  N content tag %1 ->
  GBuilder content desc (Copied content tag)
copy (N (Ur originalId) (Ur content')) = do
  Ur copyId <- makeNRecord content'

  let originalRef = NRef originalId
  let copyRef = NRef copyId

  return
    ( Copied
        (N (Ur originalId) (Ur content'))
        (N (Ur copyId) (Ur content'))
        (makeSeen2 originalRef content' copyRef content')
    )

replace ::
  N content tag %1 ->
  N content tag %1 ->
  GBuilder content desc (Replaced content tag)
replace oldNode newNode =
  case oldNode of
    N (Ur oldId) (Ur oldContent) ->
      case newNode of
        N (Ur newId) (Ur newContent) ->
          return
            ( Replaced
                (N (Ur newId) (Ur newContent))
                (makeSeen2 (NRef oldId) oldContent (NRef newId) newContent)
            )

compute ::
  OneUse (content tag) %1 ->
  GBuilder content desc (Computed content tag)
compute (OneUse content0) =
  case unsafeUr content0 of
    Ur content' -> do
      Ur nid <- makeNRecord content'

      let r = NRef nid

      return
        ( Computed
            (N (Ur nid) (Ur content'))
            (makeSeen1 r content')
        )

destroy ::
  N content tag %1 ->
  GBuilder content desc (Destroyed content tag)
destroy (N (Ur nid) (Ur content')) =
  return (Destroyed (makeSeen1 (NRef nid) content'))

buildGraph ::
  GBuilder content desc () ->
  G content desc
buildGraph builder =
  let (_, finalState) =
        runState builder (GBuilderState (Ur 0) (Ur []) (Ur []))

      GBuilderState (Ur _) (Ur finalNodes) (Ur finalEvents) =
        finalState
   in G finalNodes finalEvents

padRight :: Int -> String -> String
padRight n s =
  s P.++ P.replicate (n P.- P.length s) ' '

joinWith :: String -> [String] -> String
joinWith _ [] = ""
joinWith _ [x] = x
joinWith sep (x : xs) =
  x P.++ sep P.++ joinWith sep xs
