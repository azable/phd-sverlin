{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}

-- | Lower a solved symbolic view graph into the renderer-independent IR.
module LinearTrace.Visualization.Compile
  ( compileSolved
  , compileSolvedWithTypography
  ) where

import           Control.Monad.State.Strict
import qualified Data.ByteString                      as BS
import           Data.List                            (sortOn)
import           Data.Map.Strict                      (Map)
import qualified Data.Map.Strict                      as Map
import qualified Data.Text                            as Text
import qualified Data.Text.Encoding                   as TextEncoding
import qualified LinearTrace.View.Box                 as VB
import qualified LinearTrace.View.Graph               as V
import qualified LinearTrace.View.Primitives          as VP
import qualified LinearTrace.View.Style               as VS
import qualified LinearTrace.Visualization.IR         as IR
import qualified LinearTrace.Visualization.Resource   as Resource
import qualified LinearTrace.Visualization.Typography as Typography
import           Prelude
import qualified Solver                               as S

compileSolved ::
     FilePath -> S.Solution -> V.ViewGraph -> Either String IR.Visualization
compileSolved sourcePath solution graph =
  compileSolvedWith sourcePath solution graph Map.empty [] []

compileSolvedWithTypography ::
     FilePath
  -> S.Solution
  -> V.ViewGraph
  -> Typography.TypographyOutput
  -> Either String IR.Visualization
compileSolvedWithTypography sourcePath solution graph typography =
  compileSolvedWith
    sourcePath
    solution
    graph
    (Typography.typographyOutputContents typography)
    (map
       Resource.resourceBlobDescriptor
       (Typography.typographyOutputResources typography))
    (Typography.typographyOutputFindings typography)

compileSolvedWith ::
     FilePath
  -> S.Solution
  -> V.ViewGraph
  -> Map Int IR.VisualContent
  -> [IR.ResourceDescriptor]
  -> [IR.VisualizationFinding]
  -> Either String IR.Visualization
compileSolvedWith sourcePath solution graph contents resources findings = do
  let children = childIndex (V.viewNodes graph)
  elements <-
    traverse (compileElement solution contents children) (V.viewNodes graph)
  _ <- requireCanvasRoot elements
  let emphasis = emphasisLookup (V.viewNodes graph)
      elementsById = elementLookup elements
      instanceIds = instanceIdLookup elements
  validateEmphasisContent elementsById emphasis
  steps <-
    evalStateT
      (compileSteps elementsById instanceIds emphasis (V.viewSteps graph))
      emptySceneState
  validateEmphasisTargets emphasis steps
  pure
    IR.Visualization
      { IR.visualizationIrVersion = 1
      , IR.visualizationSeed = solutionSeedInt solution
      , IR.visualizationSourcePath = sourcePath
      , IR.visualizationSampling = Just (compileSampling solution)
      , IR.visualizationCoordinates =
          IR.CoordinateSystem
            { IR.coordinateSystemName = "sverlin-logical-y-down"
            , IR.coordinateSystemOrigin = "top-left"
            , IR.coordinateSystemYAxis = "down"
            }
      , IR.visualizationRoot = IR.VisualId (-1)
      , IR.visualizationResources = resources
      , IR.visualizationFindings =
          map
            (attachFindingSteps steps)
            (findings ++ compileViewDiagnostics graph)
      , IR.visualizationVariables = compileVariables solution
      , IR.visualizationElements = elements
      , IR.visualizationSteps = steps
      }

compileSampling :: S.Solution -> IR.SamplingProvenance
compileSampling solution =
  case S.solutionSampling solution of
    S.LegacySampling ->
      IR.SamplingProvenance IR.LegacyOptimizer IR.LegacyCoverage
    S.SampledWith strategy coverage ->
      IR.SamplingProvenance
        (case strategy of
           S.BalancedDesignChoices -> IR.BalancedChoices
           S.GeometricVolume _     -> IR.GeometricMeasure)
        (case coverage of
           S.EnumeratedDecisions     -> IR.ExactEnumeration
           S.MipConditionedDecisions -> IR.MipConditioning)

solutionSeedInt :: S.Solution -> Int
solutionSeedInt solution =
  case S.solutionSeed solution of
    S.RandomSeed seed -> seed

compileVariables :: S.Solution -> [IR.CspVariable]
compileVariables solution =
  map numericVariable (Map.toAscList (S.solutionValues solution))
    ++ map categoryVariable (Map.toAscList (S.solutionChoices solution))
  where
    numericVariable (name, value) =
      IR.CspVariable
        { IR.cspVariableId = IR.CspVariableId name
        , IR.cspVariableValue = IR.CspNumber (roundLayout value)
        }
    categoryVariable (name, value) =
      IR.CspVariable
        { IR.cspVariableId = IR.CspVariableId name
        , IR.cspVariableValue = IR.CspCategory value
        }

compileElement ::
     S.Solution
  -> Map Int IR.VisualContent
  -> Map V.ViewId [V.ViewId]
  -> V.ViewNode
  -> Either String IR.VisualElement
compileElement solution contents children wrapped =
  case wrapped of
    V.ViewNode node -> do
      box <- compileBox solution (V.nodeBox node)
      style <- compileStyle solution (V.nodeStyle node)
      styleBindings <- compileVariableBindings solution node
      pure
        IR.VisualElement
          { IR.elementId = visualId (V.nodeRef node)
          , IR.elementRole = V.viewLabelKind (V.nodeLabel node)
          , IR.elementBox = box
          , IR.elementChildren =
              map
                (IR.VisualId . V.viewIdInt)
                (Map.findWithDefault [] (V.viewRefId (V.nodeRef node)) children)
          , IR.elementContent = compileContent contents node
          , IR.elementStyle = style
          , IR.elementStyleVariables = styleBindings
          }

childIndex :: [V.ViewNode] -> Map V.ViewId [V.ViewId]
childIndex = foldl addChild Map.empty
  where
    addChild index (V.ViewNode node) =
      case V.nodeParent node of
        Nothing -> index
        Just parent ->
          Map.insertWith (flip (++)) parent [V.viewRefId (V.nodeRef node)] index

requireCanvasRoot :: [IR.VisualElement] -> Either String IR.VisualElement
requireCanvasRoot elements =
  case filter ((== IR.VisualId (-1)) . IR.elementId) elements of
    [root] -> Right root
    []     -> Left "visualization graph has no canvas root"
    _      -> Left "visualization graph has more than one canvas root"

visualId :: V.ViewRef tag -> IR.VisualId
visualId = IR.VisualId . V.viewRefInt

compileContent ::
     Map Int IR.VisualContent -> V.Node tag -> Maybe IR.VisualContent
compileContent contents node =
  case Map.lookup (V.viewRefInt (V.nodeRef node)) contents of
    Just content -> Just content
    Nothing ->
      case V.nodeContent node of
        V.ContentEmpty -> Nothing
        V.ContentText value -> Just (IR.LegacyTextContent value)
        V.ContentFitText value -> Just (IR.LegacyTextContent value)
        V.ContentCode code ->
          Just (IR.LegacyTextContent (V.codeContentSource code))

attachFindingSteps ::
     [IR.TimelineStep] -> IR.VisualizationFinding -> IR.VisualizationFinding
attachFindingSteps steps finding
  | not (null (IR.visualizationFindingStepIndices finding)) = finding
  | otherwise =
    finding
      { IR.visualizationFindingStepIndices =
          [ index
          | (index, step) <- zip [0 :: Int ..] steps
          , any
              (\instance' ->
                 IR.instanceElementId instance'
                   `elem` IR.visualizationFindingElementIds finding)
              (IR.stepInstances step)
          ]
      }

compileStyle :: S.Solution -> VS.NodeStyle -> Either String IR.VisualStyle
compileStyle solution style = do
  IR.VisualStyle
    <$> resolvedScalar @VS.Opacity
    <*> resolvedScalar @VS.ZIndex
    <*> resolvedScalar @VS.FontSize
    <*> resolvedScalar @VS.Radius
    <*> resolvedScalar @VS.StrokeWidth
    <*> resolvedScalar @VS.Alpha
    <*> resolvedColor @VS.Fill
    <*> resolvedColor @VS.Stroke
    <*> resolved @VS.FontFamily
    <*> resolved @VS.FontWeight
    <*> resolved @VS.FontStyle
    <*> resolved @VS.TextAlign
    <*> resolved @VS.BorderStyle
    <*> resolved @VS.WhiteSpace
  where
    resolved ::
         forall field. VS.StyleField field
      => Either String (Maybe (VS.ResolvedStyleValue field))
    resolved = VS.materializeStyleField @field solution style
    resolvedScalar ::
         forall field.
         (VS.StyleField field, VS.ResolvedStyleValue field ~ Double)
      => Either String (Maybe Double)
    resolvedScalar = fmap (fmap roundLayout) (resolved @field)
    resolvedColor ::
         forall field.
         (VS.StyleField field, VS.ResolvedStyleValue field ~ VP.ConcreteHsl)
      => Either String (Maybe IR.HslColor)
    resolvedColor = fmap (fmap compileColor) (resolved @field)

compileBox :: S.Solution -> VB.NodeBox -> Either String IR.VisualBox
compileBox solution box = do
  let VP.Bounds top left width height = VB.nodeBoxBounds box
  bounds <-
    IR.LayoutRect
      <$> solved "left" left
      <*> solved "top" top
      <*> solved "width" width
      <*> solved "height" height
  padding <- VB.materializeNodePadding solution box
  margin <- VB.materializeNodeMargin solution box
  pure
    IR.VisualBox
      { IR.boxBounds = bounds
      , IR.boxPadding = compileInsets padding
      , IR.boxMargin = compileInsets margin
      }
  where
    solved label expression =
      case S.evalExpr solution expression of
        Just value -> Right (roundLayout value)
        Nothing ->
          Left
            ("could not materialize "
               ++ label
               ++ "; the expression references an unsolved variable")

compileInsets :: VB.ConcreteInsets -> IR.EdgeInsets
compileInsets insets =
  IR.EdgeInsets
    { IR.insetsTop = roundLayout (VB.insetTop insets)
    , IR.insetsRight = roundLayout (VB.insetRight insets)
    , IR.insetsBottom = roundLayout (VB.insetBottom insets)
    , IR.insetsLeft = roundLayout (VB.insetLeft insets)
    }

compileColor :: VP.ConcreteHsl -> IR.HslColor
compileColor color =
  IR.HslColor
    { IR.hslHue = roundLayout (VP.hue color)
    , IR.hslSaturation = roundLayout (VP.saturation color)
    , IR.hslLightness = roundLayout (VP.lightness color)
    }

compileVariableBindings ::
     S.Solution -> V.Node tag -> Either String [IR.StyleVariableBinding]
compileVariableBindings solution node = do
  boxBindings <- VB.nodeBoxVariableBindings solution (V.nodeBox node)
  styleBindings <- VS.styleVariableBindings solution (V.nodeStyle node)
  pure (map compileBinding (boxBindings ++ styleBindings))
  where
    compileBinding (field, variables) =
      IR.StyleVariableBinding
        { IR.bindingField = field
        , IR.bindingVariables = map IR.CspVariableId variables
        }

compileViewDiagnostics :: V.ViewGraph -> [IR.VisualizationFinding]
compileViewDiagnostics graph =
  zipWith compileDiagnostic [0 :: Int ..] (V.viewDiagnostics graph)
  where
    compileDiagnostic index diagnostic =
      IR.VisualizationFinding
        { IR.visualizationFindingId =
            "hierarchy-"
              ++ show index
              ++ "-"
              ++ V.viewDiagnosticDeclaration diagnostic
        , IR.visualizationFindingSeverity = IR.FindingWarning
        , IR.visualizationFindingCode = V.viewDiagnosticCode diagnostic
        , IR.visualizationFindingMessage = V.viewDiagnosticMessage diagnostic
        , IR.visualizationFindingElementIds =
            [ visualId (V.nodeRef node)
            | V.ViewNode node <- V.viewNodes graph
            , V.nodeDeclaration node == V.viewDiagnosticDeclaration diagnostic
            ]
        , IR.visualizationFindingStepIndices = []
        , IR.visualizationFindingEvidence =
            [ IR.FindingEvidence
                "declaration"
                (IR.FindingText (V.viewDiagnosticDeclaration diagnostic))
                Nothing
            , IR.FindingEvidence
                "reason"
                (IR.FindingText (V.viewDiagnosticReason diagnostic))
                Nothing
            , IR.FindingEvidence
                "matched"
                (IR.FindingNumber
                   (fromIntegral (V.viewDiagnosticMatched diagnostic)))
                Nothing
            , IR.FindingEvidence
                "visible"
                (IR.FindingNumber
                   (fromIntegral (V.viewDiagnosticVisible diagnostic)))
                Nothing
            ]
        }

type ElementLookup = Map IR.VisualId IR.VisualElement

type InstanceIdLookup = Map IR.VisualId IR.RenderInstanceId

type EmphasisLookup = Map IR.VisualId (String, [(String, [V.CodeRange])])

elementLookup :: [IR.VisualElement] -> ElementLookup
elementLookup elements =
  Map.fromList [(IR.elementId element, element) | element <- elements]

instanceIdLookup :: [IR.VisualElement] -> InstanceIdLookup
instanceIdLookup elements =
  Map.fromList
    [ (IR.elementId element, IR.RenderInstanceId index)
    | (index, element) <- zip [0 ..] elements
    ]

emphasisLookup :: [V.ViewNode] -> EmphasisLookup
emphasisLookup = Map.fromList . foldMap entry
  where
    entry wrapped =
      case wrapped of
        V.ViewNode node ->
          case V.nodeContent node of
            V.ContentCode code
              | not (null (V.codeContentEmphasis code)) ->
                [ ( visualId (V.nodeRef node)
                  , (V.codeContentSource code, V.codeContentEmphasis code))
                ]
            _ -> []

validateEmphasisContent :: ElementLookup -> EmphasisLookup -> Either String ()
validateEmphasisContent elements emphasis =
  mapM_ validateElement (Map.keys emphasis)
  where
    validateElement elementId =
      case IR.elementContent =<< Map.lookup elementId elements of
        Just IR.CodeTextContent {} -> pure ()
        _ ->
          Left
            ("code emphasis for element "
               ++ show elementId
               ++ " requires compiler-owned code typography")

data SceneState = SceneState
  { sceneLineage   :: Map IR.VisualId IR.RenderInstanceId
  , sceneInstances :: Map IR.RenderInstanceId IR.VisualInstance
  }

emptySceneState :: SceneState
emptySceneState = SceneState Map.empty Map.empty

type CompileM = StateT SceneState (Either String)

compileSteps ::
     ElementLookup
  -> InstanceIdLookup
  -> EmphasisLookup
  -> [V.ViewStep]
  -> CompileM [IR.TimelineStep]
compileSteps lookup' instanceIds emphasis =
  traverse (compileStep lookup' instanceIds emphasis)

compileStep ::
     ElementLookup
  -> InstanceIdLookup
  -> EmphasisLookup
  -> V.ViewStep
  -> CompileM IR.TimelineStep
compileStep lookup' instanceIds emphasis step = do
  modify clearOrigins
  let (introductions, removals) = V.splitRenderIntents (V.viewStepIntents step)
  mapM_ (applyIntent lookup' instanceIds) introductions
  baseInstances <- gets (Map.elems . sceneInstances)
  instances <-
    lift
      (traverse
         (attachCodeEmphasis emphasis (V.viewStepLabel step))
         baseInstances)
  mapM_ (applyIntent lookup' instanceIds) removals
  pure
    IR.TimelineStep
      {IR.stepLabel = V.viewStepLabel step, IR.stepInstances = instances}

clearOrigins :: SceneState -> SceneState
clearOrigins scene =
  scene
    { sceneInstances =
        Map.map
          (\instance' -> instance' {IR.instanceOriginElementId = Nothing})
          (sceneInstances scene)
    }

attachCodeEmphasis ::
     EmphasisLookup
  -> String
  -> IR.VisualInstance
  -> Either String IR.VisualInstance
attachCodeEmphasis emphasis stepLabel instance' =
  case Map.lookup (IR.instanceElementId instance') emphasis of
    Nothing -> pure instance'
    Just (source, schedule) -> do
      ranges <-
        compileCodeRanges
          (IR.instanceElementId instance')
          source
          (concat
             [ configured
             | (configuredStep, configured) <- schedule
             , configuredStep == stepLabel
             ])
      pure
        instance'
          { IR.instanceCodeEmphasisRanges =
              if null ranges
                then Nothing
                else Just ranges
          }

compileCodeRanges ::
     IR.VisualId
  -> String
  -> [V.CodeRange]
  -> Either String [IR.TextSourceRange]
compileCodeRanges elementId source ranges = do
  mapM_ validateRange ranges
  pure (map compileRange (mergeCodeRanges (sortOn rangeBounds ranges)))
  where
    sourceLength = length source
    rangeBounds range = (V.codeRangeStart range, V.codeRangeEnd range)
    validateRange range
      | start < 0 = invalid "starts before the source"
      | end <= start = invalid "must have a positive length"
      | end > sourceLength = invalid "ends after the source"
      | otherwise = pure ()
      where
        start = V.codeRangeStart range
        end = V.codeRangeEnd range
        invalid reason =
          Left
            ("code emphasis range "
               ++ show (start, end)
               ++ " for element "
               ++ show elementId
               ++ " "
               ++ reason)
    compileRange range =
      IR.TextSourceRange
        { IR.textSourceRangeStart = utf8Offset (V.codeRangeStart range)
        , IR.textSourceRangeEnd = utf8Offset (V.codeRangeEnd range)
        }
    utf8Offset offset =
      BS.length (TextEncoding.encodeUtf8 (Text.pack (take offset source)))

mergeCodeRanges :: [V.CodeRange] -> [V.CodeRange]
mergeCodeRanges ranges =
  case ranges of
    []         -> []
    first:rest -> reverse (foldl merge [first] rest)
  where
    merge merged next =
      case merged of
        [] -> [next]
        current:previous
          | V.codeRangeStart next <= V.codeRangeEnd current ->
            current
              { V.codeRangeEnd =
                  max (V.codeRangeEnd current) (V.codeRangeEnd next)
              }
              : previous
          | otherwise -> next : merged

validateEmphasisTargets ::
     EmphasisLookup -> [IR.TimelineStep] -> Either String ()
validateEmphasisTargets emphasis steps =
  mapM_ validateElement (Map.toAscList emphasis)
  where
    validateElement (elementId, (_, schedule)) =
      mapM_ (validateStep elementId) schedule
    validateStep _ (_, []) = pure ()
    validateStep elementId (stepLabel, _)
      | any (isVisibleAt elementId stepLabel) steps = pure ()
      | otherwise =
        Left
          ("code emphasis for element "
             ++ show elementId
             ++ " references checkpoint "
             ++ show stepLabel
             ++ " where the element is not visible")
    isVisibleAt elementId stepLabel step =
      IR.stepLabel step == stepLabel
        && any ((== elementId) . IR.instanceElementId) (IR.stepInstances step)

applyIntent ::
     ElementLookup -> InstanceIdLookup -> V.RenderIntent -> CompileM ()
applyIntent lookup' instanceIds intent =
  case intent of
    V.RenderFresh ref ->
      mapM_ (createElement instanceIds) (lookupElement lookup' ref)
    V.RenderRemove ref -> mapM_ destroyElement (lookupElement lookup' ref)
    V.RenderContinue source target ->
      continueRef lookup' instanceIds source target
    V.RenderFork source target -> forkRef lookup' instanceIds source target

continueRef ::
     ElementLookup
  -> InstanceIdLookup
  -> V.ViewRef source
  -> V.ViewRef target
  -> CompileM ()
continueRef lookup' instanceIds sourceRef targetRef =
  case (lookupElement lookup' sourceRef, lookupElement lookup' targetRef) of
    (Nothing, Nothing)         -> pure ()
    (Nothing, Just target)     -> createElement instanceIds target
    (Just source, Nothing)     -> destroyElement source
    (Just source, Just target) -> continueElement source target

continueElement :: IR.VisualElement -> IR.VisualElement -> CompileM ()
continueElement source target = do
  instanceId <- requireLineage source
  modify
    (\scene ->
       scene
         { sceneLineage =
             Map.insert
               (IR.elementId target)
               instanceId
               (Map.delete (IR.elementId source) (sceneLineage scene))
         , sceneInstances =
             Map.insert
               instanceId
               (IR.VisualInstance
                  { IR.instanceId = instanceId
                  , IR.instanceElementId = IR.elementId target
                  , IR.instanceOriginElementId = Nothing
                  , IR.instanceCodeEmphasisRanges = Nothing
                  })
               (sceneInstances scene)
         })

forkRef ::
     ElementLookup
  -> InstanceIdLookup
  -> V.ViewRef source
  -> V.ViewRef target
  -> CompileM ()
forkRef lookup' instanceIds sourceRef targetRef =
  case lookupElement lookup' targetRef of
    Nothing -> pure ()
    Just target -> do
      origin <-
        case lookupElement lookup' sourceRef of
          Nothing -> pure Nothing
          Just source -> do
            _ <- requireLineage source
            pure (Just (IR.elementId source))
      createElementWithOrigin instanceIds origin target

createElement :: InstanceIdLookup -> IR.VisualElement -> CompileM ()
createElement instanceIds = createElementWithOrigin instanceIds Nothing

createElementWithOrigin ::
     InstanceIdLookup -> Maybe IR.VisualId -> IR.VisualElement -> CompileM ()
createElementWithOrigin instanceIds origin element =
  let elementId' = IR.elementId element
   in case Map.lookup elementId' instanceIds of
        Nothing ->
          lift (Left ("no render-instance identity for " ++ show elementId'))
        Just instanceId ->
          modify
            (\scene ->
               scene
                 { sceneLineage =
                     Map.insert elementId' instanceId (sceneLineage scene)
                 , sceneInstances =
                     Map.insert
                       instanceId
                       (IR.VisualInstance
                          { IR.instanceId = instanceId
                          , IR.instanceElementId = elementId'
                          , IR.instanceOriginElementId = origin
                          , IR.instanceCodeEmphasisRanges = Nothing
                          })
                       (sceneInstances scene)
                 })

destroyElement :: IR.VisualElement -> CompileM ()
destroyElement element = do
  instanceId <- requireLineage element
  modify
    (\scene ->
       scene
         { sceneLineage = Map.delete (IR.elementId element) (sceneLineage scene)
         , sceneInstances = Map.delete instanceId (sceneInstances scene)
         })

requireLineage :: IR.VisualElement -> CompileM IR.RenderInstanceId
requireLineage element = do
  lineage <- gets sceneLineage
  case Map.lookup (IR.elementId element) lineage of
    Just instanceId -> pure instanceId
    Nothing ->
      lift (Left ("no render lineage for " ++ show (IR.elementId element)))

lookupElement :: ElementLookup -> V.ViewRef tag -> Maybe IR.VisualElement
lookupElement lookup' ref = Map.lookup (visualId ref) lookup'

roundLayout :: Double -> Double
roundLayout value =
  let rounded = fromIntegral (round (value * 1000) :: Integer) / 1000
   in if abs rounded < 0.0005
        then 0
        else rounded
