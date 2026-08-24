{-# LANGUAGE TypeApplications #-}

-- | Solver-ready construction for hierarchical view graphs.
module LinearTrace.View.Build
  ( ViewOutput(..)
  , renderIntentOutput
  , viewNodeConstraints
  , finalizeViewGraph
  ) where

import qualified Data.Map.Strict             as Map
import           LinearTrace.View.Box        (EdgeInsets (..), nodeBoxBounds,
                                              nodeBoxChoiceConstraints,
                                              nodeBoxConstraints, nodeBoxMargin,
                                              nodeBoxPadding,
                                              paddingForGeometry)
import           LinearTrace.View.Graph
import           LinearTrace.View.Primitives
import           LinearTrace.View.Style      (nodeStyleChoiceConstraints,
                                              nodeStyleConstraints)
import qualified LinearTrace.View.Style      as Style
import           Prelude                     (Maybe (..), Monoid (..),
                                              Semigroup (..))
import qualified Prelude                     as P
import qualified Solver                      as S
import           Solver                      (ChoiceConstraint, Constraint,
                                              Range (..))

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

finalizeViewGraph ::
     [ViewNode]
  -> [Constraint]
  -> [ChoiceConstraint]
  -> [ViewStep]
  -> [ViewDiagnostic]
  -> ViewGraph
finalizeViewGraph nodes baseConstraints baseChoiceConstraints steps diagnostics =
  let children = childIndex nodes
      constraints =
        baseConstraints
          P.++ P.concatMap viewNodeConstraints nodes
          P.++ hierarchyConstraints children nodes
      choiceConstraints =
        baseChoiceConstraints P.++ P.concatMap viewNodeChoiceConstraints nodes
   in ViewGraph
        { viewNodes = nodes
        , viewConstraints = constraints
        , viewChoiceConstraints = choiceConstraints
        , viewSteps = addGeneratedRenderSteps children nodes steps
        , viewDiagnostics = diagnostics
        }

viewNodeConstraints :: ViewNode -> [Constraint]
viewNodeConstraints wrapped =
  case wrapped of
    ViewNode node ->
      nodeStyleConstraints (nodeStyle node)
        P.++ nodeBoxConstraints (nodeBox node)
        P.++ fontSizeRangeConstraints (nodeStyle node)
        P.++ boundsRangeConstraints node
        P.++ nodeConstraints node

fontSizeRangeConstraints :: Style.NodeStyle -> [Constraint]
fontSizeRangeConstraints style' =
  [ S.within expression (Range 8 maximumLayoutExtent)
  | expression <- Style.styleFieldValues @Style.FontSize style'
  ]

boundsRangeConstraints :: Node tag -> [Constraint]
boundsRangeConstraints node =
  case nodeBoxBounds (nodeBox node) of
    Bounds topExpr leftExpr widthExpr heightExpr ->
      case nodeOrigin node of
        CanvasOrigin meta ->
          [ topExpr S.@==@ S.num 0
          , leftExpr S.@==@ S.num 0
          , S.within
              widthExpr
              (Range
                 minimumLayoutExtent
                 (if canvasWidthExplicit meta
                    then maximumLayoutExtent
                    else automaticCanvasWidth))
          , S.within
              heightExpr
              (Range
                 minimumLayoutExtent
                 (if canvasHeightExplicit meta
                    then maximumLayoutExtent
                    else automaticCanvasHeight))
          ]
        _ ->
          [ S.within
              topExpr
              (Range 0 (maximumLayoutExtent P.- minimumLayoutExtent))
          , S.within
              leftExpr
              (Range 0 (maximumLayoutExtent P.- minimumLayoutExtent))
          , S.within widthExpr (Range minimumLayoutExtent maximumLayoutExtent)
          , S.within heightExpr (Range minimumLayoutExtent maximumLayoutExtent)
          ]

minimumLayoutExtent :: P.Double
minimumLayoutExtent = 20

maximumLayoutExtent :: P.Double
maximumLayoutExtent = 4096

automaticCanvasWidth :: P.Double
automaticCanvasWidth = 800

automaticCanvasHeight :: P.Double
automaticCanvasHeight = 600

viewNodeChoiceConstraints :: ViewNode -> [ChoiceConstraint]
viewNodeChoiceConstraints wrapped =
  case wrapped of
    ViewNode node ->
      nodeStyleChoiceConstraints (nodeStyle node)
        P.++ nodeBoxChoiceConstraints (nodeBox node)

type ChildIndex = Map.Map ViewId [ViewNode]

childIndex :: [ViewNode] -> ChildIndex
childIndex = P.foldl addChild Map.empty
  where
    addChild index wrapped@(ViewNode node) =
      case nodeParent node of
        Nothing     -> index
        Just parent -> Map.insertWith (P.flip (P.++)) parent [wrapped] index

hierarchyConstraints :: ChildIndex -> [ViewNode] -> [Constraint]
hierarchyConstraints children nodes = P.concatMap constraintsForNode nodes
  where
    constraintsForNode wrapped =
      case wrapped of
        ViewNode node ->
          childFitConstraints children node
            P.++ relativePinConstraints nodes node

childFitConstraints :: ChildIndex -> Node tag -> [Constraint]
childFitConstraints children parent =
  case Map.findWithDefault [] (viewRefId (nodeRef parent)) children of
    [] ->
      case nodeOrigin parent of
        CanvasOrigin meta ->
          [ width parent S.@==@ S.num automaticCanvasWidth
          | P.not (canvasWidthExplicit meta)
          ]
            P.++ [ height parent S.@==@ S.num automaticCanvasHeight
                 | P.not (canvasHeightExplicit meta)
                 ]
        _ -> []
    childNodes ->
      let padding = paddingForGeometry (nodeBoxPadding (nodeBox parent))
       in axisFitConstraints
            parent
            childNodes
            Horizontal
            (nodeHorizontalFit parent)
            padding
            P.++ axisFitConstraints
                   parent
                   childNodes
                   Vertical
                   (nodeVerticalFit parent)
                   padding

axisFitConstraints ::
     Node tag
  -> [ViewNode]
  -> Axis
  -> ContentFit
  -> EdgeInsets LayoutExpr
  -> [Constraint]
axisFitConstraints parent children axis fit padding = containment P.++ tightness
  where
    containment =
      P.concatMap
        (\child ->
           [ parentStart parent padding S.@<=@ childStart child
           , childEnd child S.@<=@ parentEnd parent padding
           ])
        children
    tightness =
      case fit of
        Contain -> []
        Hug ->
          (case nodeOrigin parent of
             CanvasOrigin _ -> []
             _ ->
               [ tightEdgeDecision
                   "start"
                   (parentStart parent padding)
                   childStart
               ])
            P.++ [tightEdgeDecision "end" (parentEnd parent padding) childEnd]
    parentStart node insets =
      case axis of
        Horizontal -> left node S.@+@ insetLeft insets
        Vertical   -> top node S.@+@ insetTop insets
        Both       -> P.error "Both is not a concrete layout axis"
    parentEnd node insets =
      case axis of
        Horizontal -> right node S.@-@ insetRight insets
        Vertical   -> bottom node S.@-@ insetBottom insets
        Both       -> P.error "Both is not a concrete layout axis"
    childStart wrapped =
      case wrapped of
        ViewNode child ->
          let margin = nodeBoxMargin (nodeBox child)
           in case axis of
                Horizontal -> left child S.@-@ insetLeft margin
                Vertical   -> top child S.@-@ insetTop margin
                Both       -> P.error "Both is not a concrete layout axis"
    childEnd wrapped =
      case wrapped of
        ViewNode child ->
          let margin = nodeBoxMargin (nodeBox child)
           in case axis of
                Horizontal -> right child S.@+@ insetRight margin
                Vertical   -> bottom child S.@+@ insetBottom margin
                Both       -> P.error "Both is not a concrete layout axis"
    tightEdgeDecision edge parentExpression childExpression =
      case P.map
             (\wrapped ->
                case wrapped of
                  ViewNode child ->
                    S.alternative
                      ("child." P.++ P.show (viewRefInt (nodeRef child)))
                      [parentExpression S.@==@ childExpression wrapped])
             children of
        [] -> P.error "Cannot fit a node around an empty child list"
        first:rest ->
          S.oneOf
            ("view.node."
               P.++ P.show (viewRefInt (nodeRef parent))
               P.++ ".fit."
               P.++ axisName axis
               P.++ "."
               P.++ edge)
            first
            rest

axisName :: Axis -> P.String
axisName axis =
  case axis of
    Horizontal -> "horizontal"
    Vertical   -> "vertical"
    Both       -> "both"

data ParentContentBox = ParentContentBox
  { parentContentLeft   :: LayoutExpr
  , parentContentTop    :: LayoutExpr
  , parentContentWidth  :: LayoutExpr
  , parentContentHeight :: LayoutExpr
  }

relativePinConstraints :: [ViewNode] -> Node tag -> [Constraint]
relativePinConstraints nodes node =
  case nodeRelativePins node of
    [] -> []
    pins ->
      case parentContentBoxFor nodes node of
        Nothing ->
          P.error
            ("Node "
               P.++ nodeDeclaration node
               P.++ " references a missing parent")
        Just parentBox -> P.map (relativePinConstraint parentBox node) pins

relativePinConstraint ::
     ParentContentBox -> Node tag -> RelativeLayoutPin -> Constraint
relativePinConstraint parentBox node pin =
  let ratio = S.num (relativeLayoutRatio pin)
   in case relativeLayoutAttr pin of
        RelativeCenterX ->
          centerX node
            S.@==@ parentContentLeft parentBox
            S.@+@ parentContentWidth parentBox
            S.@*@ ratio
        RelativeCenterY ->
          centerY node
            S.@==@ parentContentTop parentBox
            S.@+@ parentContentHeight parentBox
            S.@*@ ratio
        RelativeWidth ->
          width node S.@==@ parentContentWidth parentBox S.@*@ ratio
        RelativeHeight ->
          height node S.@==@ parentContentHeight parentBox S.@*@ ratio

parentContentBoxFor :: [ViewNode] -> Node tag -> Maybe ParentContentBox
parentContentBoxFor nodes node =
  case nodeParent node of
    Nothing -> Nothing
    Just identifier ->
      case findNode identifier nodes of
        Nothing                -> Nothing
        Just (ViewNode parent) -> Just (nodeContentBox parent)

nodeContentBox :: Node tag -> ParentContentBox
nodeContentBox node =
  let padding = paddingForGeometry (nodeBoxPadding (nodeBox node))
   in ParentContentBox
        { parentContentLeft = left node S.@+@ insetLeft padding
        , parentContentTop = top node S.@+@ insetTop padding
        , parentContentWidth =
            width node S.@-@ insetLeft padding S.@-@ insetRight padding
        , parentContentHeight =
            height node S.@-@ insetTop padding S.@-@ insetBottom padding
        }

findNode :: ViewId -> [ViewNode] -> Maybe ViewNode
findNode identifier nodes =
  case nodes of
    [] -> Nothing
    wrapped@(ViewNode node):rest
      | viewRefId (nodeRef node) P.== identifier -> Just wrapped
      | P.otherwise -> findNode identifier rest

addGeneratedRenderSteps :: ChildIndex -> [ViewNode] -> [ViewStep] -> [ViewStep]
addGeneratedRenderSteps children nodes =
  addGeneratedLifecycleSteps (generatedLifecycles children nodes)

data GeneratedLifecycle =
  GeneratedLifecycle ViewNode [ViewId] [ViewId]

generatedLifecycles :: ChildIndex -> [ViewNode] -> [GeneratedLifecycle]
generatedLifecycles children nodes =
  [ GeneratedLifecycle wrapped childIds []
  | wrapped@(ViewNode node) <- nodes
  , let childIds =
          P.map
            nodeId
            (Map.findWithDefault [] (viewRefId (nodeRef node)) children)
  , P.not (P.null childIds)
  , GeneratedOrigin _ <- [nodeOrigin node]
  ]

nodeId :: ViewNode -> ViewId
nodeId wrapped =
  case wrapped of
    ViewNode node -> viewRefId (nodeRef node)

addGeneratedLifecycleSteps :: [GeneratedLifecycle] -> [ViewStep] -> [ViewStep]
addGeneratedLifecycleSteps lifecycles steps =
  case steps of
    [] -> []
    step:rest ->
      let (nextLifecycles, generatedIntents) =
            updateGeneratedLifecycles (viewStepIntents step) lifecycles
          nextStep =
            step {viewStepIntents = viewStepIntents step P.++ generatedIntents}
       in nextStep : addGeneratedLifecycleSteps nextLifecycles rest

updateGeneratedLifecycles ::
     [RenderIntent]
  -> [GeneratedLifecycle]
  -> ([GeneratedLifecycle], [RenderIntent])
updateGeneratedLifecycles frame lifecycles =
  case lifecycles of
    [] -> ([], [])
    lifecycle:rest ->
      let (nextLifecycle, intents) = updateGeneratedLifecycle frame lifecycle
          (nextRest, restIntents) =
            updateGeneratedLifecycles (frame P.++ intents) rest
       in (nextLifecycle : nextRest, intents P.++ restIntents)

updateGeneratedLifecycle ::
     [RenderIntent]
  -> GeneratedLifecycle
  -> (GeneratedLifecycle, [RenderIntent])
updateGeneratedLifecycle frame lifecycle =
  case lifecycle of
    GeneratedLifecycle wrapped childIds liveIds ->
      let wasLive = P.not (P.null liveIds)
          (introductions, removals) = splitRenderIntents frame
          visibleLiveIds =
            P.foldl (applyGeneratedRenderIntent childIds) liveIds introductions
          nextLiveIds =
            P.foldl
              (applyGeneratedRenderIntent childIds)
              visibleLiveIds
              removals
          visibleIsLive = P.not (P.null visibleLiveIds)
          isLive = P.not (P.null nextLiveIds)
          nextLifecycle = GeneratedLifecycle wrapped childIds nextLiveIds
          introductionIntents =
            case (wasLive, visibleIsLive) of
              (P.False, P.True) -> [generatedFreshIntent wrapped]
              _                 -> []
          removalIntents =
            case (wasLive P.|| visibleIsLive, isLive) of
              (P.True, P.False) -> [generatedRemoveIntent wrapped]
              _                 -> []
       in (nextLifecycle, introductionIntents P.++ removalIntents)

applyGeneratedRenderIntent :: [ViewId] -> [ViewId] -> RenderIntent -> [ViewId]
applyGeneratedRenderIntent childIds liveIds intent =
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
addLiveChild childIds childId liveIds
  | childId `P.notElem` childIds = liveIds
  | childId `P.elem` liveIds = liveIds
  | P.otherwise = childId : liveIds

removeLiveChild :: ViewId -> [ViewId] -> [ViewId]
removeLiveChild childId = P.filter (P./= childId)

generatedFreshIntent :: ViewNode -> RenderIntent
generatedFreshIntent wrapped =
  case wrapped of
    ViewNode node -> RenderFresh (nodeRef node)

generatedRemoveIntent :: ViewNode -> RenderIntent
generatedRemoveIntent wrapped =
  case wrapped of
    ViewNode node -> RenderRemove (nodeRef node)
