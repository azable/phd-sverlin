-- | View graph output builder. Choreography accumulates 'ViewOutput' values
-- while processing core events; this module finalizes those outputs into a
-- solver-ready 'ViewGraph'.
module LinearTrace.View.Build
  ( -- * Output accumulation
    -- | Monoidal output of nodes, constraints, and render-intent frames emitted
    -- by match rules and graph construction.
    ViewOutput(..)
  , emptyViewOutput
  , appendViewOutput
  , flushViewOutput
  , renderIntentOutput
  , mergeInitialRenderIntents
  , withImplicitInitialFrame
  , -- * Graph construction
    -- | Applies node patches and finalizes accumulated output into a view
    -- graph with canvas/style constraints.
    patchedBlockOutput
  , finalizeViewGraph
  ) where

import           LinearTrace.View.Graph
import qualified LinearTrace.View.Patch      as Patch
import           LinearTrace.View.Primitives
import           LinearTrace.View.Style      (padding, styleBounds,
                                              styleCategoryConstraints,
                                              styleConstraints)
import           LinearTrace.View.Types      (ViewId, viewRefId)
import           Prelude                     (Maybe (..), Monoid (..),
                                              Semigroup (..))
import qualified Prelude                     as P
import qualified Solver                      as S
import           Solver                      (ChoiceConstraint, Constraint,
                                              Range (..))

data ViewEnv = ViewEnv
  { canvasWidthValue  :: P.Double
  , canvasHeightValue :: P.Double
  , canvasWidth       :: LayoutExpr
  , canvasHeight      :: LayoutExpr
  }

defaultViewEnv :: ViewEnv
defaultViewEnv =
  ViewEnv
    { canvasWidthValue = 800
    , canvasHeightValue = 600
    , canvasWidth = num 800
    , canvasHeight = num 600
    }

data ViewOutput = ViewOutput
  { emittedNodes             :: [ViewNode]
  , emittedConstraints       :: [Constraint]
  , emittedChoiceConstraints :: [ChoiceConstraint]
  , emittedRenderFrames      :: [[RenderIntent]]
  , pendingRenderIntents     :: [RenderIntent]
  }

instance Semigroup ViewOutput where
  ViewOutput nodesA constraintsA choicesA framesA pendingA <> ViewOutput nodesB constraintsB choicesB framesB pendingB =
    ViewOutput
      { emittedNodes = nodesA P.++ nodesB
      , emittedConstraints = constraintsA P.++ constraintsB
      , emittedChoiceConstraints = choicesA P.++ choicesB
      , emittedRenderFrames = framesA P.++ framesB
      , pendingRenderIntents = pendingA P.++ pendingB
      }

instance Monoid ViewOutput where
  mempty =
    ViewOutput
      { emittedNodes = []
      , emittedConstraints = []
      , emittedChoiceConstraints = []
      , emittedRenderFrames = []
      , pendingRenderIntents = []
      }

emptyViewOutput :: ViewOutput
emptyViewOutput = P.mempty

appendViewOutput :: ViewOutput -> ViewOutput -> ViewOutput
appendViewOutput = (<>)

flushViewOutput :: ViewOutput -> ViewOutput
flushViewOutput = flushPendingOutput

renderIntentOutput :: RenderIntent -> ViewOutput
renderIntentOutput intent = P.mempty {pendingRenderIntents = [intent]}

flushPendingOutput :: ViewOutput -> ViewOutput
flushPendingOutput output =
  case pendingRenderIntents output of
    [] -> output
    intents ->
      output
        { emittedRenderFrames =
            emittedRenderFrames output P.++ renderIntentFrames intents
        , pendingRenderIntents = []
        }

renderIntentFrames :: [RenderIntent] -> [[RenderIntent]]
renderIntentFrames intents =
  case splitRenderIntents intents of
    ([], [])                  -> []
    (introductions, [])       -> [introductions]
    ([], removals)            -> [removals]
    (introductions, removals) -> [introductions, removals]

splitRenderIntents :: [RenderIntent] -> ([RenderIntent], [RenderIntent])
splitRenderIntents intents =
  case intents of
    [] -> ([], [])
    intent:rest ->
      case splitRenderIntents rest of
        (introductions, removals) ->
          case isRemovalIntent intent of
            P.True  -> (introductions, intent : removals)
            P.False -> (intent : introductions, removals)

isRemovalIntent :: RenderIntent -> P.Bool
isRemovalIntent intent =
  case intent of
    RenderRemove _ -> P.True
    _              -> P.False

patchedBlockOutput :: Patch.NodePatch -> BlockView tag -> ViewOutput
patchedBlockOutput patch block0 =
  let block =
        block0
          { blockStyle = Patch.nodePatchStyleUpdate patch (blockStyle block0)
          , blockContent =
              case Patch.nodePatchContent patch of
                Nothing      -> blockContent block0
                Just content -> content
          }
      constraints =
        styleConstraints (blockStyle block)
          P.++ [ right block S.@<=@ canvasWidth defaultViewEnv
               , bottom block S.@<=@ canvasHeight defaultViewEnv
               ]
          P.++ Patch.patchGeometryConstraints patch block
   in P.mempty
        {emittedNodes = [BlockViewNode block], emittedConstraints = constraints}

finalizeViewGraph ::
     [ViewNode]
  -> [ViewStep]
  -> [Constraint]
  -> [ChoiceConstraint]
  -> [[RenderIntent]]
  -> ViewGraph
finalizeViewGraph nodes viewSteps' baseConstraints baseChoiceConstraints renderFrames =
  let virtualConstraints = P.concatMap virtualNodeConstraints nodes
      -- Block styles are first registered while building trace steps. Layout
      -- rules can later require optional style fields, so collect style
      -- constraints again after requirements are applied.
      nodeStyleConstraints = P.concatMap viewNodeStyleConstraints nodes
      nodeStyleChoiceConstraints =
        P.concatMap viewNodeStyleChoiceConstraints nodes
      nodeRangeConstraints =
        P.concatMap (viewNodeRangeConstraints defaultViewEnv) nodes
      constraints =
        baseConstraints
          P.++ nodeStyleConstraints
          P.++ nodeRangeConstraints
          P.++ virtualConstraints
      choiceConstraints = baseChoiceConstraints P.++ nodeStyleChoiceConstraints
      frames = addVirtualRenderFrames nodes renderFrames
   in ViewGraph
        { viewNodes = nodes
        , viewSteps = viewSteps'
        , viewConstraints = constraints
        , viewChoiceConstraints = choiceConstraints
        , viewRenderFrames = frames
        }

virtualNodeConstraints :: ViewNode -> [Constraint]
virtualNodeConstraints node =
  case node of
    BlockViewNode _ -> []
    VirtualViewNode virtual ->
      virtualCanvasConstraints virtual
        P.++ virtualFitConstraints virtual
        P.++ virtualConstraints virtual

virtualCanvasConstraints :: VirtualView tag -> [Constraint]
virtualCanvasConstraints virtual =
  [ right virtual S.@<=@ canvasWidth defaultViewEnv
  , bottom virtual S.@<=@ canvasHeight defaultViewEnv
  ]

virtualFitConstraints :: VirtualView tag -> [Constraint]
virtualFitConstraints virtual =
  case virtualChildren virtual of
    []       -> []
    [child]  -> virtualExactFitConstraints virtual child
    children -> virtualTightFitConstraints virtual children

virtualExactFitConstraints :: VirtualView tag -> AnyBlockView -> [Constraint]
virtualExactFitConstraints virtual child =
  [ left virtual S.@==@ (anyBlockLeft child S.@-@ virtualPadding virtual)
  , top virtual S.@==@ (anyBlockTop child S.@-@ virtualPadding virtual)
  , right virtual S.@==@ (anyBlockRight child S.@+@ virtualPadding virtual)
  , bottom virtual S.@==@ (anyBlockBottom child S.@+@ virtualPadding virtual)
  ]

virtualTightFitConstraints :: VirtualView tag -> [AnyBlockView] -> [Constraint]
virtualTightFitConstraints virtual children =
  case children of
    [] -> []
    child:rest ->
      let allChildren = child : rest
       in [ left virtual
              S.@==@ (minChildEdge anyBlockLeft allChildren
                        S.@-@ virtualPadding virtual)
          , top virtual
              S.@==@ (minChildEdge anyBlockTop allChildren
                        S.@-@ virtualPadding virtual)
          , right virtual
              S.@==@ (maxChildEdge anyBlockRight allChildren
                        S.@+@ virtualPadding virtual)
          , bottom virtual
              S.@==@ (maxChildEdge anyBlockBottom allChildren
                        S.@+@ virtualPadding virtual)
          ]

virtualPadding :: VirtualView tag -> LayoutExpr
virtualPadding virtual = padding (virtualStyle virtual)

minChildEdge :: (AnyBlockView -> LayoutExpr) -> [AnyBlockView] -> LayoutExpr
minChildEdge edge children =
  case children of
    []         -> P.error "Cannot shrinkwrap an empty virtual node."
    child:rest -> foldChildEdge S.minExpr edge (edge child) rest

maxChildEdge :: (AnyBlockView -> LayoutExpr) -> [AnyBlockView] -> LayoutExpr
maxChildEdge edge children =
  case children of
    []         -> P.error "Cannot shrinkwrap an empty virtual node."
    child:rest -> foldChildEdge S.maxExpr edge (edge child) rest

foldChildEdge ::
     (LayoutExpr -> LayoutExpr -> LayoutExpr)
  -> (AnyBlockView -> LayoutExpr)
  -> LayoutExpr
  -> [AnyBlockView]
  -> LayoutExpr
foldChildEdge combine edge current children =
  case children of
    []         -> current
    child:rest -> foldChildEdge combine edge (combine current (edge child)) rest

anyBlockLeft :: AnyBlockView -> LayoutExpr
anyBlockLeft anyBlock =
  case anyBlock of
    AnyBlockView child -> left child

anyBlockTop :: AnyBlockView -> LayoutExpr
anyBlockTop anyBlock =
  case anyBlock of
    AnyBlockView child -> top child

anyBlockRight :: AnyBlockView -> LayoutExpr
anyBlockRight anyBlock =
  case anyBlock of
    AnyBlockView child -> right child

anyBlockBottom :: AnyBlockView -> LayoutExpr
anyBlockBottom anyBlock =
  case anyBlock of
    AnyBlockView child -> bottom child

viewNodeStyleConstraints :: ViewNode -> [Constraint]
viewNodeStyleConstraints node =
  case node of
    BlockViewNode block     -> styleConstraints (blockStyle block)
    VirtualViewNode virtual -> styleConstraints (virtualStyle virtual)

viewNodeStyleChoiceConstraints :: ViewNode -> [ChoiceConstraint]
viewNodeStyleChoiceConstraints node =
  case node of
    BlockViewNode block     -> styleCategoryConstraints (blockStyle block)
    VirtualViewNode virtual -> styleCategoryConstraints (virtualStyle virtual)

viewNodeRangeConstraints :: ViewEnv -> ViewNode -> [Constraint]
viewNodeRangeConstraints env node =
  case node of
    BlockViewNode block ->
      blockBoundsRangeConstraints env (styleBounds (blockStyle block))
    VirtualViewNode virtual ->
      virtualBoundsRangeConstraints env (styleBounds (virtualStyle virtual))

boundsRangeConstraints ::
     ViewEnv
  -> P.Double
  -> P.Double
  -> P.Double
  -> P.Double
  -> BoundsExpr
  -> [Constraint]
boundsRangeConstraints env minWidth minHeight maxWidth maxHeight bounds' =
  case bounds' of
    Bounds topExpr leftExpr widthExpr heightExpr ->
      [ S.within
          topExpr
          (Range 0 (P.max 0 (canvasHeightValue env P.- minHeight)))
      , S.within
          leftExpr
          (Range 0 (P.max 0 (canvasWidthValue env P.- minWidth)))
      , S.within widthExpr (Range minWidth maxWidth)
      , S.within heightExpr (Range minHeight maxHeight)
      ]

minimumLayoutExtent :: P.Double
minimumLayoutExtent = 20

blockBoundsRangeConstraints :: ViewEnv -> BoundsExpr -> [Constraint]
blockBoundsRangeConstraints env =
  boundsRangeConstraints
    env
    minimumLayoutExtent
    minimumLayoutExtent
    (P.max 20 (canvasWidthValue env P./ 2))
    (P.max 20 (canvasHeightValue env P./ 2))

virtualBoundsRangeConstraints :: ViewEnv -> BoundsExpr -> [Constraint]
virtualBoundsRangeConstraints env =
  boundsRangeConstraints
    env
    minimumLayoutExtent
    minimumLayoutExtent
    (canvasWidthValue env)
    (canvasHeightValue env)

addVirtualRenderFrames :: [ViewNode] -> [[RenderIntent]] -> [[RenderIntent]]
addVirtualRenderFrames nodes frames =
  let lifecycles = virtualLifecycles nodes
   in case lifecycles of
        [] -> frames
        _  -> addVirtualLifecycleFrames lifecycles frames

data VirtualLifecycle =
  VirtualLifecycle AnyVirtualView [ViewId] [ViewId]

virtualLifecycles :: [ViewNode] -> [VirtualLifecycle]
virtualLifecycles nodes =
  [ VirtualLifecycle (AnyVirtualView virtual) (virtualChildIds virtual) []
  | VirtualViewNode virtual <- nodes
  ]

virtualChildIds :: VirtualView tag -> [ViewId]
virtualChildIds virtual =
  [viewRefId (blockRef child) | AnyBlockView child <- virtualChildren virtual]

addVirtualLifecycleFrames ::
     [VirtualLifecycle] -> [[RenderIntent]] -> [[RenderIntent]]
addVirtualLifecycleFrames lifecycles frames =
  case frames of
    [] -> []
    frame:rest ->
      let (nextLifecycles, virtualIntents) =
            updateVirtualLifecycles frame lifecycles
       in (frame P.++ virtualIntents)
            : addVirtualLifecycleFrames nextLifecycles rest

updateVirtualLifecycles ::
     [RenderIntent]
  -> [VirtualLifecycle]
  -> ([VirtualLifecycle], [RenderIntent])
updateVirtualLifecycles frame lifecycles =
  case lifecycles of
    [] -> ([], [])
    lifecycle:rest ->
      let (nextLifecycle, intents) = updateVirtualLifecycle frame lifecycle
          (nextRest, restIntents) = updateVirtualLifecycles frame rest
       in (nextLifecycle : nextRest, intents P.++ restIntents)

updateVirtualLifecycle ::
     [RenderIntent] -> VirtualLifecycle -> (VirtualLifecycle, [RenderIntent])
updateVirtualLifecycle frame lifecycle =
  case lifecycle of
    VirtualLifecycle virtual childIds liveIds ->
      let wasLive = P.not (P.null liveIds)
          nextLiveIds =
            P.foldl (applyVirtualRenderIntent childIds) liveIds frame
          isLive = P.not (P.null nextLiveIds)
          nextLifecycle = VirtualLifecycle virtual childIds nextLiveIds
          lifecycleIntents =
            case (wasLive, isLive) of
              (P.False, P.True) -> [virtualFreshIntent virtual]
              (P.True, P.False) -> [virtualRemoveIntent virtual]
              _                 -> []
       in (nextLifecycle, lifecycleIntents)

applyVirtualRenderIntent :: [ViewId] -> [ViewId] -> RenderIntent -> [ViewId]
applyVirtualRenderIntent childIds liveIds intent =
  case intent of
    RenderFresh ref -> addLiveChild childIds (viewRefId ref) liveIds
    RenderFork _ ref -> addLiveChild childIds (viewRefId ref) liveIds
    RenderContinue source target ->
      addLiveChild
        childIds
        (viewRefId target)
        (removeLiveChild (viewRefId source) liveIds)
    RenderRemove ref -> removeLiveChild (viewRefId ref) liveIds

addLiveChild :: [ViewId] -> ViewId -> [ViewId] -> [ViewId]
addLiveChild childIds blockId liveIds =
  case blockId `P.elem` childIds of
    P.False -> liveIds
    P.True ->
      case blockId `P.elem` liveIds of
        P.True  -> liveIds
        P.False -> blockId : liveIds

removeLiveChild :: ViewId -> [ViewId] -> [ViewId]
removeLiveChild blockId = P.filter (P./= blockId)

virtualFreshIntent :: AnyVirtualView -> RenderIntent
virtualFreshIntent anyVirtual =
  case anyVirtual of
    AnyVirtualView virtual -> RenderFresh (virtualRef virtual)

virtualRemoveIntent :: AnyVirtualView -> RenderIntent
virtualRemoveIntent anyVirtual =
  case anyVirtual of
    AnyVirtualView virtual -> RenderRemove (virtualRef virtual)

withImplicitInitialFrame :: [[RenderIntent]] -> [[RenderIntent]]
withImplicitInitialFrame frames =
  case frames of
    [] -> []
    first:rest ->
      case splitLeadingFresh first of
        ([], _)          -> first : rest
        (freshes, [])    -> freshes : rest
        (freshes, tail') -> freshes : tail' : rest

splitLeadingFresh :: [RenderIntent] -> ([RenderIntent], [RenderIntent])
splitLeadingFresh intents =
  case intents of
    RenderFresh ref:rest ->
      case splitLeadingFresh rest of
        (freshes, tail') -> (RenderFresh ref : freshes, tail')
    _ -> ([], intents)

mergeInitialRenderIntents :: [RenderIntent] -> ViewOutput -> ViewOutput
mergeInitialRenderIntents pending output =
  case pending of
    [] -> output
    _ ->
      case emittedRenderFrames output of
        [] ->
          output
            {pendingRenderIntents = pending P.++ pendingRenderIntents output}
        firstFrame:restFrames ->
          output {emittedRenderFrames = (pending P.++ firstFrame) : restFrames}
