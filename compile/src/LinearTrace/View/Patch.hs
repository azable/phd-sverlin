module LinearTrace.View.Patch
  ( LayoutPin(..)
  , NodePatch(..)
  , emptyNodePatch
  , appendNodePatch
  , patchGeometryConstraints
  ) where

import           LinearTrace.View.Primitives (HasBounds (..), LayoutExpr)
import           LinearTrace.View.Style      (Style)
import           LinearTrace.View.Types      (ContentMode)
import           Prelude                     (Maybe (..))
import qualified Prelude                     as P
import qualified Solver                      as S
import           Solver                      (Constraint)

data LayoutPin =
  LayoutPin LayoutExpr [Constraint]

data NodePatch = NodePatch
  { nodePatchStyleUpdate :: Style -> Style
  , nodePatchContent     :: Maybe ContentMode
  , nodePatchLeft        :: Maybe LayoutPin
  , nodePatchTop         :: Maybe LayoutPin
  , nodePatchWidth       :: Maybe LayoutPin
  , nodePatchHeight      :: Maybe LayoutPin
  , nodePatchRight       :: Maybe LayoutPin
  , nodePatchBottom      :: Maybe LayoutPin
  , nodePatchX           :: Maybe LayoutPin
  , nodePatchY           :: Maybe LayoutPin
  }

emptyNodePatch :: NodePatch
emptyNodePatch =
  NodePatch
    { nodePatchStyleUpdate = P.id
    , nodePatchContent = Nothing
    , nodePatchLeft = Nothing
    , nodePatchTop = Nothing
    , nodePatchWidth = Nothing
    , nodePatchHeight = Nothing
    , nodePatchRight = Nothing
    , nodePatchBottom = Nothing
    , nodePatchX = Nothing
    , nodePatchY = Nothing
    }

appendNodePatch :: NodePatch -> NodePatch -> NodePatch
appendNodePatch first second =
  NodePatch
    { nodePatchStyleUpdate =
        composeStyleUpdates
          (nodePatchStyleUpdate first)
          (nodePatchStyleUpdate second)
    , nodePatchContent =
        preferLater (nodePatchContent first) (nodePatchContent second)
    , nodePatchLeft = preferLater (nodePatchLeft first) (nodePatchLeft second)
    , nodePatchTop = preferLater (nodePatchTop first) (nodePatchTop second)
    , nodePatchWidth =
        preferLater (nodePatchWidth first) (nodePatchWidth second)
    , nodePatchHeight =
        preferLater (nodePatchHeight first) (nodePatchHeight second)
    , nodePatchRight =
        preferLater (nodePatchRight first) (nodePatchRight second)
    , nodePatchBottom =
        preferLater (nodePatchBottom first) (nodePatchBottom second)
    , nodePatchX = preferLater (nodePatchX first) (nodePatchX second)
    , nodePatchY = preferLater (nodePatchY first) (nodePatchY second)
    }

patchGeometryConstraints ::
     HasBounds bounds => NodePatch -> bounds -> [Constraint]
patchGeometryConstraints patch bounds =
  pinConstraints (left bounds) (nodePatchLeft patch)
    P.++ pinConstraints (top bounds) (nodePatchTop patch)
    P.++ pinConstraints (width bounds) (nodePatchWidth patch)
    P.++ pinConstraints (height bounds) (nodePatchHeight patch)
    P.++ pinConstraints (right bounds) (nodePatchRight patch)
    P.++ pinConstraints (bottom bounds) (nodePatchBottom patch)
    P.++ pinConstraints (centerX bounds) (nodePatchX patch)
    P.++ pinConstraints (centerY bounds) (nodePatchY patch)

pinConstraints :: LayoutExpr -> Maybe LayoutPin -> [Constraint]
pinConstraints expr maybePin =
  case maybePin of
    Nothing -> []
    Just pin ->
      case pin of
        LayoutPin target constraints -> constraints P.++ [expr S.@==@ target]

composeStyleUpdates :: (Style -> Style) -> (Style -> Style) -> Style -> Style
composeStyleUpdates first second style0 = second (first style0)

preferLater :: Maybe a -> Maybe a -> Maybe a
preferLater earlier later =
  case later of
    Nothing -> earlier
    Just _  -> later
