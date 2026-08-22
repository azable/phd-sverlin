-- | View graph output builder. Choreography accumulates 'ViewOutput' values
-- while processing core events; this module finalizes those outputs into a
-- solver-ready 'ViewGraph'.
module LinearTrace.View.Build
  ( -- * Output accumulation
    -- | Monoidal output of nodes and render intents emitted by match
    -- rules and graph construction. Constraints remain attached to nodes until
    -- graph finalization.
    ViewOutput(..)
  , renderIntentOutput
  , -- * Graph construction
    -- | Applies node patches and finalizes accumulated output into a view
    -- graph with canvas/style constraints.
    patchedNodeOutput
  , viewNodeConstraints
  , finalizeViewGraph
  ) where

import           LinearTrace.View.Graph
import qualified LinearTrace.View.Patch      as Patch
import           LinearTrace.View.Primitives
import           LinearTrace.View.Style      (nodeStyleBounds,
                                              nodeStyleChoiceConstraints,
                                              nodeStyleConstraints)
import qualified LinearTrace.View.Style      as Style
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
  { emittedNodes         :: [ViewNode]
  , emittedRenderIntents :: [RenderIntent]
  }

instance Semigroup ViewOutput where
  ViewOutput nodesA intentsA <> ViewOutput nodesB intentsB =
    ViewOutput
      { emittedNodes = nodesA P.++ nodesB
      , emittedRenderIntents = intentsA P.++ intentsB
      }

instance Monoid ViewOutput where
  mempty = ViewOutput {emittedNodes = [], emittedRenderIntents = []}

renderIntentOutput :: RenderIntent -> ViewOutput
renderIntentOutput intent = P.mempty {emittedRenderIntents = [intent]}

patchedNodeOutput :: Patch.NodePatch -> Node tag -> ViewOutput
patchedNodeOutput patch node0 =
  let styledNode =
        node0
          { nodeStyle = Patch.nodePatchStyleUpdate patch (nodeStyle node0)
          , nodeContent =
              case Patch.nodePatchContent patch of
                Nothing      -> nodeContent node0
                Just content -> content
          }
      node =
        styledNode
          { nodeConstraints =
              nodeConstraints styledNode
                P.++ Patch.patchGeometryConstraints patch styledNode
          }
   in P.mempty {emittedNodes = [ViewNode node]}

finalizeViewGraph ::
     [ViewNode] -> [Constraint] -> [ChoiceConstraint] -> [ViewStep] -> ViewGraph
finalizeViewGraph nodes baseConstraints baseChoiceConstraints steps =
  let allNodeConstraints = P.concatMap viewNodeConstraints nodes
      allNodeStyleChoiceConstraints =
        P.concatMap viewNodeStyleChoiceConstraints nodes
      constraints = baseConstraints P.++ allNodeConstraints
      choiceConstraints =
        baseChoiceConstraints P.++ allNodeStyleChoiceConstraints
      finalizedSteps = addCompoundRenderSteps nodes steps
   in ViewGraph
        { viewCanvasWidth = canvasWidthValue defaultViewEnv
        , viewCanvasHeight = canvasHeightValue defaultViewEnv
        , viewNodes = nodes
        , viewConstraints = constraints
        , viewChoiceConstraints = choiceConstraints
        , viewSteps = finalizedSteps
        }

viewNodeConstraints :: ViewNode -> [Constraint]
viewNodeConstraints wrapped =
  case wrapped of
    ViewNode node ->
      nodeStyleConstraints (nodeStyle node)
        P.++ viewNodeRangeConstraints defaultViewEnv wrapped
        P.++ [ right node S.@<=@ canvasWidth defaultViewEnv
             , bottom node S.@<=@ canvasHeight defaultViewEnv
             ]
        P.++ nodeConstraints node
        P.++ structureConstraints node (nodeStructure node)

structureConstraints :: Node tag -> NodeStructure -> [Constraint]
structureConstraints node structure =
  case structure of
    LeafNode -> []
    CompoundNode ShrinkWrapChildren children ->
      compoundFitConstraints node children

compoundFitConstraints :: Node tag -> [NodeChild] -> [Constraint]
compoundFitConstraints node children =
  case children of
    [] -> []
    _  -> compoundTightFitConstraints node children

compoundTightFitConstraints :: Node tag -> [NodeChild] -> [Constraint]
compoundTightFitConstraints node children =
  case children of
    [] -> []
    _ ->
      minimumFitConstraints "left" left nodeChildLeft
        P.++ minimumFitConstraints "top" top nodeChildTop
        P.++ maximumFitConstraints "right" right nodeChildRight
        P.++ maximumFitConstraints "bottom" bottom nodeChildBottom
  where
    padding = compoundPadding node
    minimumFitConstraints edgeName containerEdge childEdge =
      [ containerEdge node S.@+@ padding S.@<=@ childEdge child
      | child <- children
      ]
        P.++ [ tightEdgeDecision
                 edgeName
                 (\child ->
                    containerEdge node S.@==@ childEdge child S.@-@ padding)
             ]
    maximumFitConstraints edgeName containerEdge childEdge =
      [ childEdge child S.@+@ padding S.@<=@ containerEdge node
      | child <- children
      ]
        P.++ [ tightEdgeDecision
                 edgeName
                 (\child ->
                    containerEdge node S.@==@ childEdge child S.@+@ padding)
             ]
    tightEdgeDecision edgeName equalityFor =
      case P.map
             (\child ->
                S.alternative
                  ("child." P.++ P.show (viewIdInt (nodeChildId child)))
                  [equalityFor child])
             children of
        [] -> P.error "Cannot shrinkwrap an empty compound node."
        first:rest ->
          S.oneOf
            ("view.compound."
               P.++ P.show (viewRefInt (nodeRef node))
               P.++ ".fit."
               P.++ edgeName)
            first
            rest

compoundPadding :: Node tag -> LayoutExpr
compoundPadding node =
  case Style.getStyleField @Style.Padding (nodeStyle node) of
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

viewNodeStyleChoiceConstraints :: ViewNode -> [ChoiceConstraint]
viewNodeStyleChoiceConstraints node =
  case node of
    ViewNode viewNode -> nodeStyleChoiceConstraints (nodeStyle viewNode)

viewNodeRangeConstraints :: ViewEnv -> ViewNode -> [Constraint]
viewNodeRangeConstraints env node =
  case node of
    ViewNode viewNode ->
      case nodeStructure viewNode of
        LeafNode ->
          leafBoundsRangeConstraints env (nodeStyleBounds (nodeStyle viewNode))
        CompoundNode _ _ ->
          compoundBoundsRangeConstraints
            env
            (nodeStyleBounds (nodeStyle viewNode))

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
    (canvasWidthValue env)
    (canvasHeightValue env)

compoundBoundsRangeConstraints :: ViewEnv -> BoundsExpr -> [Constraint]
compoundBoundsRangeConstraints env =
  boundsRangeConstraints
    env
    minimumLayoutExtent
    minimumLayoutExtent
    (canvasWidthValue env)
    (canvasHeightValue env)

addCompoundRenderSteps :: [ViewNode] -> [ViewStep] -> [ViewStep]
addCompoundRenderSteps nodes steps =
  let lifecycles = compoundLifecycles nodes
   in case lifecycles of
        [] -> steps
        _  -> addCompoundLifecycleSteps lifecycles steps

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

addCompoundLifecycleSteps :: [CompoundLifecycle] -> [ViewStep] -> [ViewStep]
addCompoundLifecycleSteps lifecycles steps =
  case steps of
    [] -> []
    step:rest ->
      let (nextLifecycles, compoundIntents) =
            updateCompoundLifecycles (viewStepIntents step) lifecycles
          nextStep =
            step {viewStepIntents = viewStepIntents step P.++ compoundIntents}
       in nextStep : addCompoundLifecycleSteps nextLifecycles rest

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
          (introductions, removals) = splitRenderIntents frame
          visibleLiveIds =
            P.foldl (applyCompoundRenderIntent childIds) liveIds introductions
          nextLiveIds =
            P.foldl (applyCompoundRenderIntent childIds) visibleLiveIds removals
          visibleIsLive = P.not (P.null visibleLiveIds)
          isLive = P.not (P.null nextLiveIds)
          nextLifecycle = CompoundLifecycle node childIds nextLiveIds
          introductionIntents =
            case (wasLive, visibleIsLive) of
              (P.False, P.True) -> [compoundFreshIntent node]
              _                 -> []
          removalIntents =
            case (wasLive P.|| visibleIsLive, isLive) of
              (P.True, P.False) -> [compoundRemoveIntent node]
              _                 -> []
          lifecycleIntents = introductionIntents P.++ removalIntents
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
