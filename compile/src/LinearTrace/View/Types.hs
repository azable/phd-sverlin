module LinearTrace.View.Types
  ( ViewId(..)
  , viewIdInt
  , ViewRef(..)
  , viewRefId
  , viewRefInt
  , syntheticViewRef
  , ViewLabel(..)
  , ViewTagValue(..)
  , ViewTags(..)
  , emptyViewTags
  , viewTagsToList
  , ContentMode(..)
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

syntheticViewRef :: Int -> ViewRef tag
syntheticViewRef = ViewRef . ViewId

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
