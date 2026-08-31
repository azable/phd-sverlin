{-# LANGUAGE TypeApplications #-}

-- | Focused checks for the whole-line Render typography path.
module TypographyTest
  ( tests
  ) where

import           Control.Monad                      (unless, when)
import qualified Data.ByteString                    as BS
import           Data.List                          (isInfixOf, nub, sort)
import           Data.Maybe                         (isJust)
import qualified Data.Set                           as Set
import qualified LinearTrace.Visualization.IR       as IR
import qualified LinearTrace.Visualization.Resource as Resource
import qualified Sverlin.Internal.Render            as Render
import qualified Sverlin.Internal.Render.Compile    as Compile
import qualified Sverlin.Internal.Render.Typography as Typography
import qualified Sverlin.Internal.Semantic          as Semantic
import           Test.Tasty                         (TestTree, testGroup)
import           Test.Tasty.HUnit                   (assertBool, assertFailure,
                                                     testCase, (@?=))

data Visible

data ReferenceFrame

data Vertex

data Edge

data Parent

data Child

data NestedTextFrame

data FontWeightFrame

data PeerFrame

data Peer

tests :: TestTree
tests =
  testGroup
    "Render typography"
    [ testCase "shapes one line and maps a fragment through a ligature cluster" $ do
        preparedResult <-
          Typography.prepareLine
            "Source Serif 4"
            400
            "normal"
            "office"
            [Typography.FragmentRange (IR.TextSourceRange 2 3) ["Focus"]]
        prepared <- expectPrepared preparedResult
        assertBool
          "expected positive exact em metrics"
          (Typography.preparedLineWidthEm prepared > 0
             && Typography.preparedLineHeightEm prepared > 0)
        let resources = Typography.preparedLineResources prepared
        map
          (IR.resourceDescriptorKind . Resource.resourceBlobDescriptor)
          resources
          @?= [IR.FontResource, IR.TextRunResource]
        case resources of
          [_fontResource, textRun] ->
            BS.take 4 (Resource.resourceBlobBytes textRun)
              @?= BS.pack [0x53, 0x56, 0x54, 0x52]
          _ -> assertFailure "expected one font and one text-run resource"
        let box = IR.LayoutRect 0 0 400 80
            (_content, layout) =
              Typography.materializeLine 24 24 "left" box prepared
            active =
              Typography.activeFragmentClusters
                (Set.singleton "Focus")
                24
                layout
                prepared
            inactive =
              Typography.activeFragmentClusters Set.empty 24 layout prepared
        IR.textLayoutWrapMode layout @?= IR.TextNoAutomaticWrap
        length (IR.textLayoutLines layout) @?= 1
        inactive @?= []
        assertBool
          "the second f should select the whole ffi glyph cluster"
          (any
             (\cluster ->
                let range = IR.glyphClusterSourceRange cluster
                 in IR.textSourceRangeStart range == 1
                      && IR.textSourceRangeEnd range == 4)
             active)
    , testCase "guarded font branches shape with the sampled concrete style" $ do
        plan <- expectPlan guardedFontPlan
        marker <-
          case Render.planFrames plan of
            [declaration] ->
              pure (Semantic.TraceMarker (Render.frameStepIdentity declaration))
            declarations ->
              assertFailure
                ("expected one frame declaration, got "
                   ++ show (length declarations))
        let trace =
              Semantic.SemanticTrace
                { Semantic.semanticTraceScenarioSeed = 7
                , Semantic.semanticTraceDeclarations = [(marker, "a step")]
                , Semantic.semanticTraceVariables = []
                , Semantic.semanticTraceBlocks = []
                , Semantic.semanticTraceRelations = []
                , Semantic.semanticTraceSteps =
                    [Semantic.StepOccurrence marker [0] 0 0]
                , Semantic.semanticTraceEvents = []
                }
            seeds = [1 .. 24]
        compiled <-
          Compile.compileRenderBatch
            "TypographyTest.sverlin"
            "guarded-fonts"
            seeds
            trace
            plan
        package <-
          case compiled of
            Left problem -> assertFailure (show problem)
            Right value  -> pure value
        let visualizations = Resource.compilationPackageVisualizations package
        length visualizations @?= length seeds
        mapM_ assertTypographyMatchesStyle visualizations
    , testCase
        "relative font weight resolves against the inherited concrete weight" $ do
        visualizations <-
          compileFramePlan "relative font weight" [1] relativeWeightPlan
        case visualizations of
          [visualization] -> do
            let resolved =
                  [ ( IR.textLayoutSource layout
                    , ( IR.visualFontWeight style
                      , IR.fontInstanceWeight (IR.textLayoutFont layout)))
                  | (style, layout) <- textStyles visualization
                  ]
            length resolved @?= 2
            lookup "bolder" resolved @?= Just (Just "900", 900)
            lookup "lighter" resolved @?= Just (Just "400", 400)
          values ->
            assertFailure
              ("expected one visualization, got " ++ show (length values))
    , testCase "static managed faces reject unsupported weights" $ do
        rejected <-
          Typography.prepareLine "IBM Plex Mono" 500 "normal" "exact face" []
        case rejected of
          Left problem ->
            assertBool
              ("unexpected managed-face diagnostic: " ++ problem)
              ("does not provide weight 500" `isInfixOf` problem)
          Right _ ->
            assertFailure "expected IBM Plex Mono weight 500 to be rejected"
        visualizations <-
          compileFramePlan "IBM weight choices" [1 .. 16] ibmWeightChoicePlan
        let weights =
              [ ( IR.visualFontWeight style
                , IR.fontInstanceWeight (IR.textLayoutFont layout))
              | visualization <- visualizations
              , (style, layout) <- textStyles visualization
              ]
        length weights @?= length visualizations
        assertBool
          "categorical branches without a concrete IBM Plex Mono face must be excluded"
          (all (`elem` [(Just "400", 400), (Just "700", 700)]) weights)
    , testCase
        "nested selected content keeps one prepared line per visual mapping" $ do
        plan <- expectPlan nestedContentPlan
        marker <-
          case Render.planFrames plan of
            [declaration] ->
              pure (Semantic.TraceMarker (Render.frameStepIdentity declaration))
            declarations ->
              assertFailure
                ("expected one frame declaration, got "
                   ++ show (length declarations))
        compiled <-
          Compile.compileRenderBatch
            "TypographyTest.sverlin"
            "nested selected content"
            [5]
            (nestedContentTrace marker)
            plan
        package <-
          case compiled of
            Left problem -> assertFailure (show problem)
            Right value  -> pure value
        case Resource.compilationPackageVisualizations package of
          [visualization] -> do
            let elements = IR.visualizationElements visualization
                identifiers = map IR.elementId elements
                textElements =
                  [ ()
                  | element <- elements
                  , Just (IR.PlainTextContent _) <- [IR.elementContent element]
                  ]
            Set.size (Set.fromList identifiers) @?= length identifiers
            length textElements @?= 2
          visualizations ->
            assertFailure
              ("expected one visualization, got "
                 ++ show (length visualizations))
    , testCase "one selected mapping shares fitted size across all peers" $ do
        visualizations <-
          compilePeerPlan "shared peer text" [1 .. 6] peerTextPlan
        let sizeGroups = map textLayoutSizes visualizations
        mapM_
          (\sizes -> do
             length sizes @?= 4
             length (nub sizes) @?= 1)
          sizeGroups
        map (length . fittedSizeVariables) visualizations @?= replicate 6 1
        assertBool
          "the shared feasible size should remain seed-variable"
          (length (nub (concatMap (take 1) sizeGroups)) > 1)
    , testCase "separate mappings of one selection own separate size families" $ do
        visualizations <-
          compilePeerPlan "separate peer mappings" [3] repeatedPeerTextPlan
        case visualizations of
          [visualization] -> do
            length (textLayoutSizes visualization) @?= 8
            length (fittedSizeVariables visualization) @?= 2
          values ->
            assertFailure
              ("expected one visualization, got " ++ show (length values))
    , testCase "nested peers share the child declaration's fitted size" $ do
        plan <- expectPlan nestedContentPlan
        marker <- referenceMarker plan
        compiled <-
          Compile.compileRenderBatch
            "TypographyTest.sverlin"
            "nested shared size"
            [7]
            (nestedContentTrace marker)
            plan
        package <-
          case compiled of
            Left problem -> assertFailure (show problem)
            Right value  -> pure value
        case Resource.compilationPackageVisualizations package of
          [visualization] -> do
            length (nub (textLayoutSizes visualization)) @?= 1
            length (fittedSizeVariables visualization) @?= 1
          values ->
            assertFailure
              ("expected one visualization, got " ++ show (length values))
    , testCase "automatic leaf styles vary by family rather than by peer" $ do
        visualizations <-
          compilePeerPlan "automatic peer styles" [1 .. 96] peerSurfacePlan
        let profiles =
              sort
                (nub
                   [ token
                   | visualization <- visualizations
                   , variable <- IR.visualizationVariables visualization
                   , IR.CspVariableId name <- [IR.cspVariableId variable]
                   , ".leaf.profile" `isInfixOf` name
                   , IR.CspCategory token <- [IR.cspVariableValue variable]
                   ])
        profiles @?= ["flat", "outline", "pill", "soft-card", "transparent"]
        mapM_ assertPeerStylesCoherent visualizations
    , testCase "authored and removed surface fields beat automatic styles" $ do
        visualizations <-
          compileFramePlan "style precedence" [1 .. 24] stylePrecedencePlan
        mapM_
          (\visualization ->
             case nonCanvasStyles visualization of
               [style'] -> do
                 fmap IR.hslHue (IR.visualFill style') @?= Just 42
                 IR.visualStroke style' @?= Nothing
               styles ->
                 assertFailure
                   ("expected one visual leaf, got " ++ show (length styles)))
          visualizations
    , testCase "removed FontSize uses the fixed renderer size without fallback" $ do
        visualizations <-
          compileFramePlan "removed font size" [5] removedFontSizePlan
        case visualizations of
          [visualization] ->
            case textStyles visualization of
              [(style', layout)] -> do
                IR.visualFontSize style' @?= Nothing
                IR.textLayoutFontSize layout @?= 16
                fittedSizeVariables visualization @?= []
              values ->
                assertFailure
                  ("expected one text line, got " ++ show (length values))
          values ->
            assertFailure
              ("expected one visualization, got " ++ show (length values))
    , testCase "structural parents remain transparent by default" $ do
        visualizations <-
          compileFramePlan "transparent parent" [11] structuralStylePlan
        case visualizations of
          [visualization] -> do
            let elements =
                  [ element
                  | element <- IR.visualizationElements visualization
                  , IR.elementId element /= IR.VisualId (-1)
                  ]
                parents = filter (not . null . IR.elementChildren) elements
                profiles =
                  [ token
                  | variable <- IR.visualizationVariables visualization
                  , IR.CspVariableId name <- [IR.cspVariableId variable]
                  , ".leaf.profile" `isInfixOf` name
                  , IR.CspCategory token <- [IR.cspVariableValue variable]
                  ]
            case parents of
              [parent] -> do
                let style' = IR.elementStyle parent
                IR.visualFill style' @?= Nothing
                IR.visualStroke style' @?= Nothing
                IR.visualRadius style' @?= Nothing
              values ->
                assertFailure
                  ("expected one structural parent, got "
                     ++ show (length values))
            length profiles @?= 1
          values ->
            assertFailure
              ("expected one visualization, got " ++ show (length values))
    , testCase "context-local selections and endpoints reuse semantic mappings" $ do
        assertReferencePlan "semantic fallback" contextLocalFallbackPlan
        assertReferencePlan
          "exact mapping precedence"
          exactSelectionPrecedencePlan
    , testCase "endpoint fallback permits only mutually exclusive mappings" $ do
        exclusive <- expectPlan (endpointMultiplicityPlan False)
        marker <- referenceMarker exclusive
        compiled <-
          Compile.compileRenderBatch
            "TypographyTest.sverlin"
            "exclusive endpoint mappings"
            [1 .. 8]
            (referenceTrace marker)
            exclusive
        package <-
          case compiled of
            Left problem -> assertFailure (show problem)
            Right value  -> pure value
        map connectorCount (Resource.compilationPackageVisualizations package)
          @?= replicate 8 1
        overlapping <- expectPlan (endpointMultiplicityPlan True)
        overlappingMarker <- referenceMarker overlapping
        rejected <-
          Compile.compileRenderBatch
            "TypographyTest.sverlin"
            "overlapping endpoint mappings"
            [1]
            (referenceTrace overlappingMarker)
            overlapping
        case rejected of
          Left problem ->
            assertBool
              ("unexpected endpoint diagnostic: " ++ show problem)
              ("simultaneously active visual mappings" `isInfixOf` show problem)
          Right _ ->
            assertFailure
              "expected overlapping endpoint mappings to be rejected"
    ]

guardedFontPlan :: Either Render.RenderDiagnostic Render.RenderPlan
guardedFontPlan =
  Render.buildRenderPlan $ do
    Render.always (Render.frame @Visible)
    Render.width (Render.by 800)
    Render.height (Render.by 450)
    Render.contentFit Render.Both Render.Contain
    family <- Render.fontChoice (Render.fontKind Render.Proportional)
    slant <- Render.freshChoice @Render.FontStyle
    _ <-
      Render.node
        (do
           Render.caseOf family $ \selected ->
             Render.style @Render.FontFamily selected
           Render.caseOf slant $ \selected ->
             Render.style @Render.FontStyle selected
           Render.fitText (Render.text "office affine")
           Render.width (Render.by 360)
           Render.height (Render.by 120)
           Render.xAt (Render.percent 50)
           Render.yAt (Render.percent 50)) :: Render.Render
        (Render.Selected Render.GeneratedNode)
    pure ()

relativeWeightPlan :: Either Render.RenderDiagnostic Render.RenderPlan
relativeWeightPlan =
  Render.buildRenderPlan $ do
    Render.always (Render.frame @FontWeightFrame)
    Render.width (Render.by 400)
    Render.height (Render.by 240)
    _ <-
      Render.node
        (do
           Render.width (Render.by 300)
           Render.height (Render.by 160)
           Render.xAt (Render.percent 50)
           Render.yAt (Render.percent 50)
           Render.style @Render.FontWeight (Render.FontWeightNumber 600)
           _ <-
             Render.node
               (do
                  Render.width (Render.by 180)
                  Render.height (Render.by 48)
                  Render.xAt (Render.percent 50)
                  Render.yAt (Render.percent 30)
                  Render.style @Render.FontWeight Render.FontWeightBolder
                  Render.fitText (Render.text "bolder")) :: Render.Render
               (Render.Selected Render.GeneratedNode)
           _ <-
             Render.node
               (do
                  Render.width (Render.by 180)
                  Render.height (Render.by 48)
                  Render.xAt (Render.percent 50)
                  Render.yAt (Render.percent 70)
                  Render.style @Render.FontWeight Render.FontWeightLighter
                  Render.fitText (Render.text "lighter")) :: Render.Render
               (Render.Selected Render.GeneratedNode)
           pure ()) :: Render.Render (Render.Selected Render.GeneratedNode)
    pure ()

ibmWeightChoicePlan :: Either Render.RenderDiagnostic Render.RenderPlan
ibmWeightChoicePlan =
  Render.buildRenderPlan $ do
    Render.always (Render.frame @FontWeightFrame)
    Render.width (Render.by 400)
    Render.height (Render.by 240)
    weight <- Render.freshChoice @Render.FontWeight
    _ <-
      Render.node
        (do
           Render.width (Render.by 260)
           Render.height (Render.by 80)
           Render.xAt (Render.percent 50)
           Render.yAt (Render.percent 50)
           Render.style @Render.FontFamily Render.FontIBMPlexMono
           Render.caseOf weight $ \selected ->
             Render.style @Render.FontWeight selected
           Render.fitText (Render.text "exact static face")) :: Render.Render
        (Render.Selected Render.GeneratedNode)
    pure ()

stylePrecedencePlan :: Either Render.RenderDiagnostic Render.RenderPlan
stylePrecedencePlan =
  Render.buildRenderPlan $ do
    Render.always (Render.frame @Visible)
    Render.width (Render.by 400)
    Render.height (Render.by 240)
    _ <-
      Render.node
        (do
           Render.width (Render.by 180)
           Render.height (Render.by 72)
           Render.xAt (Render.percent 50)
           Render.yAt (Render.percent 50)
           Render.style @Render.Fill
             (Render.Hsl (Render.num 42) (Render.num 0.4) (Render.num 0.9))
           Render.withoutStyle @Render.Stroke) :: Render.Render
        (Render.Selected Render.GeneratedNode)
    pure ()

removedFontSizePlan :: Either Render.RenderDiagnostic Render.RenderPlan
removedFontSizePlan =
  Render.buildRenderPlan $ do
    Render.always (Render.frame @Visible)
    Render.width (Render.by 400)
    Render.height (Render.by 240)
    _ <-
      Render.node
        (do
           Render.width (Render.by 180)
           Render.height (Render.by 72)
           Render.xAt (Render.percent 50)
           Render.yAt (Render.percent 50)
           Render.withoutStyle @Render.FontSize
           Render.fitText (Render.text "fixed default")) :: Render.Render
        (Render.Selected Render.GeneratedNode)
    pure ()

structuralStylePlan :: Either Render.RenderDiagnostic Render.RenderPlan
structuralStylePlan =
  Render.buildRenderPlan $ do
    Render.always (Render.frame @Visible)
    Render.width (Render.by 400)
    Render.height (Render.by 240)
    _ <-
      Render.node
        (do
           Render.width (Render.by 260)
           Render.height (Render.by 160)
           Render.xAt (Render.percent 50)
           Render.yAt (Render.percent 50)
           _ <-
             Render.node
               (do
                  Render.width (Render.by 120)
                  Render.height (Render.by 60)
                  Render.xAt (Render.percent 50)
                  Render.yAt (Render.percent 50)) :: Render.Render
               (Render.Selected Render.GeneratedNode)
           pure ()) :: Render.Render (Render.Selected Render.GeneratedNode)
    pure ()

nestedContentPlan :: Either Render.RenderDiagnostic Render.RenderPlan
nestedContentPlan =
  Render.buildRenderPlan $ do
    Render.always (Render.frame @NestedTextFrame)
    Render.width (Render.by 640)
    Render.height (Render.by 360)
    parents <-
      Render.selectKind "parent" :: Render.Render (Render.Selected Parent)
    children <-
      Render.selectKind "child" :: Render.Render (Render.Selected Child)
    Render.node parents $ do
      Render.width (Render.by 180)
      Render.height (Render.by 100)
      Render.xAt (Render.percent 50)
      Render.yAt (Render.percent 50)
      Render.node children $ do
        label <- Render.bindContent
        Render.fitText label
        Render.width (Render.by 120)
        Render.height (Render.by 52)
        Render.xAt (Render.percent 50)
        Render.yAt (Render.percent 50)

nestedContentTrace :: Semantic.TraceMarker -> Semantic.SemanticTrace
nestedContentTrace marker =
  Semantic.SemanticTrace
    { Semantic.semanticTraceScenarioSeed = 5
    , Semantic.semanticTraceDeclarations = [(marker, "nested text frame")]
    , Semantic.semanticTraceVariables = []
    , Semantic.semanticTraceBlocks =
        [ block
            0
            "parent"
            ""
            [Semantic.TraceOccupancy (Semantic.BlockId 2) 0 Nothing]
        , block
            1
            "parent"
            ""
            [Semantic.TraceOccupancy (Semantic.BlockId 3) 0 Nothing]
        , block 2 "child" "alpha" []
        , block 3 "child" "beta" []
        ]
    , Semantic.semanticTraceRelations = []
    , Semantic.semanticTraceSteps = [Semantic.StepOccurrence marker [0] 0 1]
    , Semantic.semanticTraceEvents = []
    }
  where
    block identifier kind payload occupancies =
      Semantic.TraceBlock
        { Semantic.traceBlockId = Semantic.BlockId identifier
        , Semantic.traceBlockKind = Semantic.TraceMarker kind
        , Semantic.traceBlockType = Semantic.TraceMarker kind
        , Semantic.traceBlockPayloadText = payload
        , Semantic.traceBlockPayloadScalar = Nothing
        , Semantic.traceBlockBorn = 0
        , Semantic.traceBlockEnded = Nothing
        , Semantic.traceBlockOccupancies = occupancies
        }

peerTextPlan :: Either Render.RenderDiagnostic Render.RenderPlan
peerTextPlan = peerPlan [peerMapping 50 300 True]

repeatedPeerTextPlan :: Either Render.RenderDiagnostic Render.RenderPlan
repeatedPeerTextPlan =
  peerPlan [peerMapping 25 190 True, peerMapping 75 320 True]

peerSurfacePlan :: Either Render.RenderDiagnostic Render.RenderPlan
peerSurfacePlan = peerPlan [peerMapping 50 180 False]

peerPlan ::
     [Render.Selected Peer -> Render.Render ()]
  -> Either Render.RenderDiagnostic Render.RenderPlan
peerPlan mappings =
  Render.buildRenderPlan $ do
    Render.always (Render.frame @PeerFrame)
    Render.width (Render.by 800)
    Render.height (Render.by 400)
    peers <- Render.selectKind "peer" :: Render.Render (Render.Selected Peer)
    mapM_ ($ peers) mappings

peerMapping ::
     Double -> Double -> Bool -> Render.Selected Peer -> Render.Render ()
peerMapping horizontal nodeWidth withText peers =
  Render.node peers $ do
    Render.width (Render.by nodeWidth)
    Render.height (Render.by 72)
    Render.xAt (Render.percent horizontal)
    Render.yAt (Render.percent 50)
    when withText (Render.bindContent >>= Render.fitText)

compilePeerPlan ::
     String
  -> [Int]
  -> Either Render.RenderDiagnostic Render.RenderPlan
  -> IO [IR.Visualization]
compilePeerPlan label seeds planResult = do
  plan <- expectPlan planResult
  marker <- referenceMarker plan
  compiled <-
    Compile.compileRenderBatch
      "TypographyTest.sverlin"
      label
      seeds
      (peerTrace marker)
      plan
  case compiled of
    Left problem  -> assertFailure (show problem)
    Right package -> pure (Resource.compilationPackageVisualizations package)

peerTrace :: Semantic.TraceMarker -> Semantic.SemanticTrace
peerTrace marker =
  Semantic.SemanticTrace
    { Semantic.semanticTraceScenarioSeed = 1
    , Semantic.semanticTraceDeclarations = [(marker, "peer frame")]
    , Semantic.semanticTraceVariables = []
    , Semantic.semanticTraceBlocks =
        zipWith
          peerBlock
          [0 ..]
          ["1", "twenty", "three hundred", "a longer peer label"]
    , Semantic.semanticTraceRelations = []
    , Semantic.semanticTraceSteps = [Semantic.StepOccurrence marker [0] 0 1]
    , Semantic.semanticTraceEvents = []
    }
  where
    peerBlock identifier payload =
      Semantic.TraceBlock
        { Semantic.traceBlockId = Semantic.BlockId identifier
        , Semantic.traceBlockKind = Semantic.TraceMarker "peer"
        , Semantic.traceBlockType = Semantic.TraceMarker "peer"
        , Semantic.traceBlockPayloadText = payload
        , Semantic.traceBlockPayloadScalar = Nothing
        , Semantic.traceBlockBorn = 0
        , Semantic.traceBlockEnded = Nothing
        , Semantic.traceBlockOccupancies = []
        }

textLayoutSizes :: IR.Visualization -> [Double]
textLayoutSizes visualization =
  [IR.textLayoutFontSize layout | (_style, layout) <- textStyles visualization]

fittedSizeVariables :: IR.Visualization -> [(String, Double)]
fittedSizeVariables visualization =
  [ (name, value)
  | variable <- IR.visualizationVariables visualization
  , IR.CspVariableId name <- [IR.cspVariableId variable]
  , ".font-size" `isInfixOf` name
  , IR.CspNumber value <- [IR.cspVariableValue variable]
  ]

assertPeerStylesCoherent :: IR.Visualization -> IO ()
assertPeerStylesCoherent visualization = do
  let styles =
        [ IR.elementStyle element
        | element <- IR.visualizationElements visualization
        , IR.elementId element /= IR.VisualId (-1)
        ]
      profiles =
        [ token
        | variable <- IR.visualizationVariables visualization
        , IR.CspVariableId name <- [IR.cspVariableId variable]
        , ".leaf.profile" `isInfixOf` name
        , IR.CspCategory token <- [IR.cspVariableValue variable]
        ]
  length styles @?= 4
  length (nub styles) @?= 1
  length profiles @?= 1
  case (profiles, styles) of
    (["transparent"], style':_) -> do
      IR.visualFill style' @?= Nothing
      IR.visualStroke style' @?= Nothing
      IR.visualTextAlign style' @?= Just "left"
    (["outline"], style':_) -> do
      IR.visualFill style' @?= Nothing
      assertBool
        "outline profile should have a stroke"
        (isJust (IR.visualStroke style'))
      IR.visualStrokeWidth style' @?= Just 1.5
      IR.visualBorderStyle style' @?= Just "solid"
    (["flat"], style':_) ->
      assertBool
        "flat profile should have a fill"
        (isJust (IR.visualFill style'))
    (["soft-card"], style':_) -> do
      assertBool
        "soft-card profile should have a fill"
        (isJust (IR.visualFill style'))
      assertBool
        "soft-card radius should stay in its bounded theme range"
        (maybe
           False
           (\value -> value >= 6 && value <= 16)
           (IR.visualRadius style'))
    (["pill"], style':_) -> do
      assertBool
        "pill profile should have a fill"
        (isJust (IR.visualFill style'))
      IR.visualRadius style' @?= Just 36
    _ ->
      assertFailure
        ("unexpected automatic profile/style " ++ show (profiles, styles))

nonCanvasStyles :: IR.Visualization -> [IR.VisualStyle]
nonCanvasStyles visualization =
  [ IR.elementStyle element
  | element <- IR.visualizationElements visualization
  , IR.elementId element /= IR.VisualId (-1)
  ]

contextLocalFallbackPlan :: Either Render.RenderDiagnostic Render.RenderPlan
contextLocalFallbackPlan = referencePlan False

exactSelectionPrecedencePlan :: Either Render.RenderDiagnostic Render.RenderPlan
exactSelectionPrecedencePlan = referencePlan True

endpointMultiplicityPlan ::
     Bool -> Either Render.RenderDiagnostic Render.RenderPlan
endpointMultiplicityPlan overlapping =
  Render.buildRenderPlan $ do
    Render.always (Render.frame @ReferenceFrame)
    Render.width (Render.by 400)
    Render.height (Render.by 300)
    vertices <-
      Render.selectKind "vertex" :: Render.Render (Render.Selected Vertex)
    edges <- Render.selectKind "edge" :: Render.Render (Render.Selected Edge)
    sources <-
      Render.selectRelation "source-of" True :: Render.Render
        (Render.Relations Edge Vertex)
    Render.node edges $ do
      Render.width (Render.by 36)
      Render.height (Render.by 36)
      Render.xAt (Render.percent 50)
      Render.yAt (Render.percent 50)
    let mappingAt position = do
          _ <-
            Render.node
              (do
                 Render.width (Render.by 120)
                 Render.height (Render.by 100)
                 Render.xAt (Render.percent position)
                 Render.yAt (Render.percent 50)
                 Render.node vertices $ do
                   Render.width (Render.by 40)
                   Render.height (Render.by 40)
                   Render.xAt (Render.percent 50)
                   Render.yAt (Render.percent 50)) :: Render.Render
              (Render.Selected Render.GeneratedNode)
          pure ()
    if overlapping
      then mappingAt 25 >> mappingAt 75
      else Render.oneOf
             "endpoint mapping"
             (Render.alternative "left" (mappingAt 25))
             [Render.alternative "right" (mappingAt 75)]
    Render.relation sources $ do
      source <- Render.first sources
      target <- Render.second sources
      Render.connector
        (Render.anchor Render.AtBoundary source)
        (Render.anchor Render.AtBoundary target)
        (pure ())

referencePlan :: Bool -> Either Render.RenderDiagnostic Render.RenderPlan
referencePlan mapLocalSelection =
  Render.buildRenderPlan $ do
    Render.always (Render.frame @ReferenceFrame)
    Render.width (Render.by 400)
    Render.height (Render.by 300)
    vertices <-
      Render.selectKind "vertex" :: Render.Render (Render.Selected Vertex)
    edges <- Render.selectKind "edge" :: Render.Render (Render.Selected Edge)
    sources <-
      Render.selectRelation "source-of" True :: Render.Render
        (Render.Relations Edge Vertex)
    _ <-
      Render.node
        (do
           container <- Render.self
           Render.width (Render.by 300)
           Render.height (Render.by 200)
           Render.xAt (Render.percent 50)
           Render.yAt (Render.percent 50)
           Render.node vertices $ do
             Render.width (Render.by 40)
             Render.height (Render.by 40)
             Render.ensure
               (Render.x vertices
                  Render..==. Render.left container
                  Render..+. Render.by 40)
             Render.ensure (Render.y vertices Render..==. Render.y container)
           Render.node edges $ do
             Render.width (Render.by 40)
             Render.height (Render.by 40)
             Render.ensure (Render.y edges Render..==. Render.y container)
             source <- Render.within sources edges (Render.selectKind "vertex")
             when mapLocalSelection $ do
               Render.ensure
                 (Render.x edges
                    Render..==. Render.right container
                    Render..-. Render.by 40)
               Render.node source $ do
                 Render.width (Render.by 12)
                 Render.height (Render.by 12)
                 Render.ensure (Render.x source Render..==. Render.x edges)
                 Render.ensure (Render.y source Render..==. Render.y edges)
             Render.ensure (Render.x edges Render..==. Render.x source)) :: Render.Render
        (Render.Selected Render.GeneratedNode)
    unless mapLocalSelection
      $ Render.relation sources $ do
      source <- Render.first sources
      target <- Render.second sources
      Render.connector
        (Render.anchor Render.AtBoundary source)
        (Render.anchor Render.AtBoundary target)
        (pure ())

assertReferencePlan ::
     String -> Either Render.RenderDiagnostic Render.RenderPlan -> IO ()
assertReferencePlan label planResult = do
  plan <- expectPlan planResult
  marker <- referenceMarker plan
  compiled <-
    Compile.compileRenderBatch
      "TypographyTest.sverlin"
      label
      [1]
      (referenceTrace marker)
      plan
  case compiled of
    Left problem -> assertFailure (show problem)
    Right _      -> pure ()

referenceMarker :: Render.RenderPlan -> IO Semantic.TraceMarker
referenceMarker plan =
  case Render.planFrames plan of
    [declaration] ->
      pure (Semantic.TraceMarker (Render.frameStepIdentity declaration))
    declarations ->
      assertFailure
        ("expected one frame declaration, got " ++ show (length declarations))

connectorCount :: IR.Visualization -> Int
connectorCount visualization =
  maybe 0 length (IR.visualizationConnectors visualization)

referenceTrace :: Semantic.TraceMarker -> Semantic.SemanticTrace
referenceTrace marker =
  Semantic.SemanticTrace
    { Semantic.semanticTraceScenarioSeed = 1
    , Semantic.semanticTraceDeclarations = [(marker, "reference frame")]
    , Semantic.semanticTraceVariables = []
    , Semantic.semanticTraceBlocks =
        [traceBlock 1 "vertex", traceBlock 2 "edge"]
    , Semantic.semanticTraceRelations =
        [ Semantic.TraceRelation
            { Semantic.traceRelationId = 1
            , Semantic.traceRelationKind = Semantic.TraceMarker "source-of"
            , Semantic.traceRelationDirection = Semantic.OrderedRelation
            , Semantic.traceRelationSource = Semantic.BlockId 2
            , Semantic.traceRelationTarget = Semantic.BlockId 1
            , Semantic.traceRelationStart = 0
            , Semantic.traceRelationEnd = Nothing
            }
        ]
    , Semantic.semanticTraceSteps = [Semantic.StepOccurrence marker [0] 0 1]
    , Semantic.semanticTraceEvents = []
    }
  where
    traceBlock identifier kind =
      Semantic.TraceBlock
        { Semantic.traceBlockId = Semantic.BlockId identifier
        , Semantic.traceBlockKind = Semantic.TraceMarker kind
        , Semantic.traceBlockType = Semantic.TraceMarker kind
        , Semantic.traceBlockPayloadText = ""
        , Semantic.traceBlockPayloadScalar = Nothing
        , Semantic.traceBlockBorn = 0
        , Semantic.traceBlockEnded = Nothing
        , Semantic.traceBlockOccupancies = []
        }

compileFramePlan ::
     String
  -> [Int]
  -> Either Render.RenderDiagnostic Render.RenderPlan
  -> IO [IR.Visualization]
compileFramePlan label seeds planResult = do
  plan <- expectPlan planResult
  marker <- referenceMarker plan
  compiled <-
    Compile.compileRenderBatch
      "TypographyTest.sverlin"
      label
      seeds
      (frameTrace marker)
      plan
  case compiled of
    Left problem  -> assertFailure (show problem)
    Right package -> pure (Resource.compilationPackageVisualizations package)

frameTrace :: Semantic.TraceMarker -> Semantic.SemanticTrace
frameTrace marker =
  Semantic.SemanticTrace
    { Semantic.semanticTraceScenarioSeed = 1
    , Semantic.semanticTraceDeclarations = [(marker, "a step")]
    , Semantic.semanticTraceVariables = []
    , Semantic.semanticTraceBlocks = []
    , Semantic.semanticTraceRelations = []
    , Semantic.semanticTraceSteps = [Semantic.StepOccurrence marker [0] 0 0]
    , Semantic.semanticTraceEvents = []
    }

textStyles :: IR.Visualization -> [(IR.VisualStyle, IR.TextLayout)]
textStyles visualization =
  [ (IR.elementStyle element, layout)
  | element <- IR.visualizationElements visualization
  , Just (IR.PlainTextContent layout) <- [IR.elementContent element]
  ]

assertTypographyMatchesStyle :: IR.Visualization -> IO ()
assertTypographyMatchesStyle visualization =
  case textStyles visualization of
    [(style, layout)] -> do
      let face = IR.textLayoutFont layout
          family = IR.fontInstanceFamily face
          slant = IR.fontInstanceStyle face
      IR.visualFontFamily style @?= Just family
      IR.visualFontStyle style @?= Just slant
      assertBool
        "an unavailable concrete font/style pair must be excluded"
        (family /= "Space Grotesk" || slant /= "italic")
    matches ->
      assertFailure
        ("expected one materialized text layout, got " ++ show (length matches))

expectPrepared ::
     Either String Typography.PreparedLine -> IO Typography.PreparedLine
expectPrepared result =
  case result of
    Left problem -> assertFailure problem
    Right value  -> pure value

expectPlan ::
     Either Render.RenderDiagnostic Render.RenderPlan -> IO Render.RenderPlan
expectPlan result =
  case result of
    Left problem -> assertFailure (show problem)
    Right value  -> pure value
