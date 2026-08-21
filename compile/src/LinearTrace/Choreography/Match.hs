{-# LANGUAGE GADTs               #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

-- | Choreography matching and view graph assembly. This module binds
-- core trace events to 'LinearTrace.View' by turning query matches, node
-- patches, and value endpoints into symbolic view output.
module LinearTrace.Choreography.Match
  ( -- * Match specs
    -- | Accumulated node, layout, and grouping rules produced by the
    -- public choreography DSL.
    MatchSpec
  , emptyMatchSpec
  , matchSpecAppend
  , matchQueryNode
  , matchAnyQueryNode
  , matchQueryPayloadNode
  , matchGroupNode
  , MatchContext(..)
  , -- * Layout/value relations
    -- | Selection and component relation API. The DSL uses this to connect
    -- view lifespans and style/layout values through solver constraints.
    NodeSelection(..)
  , ConstraintStrength(..)
  , LayoutRelation(..)
  , CategoryRelation(..)
  , ValueComponent
  , ValueEndpoint
  , CategoryEndpoint
  , rawValueEndpoint
  , rawCategoryEndpoint
  , selectionValueEndpoint
  , selectionCategoryEndpoint
  , matchValueRelation
  , matchCategoryRelation
  , matchValueDirectedBridge
  , matchValueSymmetricBridge
  , -- * View graph assembly
    -- | Internal bridge from core event blocks to view nodes. Choreography is
    -- the intended caller; this is not re-exported directly to DSL users.
    traceNodeOfEventBlock
  , matchedNodeOutput
  , buildMatchedViewGraph
  ) where

import           Data.Maybe              (fromMaybe)
import           Data.Proxy              (Proxy (..))
import           Data.Type.Equality      ((:~:) (..))
import           Data.Typeable           (eqT)
import qualified LinearTrace.Core        as C
import qualified LinearTrace.View        as V
import qualified LinearTrace.View.Access as VA
import qualified LinearTrace.View.Patch  as VP
import           Prelude                 (Bool (..), Maybe (..), otherwise)
import qualified Prelude                 as P
import qualified Solver                  as S

type ValueComponent = VA.ValueComponent

type NodePatch = VP.NodePatch

data NodeSelection
  = TraceSelection C.Query
  | GroupSelection P.String C.Query
  deriving (P.Eq, P.Show)

data ConstraintStrength
  = EnsureConstraint
  | EncourageConstraint
  deriving (P.Eq, P.Show)

data LayoutRelation
  = LayoutEqual
  | LayoutLessOrEqual
  deriving (P.Eq, P.Show)

data CategoryRelation
  = CategoryEqual
  | CategoryDifferent
  deriving (P.Eq, P.Show)

data ValueEndpoint
  = RawValueEndpoint ValueComponent
  | SelectionValueEndpoint NodeSelection VA.ValueAccess

data CategoryEndpoint value
  = RawCategoryEndpoint (S.ChoiceValue value)
  | SelectionCategoryEndpoint NodeSelection (VA.CategoryAccess value)

data MatchSpec =
  MatchSpec [NodeRule] [LayoutRule] [GroupRule]

data NodeRule where
  QueryNodeRule
    :: C.Traceable tag=> Proxy tag
    -> C.Query
    -> C.PayloadPattern tag
    -> (MatchContext tag -> NodePatch)
    -> NodeRule
  AnyQueryNodeRule :: C.Query -> (C.MatchBindings -> NodePatch) -> NodeRule

data MatchContext tag = MatchContext
  { matchContextIndex    :: P.Int
  , matchContextPayload  :: C.Payload tag
  , matchContextLabel    :: C.PayloadView
  , matchContextBindings :: C.MatchBindings
  }

data LayoutRule where
  ValueRelationLayout
    :: ConstraintStrength
    -> [ValueEndpoint]
    -> LayoutRelation
    -> [ValueEndpoint]
    -> LayoutRule
  CategoryRelationLayout
    :: S.ChoiceDomain value=> ConstraintStrength
    -> [CategoryEndpoint value]
    -> CategoryRelation
    -> [CategoryEndpoint value]
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

data GroupRule =
  GroupRule P.String C.Query NodePatch

emptyMatchSpec :: MatchSpec
emptyMatchSpec = MatchSpec [] [] []

matchSpecAppend :: MatchSpec -> MatchSpec -> MatchSpec
matchSpecAppend lhs rhs =
  case lhs of
    MatchSpec leftNodes leftLayouts leftGroups ->
      case rhs of
        MatchSpec rightNodes rightLayouts rightGroups ->
          MatchSpec
            (leftNodes P.++ rightNodes)
            (leftLayouts P.++ rightLayouts)
            (leftGroups P.++ rightGroups)

matchQueryNode ::
     forall tag. C.Traceable tag
  => C.Query
  -> (MatchContext tag -> NodePatch)
  -> MatchSpec
matchQueryNode query makePatch =
  MatchSpec
    [QueryNodeRule (Proxy :: Proxy tag) query C.anyPayloadPattern makePatch]
    []
    []

matchAnyQueryNode :: C.Query -> (C.MatchBindings -> NodePatch) -> MatchSpec
matchAnyQueryNode query makePatch =
  MatchSpec [AnyQueryNodeRule query makePatch] [] []

matchQueryPayloadNode ::
     forall tag. C.Traceable tag
  => C.Query
  -> C.PayloadPattern tag
  -> (MatchContext tag -> NodePatch)
  -> MatchSpec
matchQueryPayloadNode query payloadPattern makePatch =
  MatchSpec
    [QueryNodeRule (Proxy :: Proxy tag) query payloadPattern makePatch]
    []
    []

matchGroupNode :: P.String -> C.Query -> NodePatch -> MatchSpec
matchGroupNode key query patch =
  MatchSpec [] [] [GroupRule (C.safeKey key) query patch]

rawValueEndpoint :: ValueComponent -> ValueEndpoint
rawValueEndpoint = RawValueEndpoint

rawCategoryEndpoint :: S.ChoiceValue value -> CategoryEndpoint value
rawCategoryEndpoint = RawCategoryEndpoint

selectionValueEndpoint :: NodeSelection -> VA.ValueAccess -> ValueEndpoint
selectionValueEndpoint = SelectionValueEndpoint

selectionCategoryEndpoint ::
     NodeSelection -> VA.CategoryAccess value -> CategoryEndpoint value
selectionCategoryEndpoint = SelectionCategoryEndpoint

matchValueRelation ::
     ConstraintStrength
  -> [ValueEndpoint]
  -> LayoutRelation
  -> [ValueEndpoint]
  -> MatchSpec
matchValueRelation strength lhs relation rhs =
  MatchSpec [] [ValueRelationLayout strength lhs relation rhs] []

matchCategoryRelation ::
     S.ChoiceDomain value
  => ConstraintStrength
  -> [CategoryEndpoint value]
  -> CategoryRelation
  -> [CategoryEndpoint value]
  -> MatchSpec
matchCategoryRelation strength lhs relation rhs =
  MatchSpec [] [CategoryRelationLayout strength lhs relation rhs] []

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

traceNodeOfEventBlock :: C.BlockSnapshot tag -> V.Node tag
traceNodeOfEventBlock block =
  let ref = coreViewRef (C.blockSnapshotRef block)
   in V.Node
        { V.nodeRef = ref
        , V.nodeLabel =
            viewLabelFromPayloadView (C.blockSnapshotPayloadView block)
        , V.nodeContent = V.ContentEmpty
        , V.nodeStyle = V.styleForRef ref
        , V.nodeOrigin =
            V.TraceOrigin (viewTagsFromFacts (C.blockSnapshotFacts block))
        , V.nodeStructure = V.LeafNode
        , V.nodeConstraints = []
        }

matchedNodeOutput :: MatchSpec -> C.BlockSnapshot tag -> V.ViewOutput
matchedNodeOutput spec eventBlock =
  C.withBlockSnapshot
    eventBlock
    (case spec of
       MatchSpec nodeRules _ _ ->
         let node = traceNodeOfEventBlock eventBlock
          in case matchedNodePatch eventBlock nodeRules of
               Nothing    -> P.mempty
               Just patch -> V.patchedNodeOutput patch node)

coreViewRef :: C.BlockRef tag -> V.ViewRef tag
coreViewRef ref = V.viewRefFromId (C.blockRefId ref)

viewLabelFromPayloadView :: C.PayloadView -> V.ViewLabel
viewLabelFromPayloadView payloadViewValue =
  case payloadViewValue of
    C.PayloadView kind -> V.ViewLabel kind

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
  => C.BlockSnapshot tag
  -> [NodeRule]
  -> Maybe NodePatch
matchedNodePatch block rules =
  foldNodePatches (matchingNodePatches 0 block rules)

matchingNodePatches ::
     forall tag. C.Traceable tag
  => P.Int
  -> C.BlockSnapshot tag
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
  -> C.BlockSnapshot sourceTag
  -> NodeRule
  -> Maybe NodePatch
nodeRulePatch matchIndex block rule =
  case rule of
    AnyQueryNodeRule query makePatch ->
      case C.queryMatches query (C.blockSnapshotFacts block) of
        Nothing       -> Nothing
        Just bindings -> Just (makePatch (C.queryMatchBindings bindings))
    QueryNodeRule (_ :: Proxy matchedTag) query payloadPattern makePatch ->
      case eqT @sourceTag @matchedTag of
        Nothing -> Nothing
        Just Refl ->
          case C.queryMatches query (C.blockSnapshotFacts block) of
            Nothing -> Nothing
            Just bindings ->
              matchedPayloadNodePatch
                matchIndex
                (C.queryMatchBindings bindings)
                block
                payloadPattern
                makePatch

matchedPayloadNodePatch ::
     P.Int
  -> C.MatchBindings
  -> C.BlockSnapshot tag
  -> C.PayloadPattern tag
  -> (MatchContext tag -> NodePatch)
  -> Maybe NodePatch
matchedPayloadNodePatch matchIndex factBindings block payloadPattern makePatch =
  case C.payloadPatternMatches payloadPattern (C.blockSnapshotPayload block) of
    Nothing -> Nothing
    Just payloadBindings ->
      Just
        (makePatch
           (MatchContext
              { matchContextIndex = matchIndex
              , matchContextPayload = C.blockSnapshotPayload block
              , matchContextLabel = C.blockSnapshotPayloadView block
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
  -> [V.ViewNode]
  -> [[V.RenderIntent]]
  -> V.ViewGraph
buildMatchedViewGraph spec builtNodes renderFrames =
  let traceNodes = applyAccessRequirementsForSpec spec builtNodes
      groupNodes =
        applyAccessRequirementsForSpec spec (groupNodesForSpec spec traceNodes)
      nodes = traceNodes P.++ groupNodes
      (matchConstraints, matchChoiceConstraints) =
        matchSpecConstraints spec nodes
   in V.finalizeViewGraph
        nodes
        matchConstraints
        matchChoiceConstraints
        renderFrames

matchSpecConstraints ::
     MatchSpec -> [V.ViewNode] -> ([S.Constraint], [S.ChoiceConstraint])
matchSpecConstraints spec nodes =
  case spec of
    MatchSpec _ layoutRules _ ->
      foldConstraintPairs (P.map (layoutRuleConstraints nodes) layoutRules)

foldConstraintPairs ::
     [([S.Constraint], [S.ChoiceConstraint])]
  -> ([S.Constraint], [S.ChoiceConstraint])
foldConstraintPairs pairs =
  case pairs of
    [] -> ([], [])
    (constraints, choiceConstraints):rest ->
      case foldConstraintPairs rest of
        (restConstraints, restChoiceConstraints) ->
          ( constraints P.++ restConstraints
          , choiceConstraints P.++ restChoiceConstraints)

layoutRuleConstraints ::
     [V.ViewNode] -> LayoutRule -> ([S.Constraint], [S.ChoiceConstraint])
layoutRuleConstraints nodes layoutRule =
  case layoutRule of
    ValueRelationLayout strength lhs relation rhs ->
      ( applyConstraintStrength
          strength
          (P.concatMap
             (valueRelationConstraints relation)
             (matchingValueTerms lhs rhs nodes))
      , [])
    CategoryRelationLayout _ lhs relation rhs ->
      ( []
      , P.concatMap
          (categoryRelationConstraints relation)
          (matchingCategoryTerms lhs rhs nodes))
    ValueDirectedBridgeLayout strength lhs gap rhs ->
      ( applyConstraintStrength
          strength
          (P.concatMap
             valueDirectedBridgeConstraints
             (matchingValueTermTriples lhs gap rhs nodes))
      , [])
    ValueSymmetricBridgeLayout strength lhs delta rhs ->
      ( applyConstraintStrength
          strength
          (P.concatMap
             valueSymmetricBridgeConstraints
             (matchingValueTermTriples lhs delta rhs nodes))
      , [])

applyConstraintStrength ::
     ConstraintStrength -> [S.Constraint] -> [S.Constraint]
applyConstraintStrength strength constraints =
  case strength of
    EnsureConstraint    -> constraints
    EncourageConstraint -> P.map S.soften constraints

data LayoutEndpointMatch =
  LayoutEndpointMatch ValueComponent C.QueryBindings

data CategoryEndpointMatch value =
  CategoryEndpointMatch (S.ChoiceValue value) C.QueryBindings

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
     [[ValueEndpoint]]
  -> [V.ViewNode]
  -> [([[ValueComponent]], C.QueryBindings)]
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
     [ValueEndpoint] -> [V.ViewNode] -> [([ValueComponent], C.QueryBindings)]
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

matchingCategoryTerms ::
     [CategoryEndpoint value]
  -> [CategoryEndpoint value]
  -> [V.ViewNode]
  -> [([S.ChoiceValue value], [S.ChoiceValue value])]
matchingCategoryTerms lhs rhs nodes =
  [ (lhsCategories, rhsCategories)
  | ([lhsCategories, rhsCategories], _) <-
      matchingCategoryTermGroups [lhs, rhs] nodes
  ]

matchingCategoryTermGroups ::
     [[CategoryEndpoint value]]
  -> [V.ViewNode]
  -> [([[S.ChoiceValue value]], C.QueryBindings)]
matchingCategoryTermGroups endpointGroups nodes =
  case endpointGroups of
    [] -> [([], [])]
    endpoints:rest ->
      [ (categories : restCategories, mergedBindings)
      | (categories, bindings) <- matchingCategoryTerm endpoints nodes
      , (restCategories, restBindings) <- matchingCategoryTermGroups rest nodes
      , Just mergedBindings <- [mergeQueryBindings bindings restBindings]
      ]

matchingCategoryTerm ::
     [CategoryEndpoint value]
  -> [V.ViewNode]
  -> [([S.ChoiceValue value], C.QueryBindings)]
matchingCategoryTerm endpoints nodes =
  case endpoints of
    [] -> [([], [])]
    endpoint:rest ->
      [ (categoryValue : restCategories, mergedBindings)
      | CategoryEndpointMatch categoryValue bindings <-
          matchingCategoryEndpointNodes endpoint nodes
      , (restCategories, restBindings) <- matchingCategoryTerm rest nodes
      , Just mergedBindings <- [mergeQueryBindings bindings restBindings]
      ]

matchingCategoryEndpointNodes ::
     CategoryEndpoint value -> [V.ViewNode] -> [CategoryEndpointMatch value]
matchingCategoryEndpointNodes endpoint nodes =
  case endpoint of
    RawCategoryEndpoint categoryValue ->
      [CategoryEndpointMatch categoryValue []]
    SelectionCategoryEndpoint selection access ->
      [ CategoryEndpointMatch (VA.categoryAccessValue access node) bindings
      | (node, bindings) <- matchingSelectionNodes selection nodes
      ]

matchingSelectionNodes ::
     NodeSelection -> [V.ViewNode] -> [(V.AnyLayoutView, C.QueryBindings)]
matchingSelectionNodes selection nodes =
  case nodes of
    [] -> []
    node:rest ->
      selectionNodeMatches selection node
        P.++ matchingSelectionNodes selection rest

selectionNodeMatches ::
     NodeSelection -> V.ViewNode -> [(V.AnyLayoutView, C.QueryBindings)]
selectionNodeMatches selection wrapped =
  case wrapped of
    V.ViewNode node ->
      case selection of
        TraceSelection query ->
          case V.traceNodeTags node of
            Nothing -> []
            Just tags ->
              case queryMatchesViewTags query tags of
                Nothing       -> []
                Just bindings -> [(V.AnyLayoutView node, bindings)]
        GroupSelection key query ->
          case V.generatedNodeMeta node of
            Just meta
              | key P.== V.generatedKey meta
                  P.&& C.queryKey query P.== V.generatedQueryKey meta ->
                [(V.AnyLayoutView node, [])]
            _ -> []

traceNodeQueryMatches ::
     C.Query -> V.AnyTraceNode -> [(V.AnyTraceNode, C.QueryBindings)]
traceNodeQueryMatches query anyNode =
  case anyNode of
    V.AnyTraceNode node ->
      case V.traceNodeTags node of
        Nothing -> []
        Just tags ->
          case queryMatchesViewTags query tags of
            Nothing       -> []
            Just bindings -> [(anyNode, bindings)]

queryMatchesViewTags :: C.Query -> V.ViewTags -> Maybe C.QueryBindings
queryMatchesViewTags query tags = C.queryMatches query (viewTagsFacts tags)

viewTagsFacts :: V.ViewTags -> C.Facts
viewTagsFacts tags = C.Facts (P.map viewTagFact (V.viewTagsToList tags))

viewTagFact :: (P.String, V.ViewTagValue) -> C.Fact
viewTagFact tag =
  case tag of
    (name, value) ->
      case value of
        V.ViewTagAtom    -> C.factAtom name
        V.ViewTagInt int -> C.factInt name int

mergeQueryBindings ::
     C.QueryBindings -> C.QueryBindings -> Maybe C.QueryBindings
mergeQueryBindings lhs rhs =
  case rhs of
    [] -> Just lhs
    (name, value):rest ->
      case C.bindQueryInt name value lhs of
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

categoryRelationConstraints ::
     S.ChoiceDomain value
  => CategoryRelation
  -> ([S.ChoiceValue value], [S.ChoiceValue value])
  -> [S.ChoiceConstraint]
categoryRelationConstraints relation pair' =
  case pair' of
    (lhsCategories, rhsCategories) ->
      zipCategoryConstraints relation lhsCategories rhsCategories

zipCategoryConstraints ::
     S.ChoiceDomain value
  => CategoryRelation
  -> [S.ChoiceValue value]
  -> [S.ChoiceValue value]
  -> [S.ChoiceConstraint]
zipCategoryConstraints relation lhs rhs =
  case (lhs, rhs) of
    ([], []) -> []
    (lhsCategory:lhsRest, rhsCategory:rhsRest) ->
      categoryValueRelationConstraints relation lhsCategory rhsCategory
        P.++ zipCategoryConstraints relation lhsRest rhsRest
    _ ->
      P.error "Cannot relate category values with different component counts."

categoryValueRelationConstraints ::
     S.ChoiceDomain value
  => CategoryRelation
  -> S.ChoiceValue value
  -> S.ChoiceValue value
  -> [S.ChoiceConstraint]
categoryValueRelationConstraints relation lhs rhs =
  case relation of
    CategoryEqual     -> categoryEqualConstraints lhs rhs
    CategoryDifferent -> categoryDifferentConstraints lhs rhs

categoryEqualConstraints ::
     S.ChoiceDomain value
  => S.ChoiceValue value
  -> S.ChoiceValue value
  -> [S.ChoiceConstraint]
categoryEqualConstraints lhs rhs =
  case (lhs, rhs) of
    (S.Fixed lhsValue, S.Fixed rhsValue)
      | categoryTokensEqual lhsValue rhsValue -> []
      | otherwise -> impossibleCategoryConstraints lhsValue
    (S.Fixed fixed, S.Variable selected) -> [S.choose selected fixed]
    (S.Variable selected, S.Fixed fixed) -> [S.choose selected fixed]
    (S.Variable lhsChoice, S.Variable rhsChoice) ->
      [S.sameChoice lhsChoice rhsChoice]

categoryDifferentConstraints ::
     S.ChoiceDomain value
  => S.ChoiceValue value
  -> S.ChoiceValue value
  -> [S.ChoiceConstraint]
categoryDifferentConstraints lhs rhs =
  case (lhs, rhs) of
    (S.Fixed lhsValue, S.Fixed rhsValue)
      | categoryTokensEqual lhsValue rhsValue ->
        impossibleCategoryConstraints lhsValue
      | otherwise -> []
    (S.Fixed fixed, S.Variable selected) ->
      fixedCategoryChoiceConstraints fixed
        P.++ [S.differentChoice (fixedCategoryChoice fixed) selected]
    (S.Variable selected, S.Fixed fixed) ->
      fixedCategoryChoiceConstraints fixed
        P.++ [S.differentChoice selected (fixedCategoryChoice fixed)]
    (S.Variable lhsChoice, S.Variable rhsChoice) ->
      [S.differentChoice lhsChoice rhsChoice]

categoryTokensEqual :: S.ChoiceDomain value => value -> value -> P.Bool
categoryTokensEqual lhs rhs = S.choiceToken lhs P.== S.choiceToken rhs

fixedCategoryChoiceConstraints ::
     S.ChoiceDomain value => value -> [S.ChoiceConstraint]
fixedCategoryChoiceConstraints value =
  [S.choose (fixedCategoryChoice value) value]

impossibleCategoryConstraints ::
     S.ChoiceDomain value => value -> [S.ChoiceConstraint]
impossibleCategoryConstraints value =
  let selected = fixedCategoryChoice value
   in [S.differentChoice selected selected]

fixedCategoryChoice :: S.ChoiceDomain value => value -> S.Choice value
fixedCategoryChoice value = S.choice (fixedCategoryChoiceName value)

fixedCategoryChoiceName :: S.ChoiceDomain value => value -> P.String
fixedCategoryChoiceName value =
  "view.fixed." P.++ categoryDomainKey value P.++ "." P.++ S.choiceToken value

categoryDomainKey ::
     forall value. S.ChoiceDomain value
  => value
  -> P.String
categoryDomainKey _ =
  joinCategoryTokens (P.map S.choiceToken (S.choiceDomain :: [value]))

joinCategoryTokens :: [P.String] -> P.String
joinCategoryTokens tokens =
  case tokens of
    []         -> "empty"
    token:rest -> token P.++ joinCategoryTokenRest rest

joinCategoryTokenRest :: [P.String] -> P.String
joinCategoryTokenRest tokens =
  case tokens of
    []         -> ""
    token:rest -> "-" P.++ token P.++ joinCategoryTokenRest rest

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
    CategoryRelationLayout _ lhs _ rhs ->
      applyAccessRequirementsForCategoryEndpoints (lhs P.++ rhs) node
    ValueDirectedBridgeLayout _ lhs gap rhs ->
      applyAccessRequirementsForEndpoints (lhs P.++ gap P.++ rhs) node
    ValueSymmetricBridgeLayout _ lhs delta rhs ->
      applyAccessRequirementsForEndpoints (lhs P.++ delta P.++ rhs) node

applyAccessRequirementsForCategoryEndpoints ::
     [CategoryEndpoint value] -> V.ViewNode -> V.ViewNode
applyAccessRequirementsForCategoryEndpoints endpoints node =
  case endpoints of
    [] -> node
    endpoint:rest ->
      applyAccessRequirementsForCategoryEndpoints
        rest
        (applyAccessRequirementsForCategoryEndpoint endpoint node)

applyAccessRequirementsForCategoryEndpoint ::
     CategoryEndpoint value -> V.ViewNode -> V.ViewNode
applyAccessRequirementsForCategoryEndpoint endpoint node =
  case endpoint of
    RawCategoryEndpoint _ -> node
    SelectionCategoryEndpoint selection access ->
      case nodeMatchesSelection selection node of
        False -> node
        True ->
          VA.applyStyleRequirements (VA.categoryAccessRequirements access) node

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

groupNodesForSpec :: MatchSpec -> [V.ViewNode] -> [V.ViewNode]
groupNodesForSpec spec nodes =
  case spec of
    MatchSpec _ _ groupRules -> maybeGroupNodes (mergedGroupRules groupRules)
  where
    traceNodes = V.viewTraceNodes nodes
    maybeGroupNodes rules =
      case rules of
        [] -> []
        rule:rest ->
          case groupNodeForRule traceNodes rule of
            Nothing   -> maybeGroupNodes rest
            Just node -> node : maybeGroupNodes rest

mergedGroupRules :: [GroupRule] -> [GroupRule]
mergedGroupRules rules =
  case rules of
    [] -> []
    GroupRule key query patch:rest ->
      case mergeGroupRule key query patch rest of
        (mergedPatch, remaining) ->
          GroupRule key query mergedPatch : mergedGroupRules remaining

mergeGroupRule ::
     P.String -> C.Query -> NodePatch -> [GroupRule] -> (NodePatch, [GroupRule])
mergeGroupRule key query patch rules =
  case rules of
    [] -> (patch, [])
    GroupRule nextKey nextQuery nextPatch:rest ->
      case key P.== nextKey P.&& query P.== nextQuery of
        True ->
          mergeGroupRule key query (VP.appendNodePatch patch nextPatch) rest
        False ->
          case mergeGroupRule key query patch rest of
            (mergedPatch, remaining) ->
              (mergedPatch, GroupRule nextKey nextQuery nextPatch : remaining)

groupNodeForRule :: [V.AnyTraceNode] -> GroupRule -> Maybe V.ViewNode
groupNodeForRule traceNodes rule =
  case rule of
    GroupRule key query patch ->
      case matchingQueryTraceNodes query traceNodes of
        [] -> Nothing
        children ->
          Just
            (V.ViewNode
               (generatedCompoundNodeForRule key query patch children :: V.Node
                  ()))

matchingQueryTraceNodes :: C.Query -> [V.AnyTraceNode] -> [V.AnyTraceNode]
matchingQueryTraceNodes query nodes =
  [ anyNode
  | anyNode <- nodes
  , (_matchedNode, _bindings) <- traceNodeQueryMatches query anyNode
  ]

generatedCompoundNodeForRule ::
     P.String -> C.Query -> NodePatch -> [V.AnyTraceNode] -> V.Node tag
generatedCompoundNodeForRule key query patch children =
  let queryKey' = C.queryKey query
      ref = V.viewRefFromId (V.generatedNodeId key queryKey')
      baseStyle = V.styleForNodeRoot (V.generatedNodeRoot key queryKey')
      style' = VP.nodePatchStyleUpdate patch baseStyle
   in V.Node
        { V.nodeRef = ref
        , V.nodeLabel = V.ViewLabel ("Group." P.++ key)
        , V.nodeContent = fromMaybe V.ContentEmpty (VP.nodePatchContent patch)
        , V.nodeStyle = style'
        , V.nodeOrigin =
            V.GeneratedOrigin
              V.GeneratedMeta
                {V.generatedKey = key, V.generatedQueryKey = queryKey'}
        , V.nodeStructure =
            V.CompoundNode
              V.ShrinkWrapChildren
              (P.map V.nodeChildFromTraceNode children)
        , V.nodeConstraints = VP.patchGeometryConstraints patch style'
        }
