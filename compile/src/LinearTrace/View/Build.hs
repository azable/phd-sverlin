{-# LANGUAGE TypeApplications #-}

-- | Solver-ready construction for hierarchical view graphs.
module LinearTrace.View.Build
  ( ViewOutput(..)
  , renderIntentOutput
  , viewNodeConstraints
  , finalizeViewGraph
  ) where

import           Data.Maybe                  (mapMaybe)
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

finalizeViewGraph ::
     [ViewNode]
  -> [Constraint]
  -> [ChoiceConstraint]
  -> [ViewStep]
  -> [ViewDiagnostic]
  -> ViewGraph
finalizeViewGraph nodes baseConstraints baseChoiceConstraints steps diagnostics =
  let constraints =
        baseConstraints
          P.++ P.concatMap viewNodeConstraints nodes
          P.++ hierarchyConstraints defaultViewEnv nodes
      choiceConstraints =
        baseChoiceConstraints P.++ P.concatMap viewNodeChoiceConstraints nodes
   in ViewGraph
        { viewCanvasWidth = canvasWidthValue defaultViewEnv
        , viewCanvasHeight = canvasHeightValue defaultViewEnv
        , viewNodes = nodes
        , viewConstraints = constraints
        , viewChoiceConstraints = choiceConstraints
        , viewSteps = addGeneratedRenderSteps nodes steps
        , viewDiagnostics = diagnostics
        }

viewNodeConstraints :: ViewNode -> [Constraint]
viewNodeConstraints wrapped =
  case wrapped of
    ViewNode node ->
      nodeStyleConstraints (nodeStyle node)
        P.++ nodeBoxConstraints (nodeBox node)
        P.++ fontSizeRangeConstraints defaultViewEnv (nodeStyle node)
        P.++ boundsRangeConstraints
               defaultViewEnv
               (nodeBoxBounds (nodeBox node))
        P.++ nodeConstraints node

fontSizeRangeConstraints :: ViewEnv -> Style.NodeStyle -> [Constraint]
fontSizeRangeConstraints env style' =
  [ S.within
    expression
    (Range 8 (P.max (canvasWidthValue env) (canvasHeightValue env)))
  | expression <- Style.styleFieldValues @Style.FontSize style'
  ]

boundsRangeConstraints :: ViewEnv -> BoundsExpr -> [Constraint]
boundsRangeConstraints env bounds' =
  case bounds' of
    Bounds topExpr leftExpr widthExpr heightExpr ->
      [ S.within
          topExpr
          (Range 0 (P.max 0 (canvasHeightValue env P.- minimumLayoutExtent)))
      , S.within
          leftExpr
          (Range 0 (P.max 0 (canvasWidthValue env P.- minimumLayoutExtent)))
      , S.within widthExpr (Range minimumLayoutExtent (canvasWidthValue env))
      , S.within heightExpr (Range minimumLayoutExtent (canvasHeightValue env))
      ]

minimumLayoutExtent :: P.Double
minimumLayoutExtent = 20

viewNodeChoiceConstraints :: ViewNode -> [ChoiceConstraint]
viewNodeChoiceConstraints wrapped =
  case wrapped of
    ViewNode node ->
      nodeStyleChoiceConstraints (nodeStyle node)
        P.++ nodeBoxChoiceConstraints (nodeBox node)

hierarchyConstraints :: ViewEnv -> [ViewNode] -> [Constraint]
hierarchyConstraints env nodes = P.concatMap constraintsForNode nodes
  where
    constraintsForNode wrapped =
      case wrapped of
        ViewNode node ->
          (case nodeParent node of
             Nothing -> canvasContainment env node
             Just _  -> [])
            P.++ childFitConstraints nodes node
            P.++ relativePinConstraints env nodes node

canvasContainment :: ViewEnv -> Node tag -> [Constraint]
canvasContainment env node =
  let margin = nodeBoxMargin (nodeBox node)
   in [ S.num 0 S.@<=@ left node S.@-@ insetLeft margin
      , S.num 0 S.@<=@ top node S.@-@ insetTop margin
      , right node S.@+@ insetRight margin S.@<=@ canvasWidth env
      , bottom node S.@+@ insetBottom margin S.@<=@ canvasHeight env
      ]

childFitConstraints :: [ViewNode] -> Node tag -> [Constraint]
childFitConstraints nodes parent =
  case mapMaybe (`findNode` nodes) (nodeChildren parent) of
    [] -> []
    children ->
      let padding = paddingForGeometry (nodeBoxPadding (nodeBox parent))
       in axisFitConstraints
            parent
            children
            Horizontal
            (nodeHorizontalFit parent)
            padding
            P.++ axisFitConstraints
                   parent
                   children
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
          [ tightEdgeDecision "start" (parentStart parent padding) childStart
          , tightEdgeDecision "end" (parentEnd parent padding) childEnd
          ]
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

relativePinConstraints :: ViewEnv -> [ViewNode] -> Node tag -> [Constraint]
relativePinConstraints env nodes node =
  case nodeRelativePins node of
    [] -> []
    pins ->
      case parentContentBoxFor env nodes node of
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

parentContentBoxFor ::
     ViewEnv -> [ViewNode] -> Node tag -> Maybe ParentContentBox
parentContentBoxFor env nodes node =
  case nodeParent node of
    Nothing ->
      Just
        ParentContentBox
          { parentContentLeft = S.num 0
          , parentContentTop = S.num 0
          , parentContentWidth = canvasWidth env
          , parentContentHeight = canvasHeight env
          }
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

addGeneratedRenderSteps :: [ViewNode] -> [ViewStep] -> [ViewStep]
addGeneratedRenderSteps nodes =
  addGeneratedLifecycleSteps (generatedLifecycles nodes)

data GeneratedLifecycle =
  GeneratedLifecycle ViewNode [ViewId] [ViewId]

generatedLifecycles :: [ViewNode] -> [GeneratedLifecycle]
generatedLifecycles nodes =
  [ GeneratedLifecycle wrapped (nodeChildren node) []
  | wrapped@(ViewNode node) <- nodes
  , P.not (P.null (nodeChildren node))
  ]

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
