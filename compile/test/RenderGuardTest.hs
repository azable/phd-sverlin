{-# LANGUAGE TypeApplications #-}

-- | Focused characterization of automatic optional-dependency propagation.
module RenderGuardTest
  ( tests
  ) where

import           Data.List                          (nub, sort)
import qualified LinearTrace.Visualization.IR       as IR
import qualified LinearTrace.Visualization.Resource as Resource
import qualified Sverlin.Internal.Render            as Render
import qualified Sverlin.Internal.Render.Compile    as Compile
import qualified Sverlin.Internal.Semantic          as Semantic
import           Test.Tasty                         (TestTree, testGroup)
import           Test.Tasty.HUnit                   (assertBool, assertFailure,
                                                     testCase, (@?=))

data Item

data Member

data Row

data Cell

data RankingFrame

data MembershipBefore

data MembershipAfter

tests :: TestTree
tests =
  testGroup
    "Render optional dependencies"
    [ testCase "selection and relation consumers inherit both guards" $ do
        plan <- expectPlan structuralPlan
        let nodeGuards = selectionGuards "optional.nodes" plan
            relationGuards = relationSelectionGuards "optional.links" plan
            expected = sort (nodeGuards ++ relationGuards)
        case Render.planNodes plan of
          [mapping] ->
            sortedGuards (Render.nodeDeclarationScope mapping) @?= nodeGuards
          nodes ->
            assertFailure
              ("expected one selected-node mapping, got " ++ show (length nodes))
        selectionGuards "within.consumer" plan `shouldContainExactly` expected
        selectionGuards "relation.consumer" plan
          `shouldContainExactly` relationGuards
        map
          (sortedGuards . Render.rankingDeclarationScope)
          (Render.planRankings plan)
          @?= replicate 3 expected
        map
          (sortedGuards . Render.arrangementDeclarationScope)
          (Render.planArrangements plan)
          @?= [expected]
    , testCase
        "a late visual dependency promotes its node, prior work, and descendants" $ do
        plan <- expectPlan generatedNodePlan
        case Render.planNodes plan of
          [explanation, detail, child, sibling, consumer] -> do
            let guards = sortedGuards (Render.nodeDeclarationScope explanation)
            sortedGuards (Render.nodeDeclarationScope detail) @?= guards
            sortedGuards (Render.nodeDeclarationScope child) @?= guards
            sortedGuards (Render.nodeDeclarationScope sibling) @?= []
            sortedGuards (Render.nodeDeclarationScope consumer) @?= guards
            scopedDeclarationsFor
              [ Render.GeneratedReference (Render.nodeDeclarationId detail)
              , Render.GeneratedReference (Render.nodeDeclarationId child)
              ]
              plan
              @?= replicate 2 guards
            scopedDeclarationsFor
              [Render.GeneratedReference (Render.nodeDeclarationId sibling)]
              plan
              @?= [[]]
            map
              (sortedGuards . Render.constraintDeclarationScope)
              (Render.planConstraints plan)
              @?= [guards, guards]
            map
              (sortedGuards . Render.contentDeclarationScope)
              (Render.planContents plan)
              @?= [guards]
          nodes ->
            assertFailure
              ("expected five generated nodes, got " ++ show (length nodes))
    , testCase "ranking text carries a relation guard into its node mapping" $ do
        plan <- expectPlan rankingTextPlan
        let guards = relationSelectionGuards "optional.order" plan
        map
          (sortedGuards . Render.rankingDeclarationScope)
          (Render.planRankings plan)
          @?= [guards]
        map (sortedGuards . Render.nodeDeclarationScope) (Render.planNodes plan)
          @?= [guards]
        map
          (sortedGuards . Render.geometryAssignmentScope)
          (Render.planGeometry plan)
          @?= [guards]
        map
          (sortedGuards . Render.contentDeclarationScope)
          (Render.planContents plan)
          @?= [guards]
    , testCase "choice and connector dependencies promote only their component" $ do
        choicePlan <- expectPlan guardedChoicePlan
        case Render.planNodes choicePlan of
          [choiceConsumer, branchConsumer] -> do
            let guards =
                  sortedGuards (Render.nodeDeclarationScope choiceConsumer)
            length guards @?= 1
            sortedGuards (Render.nodeDeclarationScope branchConsumer) @?= []
            map
              (sortedGuards . Render.geometryAssignmentScope)
              (Render.planGeometry choicePlan)
              @?= [guards]
            let branchStyleScopes =
                  [ ( Render.styleDeclarationField declaration
                    , sortedGuards (Render.styleDeclarationScope declaration))
                  | declaration <- Render.planStyles choicePlan
                  , Render.styleDeclarationTarget declaration
                      == Render.NodeBuilderTarget
                           (Render.GeneratedReference
                              (Render.nodeDeclarationId branchConsumer))
                  ]
                alignmentScopes =
                  [scope | (Render.TextAlignField, scope) <- branchStyleScopes]
                weightScopes =
                  [scope | (Render.FontWeightField, scope) <- branchStyleScopes]
            map length alignmentScopes @?= [1, 1, 1]
            map length weightScopes @?= [2, 2, 2]
          nodes ->
            assertFailure
              ("expected two choice consumers, got " ++ show (length nodes))
        connectorPlan <- expectPlan guardedConnectorPlan
        case Render.planNodes connectorPlan of
          [start, _end, source] ->
            case Render.planConnectors connectorPlan of
              [declaration] -> do
                let expected =
                      sort
                        (Render.scopeGuards (Render.nodeDeclarationScope start)
                           ++ Render.scopeGuards
                                (Render.nodeDeclarationScope source))
                sortedGuards (Render.connectorDeclarationScope declaration)
                  @?= expected
                map
                  (sortedGuards . Render.styleDeclarationScope)
                  (Render.planStyles connectorPlan)
                  @?= replicate 2 expected
              declarations ->
                assertFailure
                  ("expected one connector, got " ++ show (length declarations))
          nodes ->
            assertFailure
              ("expected three connector nodes, got " ++ show (length nodes))
    , testCase "connectors reject node-only styles"
        $ case invalidConnectorStylePlan of
            Left diagnostic ->
              Render.renderDiagnosticMessage diagnostic
                @?= "connectors support only Opacity, StrokeWidth, and Stroke styles"
            Right _ ->
              assertFailure "expected a connector font style to be rejected"
    , testCase
        "separate mappings of one semantic selection own separate content" $ do
        plan <- expectPlan repeatedSelectionContentPlan
        assertIndependentContentMappings 2 plan
        map
          (length . Render.scopeGuards . Render.contentDeclarationScope)
          (Render.planContents plan)
          @?= [0, 0]
    , testCase "mutually exclusive mappings own separate content" $ do
        plan <- expectPlan alternativeSelectionContentPlan
        assertIndependentContentMappings 2 plan
        map
          (length . Render.scopeGuards . Render.contentDeclarationScope)
          (Render.planContents plan)
          @?= [1, 1]
    , testCase "one visual mapping still rejects a second content declaration"
        $ case duplicateMappingContentPlan of
            Left diagnostic ->
              Render.renderDiagnosticMessage diagnostic
                @?= "one node may declare content exactly once"
            Right _ ->
              assertFailure
                "expected duplicate content in one visual mapping to be rejected"
    , testCase "sometimes keeps the scope where its decision was introduced" $ do
        plan <- expectPlan presenceOwnershipPlan
        case (Render.planPresences plan, Render.planNodes plan) of
          ([(presence, ownerScope)], [parent, optional, child]) -> do
            Render.scopeCurrentNode ownerScope
              @?= Just (Render.nodeDeclarationId parent)
            let expected = [Render.PresenceDecision presence]
            Render.scopeGuards (Render.nodeDeclarationScope optional)
              @?= expected
            Render.scopeGuards (Render.nodeDeclarationScope child) @?= expected
            map
              (Render.scopeGuards . Render.contentDeclarationScope)
              (Render.planContents plan)
              @?= [expected]
          (_, nodes) ->
            assertFailure
              ("expected one presence and three node declarations, got "
                 ++ show (length (Render.planPresences plan))
                 ++ " presences and "
                 ++ show (length nodes)
                 ++ " nodes")
    , testCase "within validates an independent sequence for each current owner" $ do
        plan <- expectPlan scopedRankingPlan
        frameIdentity <-
          case Render.planFrames plan of
            [declaration] -> pure (Render.frameStepIdentity declaration)
            declarations ->
              assertFailure
                ("expected one frame declaration, got "
                   ++ show (length declarations))
        compiled <-
          Compile.compileRenderBatch
            "RenderGuardTest.sverlin"
            "scoped rankings"
            [1]
            (scopedRankingTrace frameIdentity)
            plan
        case compiled of
          Left problem -> assertFailure (show problem)
          Right _      -> pure ()
    , testCase "different-kind membership remains independent of Slot occupancy" $ do
        plan <- expectPlan membershipLifetimePlan
        frameIdentities <-
          case map Render.frameStepIdentity (Render.planFrames plan) of
            [before, after] -> pure (before, after)
            identities ->
              assertFailure
                ("expected two frame declarations, got "
                   ++ show (length identities))
        compiled <-
          Compile.compileRenderBatch
            "RenderGuardTest.sverlin"
            "membership and occupancy lifetimes"
            [1]
            (membershipLifetimeTrace frameIdentities)
            plan
        package <-
          case compiled of
            Left problem -> assertFailure (show problem)
            Right value  -> pure value
        visualization <-
          case Resource.compilationPackageVisualizations package of
            [value] -> pure value
            values ->
              assertFailure
                ("expected one compiled visualization, got "
                   ++ show (length values))
        case IR.visualizationSteps visualization of
          [before, after] -> do
            assertBool
              "the ordinary nested Label should be visible while it occupies the parent Slot"
              (roleVisibleAt "membership-label" visualization before)
            assertBool
              "the related Cell should be visible in the first frame"
              (roleVisibleAt "membership-cell" visualization before)
            assertBool
              "the ordinary nested Label should disappear when its Slot occupancy ends"
              (not (roleVisibleAt "membership-label" visualization after))
            assertBool
              "the explicitly within-scoped Cell should outlive the unrelated Label occupancy"
              (roleVisibleAt "membership-cell" visualization after)
          steps ->
            assertFailure
              ("expected two compiled frames, got " ++ show (length steps))
    ]

structuralPlan :: Either Render.RenderDiagnostic Render.RenderPlan
structuralPlan =
  Render.buildRenderPlan $ do
    nodes <-
      Render.sometimes
        (Render.selectKind "optional.nodes" :: Render.Render
           (Render.Selected Item))
    links <-
      Render.sometimes
        (Render.selectRelation "optional.links" True :: Render.Render
           (Render.Relations Item Item))
    Render.node nodes (pure ())
    Render.within links nodes $ do
      _ <-
        Render.selectKind "within.consumer" :: Render.Render
          (Render.Selected Member)
      pure ()
    Render.relation links $ do
      _ <-
        Render.selectKind "relation.consumer" :: Render.Render
          (Render.Selected Member)
      pure ()
    _ <- Render.asSequence links nodes
    _ <- Render.asTree links nodes
    _ <- Render.asDag links nodes
    Render.arrange
      (Render.ArrangeLayered links (Render.vec2 (Render.by 8) (Render.by 12)))
      nodes

generatedNodePlan :: Either Render.RenderDiagnostic Render.RenderPlan
generatedNodePlan =
  Render.buildRenderPlan $ do
    explanation <- Render.sometimes emptyNode
    detail <-
      Render.node
        (do
           Render.width (Render.by 80)
           _ <-
             Render.node (Render.width (Render.by 30)) :: Render.Render
               (Render.Selected Render.GeneratedNode)
           current <- Render.self
           Render.ensure
             (Render.top current
                Render..==. Render.bottom explanation
                Render..+. Render.by 12)
           Render.content (Render.literal "detail")) :: Render.Render
        (Render.Selected Render.GeneratedNode)
    _ <-
      Render.node (Render.width (Render.by 40)) :: Render.Render
        (Render.Selected Render.GeneratedNode)
    _ <-
      Render.node
        (do
           current <- Render.self
           Render.ensure
             (Render.top current
                Render..==. Render.bottom detail
                Render..+. Render.by 10)) :: Render.Render
        (Render.Selected Render.GeneratedNode)
    pure ()

rankingTextPlan :: Either Render.RenderDiagnostic Render.RenderPlan
rankingTextPlan =
  Render.buildRenderPlan $ do
    nodes <-
      Render.selectKind "plain.nodes" :: Render.Render (Render.Selected Item)
    links <-
      Render.sometimes
        (Render.selectRelation "optional.order" True :: Render.Render
           (Render.Relations Item Item))
    ranking <- Render.asSequence links nodes
    Render.node nodes $ do
      Render.width (Render.by 50)
      ordinal <- Render.rankOf ranking
      Render.content (Render.literal "#" <> Render.asText ordinal)

guardedChoicePlan :: Either Render.RenderDiagnostic Render.RenderPlan
guardedChoicePlan =
  Render.buildRenderPlan $ do
    weight <- Render.sometimes (Render.freshChoice @Render.FontWeight)
    _ <-
      Render.node
        (do
           Render.width (Render.by 90)
           Render.style @Render.FontWeight weight) :: Render.Render
        (Render.Selected Render.GeneratedNode)
    alignment <- Render.freshChoice @Render.TextAlign
    _ <-
      Render.node
        (Render.caseOf alignment $ \value -> do
           Render.style @Render.TextAlign value
           Render.style @Render.FontWeight weight) :: Render.Render
        (Render.Selected Render.GeneratedNode)
    pure ()

guardedConnectorPlan :: Either Render.RenderDiagnostic Render.RenderPlan
guardedConnectorPlan =
  Render.buildRenderPlan $ do
    start <- Render.sometimes emptyNode
    end <- emptyNode
    source <- Render.sometimes emptyNode
    Render.connector
      (Render.anchor Render.AtBoundary start)
      (Render.anchor Render.AtBoundary end) $ do
      Render.style @Render.StrokeWidth (Render.by 2)
      Render.style @Render.Opacity (Render.styleOf @Render.Opacity source)

invalidConnectorStylePlan :: Either Render.RenderDiagnostic Render.RenderPlan
invalidConnectorStylePlan =
  Render.buildRenderPlan $ do
    start <- emptyNode
    end <- emptyNode
    Render.connector
      (Render.anchor Render.AtBoundary start)
      (Render.anchor Render.AtBoundary end)
      $ Render.style @Render.FontFamily Render.FontInter

repeatedSelectionContentPlan :: Either Render.RenderDiagnostic Render.RenderPlan
repeatedSelectionContentPlan =
  Render.buildRenderPlan $ do
    items <-
      Render.selectKind "content.items" :: Render.Render (Render.Selected Item)
    Render.node items (Render.content (Render.text "primary"))
    Render.node items (Render.content (Render.text "secondary"))

alternativeSelectionContentPlan ::
     Either Render.RenderDiagnostic Render.RenderPlan
alternativeSelectionContentPlan =
  Render.buildRenderPlan $ do
    items <-
      Render.selectKind "content.alternatives" :: Render.Render
        (Render.Selected Item)
    Render.oneOf
      "content-layout"
      (Render.alternative
         "compact"
         (Render.node items (Render.content (Render.text "compact"))))
      [ Render.alternative
          "expanded"
          (Render.node items (Render.content (Render.text "expanded")))
      ]

duplicateMappingContentPlan :: Either Render.RenderDiagnostic Render.RenderPlan
duplicateMappingContentPlan =
  Render.buildRenderPlan $ do
    items <-
      Render.selectKind "content.duplicate" :: Render.Render
        (Render.Selected Item)
    Render.node items $ do
      Render.content (Render.text "first")
      Render.fitText (Render.text "second")

presenceOwnershipPlan :: Either Render.RenderDiagnostic Render.RenderPlan
presenceOwnershipPlan =
  Render.buildRenderPlan $ do
    items <-
      Render.selectKind "presence.items" :: Render.Render (Render.Selected Item)
    Render.node items $ do
      Render.sometimes $ do
        _ <-
          Render.node
            (do
               Render.padding (Render.uniform (Render.by 8))
               _ <-
                 Render.node (Render.content (Render.text "nested")) :: Render.Render
                   (Render.Selected Render.GeneratedNode)
               pure ()) :: Render.Render (Render.Selected Render.GeneratedNode)
        pure ()

scopedRankingPlan :: Either Render.RenderDiagnostic Render.RenderPlan
scopedRankingPlan =
  Render.buildRenderPlan $ do
    Render.always (Render.frame @RankingFrame)
    Render.width (Render.by 480)
    Render.height (Render.by 320)
    rows <- Render.selectKind "row" :: Render.Render (Render.Selected Row)
    memberships <-
      Render.selectRelation "row-member" True :: Render.Render
        (Render.Relations Row Cell)
    links <-
      Render.selectRelation "member-next" True :: Render.Render
        (Render.Relations Cell Cell)
    Render.node rows $ do
      Render.width (Render.by 120)
      Render.height (Render.by 48)
      Render.xAt (Render.percent 50)
      Render.yAt (Render.percent 50)
      Render.within memberships rows $ do
        cells <-
          Render.selectKind "cell" :: Render.Render (Render.Selected Cell)
        _ <- Render.asSequence links cells
        pure ()

scopedRankingTrace :: String -> Semantic.SemanticTrace
scopedRankingTrace frameIdentity =
  Semantic.SemanticTrace
    { Semantic.semanticTraceScenarioSeed = 3
    , Semantic.semanticTraceDeclarations =
        [(marker frameIdentity, "ranking frame")]
    , Semantic.semanticTraceVariables = []
    , Semantic.semanticTraceBlocks =
        [ block 0 "row"
        , block 1 "row"
        , block 2 "cell"
        , block 3 "cell"
        , block 4 "cell"
        , block 5 "cell"
        ]
    , Semantic.semanticTraceRelations =
        [ relationRecord 0 "row-member" 0 2
        , relationRecord 1 "row-member" 0 3
        , relationRecord 2 "row-member" 1 4
        , relationRecord 3 "row-member" 1 5
        , relationRecord 4 "member-next" 2 3
        , relationRecord 5 "member-next" 4 5
        ]
    , Semantic.semanticTraceSteps =
        [Semantic.StepOccurrence (marker frameIdentity) [0] 0 1]
    , Semantic.semanticTraceEvents = []
    }
  where
    marker = Semantic.TraceMarker
    block identifier kind =
      Semantic.TraceBlock
        { Semantic.traceBlockId = Semantic.BlockId identifier
        , Semantic.traceBlockKind = marker kind
        , Semantic.traceBlockType = marker kind
        , Semantic.traceBlockPayloadText = ""
        , Semantic.traceBlockPayloadScalar = Nothing
        , Semantic.traceBlockBorn = 0
        , Semantic.traceBlockEnded = Nothing
        , Semantic.traceBlockOccupancies = []
        }
    relationRecord identifier kind source target =
      Semantic.TraceRelation
        { Semantic.traceRelationId = identifier
        , Semantic.traceRelationKind = marker kind
        , Semantic.traceRelationDirection = Semantic.OrderedRelation
        , Semantic.traceRelationSource = Semantic.BlockId source
        , Semantic.traceRelationTarget = Semantic.BlockId target
        , Semantic.traceRelationStart = 0
        , Semantic.traceRelationEnd = Nothing
        }

membershipLifetimePlan :: Either Render.RenderDiagnostic Render.RenderPlan
membershipLifetimePlan =
  Render.buildRenderPlan $ do
    Render.always (Render.frame @MembershipBefore)
    Render.always (Render.frame @MembershipAfter)
    Render.width (Render.by 500)
    Render.height (Render.by 300)
    parents <-
      Render.selectKind "membership-parent" :: Render.Render
        (Render.Selected Row)
    contains <-
      Render.selectRelation "membership-contains" True :: Render.Render
        (Render.Relations Row Cell)
    Render.node parents $ do
      Render.width (Render.by 200)
      Render.height (Render.by 140)
      Render.xAt (Render.percent 50)
      Render.yAt (Render.percent 50)
      labels <-
        Render.selectKind "membership-label" :: Render.Render
          (Render.Selected Member)
      Render.node labels $ do
        Render.width (Render.by 80)
        Render.height (Render.by 32)
        Render.xAt (Render.percent 50)
        Render.yAt (Render.percent 30)
      Render.within contains parents $ do
        cells <-
          Render.selectKind "membership-cell" :: Render.Render
            (Render.Selected Cell)
        Render.node cells $ do
          Render.width (Render.by 80)
          Render.height (Render.by 32)
          Render.xAt (Render.percent 50)
          Render.yAt (Render.percent 70)

membershipLifetimeTrace :: (String, String) -> Semantic.SemanticTrace
membershipLifetimeTrace (before, after) =
  Semantic.SemanticTrace
    { Semantic.semanticTraceScenarioSeed = 4
    , Semantic.semanticTraceDeclarations =
        [ (marker before, "before occupancy ends")
        , (marker after, "after occupancy ends")
        ]
    , Semantic.semanticTraceVariables = []
    , Semantic.semanticTraceBlocks =
        [ block
            0
            "membership-parent"
            [Semantic.TraceOccupancy (Semantic.BlockId 1) 0 (Just 2)]
        , block 1 "membership-label" []
        , block 2 "membership-cell" []
        ]
    , Semantic.semanticTraceRelations =
        [ Semantic.TraceRelation
            { Semantic.traceRelationId = 0
            , Semantic.traceRelationKind = marker "membership-contains"
            , Semantic.traceRelationDirection = Semantic.OrderedRelation
            , Semantic.traceRelationSource = Semantic.BlockId 0
            , Semantic.traceRelationTarget = Semantic.BlockId 2
            , Semantic.traceRelationStart = 0
            , Semantic.traceRelationEnd = Nothing
            }
        ]
    , Semantic.semanticTraceSteps =
        [ Semantic.StepOccurrence (marker before) [0] 0 1
        , Semantic.StepOccurrence (marker after) [1] 2 3
        ]
    , Semantic.semanticTraceEvents = []
    }
  where
    marker = Semantic.TraceMarker
    block identifier kind occupancies =
      Semantic.TraceBlock
        { Semantic.traceBlockId = Semantic.BlockId identifier
        , Semantic.traceBlockKind = marker kind
        , Semantic.traceBlockType = marker kind
        , Semantic.traceBlockPayloadText = ""
        , Semantic.traceBlockPayloadScalar = Nothing
        , Semantic.traceBlockBorn = 0
        , Semantic.traceBlockEnded = Nothing
        , Semantic.traceBlockOccupancies = occupancies
        }

roleVisibleAt :: String -> IR.Visualization -> IR.TimelineStep -> Bool
roleVisibleAt role visualization step =
  any instanceHasRole (IR.stepInstances step)
  where
    instanceHasRole instance' =
      any
        (\element ->
           IR.elementId element == IR.instanceElementId instance'
             && IR.elementRole element == role)
        (IR.visualizationElements visualization)

emptyNode :: Render.Render (Render.Selected Render.GeneratedNode)
emptyNode = Render.node (Render.renderPure ())

expectPlan ::
     Either Render.RenderDiagnostic Render.RenderPlan -> IO Render.RenderPlan
expectPlan result =
  case result of
    Left diagnostic -> assertFailure (show diagnostic)
    Right plan      -> pure plan

assertIndependentContentMappings :: Int -> Render.RenderPlan -> IO ()
assertIndependentContentMappings expected plan = do
  let declarations = Render.planContents plan
      references = map Render.contentDeclarationNode declarations
      owners =
        map
          (Render.scopeCurrentNode . Render.contentDeclarationScope)
          declarations
  length declarations @?= expected
  length (nub references) @?= 1
  length (nub owners) @?= expected

selectionGuards :: String -> Render.RenderPlan -> [Render.PresenceGuard]
selectionGuards key plan =
  case [ sortedGuards (Render.selectionDeclarationScope declaration)
       | declaration <- Render.planSelections plan
       , Render.selectionDeclarationKindKey declaration == key
       ] of
    [guards] -> guards
    matches ->
      error
        ("expected one selection for "
           ++ show key
           ++ ", got "
           ++ show (length matches))

relationSelectionGuards :: String -> Render.RenderPlan -> [Render.PresenceGuard]
relationSelectionGuards key plan =
  case [ sortedGuards (Render.relationSelectionDeclarationScope declaration)
       | declaration <- Render.planRelationSelections plan
       , Render.relationSelectionDeclarationKindKey declaration == key
       ] of
    [guards] -> guards
    matches ->
      error
        ("expected one relation selection for "
           ++ show key
           ++ ", got "
           ++ show (length matches))

scopedDeclarationsFor ::
     [Render.NodeReference] -> Render.RenderPlan -> [[Render.PresenceGuard]]
scopedDeclarationsFor references plan =
  [ sortedGuards (Render.geometryAssignmentScope declaration)
  | reference <- references
  , declaration <- Render.planGeometry plan
  , Render.geometryAssignmentTarget declaration == reference
  ]

sortedGuards :: Render.Scope -> [Render.PresenceGuard]
sortedGuards = sort . Render.scopeGuards

shouldContainExactly ::
     [Render.PresenceGuard] -> [Render.PresenceGuard] -> IO ()
actual `shouldContainExactly` expected = sort actual @?= sort expected
