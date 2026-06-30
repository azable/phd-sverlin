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
    patchedNodeOutput
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

patchedNodeOutput :: Patch.NodePatch -> Node tag -> ViewOutput
patchedNodeOutput patch node0 =
  let node =
        node0
          { nodeStyle = Patch.nodePatchStyleUpdate patch (nodeStyle node0)
          , nodeContent =
              case Patch.nodePatchContent patch of
                Nothing      -> nodeContent node0
                Just content -> content
          }
      constraints =
        styleConstraints (nodeStyle node)
          P.++ [ right node S.@<=@ canvasWidth defaultViewEnv
               , bottom node S.@<=@ canvasHeight defaultViewEnv
               ]
          P.++ Patch.patchGeometryConstraints patch node
   in P.mempty
        {emittedNodes = [ViewNode node], emittedConstraints = constraints}

finalizeViewGraph ::
     [ViewNode]
  -> [ViewStep]
  -> [Constraint]
  -> [ChoiceConstraint]
  -> [[RenderIntent]]
  -> ViewGraph
finalizeViewGraph nodes viewSteps' baseConstraints baseChoiceConstraints renderFrames =
  let compoundConstraints = P.concatMap compoundNodeConstraints nodes
      -- Node styles are first registered while building trace steps. Layout
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
          P.++ compoundConstraints
      choiceConstraints = baseChoiceConstraints P.++ nodeStyleChoiceConstraints
      frames = addCompoundRenderFrames nodes renderFrames
   in ViewGraph
        { viewNodes = nodes
        , viewSteps = viewSteps'
        , viewConstraints = constraints
        , viewChoiceConstraints = choiceConstraints
        , viewRenderFrames = frames
        }

compoundNodeConstraints :: ViewNode -> [Constraint]
compoundNodeConstraints wrapped =
  case wrapped of
    ViewNode node ->
      nodeConstraints node P.++ structureConstraints node (nodeStructure node)

structureConstraints :: Node tag -> NodeStructure -> [Constraint]
structureConstraints node structure =
  case structure of
    LeafNode -> []
    CompoundNode ShrinkWrapChildren children ->
      compoundCanvasConstraints node P.++ compoundFitConstraints node children

compoundCanvasConstraints :: Node tag -> [Constraint]
compoundCanvasConstraints node =
  [ right node S.@<=@ canvasWidth defaultViewEnv
  , bottom node S.@<=@ canvasHeight defaultViewEnv
  ]

compoundFitConstraints :: Node tag -> [NodeChild] -> [Constraint]
compoundFitConstraints node children =
  case children of
    [] -> []
    _  -> compoundTightFitConstraints node children

compoundTightFitConstraints :: Node tag -> [NodeChild] -> [Constraint]
compoundTightFitConstraints node children =
  case children of
    [] -> []
    child:rest ->
      let allChildren = child : rest
       in [ left node
              S.@==@ (minChildEdge nodeChildLeft allChildren
                        S.@-@ compoundPadding node)
          , top node
              S.@==@ (minChildEdge nodeChildTop allChildren
                        S.@-@ compoundPadding node)
          , right node
              S.@==@ (maxChildEdge nodeChildRight allChildren
                        S.@+@ compoundPadding node)
          , bottom node
              S.@==@ (maxChildEdge nodeChildBottom allChildren
                        S.@+@ compoundPadding node)
          ]

compoundPadding :: Node tag -> LayoutExpr
compoundPadding node =
  case padding (nodeStyle node) of
    Nothing    -> num 0
    Just value -> value

nodeChildLeft :: NodeChild -> LayoutExpr
nodeChildLeft child = left (nodeChildBounds child)

nodeChildTop :: NodeChild -> LayoutExpr
nodeChildTop child = top (nodeChildBounds child)

nodeChildRight :: NodeChild -> LayoutExpr
nodeChildRight child = right (nodeChildBounds child)

nodeChildBottom :: NodeChild -> LayoutExpr
nodeChildBottom child = bottom (nodeChildBounds child)

minChildEdge :: (NodeChild -> LayoutExpr) -> [NodeChild] -> LayoutExpr
minChildEdge edge children =
  case children of
    []         -> P.error "Cannot shrinkwrap an empty compound node."
    child:rest -> foldChildEdge S.minExpr edge (edge child) rest

maxChildEdge :: (NodeChild -> LayoutExpr) -> [NodeChild] -> LayoutExpr
maxChildEdge edge children =
  case children of
    []         -> P.error "Cannot shrinkwrap an empty compound node."
    child:rest -> foldChildEdge S.maxExpr edge (edge child) rest

foldChildEdge ::
     (LayoutExpr -> LayoutExpr -> LayoutExpr)
  -> (NodeChild -> LayoutExpr)
  -> LayoutExpr
  -> [NodeChild]
  -> LayoutExpr
foldChildEdge combine edge current children =
  case children of
    []         -> current
    child:rest -> foldChildEdge combine edge (combine current (edge child)) rest

viewNodeStyleConstraints :: ViewNode -> [Constraint]
viewNodeStyleConstraints node =
  case node of
    ViewNode viewNode -> styleConstraints (nodeStyle viewNode)

viewNodeStyleChoiceConstraints :: ViewNode -> [ChoiceConstraint]
viewNodeStyleChoiceConstraints node =
  case node of
    ViewNode viewNode -> styleCategoryConstraints (nodeStyle viewNode)

viewNodeRangeConstraints :: ViewEnv -> ViewNode -> [Constraint]
viewNodeRangeConstraints env node =
  case node of
    ViewNode viewNode ->
      case nodeStructure viewNode of
        LeafNode ->
          leafBoundsRangeConstraints env (styleBounds (nodeStyle viewNode))
        CompoundNode _ _ ->
          compoundBoundsRangeConstraints env (styleBounds (nodeStyle viewNode))

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

leafBoundsRangeConstraints :: ViewEnv -> BoundsExpr -> [Constraint]
leafBoundsRangeConstraints env =
  boundsRangeConstraints
    env
    minimumLayoutExtent
    minimumLayoutExtent
    (P.max 20 (canvasWidthValue env P./ 2))
    (P.max 20 (canvasHeightValue env P./ 2))

compoundBoundsRangeConstraints :: ViewEnv -> BoundsExpr -> [Constraint]
compoundBoundsRangeConstraints env =
  boundsRangeConstraints
    env
    minimumLayoutExtent
    minimumLayoutExtent
    (canvasWidthValue env)
    (canvasHeightValue env)

addCompoundRenderFrames :: [ViewNode] -> [[RenderIntent]] -> [[RenderIntent]]
addCompoundRenderFrames nodes frames =
  let lifecycles = compoundLifecycles nodes
   in case lifecycles of
        [] -> frames
        _  -> addCompoundLifecycleFrames lifecycles frames

data CompoundLifecycle =
  CompoundLifecycle ViewNode [ViewId] [ViewId]

compoundLifecycles :: [ViewNode] -> [CompoundLifecycle]
compoundLifecycles nodes =
  case nodes of
    [] -> []
    wrapped@(ViewNode node):rest ->
      case nodeStructure node of
        CompoundNode _ children ->
          CompoundLifecycle wrapped (compoundChildIds children) []
            : compoundLifecycles rest
        LeafNode -> compoundLifecycles rest

compoundChildIds :: [NodeChild] -> [ViewId]
compoundChildIds = P.map nodeChildId

addCompoundLifecycleFrames ::
     [CompoundLifecycle] -> [[RenderIntent]] -> [[RenderIntent]]
addCompoundLifecycleFrames lifecycles frames =
  case frames of
    [] -> []
    frame:rest ->
      let (nextLifecycles, compoundIntents) =
            updateCompoundLifecycles frame lifecycles
       in (frame P.++ compoundIntents)
            : addCompoundLifecycleFrames nextLifecycles rest

updateCompoundLifecycles ::
     [RenderIntent]
  -> [CompoundLifecycle]
  -> ([CompoundLifecycle], [RenderIntent])
updateCompoundLifecycles frame lifecycles =
  case lifecycles of
    [] -> ([], [])
    lifecycle:rest ->
      let (nextLifecycle, intents) = updateCompoundLifecycle frame lifecycle
          (nextRest, restIntents) = updateCompoundLifecycles frame rest
       in (nextLifecycle : nextRest, intents P.++ restIntents)

updateCompoundLifecycle ::
     [RenderIntent] -> CompoundLifecycle -> (CompoundLifecycle, [RenderIntent])
updateCompoundLifecycle frame lifecycle =
  case lifecycle of
    CompoundLifecycle node childIds liveIds ->
      let wasLive = P.not (P.null liveIds)
          nextLiveIds =
            P.foldl (applyCompoundRenderIntent childIds) liveIds frame
          isLive = P.not (P.null nextLiveIds)
          nextLifecycle = CompoundLifecycle node childIds nextLiveIds
          lifecycleIntents =
            case (wasLive, isLive) of
              (P.False, P.True) -> [compoundFreshIntent node]
              (P.True, P.False) -> [compoundRemoveIntent node]
              _                 -> []
       in (nextLifecycle, lifecycleIntents)

applyCompoundRenderIntent :: [ViewId] -> [ViewId] -> RenderIntent -> [ViewId]
applyCompoundRenderIntent childIds liveIds intent =
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
addLiveChild childIds childId liveIds =
  case childId `P.elem` childIds of
    P.False -> liveIds
    P.True ->
      case childId `P.elem` liveIds of
        P.True  -> liveIds
        P.False -> childId : liveIds

removeLiveChild :: ViewId -> [ViewId] -> [ViewId]
removeLiveChild childId = P.filter (P./= childId)

compoundFreshIntent :: ViewNode -> RenderIntent
compoundFreshIntent wrapped =
  case wrapped of
    ViewNode node -> RenderFresh (nodeRef node)

compoundRemoveIntent :: ViewNode -> RenderIntent
compoundRemoveIntent wrapped =
  case wrapped of
    ViewNode node -> RenderRemove (nodeRef node)

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
