{-# LANGUAGE GADTs               #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

-- | Choreography matching and view graph assembly. This module binds
-- 'LinearTrace.Core.Events' to 'LinearTrace.View' by turning query matches,
-- node patches, and value endpoints into symbolic view output.
module LinearTrace.Choreography.Match
  ( -- * Match specs
    -- | Accumulated node, layout, and virtual grouping rules produced by the
    -- public choreography DSL.
    MatchSpec
  , emptyMatchSpec
  , matchSpecAppend
  , matchQueryNode
  , matchAnyQueryNode
  , matchQueryPayloadNode
  , matchVirtualNode
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
    blockViewOfEventBlock
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
import qualified LinearTrace.View.Style         as VS
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

data CategoryRelation
  = CategoryEqual
  | CategoryDifferent
  deriving (P.Eq, P.Show)

data ValueEndpoint
  = RawValueEndpoint ValueComponent
  | SelectionValueEndpoint NodeSelection VA.ValueAccess

data CategoryEndpoint value
  = RawCategoryEndpoint (VS.StyleCategory value)
  | SelectionCategoryEndpoint NodeSelection (VA.CategoryAccess value)

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
  CategoryRelationLayout
    :: VS.StyleCategoryType value=> ConstraintStrength
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

rawCategoryEndpoint :: VS.StyleCategory value -> CategoryEndpoint value
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
     VS.StyleCategoryType value
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
  -> [S.ChoiceConstraint]
  -> [[V.RenderIntent]]
  -> V.ViewGraph
buildMatchedViewGraph spec viewSteps' builtNodes builtConstraints builtChoiceConstraints renderFrames =
  let traceNodes = applyAccessRequirementsForSpec spec builtNodes
      virtualNodes =
        applyAccessRequirementsForSpec
          spec
          (virtualNodesForSpec spec traceNodes)
      nodes = traceNodes P.++ virtualNodes
      (matchConstraints, matchChoiceConstraints) =
        matchSpecConstraints spec nodes
      constraints = builtConstraints P.++ matchConstraints
      choiceConstraints = builtChoiceConstraints P.++ matchChoiceConstraints
   in V.finalizeViewGraph
        nodes
        viewSteps'
        constraints
        choiceConstraints
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
  LayoutEndpointMatch ValueComponent QueryBindings

data CategoryEndpointMatch value =
  CategoryEndpointMatch (VS.StyleCategory value) QueryBindings

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

matchingCategoryTerms ::
     [CategoryEndpoint value]
  -> [CategoryEndpoint value]
  -> [V.ViewNode]
  -> [([VS.StyleCategory value], [VS.StyleCategory value])]
matchingCategoryTerms lhs rhs nodes =
  [ (lhsCategories, rhsCategories)
  | ([lhsCategories, rhsCategories], _) <-
      matchingCategoryTermGroups [lhs, rhs] nodes
  ]

matchingCategoryTermGroups ::
     [[CategoryEndpoint value]]
  -> [V.ViewNode]
  -> [([[VS.StyleCategory value]], QueryBindings)]
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
  -> [([VS.StyleCategory value], QueryBindings)]
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

categoryRelationConstraints ::
     VS.StyleCategoryType value
  => CategoryRelation
  -> ([VS.StyleCategory value], [VS.StyleCategory value])
  -> [S.ChoiceConstraint]
categoryRelationConstraints relation pair' =
  case pair' of
    (lhsCategories, rhsCategories) ->
      zipCategoryConstraints relation lhsCategories rhsCategories

zipCategoryConstraints ::
     VS.StyleCategoryType value
  => CategoryRelation
  -> [VS.StyleCategory value]
  -> [VS.StyleCategory value]
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
     VS.StyleCategoryType value
  => CategoryRelation
  -> VS.StyleCategory value
  -> VS.StyleCategory value
  -> [S.ChoiceConstraint]
categoryValueRelationConstraints relation lhs rhs =
  case relation of
    CategoryEqual     -> categoryEqualConstraints lhs rhs
    CategoryDifferent -> categoryDifferentConstraints lhs rhs

categoryEqualConstraints ::
     VS.StyleCategoryType value
  => VS.StyleCategory value
  -> VS.StyleCategory value
  -> [S.ChoiceConstraint]
categoryEqualConstraints lhs rhs =
  case (lhs, rhs) of
    (VS.FixedCategory lhsValue, VS.FixedCategory rhsValue)
      | categoryTokensEqual lhsValue rhsValue -> []
      | otherwise -> impossibleCategoryConstraints lhsValue
    (VS.FixedCategory fixed, VS.VariableCategory selected) ->
      [S.choose selected (S.category (VS.styleCategoryToken fixed))]
    (VS.VariableCategory selected, VS.FixedCategory fixed) ->
      [S.choose selected (S.category (VS.styleCategoryToken fixed))]
    (VS.VariableCategory lhsChoice, VS.VariableCategory rhsChoice) ->
      [S.sameChoice lhsChoice rhsChoice]

categoryDifferentConstraints ::
     VS.StyleCategoryType value
  => VS.StyleCategory value
  -> VS.StyleCategory value
  -> [S.ChoiceConstraint]
categoryDifferentConstraints lhs rhs =
  case (lhs, rhs) of
    (VS.FixedCategory lhsValue, VS.FixedCategory rhsValue)
      | categoryTokensEqual lhsValue rhsValue ->
        impossibleCategoryConstraints lhsValue
      | otherwise -> []
    (VS.FixedCategory fixed, VS.VariableCategory selected) ->
      fixedCategoryChoiceConstraints fixed
        P.++ [S.differentChoice (fixedCategoryChoice fixed) selected]
    (VS.VariableCategory selected, VS.FixedCategory fixed) ->
      fixedCategoryChoiceConstraints fixed
        P.++ [S.differentChoice selected (fixedCategoryChoice fixed)]
    (VS.VariableCategory lhsChoice, VS.VariableCategory rhsChoice) ->
      [S.differentChoice lhsChoice rhsChoice]

categoryTokensEqual :: VS.StyleCategoryType value => value -> value -> P.Bool
categoryTokensEqual lhs rhs =
  VS.styleCategoryToken lhs P.== VS.styleCategoryToken rhs

fixedCategoryChoiceConstraints ::
     VS.StyleCategoryType value => value -> [S.ChoiceConstraint]
fixedCategoryChoiceConstraints value =
  [ S.choose
      (fixedCategoryChoice value)
      (S.category (VS.styleCategoryToken value))
  ]

impossibleCategoryConstraints ::
     VS.StyleCategoryType value => value -> [S.ChoiceConstraint]
impossibleCategoryConstraints value =
  [S.choose (fixedCategoryChoice value) (S.category "__impossible__")]

fixedCategoryChoice :: VS.StyleCategoryType value => value -> S.Choice value
fixedCategoryChoice value = S.choice (fixedCategoryChoiceName value)

fixedCategoryChoiceName :: VS.StyleCategoryType value => value -> P.String
fixedCategoryChoiceName value =
  "view.fixed."
    P.++ categoryDomainKey value
    P.++ "."
    P.++ VS.styleCategoryToken value

categoryDomainKey ::
     forall value. VS.StyleCategoryType value
  => value
  -> P.String
categoryDomainKey _ =
  joinCategoryTokens
    (P.map VS.styleCategoryToken (VS.styleCategoryDomain :: [value]))

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
