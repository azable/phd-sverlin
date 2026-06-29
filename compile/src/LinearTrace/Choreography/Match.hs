{-# LANGUAGE GADTs               #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

module LinearTrace.Choreography.Match
  ( MatchSpec
  , emptyMatchSpec
  , matchSpecAppend
  , matchQueryNode
  , matchAnyQueryNode
  , matchQueryPayloadNode
  , matchVirtualNode
  , NodeSelection(..)
  , ConstraintStrength(..)
  , LayoutRelation(..)
  , ValueComponent
  , ValueEndpoint
  , rawValueEndpoint
  , selectionValueEndpoint
  , matchValueRelation
  , matchValueDirectedBridge
  , matchValueSymmetricBridge
  , blockViewOfEventBlock
  , matchedBlockOutput
  , buildMatchedViewGraph
  ) where

import           Data.Maybe                     (fromMaybe)
import           Data.Proxy                     (Proxy (..))
import           Data.Type.Equality             ((:~:) (..))
import           Data.Typeable                  (eqT)
import           LinearTrace.Choreography.Query (MatchBindings,
                                                 MatchContext (..),
                                                 PayloadPattern, Query,
                                                 QueryBindings)
import qualified LinearTrace.Choreography.Query as Q
import qualified LinearTrace.Core               as C
import qualified LinearTrace.Core.Events        as E
import qualified LinearTrace.View               as V
import qualified LinearTrace.View.Access        as VA
import qualified LinearTrace.View.Patch         as VP
import           Prelude                        (Bool (..), Maybe (..),
                                                 otherwise)
import qualified Prelude                        as P
import qualified Solver                         as S

type ValueComponent = VA.ValueComponent

type NodePatch = VP.NodePatch

data NodeSelection
  = TraceSelection Query
  | VirtualSelection P.String Query
  deriving (P.Eq, P.Show)

data ConstraintStrength
  = EnsureConstraint
  | EncourageConstraint
  deriving (P.Eq, P.Show)

data LayoutRelation
  = LayoutEqual
  | LayoutLessOrEqual
  deriving (P.Eq, P.Show)

data ValueEndpoint
  = RawValueEndpoint ValueComponent
  | SelectionValueEndpoint NodeSelection VA.ValueAccess

data MatchSpec =
  MatchSpec [NodeRule] [LayoutRule] [VirtualRule]

data NodeRule where
  QueryNodeRule
    :: C.Traceable tag=> Proxy tag
    -> Query
    -> PayloadPattern tag
    -> (MatchContext tag -> NodePatch)
    -> NodeRule
  AnyQueryNodeRule :: Query -> (MatchBindings -> NodePatch) -> NodeRule

data LayoutRule where
  ValueRelationLayout
    :: ConstraintStrength
    -> [ValueEndpoint]
    -> LayoutRelation
    -> [ValueEndpoint]
    -> LayoutRule
  ValueDirectedBridgeLayout
    :: ConstraintStrength
    -> [ValueEndpoint]
    -> [ValueEndpoint]
    -> [ValueEndpoint]
    -> LayoutRule
  ValueSymmetricBridgeLayout
    :: ConstraintStrength
    -> [ValueEndpoint]
    -> [ValueEndpoint]
    -> [ValueEndpoint]
    -> LayoutRule

data VirtualRule =
  VirtualRule P.String Query NodePatch

emptyMatchSpec :: MatchSpec
emptyMatchSpec = MatchSpec [] [] []

matchSpecAppend :: MatchSpec -> MatchSpec -> MatchSpec
matchSpecAppend lhs rhs =
  case lhs of
    MatchSpec leftNodes leftLayouts leftVirtuals ->
      case rhs of
        MatchSpec rightNodes rightLayouts rightVirtuals ->
          MatchSpec
            (leftNodes P.++ rightNodes)
            (leftLayouts P.++ rightLayouts)
            (leftVirtuals P.++ rightVirtuals)

matchQueryNode ::
     forall tag. C.Traceable tag
  => Query
  -> (MatchContext tag -> NodePatch)
  -> MatchSpec
matchQueryNode query makePatch =
  MatchSpec
    [QueryNodeRule (Proxy :: Proxy tag) query Q.anyPayloadPattern makePatch]
    []
    []

matchAnyQueryNode :: Query -> (MatchBindings -> NodePatch) -> MatchSpec
matchAnyQueryNode query makePatch =
  MatchSpec [AnyQueryNodeRule query makePatch] [] []

matchQueryPayloadNode ::
     forall tag. C.Traceable tag
  => Query
  -> PayloadPattern tag
  -> (MatchContext tag -> NodePatch)
  -> MatchSpec
matchQueryPayloadNode query payloadPattern makePatch =
  MatchSpec
    [QueryNodeRule (Proxy :: Proxy tag) query payloadPattern makePatch]
    []
    []

matchVirtualNode :: P.String -> Query -> NodePatch -> MatchSpec
matchVirtualNode key query patch =
  MatchSpec [] [] [VirtualRule (Q.safeKey key) query patch]

rawValueEndpoint :: ValueComponent -> ValueEndpoint
rawValueEndpoint = RawValueEndpoint

selectionValueEndpoint :: NodeSelection -> VA.ValueAccess -> ValueEndpoint
selectionValueEndpoint = SelectionValueEndpoint

matchValueRelation ::
     ConstraintStrength
  -> [ValueEndpoint]
  -> LayoutRelation
  -> [ValueEndpoint]
  -> MatchSpec
matchValueRelation strength lhs relation rhs =
  MatchSpec [] [ValueRelationLayout strength lhs relation rhs] []

matchValueDirectedBridge ::
     ConstraintStrength
  -> [ValueEndpoint]
  -> [ValueEndpoint]
  -> [ValueEndpoint]
  -> MatchSpec
matchValueDirectedBridge strength lhs gap rhs =
  MatchSpec [] [ValueDirectedBridgeLayout strength lhs gap rhs] []

matchValueSymmetricBridge ::
     ConstraintStrength
  -> [ValueEndpoint]
  -> [ValueEndpoint]
  -> [ValueEndpoint]
  -> MatchSpec
matchValueSymmetricBridge strength lhs delta rhs =
  MatchSpec [] [ValueSymmetricBridgeLayout strength lhs delta rhs] []

blockViewOfEventBlock :: E.EventBlock tag -> V.BlockView tag
blockViewOfEventBlock block =
  let ref = coreViewRef (E.eventBlockRef block)
   in V.BlockView
        { V.blockRef = ref
        , V.blockLabel =
            viewLabelFromPayloadView (E.eventBlockPayloadView block)
        , V.blockContent = V.ContentEmpty
        , V.blockTags = viewTagsFromFacts (E.eventBlockFacts block)
        , V.blockNodeKey = V.defaultNodeKey
        , V.blockPieceKey = V.defaultPieceKey
        , V.blockStyle = V.styleForRef ref
        }

matchedBlockOutput ::
     C.Traceable tag => MatchSpec -> E.EventBlock tag -> V.ViewOutput
matchedBlockOutput spec eventBlock =
  case spec of
    MatchSpec nodeRules _ _ ->
      let block = blockViewOfEventBlock eventBlock
       in case matchedNodePatch eventBlock nodeRules of
            Nothing    -> V.emptyViewOutput
            Just patch -> V.patchedBlockOutput patch block

coreViewRef :: E.BlockRef tag -> V.ViewRef tag
coreViewRef ref = V.syntheticViewRef (E.blockRefId ref)

viewLabelFromPayloadView :: C.PayloadView -> V.ViewLabel
viewLabelFromPayloadView payloadViewValue =
  case payloadViewValue of
    C.PayloadView kind contentValue -> V.ViewLabel kind contentValue

viewTagsFromFacts :: C.Facts -> V.ViewTags
viewTagsFromFacts facts =
  V.ViewTags (P.map viewTagFromFact (C.factsToList facts))

viewTagFromFact :: C.Fact -> (P.String, V.ViewTagValue)
viewTagFromFact fact =
  case fact of
    C.Fact name value ->
      case value of
        C.FactAtom     -> (name, V.ViewTagAtom)
        C.FactInt int  -> (name, V.ViewTagInt int)
        C.FactSymbol _ -> (name, V.ViewTagAtom)

matchedNodePatch ::
     forall tag. C.Traceable tag
  => E.EventBlock tag
  -> [NodeRule]
  -> Maybe NodePatch
matchedNodePatch block rules =
  foldNodePatches (matchingNodePatches 0 block rules)

matchingNodePatches ::
     forall tag. C.Traceable tag
  => P.Int
  -> E.EventBlock tag
  -> [NodeRule]
  -> [NodePatch]
matchingNodePatches _ _ [] = []
matchingNodePatches matchIndex block (rule:rest) =
  case nodeRulePatch matchIndex block rule of
    Nothing    -> matchingNodePatches matchIndex block rest
    Just patch -> patch : matchingNodePatches (matchIndex P.+ 1) block rest

nodeRulePatch ::
     forall sourceTag. C.Traceable sourceTag
  => P.Int
  -> E.EventBlock sourceTag
  -> NodeRule
  -> Maybe NodePatch
nodeRulePatch matchIndex block rule =
  case rule of
    AnyQueryNodeRule query makePatch ->
      case Q.queryMatches query (E.eventBlockFacts block) of
        Nothing       -> Nothing
        Just bindings -> Just (makePatch (Q.queryMatchBindings bindings))
    QueryNodeRule (_ :: Proxy matchedTag) query payloadPattern makePatch ->
      case eqT @sourceTag @matchedTag of
        Nothing -> Nothing
        Just Refl ->
          case Q.queryMatches query (E.eventBlockFacts block) of
            Nothing -> Nothing
            Just bindings ->
              matchedPayloadNodePatch
                matchIndex
                (Q.queryMatchBindings bindings)
                block
                payloadPattern
                makePatch

matchedPayloadNodePatch ::
     P.Int
  -> MatchBindings
  -> E.EventBlock tag
  -> PayloadPattern tag
  -> (MatchContext tag -> NodePatch)
  -> Maybe NodePatch
matchedPayloadNodePatch matchIndex factBindings block payloadPattern makePatch =
  case Q.payloadPatternMatches
         payloadPattern
         (E.eventBlockPayload block)
         (E.eventBlockPayloadView block) of
    Nothing -> Nothing
    Just payloadBindings ->
      Just
        (makePatch
           (MatchContext
              { matchContextIndex = matchIndex
              , matchContextPayload = E.eventBlockPayload block
              , matchContextLabel = E.eventBlockPayloadView block
              , matchContextBindings = factBindings P.++ payloadBindings
              }))

foldNodePatches :: [NodePatch] -> Maybe NodePatch
foldNodePatches patches =
  case patches of
    []         -> Nothing
    patch:rest -> Just (foldNodePatchesFrom patch rest)

foldNodePatchesFrom :: NodePatch -> [NodePatch] -> NodePatch
foldNodePatchesFrom current patches =
  case patches of
    []         -> current
    patch:rest -> foldNodePatchesFrom (VP.appendNodePatch current patch) rest

buildMatchedViewGraph ::
     MatchSpec
  -> [V.ViewStep]
  -> [V.ViewNode]
  -> [S.Constraint]
  -> [[V.RenderIntent]]
  -> V.ViewGraph
buildMatchedViewGraph spec viewSteps' builtNodes builtConstraints renderFrames =
  let traceNodes = applyAccessRequirementsForSpec spec builtNodes
      virtualNodes =
        applyAccessRequirementsForSpec
          spec
          (virtualNodesForSpec spec traceNodes)
      nodes = traceNodes P.++ virtualNodes
      constraints = builtConstraints P.++ matchSpecConstraints spec nodes
   in V.finalizeViewGraph nodes viewSteps' constraints renderFrames

matchSpecConstraints :: MatchSpec -> [V.ViewNode] -> [S.Constraint]
matchSpecConstraints spec nodes =
  case spec of
    MatchSpec _ layoutRules _ ->
      P.concatMap (layoutRuleConstraints nodes) layoutRules

layoutRuleConstraints :: [V.ViewNode] -> LayoutRule -> [S.Constraint]
layoutRuleConstraints nodes layoutRule =
  case layoutRule of
    ValueRelationLayout strength lhs relation rhs ->
      applyConstraintStrength
        strength
        (P.concatMap
           (valueRelationConstraints relation)
           (matchingValueTerms lhs rhs nodes))
    ValueDirectedBridgeLayout strength lhs gap rhs ->
      applyConstraintStrength
        strength
        (P.concatMap
           valueDirectedBridgeConstraints
           (matchingValueTermTriples lhs gap rhs nodes))
    ValueSymmetricBridgeLayout strength lhs delta rhs ->
      applyConstraintStrength
        strength
        (P.concatMap
           valueSymmetricBridgeConstraints
           (matchingValueTermTriples lhs delta rhs nodes))

applyConstraintStrength ::
     ConstraintStrength -> [S.Constraint] -> [S.Constraint]
applyConstraintStrength strength constraints =
  case strength of
    EnsureConstraint    -> constraints
    EncourageConstraint -> P.map S.soften constraints

data LayoutEndpointMatch =
  LayoutEndpointMatch ValueComponent QueryBindings

matchingValueTerms ::
     [ValueEndpoint]
  -> [ValueEndpoint]
  -> [V.ViewNode]
  -> [([ValueComponent], [ValueComponent])]
matchingValueTerms lhs rhs nodes =
  [ (lhsComponents, rhsComponents)
  | ([lhsComponents, rhsComponents], _) <-
      matchingValueTermGroups [lhs, rhs] nodes
  ]

matchingValueTermTriples ::
     [ValueEndpoint]
  -> [ValueEndpoint]
  -> [ValueEndpoint]
  -> [V.ViewNode]
  -> [([ValueComponent], [ValueComponent], [ValueComponent])]
matchingValueTermTriples first second third nodes =
  [ (firstComponents, secondComponents, thirdComponents)
  | ([firstComponents, secondComponents, thirdComponents], _) <-
      matchingValueTermGroups [first, second, third] nodes
  ]

matchingValueTermGroups ::
     [[ValueEndpoint]] -> [V.ViewNode] -> [([[ValueComponent]], QueryBindings)]
matchingValueTermGroups endpointGroups nodes =
  case endpointGroups of
    [] -> [([], [])]
    endpoints:rest ->
      [ (components : restComponents, mergedBindings)
      | (components, bindings) <- matchingValueTerm endpoints nodes
      , (restComponents, restBindings) <- matchingValueTermGroups rest nodes
      , Just mergedBindings <- [mergeQueryBindings bindings restBindings]
      ]

matchingValueTerm ::
     [ValueEndpoint] -> [V.ViewNode] -> [([ValueComponent], QueryBindings)]
matchingValueTerm endpoints nodes =
  case endpoints of
    [] -> [([], [])]
    endpoint:rest ->
      [ (component : restComponents, mergedBindings)
      | LayoutEndpointMatch component bindings <-
          matchingEndpointNodes endpoint nodes
      , (restComponents, restBindings) <- matchingValueTerm rest nodes
      , Just mergedBindings <- [mergeQueryBindings bindings restBindings]
      ]

matchingEndpointNodes :: ValueEndpoint -> [V.ViewNode] -> [LayoutEndpointMatch]
matchingEndpointNodes endpoint nodes =
  case endpoint of
    RawValueEndpoint component -> [LayoutEndpointMatch component []]
    SelectionValueEndpoint selection access ->
      [ LayoutEndpointMatch (VA.valueAccessComponent access node) bindings
      | (node, bindings) <- matchingSelectionNodes selection nodes
      ]

matchingSelectionNodes ::
     NodeSelection -> [V.ViewNode] -> [(V.AnyLayoutView, QueryBindings)]
matchingSelectionNodes selection nodes =
  case nodes of
    [] -> []
    node:rest ->
      selectionNodeMatches selection node
        P.++ matchingSelectionNodes selection rest

selectionNodeMatches ::
     NodeSelection -> V.ViewNode -> [(V.AnyLayoutView, QueryBindings)]
selectionNodeMatches selection node =
  case selection of
    TraceSelection query ->
      case node of
        V.BlockViewNode block ->
          case Q.queryMatchesTags query (V.blockTags block) of
            Nothing       -> []
            Just bindings -> [(V.AnyLayoutBlock block, bindings)]
        V.VirtualViewNode _ -> []
    VirtualSelection key query ->
      case node of
        V.BlockViewNode _ -> []
        V.VirtualViewNode virtual
          | key P.== V.virtualNodeKey virtual
              P.&& Q.queryKey query P.== V.virtualQueryKey virtual ->
            [(V.AnyLayoutVirtual virtual, [])]
          | otherwise -> []

anyBlockQueryMatches ::
     Query -> V.AnyBlockView -> [(V.AnyBlockView, QueryBindings)]
anyBlockQueryMatches query anyBlock =
  case anyBlock of
    V.AnyBlockView block ->
      case Q.queryMatchesTags query (V.blockTags block) of
        Nothing       -> []
        Just bindings -> [(anyBlock, bindings)]

mergeQueryBindings :: QueryBindings -> QueryBindings -> Maybe QueryBindings
mergeQueryBindings lhs rhs =
  case rhs of
    [] -> Just lhs
    (name, value):rest ->
      case Q.bindQueryInt name value lhs of
        Nothing     -> Nothing
        Just merged -> mergeQueryBindings merged rest

valueRelationConstraints ::
     LayoutRelation -> ([ValueComponent], [ValueComponent]) -> [S.Constraint]
valueRelationConstraints relation pair' =
  case pair' of
    (lhsComponents, rhsComponents) ->
      S.relateComponents (termRelation relation) lhsComponents rhsComponents

termRelation :: LayoutRelation -> S.ComponentRelation
termRelation relation =
  case relation of
    LayoutEqual       -> S.ComponentEqual
    LayoutLessOrEqual -> S.ComponentLessOrEqual

valueDirectedBridgeConstraints ::
     ([ValueComponent], [ValueComponent], [ValueComponent]) -> [S.Constraint]
valueDirectedBridgeConstraints triple =
  case triple of
    (lhsComponents, gapComponents, rhsComponents) ->
      S.directedBridgeComponents lhsComponents gapComponents rhsComponents

valueSymmetricBridgeConstraints ::
     ([ValueComponent], [ValueComponent], [ValueComponent]) -> [S.Constraint]
valueSymmetricBridgeConstraints triple =
  case triple of
    (lhsComponents, deltaComponents, rhsComponents) ->
      S.symmetricBridgeComponents lhsComponents deltaComponents rhsComponents

applyAccessRequirementsForSpec :: MatchSpec -> [V.ViewNode] -> [V.ViewNode]
applyAccessRequirementsForSpec spec nodes =
  case spec of
    MatchSpec _ layoutRules _ ->
      P.map (applyAccessRequirementsForRules layoutRules) nodes

applyAccessRequirementsForRules :: [LayoutRule] -> V.ViewNode -> V.ViewNode
applyAccessRequirementsForRules rules node =
  case rules of
    [] -> node
    rule:rest ->
      applyAccessRequirementsForRules
        rest
        (applyAccessRequirementsForRule rule node)

applyAccessRequirementsForRule :: LayoutRule -> V.ViewNode -> V.ViewNode
applyAccessRequirementsForRule rule node =
  case rule of
    ValueRelationLayout _ lhs _ rhs ->
      applyAccessRequirementsForEndpoints (lhs P.++ rhs) node
    ValueDirectedBridgeLayout _ lhs gap rhs ->
      applyAccessRequirementsForEndpoints (lhs P.++ gap P.++ rhs) node
    ValueSymmetricBridgeLayout _ lhs delta rhs ->
      applyAccessRequirementsForEndpoints (lhs P.++ delta P.++ rhs) node

applyAccessRequirementsForEndpoints ::
     [ValueEndpoint] -> V.ViewNode -> V.ViewNode
applyAccessRequirementsForEndpoints endpoints node =
  case endpoints of
    [] -> node
    endpoint:rest ->
      applyAccessRequirementsForEndpoints
        rest
        (applyAccessRequirementsForEndpoint endpoint node)

applyAccessRequirementsForEndpoint :: ValueEndpoint -> V.ViewNode -> V.ViewNode
applyAccessRequirementsForEndpoint endpoint node =
  case endpoint of
    RawValueEndpoint _ -> node
    SelectionValueEndpoint selection access ->
      case nodeMatchesSelection selection node of
        False -> node
        True ->
          VA.applyStyleRequirements (VA.valueAccessRequirements access) node

nodeMatchesSelection :: NodeSelection -> V.ViewNode -> P.Bool
nodeMatchesSelection selection node =
  case selectionNodeMatches selection node of
    [] -> False
    _  -> True

virtualNodesForSpec :: MatchSpec -> [V.ViewNode] -> [V.ViewNode]
virtualNodesForSpec spec nodes =
  case spec of
    MatchSpec _ _ virtualRules ->
      maybeVirtualNodes (mergedVirtualRules virtualRules)
  where
    blocks = V.viewNodeBlocks nodes
    maybeVirtualNodes rules =
      case rules of
        [] -> []
        rule:rest ->
          case virtualNodeForRule blocks rule of
            Nothing   -> maybeVirtualNodes rest
            Just node -> node : maybeVirtualNodes rest

mergedVirtualRules :: [VirtualRule] -> [VirtualRule]
mergedVirtualRules rules =
  case rules of
    [] -> []
    VirtualRule key query patch:rest ->
      case mergeVirtualRule key query patch rest of
        (mergedPatch, remaining) ->
          VirtualRule key query mergedPatch : mergedVirtualRules remaining

mergeVirtualRule ::
     P.String
  -> Query
  -> NodePatch
  -> [VirtualRule]
  -> (NodePatch, [VirtualRule])
mergeVirtualRule key query patch rules =
  case rules of
    [] -> (patch, [])
    VirtualRule nextKey nextQuery nextPatch:rest ->
      case key P.== nextKey P.&& query P.== nextQuery of
        True ->
          mergeVirtualRule key query (VP.appendNodePatch patch nextPatch) rest
        False ->
          case mergeVirtualRule key query patch rest of
            (mergedPatch, remaining) ->
              (mergedPatch, VirtualRule nextKey nextQuery nextPatch : remaining)

virtualNodeForRule :: [V.AnyBlockView] -> VirtualRule -> Maybe V.ViewNode
virtualNodeForRule blocks rule =
  case rule of
    VirtualRule key query patch ->
      case matchingQueryBlocks query blocks of
        [] -> Nothing
        children ->
          Just
            (V.VirtualViewNode
               (virtualViewForRule key query patch children :: V.VirtualView ()))

matchingQueryBlocks :: Query -> [V.AnyBlockView] -> [V.AnyBlockView]
matchingQueryBlocks query blocks =
  [ anyBlock
  | anyBlock <- blocks
  , (_matchedNode, _bindings) <- anyBlockQueryMatches query anyBlock
  ]

virtualViewForRule ::
     P.String -> Query -> NodePatch -> [V.AnyBlockView] -> V.VirtualView tag
virtualViewForRule key query patch children =
  let queryKey' = Q.queryKey query
      ref = V.syntheticViewRef (V.virtualBlockId key queryKey')
      baseStyle = V.styleForVirtualKey key queryKey'
      virtualStyle = VP.nodePatchStyleUpdate patch baseStyle
   in V.VirtualView
        { V.virtualRef = ref
        , V.virtualLabel = V.ViewLabel ("Virtual." P.++ key) ""
        , V.virtualContent =
            fromMaybe V.ContentEmpty (VP.nodePatchContent patch)
        , V.virtualQueryKey = queryKey'
        , V.virtualNodeKey = key
        , V.virtualPieceKey = V.defaultPieceKey
        , V.virtualStyle = virtualStyle
        , V.virtualConstraints = VP.patchGeometryConstraints patch virtualStyle
        , V.virtualChildren = children
        }
