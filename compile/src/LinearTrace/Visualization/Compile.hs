{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE GADTs             #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications  #-}
{-# LANGUAGE TypeFamilies      #-}

-- | Lower a solved symbolic view graph into the renderer-independent IR.
module LinearTrace.Visualization.Compile
  ( compileSolved
  ) where

import           Control.Monad.State.Strict
import           Data.Map.Strict                  (Map)
import qualified Data.Map.Strict                  as Map
import qualified LinearTrace.View.Graph           as V
import qualified LinearTrace.View.Primitives      as VP
import qualified LinearTrace.View.Style           as VS
import qualified LinearTrace.Visualization.IR     as IR
import           Prelude
import qualified Solver                           as S

compileSolved ::
     FilePath
  -> S.Solution
  -> V.ViewGraph
  -> Either String IR.VisualizationPackage
compileSolved sourcePath solution graph = do
  elements <- traverse (compileElement solution) (V.viewNodes graph)
  frames <-
    evalStateT
      (compileFrames (elementLookup elements) (V.viewRenderFrames graph))
      emptySceneState
  pure
    IR.VisualizationPackage
      { IR.packageSchemaVersion = 2
      , IR.packageSeed = solutionSeedInt solution
      , IR.packageSourcePath = sourcePath
      , IR.packageCanvas =
          IR.CanvasSpec
            { IR.canvasWidth = roundLayout (V.viewCanvasWidth graph)
            , IR.canvasHeight = roundLayout (V.viewCanvasHeight graph)
            }
      , IR.packageVariables = compileVariables solution
      , IR.packageElements = elements
      , IR.packageFrames = frames
      }

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
     S.Solution -> V.ViewNode -> Either String IR.VisualElement
compileElement solution wrapped =
  case wrapped of
    V.ViewNode node ->
      IR.VisualElement
        <$> pure (visualId (V.nodeRef node))
        <*> pure (V.viewLabelKind (V.nodeLabel node))
        <*> pure (compileElementKind (V.nodeStructure node))
        <*> pure (compileContent (V.nodeContent node))
        <*> compileStyle solution (V.nodeStyle node)
        <*> pure (compileStyleBindings (V.nodeStyle node))

compileElementKind :: V.NodeStructure -> IR.VisualElementKind
compileElementKind structure =
  case structure of
    V.LeafNode -> IR.ElementTrace
    V.CompoundNode _ children ->
      IR.ElementGroup
        (map (IR.VisualId . V.viewIdInt . V.nodeChildId) children)

visualId :: V.ViewRef tag -> IR.VisualId
visualId = IR.VisualId . V.viewRefInt

compileContent :: V.ContentMode -> Maybe String
compileContent content =
  case content of
    V.ContentEmpty      -> Nothing
    V.ContentText value -> Just value

compileStyle :: S.Solution -> VS.NodeStyle -> Either String IR.VisualStyle
compileStyle solution style = do
  let VP.Bounds top left width height = VS.nodeStyleBounds style
  IR.VisualStyle
    <$> solved "top" top
    <*> solved "left" left
    <*> solved "width" width
    <*> solved "height" height
    <*> resolvedScalar @VS.Opacity
    <*> resolvedScalar @VS.ZIndex
    <*> resolvedScalar @VS.Padding
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
    solved label expression =
      case S.evalExpr solution expression of
        Just value -> Right (roundLayout value)
        Nothing ->
          Left
            ("could not materialize "
               ++ label
               ++ "; the expression references an unsolved variable")
    resolved :: forall field.
         VS.StyleField field
      => Either String (Maybe (VS.ResolvedStyleValue field))
    resolved = VS.materializeStyleField @field solution style
    resolvedScalar :: forall field.
         ( VS.StyleField field
         , VS.ResolvedStyleValue field ~ Double
         )
      => Either String (Maybe Double)
    resolvedScalar = fmap (fmap roundLayout) (resolved @field)
    resolvedColor :: forall field.
         ( VS.StyleField field
         , VS.ResolvedStyleValue field ~ VP.ConcreteHsl
         )
      => Either String (Maybe IR.HslColor)
    resolvedColor =
      fmap (fmap compileColor) (resolved @field)

compileColor :: VP.ConcreteHsl -> IR.HslColor
compileColor color =
  IR.HslColor
    { IR.hslHue = roundLayout (VP.hue color)
    , IR.hslSaturation = roundLayout (VP.saturation color)
    , IR.hslLightness = roundLayout (VP.lightness color)
    }

compileStyleBindings :: VS.NodeStyle -> [IR.StyleVariableBinding]
compileStyleBindings =
  map
    (\(field, variables) ->
       IR.StyleVariableBinding
         { IR.bindingField = field
         , IR.bindingVariables = map IR.CspVariableId variables
         })
    . VS.styleVariableBindings

type ElementLookup = Map IR.VisualId IR.VisualElement

elementLookup :: [IR.VisualElement] -> ElementLookup
elementLookup elements =
  Map.fromList
    [ (IR.elementId element, element)
    | element <- elements
    ]

data SceneState = SceneState
  { sceneLineage  :: Map IR.VisualId IR.RenderInstanceId
  , sceneInstances :: Map IR.RenderInstanceId IR.VisualInstance
  }

emptySceneState :: SceneState
emptySceneState = SceneState Map.empty Map.empty

type CompileM = StateT SceneState (Either String)

compileFrames ::
     ElementLookup
  -> [[V.RenderIntent]]
  -> CompileM [[IR.VisualInstance]]
compileFrames lookup' = traverse (compileFrame lookup')

compileFrame :: ElementLookup -> [V.RenderIntent] -> CompileM [IR.VisualInstance]
compileFrame lookup' intents = do
  modify clearOrigins
  mapM_ (applyIntent lookup') intents
  gets (Map.elems . sceneInstances)

clearOrigins :: SceneState -> SceneState
clearOrigins scene =
  scene
    { sceneInstances =
        Map.map
          (\instance' -> instance' {IR.instanceOriginElementId = Nothing})
          (sceneInstances scene)
    }

applyIntent :: ElementLookup -> V.RenderIntent -> CompileM ()
applyIntent lookup' intent =
  case intent of
    V.RenderFresh ref -> mapM_ createElement (lookupElement lookup' ref)
    V.RenderRemove ref -> mapM_ destroyElement (lookupElement lookup' ref)
    V.RenderContinue source target -> continueRef lookup' source target
    V.RenderFork source target -> forkRef lookup' source target

continueRef ::
     ElementLookup -> V.ViewRef source -> V.ViewRef target -> CompileM ()
continueRef lookup' sourceRef targetRef =
  case (lookupElement lookup' sourceRef, lookupElement lookup' targetRef) of
    (Nothing, Nothing) -> pure ()
    (Nothing, Just target) -> createElement target
    (Just source, Nothing) -> destroyElement source
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
               (IR.VisualInstance instanceId (IR.elementId target) Nothing)
               (sceneInstances scene)
         })

forkRef :: ElementLookup -> V.ViewRef source -> V.ViewRef target -> CompileM ()
forkRef lookup' sourceRef targetRef =
  case lookupElement lookup' targetRef of
    Nothing -> pure ()
    Just target -> do
      origin <-
        case lookupElement lookup' sourceRef of
          Nothing -> pure Nothing
          Just source -> do
            _ <- requireLineage source
            pure (Just (IR.elementId source))
      createElementWithOrigin origin target

createElement :: IR.VisualElement -> CompileM ()
createElement = createElementWithOrigin Nothing

createElementWithOrigin :: Maybe IR.VisualId -> IR.VisualElement -> CompileM ()
createElementWithOrigin origin element =
  let elementId' = IR.elementId element
      instanceId = instanceIdFor elementId'
   in modify
        (\scene ->
           scene
             { sceneLineage =
                 Map.insert elementId' instanceId (sceneLineage scene)
             , sceneInstances =
                 Map.insert
                   instanceId
                   (IR.VisualInstance instanceId elementId' origin)
                   (sceneInstances scene)
             })

destroyElement :: IR.VisualElement -> CompileM ()
destroyElement element = do
  instanceId <- requireLineage element
  modify
    (\scene ->
       scene
         { sceneLineage =
             Map.delete (IR.elementId element) (sceneLineage scene)
         , sceneInstances = Map.delete instanceId (sceneInstances scene)
         })

requireLineage :: IR.VisualElement -> CompileM IR.RenderInstanceId
requireLineage element = do
  lineage <- gets sceneLineage
  case Map.lookup (IR.elementId element) lineage of
    Just instanceId -> pure instanceId
    Nothing ->
      lift
        (Left ("no render lineage for " ++ show (IR.elementId element)))

lookupElement ::
     ElementLookup -> V.ViewRef tag -> Maybe IR.VisualElement
lookupElement lookup' ref = Map.lookup (visualId ref) lookup'

instanceIdFor :: IR.VisualId -> IR.RenderInstanceId
instanceIdFor elementId' =
  case elementId' of
    IR.VisualId value -> IR.RenderInstanceId value

roundLayout :: Double -> Double
roundLayout value =
  let rounded = fromIntegral (round (value * 1000) :: Integer) / 1000
   in if abs rounded < 0.0005 then 0 else rounded
