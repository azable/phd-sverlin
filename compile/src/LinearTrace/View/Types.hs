-- | Small shared view identity, tag, label, and content types. These are used
-- across query matching, graph construction, materialization, and compile
-- output, so this module intentionally has no dependency on solver/style code.
module LinearTrace.View.Types
  ( -- * Identity
    -- | Typed view references that let choreography attach view nodes to core
    -- event lifetimes while preserving payload tags at compile time.
    ViewId(..)
  , viewIdInt
  , ViewRef(..)
  , viewRefId
  , viewRefInt
  , viewRefFromId
  , -- * Labels and tags
    -- | Display labels and neutral tags used by query/match logic and render
    -- identity generation.
    ViewLabel(..)
  , ViewTagValue(..)
  , ViewTags(..)
  , emptyViewTags
  , viewTagsToList
  , -- * Content
    -- | Optional text content stored on symbolic view nodes before
    -- materialization.
    ContentMode(..)
  ) where

import           Prelude

newtype ViewId =
  ViewId Int
  deriving (Eq, Ord, Show)

viewIdInt :: ViewId -> Int
viewIdInt viewId =
  case viewId of
    ViewId value -> value

newtype ViewRef tag =
  ViewRef ViewId
  deriving (Eq, Ord, Show)

viewRefId :: ViewRef tag -> ViewId
viewRefId viewRef =
  case viewRef of
    ViewRef viewId -> viewId

viewRefInt :: ViewRef tag -> Int
viewRefInt = viewIdInt . viewRefId

viewRefFromId :: Int -> ViewRef tag
viewRefFromId = ViewRef . ViewId

data ViewLabel = ViewLabel
  { viewLabelKind    :: String
  , viewLabelContent :: String
  } deriving (Eq, Show)

data ViewTagValue
  = ViewTagAtom
  | ViewTagInt Int
  deriving (Eq, Ord, Show)

newtype ViewTags =
  ViewTags [(String, ViewTagValue)]
  deriving (Eq, Show)

emptyViewTags :: ViewTags
emptyViewTags = ViewTags []

viewTagsToList :: ViewTags -> [(String, ViewTagValue)]
viewTagsToList tags =
  case tags of
    ViewTags values -> values

data ContentMode
  = ContentEmpty
  | ContentText String
  deriving (Eq, Show)
