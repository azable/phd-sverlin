{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

-- | Choreography matching and hierarchical view graph assembly.
module LinearTrace.Choreography.Match
  ( -- * Specifications
    MatchSpec
  , emptyMatchSpec
  , matchSpecAppend
  , validateMatchSpec
  , ParentRef(..)
  , canvasDeclarationKey
  , registerQuerySelection
  , registerAnyQuerySelection
  , declareTraceNode
  , declareGeneratedNode
  , editNodeDeclaration
  , -- * Layout/value relations
    -- | Selection and component relation API. The DSL uses this to connect
    -- view lifespans and style/layout values through solver constraints.
    NodeSelection(..)
  , ConstraintStrength(..)
  , LayoutRelation(..)
  , CategoryRelation(..)
  , ValueComponent
  , ValueExpr
  , CategoryEndpoint
  , rawValueExpr
  , selectionValueExpr
  , addValueExpr
  , subtractValueExpr
  , scaleValueExpr
  , divideValueExpr
  , rawCategoryEndpoint
  , selectionCategoryEndpoint
  , matchValueRelation
  , matchCategoryRelation
  , matchValueDirectedBridge
  , matchValueSymmetricBridge
  , matchFiniteDecision
  , -- * View graph assembly
    -- | Internal bridge from core event blocks to view nodes. Choreography is
    -- the intended caller; this is not re-exported directly to DSL users.
    traceNodeOfEventBlock
  , matchedNodeOutput
  , buildMatchedViewGraph
  , buildMatchedViewGraphWith
  ) where

import           Data.List                 (find)
import           Data.Maybe                (mapMaybe)
import           Data.Proxy                (Proxy (..))
import           Data.Type.Equality        ((:~:) (..))
import           Data.Typeable             (eqT)
import qualified LinearTrace.Core          as C
import qualified LinearTrace.View.Access   as VA
import qualified LinearTrace.View.Build    as V
import qualified LinearTrace.View.Graph    as V
import qualified LinearTrace.View.Style    as VS
import qualified LinearTrace.View.Template as VT
import           Prelude                   (Bool (..), Maybe (..), otherwise)
import qualified Prelude                   as P
import qualified Solver                    as S

type ValueComponent = VA.ValueComponent

data NodeSelection
  = QueryNodeSelection P.String
  | ExactNodeSelection V.ViewId
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

data ValueExpr
  = RawValueExpr ValueComponent
  | SelectionValueExpr NodeSelection VA.ValueAccess
  | AddValueExpr ValueExpr ValueExpr
  | SubtractValueExpr ValueExpr ValueExpr
  | ScaleValueExpr ValueExpr ValueComponent
  | DivideValueExpr ValueExpr ValueComponent

data CategoryEndpoint value
  = RawCategoryEndpoint (S.ChoiceValue value)
  | SelectionCategoryEndpoint NodeSelection (VA.CategoryAccess value)

data MatchSpec =
  MatchSpec
    [SelectionRule]
    [TraceNodeDeclaration]
    [GeneratedNodeDeclaration]
    [NodeEdit]
    [LayoutRule]

newtype ParentRef =
  ParentRef P.String
  deriving (P.Eq, P.Show)

canvasDeclarationKey :: P.String
canvasDeclarationKey = "canvas"

data SelectionRule where
  QuerySelectionRule
    :: C.Traceable tag => P.String -> Proxy tag -> C.Query -> SelectionRule
  AnyQuerySelectionRule :: P.String -> C.Query -> SelectionRule

data TraceNodeDeclaration = TraceNodeDeclaration
  { traceDeclarationKey      :: P.String
  , traceDeclarationSelector :: P.String
  , traceDeclarationParent   :: ParentRef
  }

data GeneratedNodeDeclaration = GeneratedNodeDeclaration
  { generatedDeclarationKey    :: P.String
  , generatedDeclarationParent :: ParentRef
  }

data NodeEdit =
  NodeEdit
    P.String
    P.String
    (C.MatchBindings -> VT.NodeTemplate -> VT.NodeTemplate)

data LayoutRule where
  ValueRelationLayout
    :: ConstraintStrength
    -> [ValueExpr]
    -> LayoutRelation
    -> [ValueExpr]
    -> LayoutRule
  CategoryRelationLayout
    :: S.ChoiceDomain value=> ConstraintStrength
    -> [CategoryEndpoint value]
    -> CategoryRelation
    -> [CategoryEndpoint value]
    -> LayoutRule
  ValueDirectedBridgeLayout
    :: ConstraintStrength
    -> [ValueExpr]
    -> [ValueExpr]
    -> [ValueExpr]
    -> LayoutRule
  ValueSymmetricBridgeLayout
    :: ConstraintStrength
    -> [ValueExpr]
    -> [ValueExpr]
    -> [ValueExpr]
    -> LayoutRule
  FiniteDecisionLayout :: P.String -> [(P.String, [LayoutRule])] -> LayoutRule

emptyMatchSpec :: MatchSpec
emptyMatchSpec = MatchSpec [] [] [] [] []

matchSpecAppend :: MatchSpec -> MatchSpec -> MatchSpec
matchSpecAppend lhs rhs =
  case lhs of
    MatchSpec leftSelections leftTrace leftGenerated leftEdits leftLayouts ->
      case rhs of
        MatchSpec rightSelections rightTrace rightGenerated rightEdits rightLayouts ->
          MatchSpec
            (leftSelections P.++ rightSelections)
            (leftTrace P.++ rightTrace)
            (leftGenerated P.++ rightGenerated)
            (leftEdits P.++ rightEdits)
            (leftLayouts P.++ rightLayouts)

validateMatchSpec :: MatchSpec -> MatchSpec
validateMatchSpec spec =
  case spec of
    MatchSpec selections traceDeclarations generatedDeclarations edits _ ->
      case duplicateValues (P.map selectionRuleKey selections) of
        key:_ -> P.error ("Duplicate visual selection key " P.++ key)
        [] ->
          let declarations =
                canvasDeclarationKey
                  : P.map traceDeclarationKey traceDeclarations
                  P.++ P.map generatedDeclarationKey generatedDeclarations
           in case duplicateValues declarations of
                key:_ -> P.error ("Duplicate node declaration key " P.++ key)
                [] ->
                  case [ target
                       | NodeEdit target _ _ <- edits
                       , target `P.notElem` declarations
                       ] of
                    target:_ ->
                      P.error
                        ("A node property was declared outside a node body: "
                           P.++ target)
                    [] -> spec

duplicateValues :: P.Eq value => [value] -> [value]
duplicateValues values =
  case values of
    [] -> []
    value:rest
      | value `P.elem` rest -> value : duplicateValues rest
      | otherwise -> duplicateValues rest

registerQuerySelection ::
     forall tag. C.Traceable tag
  => P.String
  -> C.Query
  -> MatchSpec
registerQuerySelection key query =
  MatchSpec [QuerySelectionRule key (Proxy :: Proxy tag) query] [] [] [] []

registerAnyQuerySelection :: P.String -> C.Query -> MatchSpec
registerAnyQuerySelection key query =
  MatchSpec [AnyQuerySelectionRule key query] [] [] [] []

declareTraceNode :: P.String -> P.String -> ParentRef -> MatchSpec
declareTraceNode declaration selector parent =
  MatchSpec [] [TraceNodeDeclaration declaration selector parent] [] [] []

declareGeneratedNode :: P.String -> ParentRef -> MatchSpec
declareGeneratedNode key parent =
  MatchSpec [] [] [GeneratedNodeDeclaration key parent] [] []

editNodeDeclaration ::
     P.String
  -> P.String
  -> (C.MatchBindings -> VT.NodeTemplate -> VT.NodeTemplate)
  -> MatchSpec
editNodeDeclaration declaration property update =
  MatchSpec [] [] [] [NodeEdit declaration property update] []

rawValueExpr :: ValueComponent -> ValueExpr
rawValueExpr = RawValueExpr

selectionValueExpr :: NodeSelection -> VA.ValueAccess -> ValueExpr
selectionValueExpr = SelectionValueExpr

addValueExpr :: ValueExpr -> ValueExpr -> ValueExpr
addValueExpr = AddValueExpr

subtractValueExpr :: ValueExpr -> ValueExpr -> ValueExpr
subtractValueExpr = SubtractValueExpr

scaleValueExpr :: ValueExpr -> ValueComponent -> ValueExpr
scaleValueExpr = ScaleValueExpr

divideValueExpr :: ValueExpr -> ValueComponent -> ValueExpr
divideValueExpr = DivideValueExpr

rawCategoryEndpoint :: S.ChoiceValue value -> CategoryEndpoint value
rawCategoryEndpoint = RawCategoryEndpoint

selectionCategoryEndpoint ::
     NodeSelection -> VA.CategoryAccess value -> CategoryEndpoint value
selectionCategoryEndpoint = SelectionCategoryEndpoint

matchValueRelation ::
     ConstraintStrength
  -> [ValueExpr]
  -> LayoutRelation
  -> [ValueExpr]
  -> MatchSpec
matchValueRelation strength lhs relation rhs =
  MatchSpec [] [] [] [] [ValueRelationLayout strength lhs relation rhs]

matchCategoryRelation ::
     S.ChoiceDomain value
  => ConstraintStrength
  -> [CategoryEndpoint value]
  -> CategoryRelation
  -> [CategoryEndpoint value]
  -> MatchSpec
matchCategoryRelation strength lhs relation rhs =
  MatchSpec [] [] [] [] [CategoryRelationLayout strength lhs relation rhs]

matchValueDirectedBridge ::
     ConstraintStrength
  -> [ValueExpr]
  -> [ValueExpr]
  -> [ValueExpr]
  -> MatchSpec
matchValueDirectedBridge strength lhs gap rhs =
  MatchSpec [] [] [] [] [ValueDirectedBridgeLayout strength lhs gap rhs]

matchValueSymmetricBridge ::
     ConstraintStrength
  -> [ValueExpr]
  -> [ValueExpr]
  -> [ValueExpr]
  -> MatchSpec
matchValueSymmetricBridge strength lhs delta rhs =
  MatchSpec [] [] [] [] [ValueSymmetricBridgeLayout strength lhs delta rhs]

matchFiniteDecision :: P.String -> [(P.String, MatchSpec)] -> MatchSpec
matchFiniteDecision name alternatives =
  MatchSpec
    (P.concatMap alternativeSelections alternatives)
    (P.concatMap alternativeTraceDeclarations alternatives)
    (P.concatMap alternativeGeneratedDeclarations alternatives)
    (P.concatMap alternativeEdits alternatives)
    [FiniteDecisionLayout name (P.map alternativeLayouts alternatives)]
  where
    alternativeSelections (_, MatchSpec rules _ _ _ _) = rules
    alternativeTraceDeclarations (_, MatchSpec _ rules _ _ _) = rules
    alternativeGeneratedDeclarations (_, MatchSpec _ _ rules _ _) = rules
    alternativeEdits (_, MatchSpec _ _ _ rules _) = rules
    alternativeLayouts (token, MatchSpec _ _ _ _ rules) = (token, rules)

traceNodeOfEventBlock :: C.BlockSnapshot tag -> V.Node tag
traceNodeOfEventBlock block =
  let ref = coreViewRef (C.blockSnapshotRef block)
   in V.Node
        { V.nodeRef = ref
        , V.nodeLabel =
            viewLabelFromPayloadView (C.blockSnapshotPayloadView block)
        , V.nodeContent = V.ContentEmpty
        , V.nodeBox = V.boxForRef ref
        , V.nodeStyle = V.styleForRef ref
        , V.nodeOrigin =
            V.TraceOrigin (viewTagsFromFacts (C.blockSnapshotFacts block))
        , V.nodeDeclaration = ""
        , V.nodeSelectionBindings = []
        , V.nodeParent = Nothing
        , V.nodeHorizontalFit = V.Hug
        , V.nodeVerticalFit = V.Hug
        , V.nodeRelativePins = []
        , V.nodeConstraints = []
        }

matchedNodeOutput :: MatchSpec -> C.BlockSnapshot tag -> V.ViewOutput
matchedNodeOutput spec eventBlock =
  C.withBlockSnapshot
    eventBlock
    (case matchingTraceDeclarations spec eventBlock of
       [] -> P.mempty
       [(declaration, bindings)] ->
         let base = traceNodeOfEventBlock eventBlock
             template =
               templateForDeclaration
                 spec
                 (traceDeclarationKey declaration)
                 bindings
             node =
               VT.applyNodeTemplate
                 template
                 base
                   { V.nodeDeclaration = traceDeclarationKey declaration
                   , V.nodeSelectionBindings =
                       selectionBindingsForBlock spec eventBlock
                   , V.nodeParent =
                       parentViewId (traceDeclarationParent declaration)
                   }
          in P.mempty {V.emittedNodes = [V.ViewNode node]}
       matches ->
         P.error
           ("A trace output matched more than one node declaration: "
              P.++ commaSeparated
                     (P.map (traceDeclarationKey P.. P.fst) matches)))

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

data SelectionMatch =
  SelectionMatch C.MatchBindings C.QueryBindings

matchingTraceDeclarations ::
     C.Traceable tag
  => MatchSpec
  -> C.BlockSnapshot tag
  -> [(TraceNodeDeclaration, C.MatchBindings)]
matchingTraceDeclarations spec block =
  case spec of
    MatchSpec selections declarations _ _ _ ->
      [ (declaration, bindings)
      | declaration <- declarations
      , Just rule <-
          [findSelectionRule (traceDeclarationSelector declaration) selections]
      , Just (SelectionMatch bindings _) <- [selectionRuleMatch block rule]
      ]

findSelectionRule :: P.String -> [SelectionRule] -> Maybe SelectionRule
findSelectionRule key = find ((P.== key) P.. selectionRuleKey)

selectionRuleKey :: SelectionRule -> P.String
selectionRuleKey rule =
  case rule of
    QuerySelectionRule key _ _  -> key
    AnyQuerySelectionRule key _ -> key

selectionRuleMatch ::
     forall sourceTag. C.Traceable sourceTag
  => C.BlockSnapshot sourceTag
  -> SelectionRule
  -> Maybe SelectionMatch
selectionRuleMatch block rule =
  case rule of
    AnyQuerySelectionRule _ query -> do
      queryBindings <- C.queryMatches query (C.blockSnapshotFacts block)
      payloadBindings <-
        C.queryPayloadMatches query (C.blockSnapshotPayload block)
      P.pure
        (SelectionMatch
           (C.queryMatchBindings queryBindings P.++ payloadBindings)
           queryBindings)
    QuerySelectionRule _ (_ :: Proxy matchedTag) query ->
      case eqT @sourceTag @matchedTag of
        Nothing -> Nothing
        Just Refl -> do
          queryBindings <- C.queryMatches query (C.blockSnapshotFacts block)
          payloadBindings <-
            C.queryPayloadMatches query (C.blockSnapshotPayload block)
          P.pure
            (SelectionMatch
               (C.queryMatchBindings queryBindings P.++ payloadBindings)
               queryBindings)

selectionBindingsForBlock ::
     C.Traceable tag
  => MatchSpec
  -> C.BlockSnapshot tag
  -> [(P.String, C.QueryBindings)]
selectionBindingsForBlock spec block =
  case spec of
    MatchSpec selections _ _ _ _ ->
      [ (selectionRuleKey rule, bindings)
      | rule <- selections
      , Just (SelectionMatch _ bindings) <- [selectionRuleMatch block rule]
      ]

templateForDeclaration ::
     MatchSpec -> P.String -> C.MatchBindings -> VT.NodeTemplate
templateForDeclaration spec declaration bindings =
  substituteTemplateBindings
    bindings
    (P.foldl applyEdit VT.emptyNodeTemplate (declarationEdits spec declaration))
  where
    applyEdit template edit =
      case edit of
        NodeEdit _ _ update -> update bindings template

declarationEdits :: MatchSpec -> P.String -> [NodeEdit]
declarationEdits spec declaration =
  case spec of
    MatchSpec _ _ _ edits _ ->
      [edit | edit@(NodeEdit target _ _) <- edits, target P.== declaration]

substituteTemplateBindings ::
     C.MatchBindings -> VT.NodeTemplate -> VT.NodeTemplate
substituteTemplateBindings bindings =
  VT.substituteNodeTemplateVars (bindingExprSubstitutions bindings)

bindingExprSubstitutions :: C.MatchBindings -> [(P.String, P.Double)]
bindingExprSubstitutions bindings =
  case bindings of
    [] -> []
    C.MatchBinding name value:rest ->
      case P.reads value of
        [(number, "")] ->
          ("global." P.++ name, number) : bindingExprSubstitutions rest
        _ -> bindingExprSubstitutions rest

parentViewId :: ParentRef -> Maybe V.ViewId
parentViewId parent =
  case parent of
    ParentRef key
      | key P.== canvasDeclarationKey -> Just V.canvasViewId
      | P.otherwise -> Just (V.ViewId (V.generatedNodeId key))

commaSeparated :: [P.String] -> P.String
commaSeparated values =
  case values of
    []         -> ""
    [value]    -> value
    value:rest -> value P.++ ", " P.++ commaSeparated rest

buildMatchedViewGraph ::
     MatchSpec -> [V.ViewNode] -> [V.ViewStep] -> V.ViewGraph
buildMatchedViewGraph = buildMatchedViewGraphWith P.id

buildMatchedViewGraphWith ::
     ([V.ViewNode] -> [V.ViewNode])
  -> MatchSpec
  -> [V.ViewNode]
  -> [V.ViewStep]
  -> V.ViewGraph
buildMatchedViewGraphWith transformNodes spec builtNodes steps =
  let visibleIds = introducedViewIds steps
      retainedTraceNodes =
        P.filter (\wrapped -> nodeId wrapped `P.elem` visibleIds) builtNodes
      generatedNodes = generatedNodesForSpec spec retainedTraceNodes
      rootNode = canvasNodeForSpec spec
      hierarchicalNodes =
        cascadeNodeStyles (rootNode : retainedTraceNodes P.++ generatedNodes)
      nodes =
        transformNodes (applyAccessRequirementsForSpec spec hierarchicalNodes)
      (matchConstraints, matchChoiceConstraints) =
        matchSpecConstraints spec nodes
      diagnostics = hierarchyDiagnostics spec builtNodes nodes steps
   in V.finalizeViewGraph
        nodes
        matchConstraints
        matchChoiceConstraints
        steps
        diagnostics

matchSpecConstraints ::
     MatchSpec -> [V.ViewNode] -> ([S.Constraint], [S.ChoiceConstraint])
matchSpecConstraints spec nodes =
  case spec of
    MatchSpec _ _ _ _ layoutRules ->
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
             valueDirectedBridgeRelationConstraints
             (matchingValueExprTriples lhs gap rhs nodes))
      , [])
    ValueSymmetricBridgeLayout strength lhs delta rhs ->
      ( applyConstraintStrength
          strength
          (P.concatMap
             valueSymmetricBridgeConstraints
             (matchingValueExprTriples lhs delta rhs nodes))
      , [])
    FiniteDecisionLayout name alternatives ->
      ([finiteDecisionConstraint name alternatives], [])
      where
        finiteDecisionConstraint decisionName branches =
          case P.map compileAlternative branches of
            [] -> P.error "A finite visual decision requires an alternative."
            first:rest -> S.oneOf decisionName first rest
        compileAlternative (token, rules) =
          case foldConstraintPairs (P.map (layoutRuleConstraints nodes) rules) of
            (constraints, []) -> S.alternative token constraints
            (_, _:_) ->
              P.error
                "Categorical visual relations cannot be conditional; define category relations globally."

applyConstraintStrength ::
     ConstraintStrength -> [S.Constraint] -> [S.Constraint]
applyConstraintStrength strength constraints =
  case strength of
    EnsureConstraint    -> constraints
    EncourageConstraint -> P.map S.soften constraints

data CategoryEndpointMatch value =
  CategoryEndpointMatch (S.ChoiceValue value) C.QueryBindings

matchingValueTerms ::
     [ValueExpr]
  -> [ValueExpr]
  -> [V.ViewNode]
  -> [([ValueComponent], [ValueComponent])]
matchingValueTerms lhs rhs nodes =
  [ (lhsComponents, rhsComponents)
  | ([lhsComponents, rhsComponents], _) <-
      matchingValueTermGroups [lhs, rhs] nodes
  ]

matchingValueExprTriples ::
     [ValueExpr]
  -> [ValueExpr]
  -> [ValueExpr]
  -> [V.ViewNode]
  -> [([ValueComponent], [ValueComponent], [ValueComponent])]
matchingValueExprTriples first second third nodes =
  [ (firstComponents, secondComponents, thirdComponents)
  | ([firstComponents, secondComponents, thirdComponents], _) <-
      matchingValueTermGroups [first, second, third] nodes
  ]

matchingValueTermGroups ::
     [[ValueExpr]] -> [V.ViewNode] -> [([[ValueComponent]], C.QueryBindings)]
matchingValueTermGroups expressionGroups nodes =
  [ ( P.map (P.map (lowerValueExpr assignment bindings)) expressionGroups
    , bindings)
  | (assignment, bindings) <-
      matchingSelectionAssignments
        (uniqueSelections
           (P.concatMap (P.concatMap valueExprSelections) expressionGroups))
        nodes
  ]

type SelectionAssignment = [(NodeSelection, V.AnyLayoutView)]

matchingSelectionAssignments ::
     [NodeSelection] -> [V.ViewNode] -> [(SelectionAssignment, C.QueryBindings)]
matchingSelectionAssignments selections nodes =
  case selections of
    [] -> [([], [])]
    selection:rest ->
      [ ((selection, view) : assignment, mergedBindings)
      | (view, bindings) <- matchingSelectionNodes selection nodes
      , (assignment, restBindings) <- matchingSelectionAssignments rest nodes
      , Just mergedBindings <- [mergeQueryBindings bindings restBindings]
      ]

uniqueSelections :: [NodeSelection] -> [NodeSelection]
uniqueSelections selections =
  case selections of
    [] -> []
    selection:rest
      | selection `P.elem` rest -> uniqueSelections rest
      | P.otherwise -> selection : uniqueSelections rest

valueExprSelections :: ValueExpr -> [NodeSelection]
valueExprSelections expression =
  case expression of
    RawValueExpr _ -> []
    SelectionValueExpr selection _ -> [selection]
    AddValueExpr lhs rhs -> valueExprSelections lhs P.++ valueExprSelections rhs
    SubtractValueExpr lhs rhs ->
      valueExprSelections lhs P.++ valueExprSelections rhs
    ScaleValueExpr value _ -> valueExprSelections value
    DivideValueExpr value _ -> valueExprSelections value

lowerValueExpr ::
     SelectionAssignment -> C.QueryBindings -> ValueExpr -> ValueComponent
lowerValueExpr assignment bindings expression =
  case expression of
    RawValueExpr component -> substituteBindings bindings component
    SelectionValueExpr selection access ->
      case P.lookup selection assignment of
        Nothing -> P.error "A selected visual expression was not resolved."
        Just view ->
          substituteBindings bindings (VA.valueAccessComponent access view)
    AddValueExpr lhs rhs ->
      S.addComponents
        (lowerValueExpr assignment bindings lhs)
        (lowerValueExpr assignment bindings rhs)
    SubtractValueExpr lhs rhs ->
      S.subtractComponents
        (lowerValueExpr assignment bindings lhs)
        (lowerValueExpr assignment bindings rhs)
    ScaleValueExpr value factor ->
      lowerScaledValue False assignment bindings value factor
    DivideValueExpr value divisor ->
      lowerScaledValue True assignment bindings value divisor

lowerScaledValue ::
     P.Bool
  -> SelectionAssignment
  -> C.QueryBindings
  -> ValueExpr
  -> ValueComponent
  -> ValueComponent
lowerScaledValue reciprocal assignment bindings expression scalar =
  let resolvedScalar = substituteBindings bindings scalar
      scale =
        case S.componentConstantValue resolvedScalar of
          Nothing ->
            P.error
              "A visual expression may only be scaled by a fixed or query-resolved scalar."
          Just 0
            | reciprocal ->
              P.error "A visual expression cannot be divided by zero."
          Just value ->
            if reciprocal
              then 1 P./ value
              else value
      scaled =
        S.scaleComponent scale (lowerValueExpr assignment bindings expression)
   in S.addComponentConstraints (S.componentConstraints resolvedScalar) scaled

substituteBindings :: C.QueryBindings -> ValueComponent -> ValueComponent
substituteBindings bindings =
  S.substituteComponentVars
    [("global." P.++ name, P.fromIntegral value) | (name, value) <- bindings]

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
        ExactNodeSelection identifier
          | V.viewRefId (V.nodeRef node) P.== identifier ->
            [(V.AnyLayoutView node, [])]
          | P.otherwise -> []
        QueryNodeSelection key ->
          case P.lookup key (V.nodeSelectionBindings node) of
            Nothing       -> []
            Just bindings -> [(V.AnyLayoutView node, bindings)]

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

valueDirectedBridgeRelationConstraints ::
     ([ValueComponent], [ValueComponent], [ValueComponent]) -> [S.Constraint]
valueDirectedBridgeRelationConstraints triple =
  case triple of
    (lhsComponents, gapComponents, rhsComponents) ->
      S.relateComponents
        S.ComponentEqual
        (zipValueComponents S.addComponents lhsComponents gapComponents)
        rhsComponents

zipValueComponents ::
     (ValueComponent -> ValueComponent -> ValueComponent)
  -> [ValueComponent]
  -> [ValueComponent]
  -> [ValueComponent]
zipValueComponents combine lhs rhs =
  case (lhs, rhs) of
    ([], []) -> []
    (leftComponent:leftRest, rightComponent:rightRest) ->
      combine leftComponent rightComponent
        : zipValueComponents combine leftRest rightRest
    _ -> P.error "Cannot combine visual values with different component counts."

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
    MatchSpec _ _ _ _ layoutRules ->
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
      applyAccessRequirementsForValueExprs (lhs P.++ rhs) node
    CategoryRelationLayout _ lhs _ rhs ->
      applyAccessRequirementsForCategoryEndpoints (lhs P.++ rhs) node
    ValueDirectedBridgeLayout _ lhs gap rhs ->
      applyAccessRequirementsForValueExprs (lhs P.++ gap P.++ rhs) node
    ValueSymmetricBridgeLayout _ lhs delta rhs ->
      applyAccessRequirementsForValueExprs (lhs P.++ delta P.++ rhs) node
    FiniteDecisionLayout _ alternatives ->
      applyAccessRequirementsForRules (P.concatMap P.snd alternatives) node

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

applyAccessRequirementsForValueExprs :: [ValueExpr] -> V.ViewNode -> V.ViewNode
applyAccessRequirementsForValueExprs expressions node =
  case expressions of
    [] -> node
    expression:rest ->
      applyAccessRequirementsForValueExprs
        rest
        (applyAccessRequirementsForValueExpr expression node)

applyAccessRequirementsForValueExpr :: ValueExpr -> V.ViewNode -> V.ViewNode
applyAccessRequirementsForValueExpr expression node =
  case expression of
    RawValueExpr _ -> node
    SelectionValueExpr selection access ->
      case nodeMatchesSelection selection node of
        False -> node
        True ->
          VA.applyStyleRequirements (VA.valueAccessRequirements access) node
    AddValueExpr lhs rhs -> applyBinary lhs rhs
    SubtractValueExpr lhs rhs -> applyBinary lhs rhs
    ScaleValueExpr value _ -> applyAccessRequirementsForValueExpr value node
    DivideValueExpr value _ -> applyAccessRequirementsForValueExpr value node
  where
    applyBinary lhs rhs =
      applyAccessRequirementsForValueExpr
        rhs
        (applyAccessRequirementsForValueExpr lhs node)

nodeMatchesSelection :: NodeSelection -> V.ViewNode -> P.Bool
nodeMatchesSelection selection node =
  case selectionNodeMatches selection node of
    [] -> False
    _  -> True

generatedNodesForSpec :: MatchSpec -> [V.ViewNode] -> [V.ViewNode]
generatedNodesForSpec spec traceNodes =
  P.concatMap
    (generatedTreeForDeclaration spec traceNodes)
    (rootGeneratedDeclarations spec)

rootGeneratedDeclarations :: MatchSpec -> [GeneratedNodeDeclaration]
rootGeneratedDeclarations spec =
  case spec of
    MatchSpec _ _ declarations _ _ ->
      [ declaration
      | declaration <- declarations
      , generatedDeclarationParent declaration
          P.== ParentRef canvasDeclarationKey
      ]

generatedTreeForDeclaration ::
     MatchSpec -> [V.ViewNode] -> GeneratedNodeDeclaration -> [V.ViewNode]
generatedTreeForDeclaration spec traceNodes declaration =
  let key = generatedDeclarationKey declaration
      nestedTrees =
        P.map
          (generatedTreeForDeclaration spec traceNodes)
          (childGeneratedDeclarations spec key)
      nestedNodes = P.concat nestedTrees
      nestedRoots = mapMaybe lastNodeId nestedTrees
      traceChildIds =
        [ V.viewRefId (V.nodeRef node)
        | V.ViewNode node <- traceNodes
        , V.nodeParent node P.== Just (V.ViewId (V.generatedNodeId key))
        ]
      children = traceChildIds P.++ nestedRoots
   in case children of
        [] -> []
        _  -> nestedNodes P.++ [generatedNodeForDeclaration spec declaration]

lastNodeId :: [V.ViewNode] -> Maybe V.ViewId
lastNodeId nodes =
  case P.reverse nodes of
    []                -> Nothing
    V.ViewNode node:_ -> Just (V.viewRefId (V.nodeRef node))

childGeneratedDeclarations ::
     MatchSpec -> P.String -> [GeneratedNodeDeclaration]
childGeneratedDeclarations spec parentKey =
  case spec of
    MatchSpec _ _ declarations _ _ ->
      [ declaration
      | declaration <- declarations
      , generatedDeclarationParent declaration P.== ParentRef parentKey
      ]

generatedNodeForDeclaration ::
     MatchSpec -> GeneratedNodeDeclaration -> V.ViewNode
generatedNodeForDeclaration spec declaration =
  let key = generatedDeclarationKey declaration
      ref = V.viewRefFromId (V.generatedNodeId key)
      template = templateForDeclaration spec key []
      base =
        V.Node
          { V.nodeRef = ref
          , V.nodeLabel = V.ViewLabel ("Node." P.++ key)
          , V.nodeContent = V.ContentEmpty
          , V.nodeBox = V.boxForNodeRoot (V.generatedNodeRoot key)
          , V.nodeStyle = V.styleForNodeRoot (V.generatedNodeRoot key)
          , V.nodeOrigin = V.GeneratedOrigin (V.GeneratedMeta key)
          , V.nodeDeclaration = key
          , V.nodeSelectionBindings = [(key, [])]
          , V.nodeParent = parentViewId (generatedDeclarationParent declaration)
          , V.nodeHorizontalFit = V.Hug
          , V.nodeVerticalFit = V.Hug
          , V.nodeRelativePins = []
          , V.nodeConstraints = []
          }
   in V.ViewNode (VT.applyNodeTemplate template base)

canvasNodeForSpec :: MatchSpec -> V.ViewNode
canvasNodeForSpec spec =
  let template = templateForDeclaration spec canvasDeclarationKey []
      explicit pin =
        case pin of
          Nothing -> False
          Just _  -> True
      root = V.generatedNodeRoot canvasDeclarationKey
      base =
        V.Node
          { V.nodeRef = V.ViewRef V.canvasViewId
          , V.nodeLabel = V.ViewLabel "Canvas"
          , V.nodeContent = V.ContentEmpty
          , V.nodeBox = V.boxForNodeRoot V.canvasNodeRoot
          , V.nodeStyle = V.styleForNodeRoot root
          , V.nodeOrigin =
              V.CanvasOrigin
                V.CanvasMeta
                  { V.canvasWidthExplicit = explicit (VT.templateWidth template)
                  , V.canvasHeightExplicit =
                      explicit (VT.templateHeight template)
                  }
          , V.nodeDeclaration = canvasDeclarationKey
          , V.nodeSelectionBindings = []
          , V.nodeParent = Nothing
          , V.nodeHorizontalFit = V.Hug
          , V.nodeVerticalFit = V.Hug
          , V.nodeRelativePins = []
          , V.nodeConstraints = []
          }
   in V.ViewNode (VT.applyNodeTemplate template base)

cascadeNodeStyles :: [V.ViewNode] -> [V.ViewNode]
cascadeNodeStyles nodes = P.map cascadeNode nodes
  where
    cascadeNode wrapped =
      case wrapped of
        V.ViewNode node ->
          V.ViewNode
            node
              { V.nodeStyle =
                  case V.nodeParent node P.>>= cascadedStyleFor of
                    Nothing -> V.nodeStyle node
                    Just parentStyle ->
                      VS.cascadeNodeStyle parentStyle (V.nodeStyle node)
              }
    cascadedStyleFor identifier =
      case findNode identifier nodes of
        Nothing -> Nothing
        Just (V.ViewNode node) ->
          Just
            (case V.nodeParent node P.>>= cascadedStyleFor of
               Nothing -> V.nodeStyle node
               Just parentStyle ->
                 VS.cascadeNodeStyle parentStyle (V.nodeStyle node))

findNode :: V.ViewId -> [V.ViewNode] -> Maybe V.ViewNode
findNode identifier =
  find (\(V.ViewNode node) -> V.viewRefId (V.nodeRef node) P.== identifier)

hierarchyDiagnostics ::
     MatchSpec
  -> [V.ViewNode]
  -> [V.ViewNode]
  -> [V.ViewStep]
  -> [V.ViewDiagnostic]
hierarchyDiagnostics spec matchedNodes retainedNodes steps =
  traceDeclarationDiagnostics spec matchedNodes steps
    P.++ generatedDeclarationDiagnostics spec retainedNodes steps

traceDeclarationDiagnostics ::
     MatchSpec -> [V.ViewNode] -> [V.ViewStep] -> [V.ViewDiagnostic]
traceDeclarationDiagnostics spec nodes steps =
  case spec of
    MatchSpec _ declarations _ _ _ -> mapMaybe diagnostic declarations
  where
    visibleIds = introducedViewIds steps
    diagnostic declaration =
      let matchingNodes =
            nodesForDeclaration (traceDeclarationKey declaration) nodes
          visible =
            P.length
              (P.filter (`P.elem` visibleIds) (P.map nodeId matchingNodes))
          matched = P.length matchingNodes
       in if matched P.== 0 P.|| visible P.== 0
            then Just
                   V.ViewDiagnostic
                     { V.viewDiagnosticCode = "hierarchy.node-never-rendered"
                     , V.viewDiagnosticMessage =
                         "A node declaration never produced visible output."
                     , V.viewDiagnosticDeclaration =
                         traceDeclarationKey declaration
                     , V.viewDiagnosticReason =
                         if matched P.== 0
                           then "the selection matched no materialized trace output"
                           else "matched nodes were never introduced at a checkpoint"
                     , V.viewDiagnosticMatched = matched
                     , V.viewDiagnosticVisible = visible
                     }
            else Nothing

generatedDeclarationDiagnostics ::
     MatchSpec -> [V.ViewNode] -> [V.ViewStep] -> [V.ViewDiagnostic]
generatedDeclarationDiagnostics spec nodes steps =
  case spec of
    MatchSpec _ _ declarations _ _ -> mapMaybe diagnostic declarations
  where
    visibleIds = introducedViewIds steps
    diagnostic declaration =
      case nodesForDeclaration (generatedDeclarationKey declaration) nodes of
        [] ->
          Just
            V.ViewDiagnostic
              { V.viewDiagnosticCode = "hierarchy.parent-pruned"
              , V.viewDiagnosticMessage =
                  "An empty generated parent was pruned from the output."
              , V.viewDiagnosticDeclaration =
                  generatedDeclarationKey declaration
              , V.viewDiagnosticReason =
                  "none of its child declarations produced a node"
              , V.viewDiagnosticMatched = 0
              , V.viewDiagnosticVisible = 0
              }
        matchingNodes ->
          let visible =
                P.length
                  [ ()
                  | wrapped <- matchingNodes
                  , nodeOrDescendantVisible nodes visibleIds wrapped
                  ]
           in if visible P.== 0
                then Just
                       V.ViewDiagnostic
                         { V.viewDiagnosticCode =
                             "hierarchy.node-never-rendered"
                         , V.viewDiagnosticMessage =
                             "A generated node never produced visible output."
                         , V.viewDiagnosticDeclaration =
                             generatedDeclarationKey declaration
                         , V.viewDiagnosticReason =
                             "none of its descendants were introduced at a checkpoint"
                         , V.viewDiagnosticMatched = P.length matchingNodes
                         , V.viewDiagnosticVisible = 0
                         }
                else Nothing

nodesForDeclaration :: P.String -> [V.ViewNode] -> [V.ViewNode]
nodesForDeclaration declaration =
  P.filter (\(V.ViewNode node) -> V.nodeDeclaration node P.== declaration)

nodeId :: V.ViewNode -> V.ViewId
nodeId wrapped =
  case wrapped of
    V.ViewNode node -> V.viewRefId (V.nodeRef node)

introducedViewIds :: [V.ViewStep] -> [V.ViewId]
introducedViewIds =
  P.concatMap (P.concatMap introducedByIntent P.. V.viewStepIntents)
  where
    introducedByIntent intent =
      case intent of
        V.RenderFresh ref      -> [V.viewRefId ref]
        V.RenderContinue _ ref -> [V.viewRefId ref]
        V.RenderFork _ ref     -> [V.viewRefId ref]
        V.RenderRemove _       -> []

nodeOrDescendantVisible :: [V.ViewNode] -> [V.ViewId] -> V.ViewNode -> P.Bool
nodeOrDescendantVisible nodes visibleIds wrapped =
  case wrapped of
    V.ViewNode node ->
      V.viewRefId (V.nodeRef node) `P.elem` visibleIds
        P.|| P.any
               childVisible
               [ nodeId child
               | child@(V.ViewNode childNode) <- nodes
               , V.nodeParent childNode P.== Just (V.viewRefId (V.nodeRef node))
               ]
  where
    childVisible identifier =
      case findNode identifier nodes of
        Nothing    -> False
        Just child -> nodeOrDescendantVisible nodes visibleIds child
