{-# LANGUAGE GADTs             #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Compile a solved view graph into the canonical visualization IR.
module LinearTrace.Compile
  ( Visualization
  , compileSolved
  , compileSolvedWithViewport
  ) where

import           Control.Monad.State.Strict
import           Data.List                         (find, nub, sortOn)
import           Data.Map.Strict                   (Map)
import qualified Data.Map.Strict                   as Map
import           Data.Maybe                        (fromMaybe)
import qualified LinearTrace.View                  as V
import qualified LinearTrace.View.Style            as VS
import qualified LinearTrace.Visualization.IR      as IR
import           Prelude
import qualified Solver                            as S

type Visualization = IR.VisualizationPackage

defaultCompiledWidth :: Double
defaultCompiledWidth = 800

defaultCompiledHeight :: Double
defaultCompiledHeight = 600

compileSolved :: S.Solution -> V.ViewGraph -> Either String Visualization
compileSolved = compileSolvedWithViewport defaultCompiledWidth defaultCompiledHeight

compileSolvedWithViewport ::
     Double
  -> Double
  -> S.Solution
  -> V.ViewGraph
  -> Either String Visualization
compileSolvedWithViewport viewportWidth viewportHeight solution graph = do
  elements <- compileElements solution graph
  frames <-
    evalStateT
      (compileFrames (elementLookup elements) (V.viewRenderFrames graph))
      emptySceneState
  pure
    IR.VisualizationPackage
      { IR.packageSchemaVersion = 1
      , IR.packageSeed = solutionSeedInt solution
      , IR.packageSource =
          IR.SourceMetadata
            { IR.sourcePath = "compile/app/DSL/Main.hs"
            , IR.sourceCompilerVersion = "0.1.0.0"
            }
      , IR.packageCanvas =
          IR.CanvasSpec
            { IR.canvasWidth = roundLayout viewportWidth
            , IR.canvasHeight = roundLayout viewportHeight
            , IR.canvasBackground = Nothing
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

--------------------------------------------------------------------------------
-- Element registry
--------------------------------------------------------------------------------

compileElements :: S.Solution -> V.ViewGraph -> Either String [IR.VisualElement]
compileElements solution graph =
  traverse (compileElement solution nodeKeys) (V.viewNodes graph)
  where
    nodeKeys =
      Map.fromList
        [ (V.viewRefInt (V.nodeRef node), V.nodeKey node)
        | V.ViewNode node <- V.viewNodes graph
        ]

compileElement ::
     S.Solution
  -> Map Int String
  -> V.ViewNode
  -> Either String IR.VisualElement
compileElement solution nodeKeys symbolic =
  case symbolic of
    V.ViewNode node -> do
      style <- compileStyle solution (V.nodeStyle node)
      pure
        IR.VisualElement
          { IR.elementId = visualIdFor (nodeId node) (V.nodeKey node)
          , IR.elementNodeId = nodeId node
          , IR.elementNodeKey = V.nodeKey node
          , IR.elementRole = V.viewLabelKind (V.nodeLabel node)
          , IR.elementKind = compileElementKind nodeKeys (V.nodeStructure node)
          , IR.elementContent = compileContent (V.nodeContent node)
          , IR.elementStyle = style
          , IR.elementVariables = compileStyleTrace (V.nodeStyle node)
          }

compileElementKind :: Map Int String -> V.NodeStructure -> IR.VisualElementKind
compileElementKind nodeKeys structure =
  case structure of
    V.LeafNode -> IR.ElementTrace
    V.CompoundNode _ children ->
      IR.ElementGroup
        [ visualIdFor childId (fromMaybe V.defaultNodeKey (Map.lookup childId nodeKeys))
        | child <- children
        , let childId = V.viewIdInt (V.nodeChildId child)
        ]

visualIdFor :: Int -> String -> IR.VisualId
visualIdFor nodeId' key = IR.VisualId ("node." ++ show nodeId' ++ "." ++ key)

nodeId :: V.Node tag -> Int
nodeId = V.viewRefInt . V.nodeRef

compileContent :: V.ContentMode -> Maybe String
compileContent content =
  case content of
    V.ContentEmpty      -> Nothing
    V.ContentText value -> Just value

compileStyle :: S.Solution -> VS.NodeStyle -> Either String IR.VisualStyle
compileStyle solution style = do
  let V.Bounds top left width height = VS.nodeStyleBounds style
  concreteFields <- traverse (VS.materializeAnyStyleField solution) (VS.nodeStyleFields style)
  IR.VisualStyle
    <$> solved "top" top
    <*> solved "left" left
    <*> solved "width" width
    <*> solved "height" height
    <*> pure (scalarField "opacity" concreteFields)
    <*> pure (scalarField "zIndex" concreteFields)
    <*> pure (scalarField "padding" concreteFields)
    <*> pure (scalarField "fontSize" concreteFields)
    <*> pure (scalarField "radius" concreteFields)
    <*> pure (scalarField "strokeWidth" concreteFields)
    <*> pure (scalarField "alpha" concreteFields)
    <*> pure (colorField "fill" concreteFields)
    <*> pure (colorField "stroke" concreteFields)
    <*> pure (tokenField "fontFamily" concreteFields)
    <*> pure (tokenField "fontWeight" concreteFields)
    <*> pure (tokenField "fontStyle" concreteFields)
    <*> pure (tokenField "textAlign" concreteFields)
    <*> pure (tokenField "borderStyle" concreteFields)
    <*> pure (tokenField "whiteSpace" concreteFields)
  where
    solved label expression =
      case S.evalExpr solution expression of
        Just value -> Right (roundLayout value)
        Nothing ->
          Left
            ("could not materialize "
               ++ label
               ++ "; the expression references an unsolved variable")

scalarField :: String -> [VS.ConcreteStyleField] -> Maybe Double
scalarField name fields =
  case concreteField name fields of
    Just (VS.ConcreteScalar value _) -> Just (roundLayout value)
    _                                -> Nothing

colorField :: String -> [VS.ConcreteStyleField] -> Maybe IR.HslColor
colorField name fields =
  case concreteField name fields of
    Just (VS.ConcreteColor color) ->
      Just
        IR.HslColor
          { IR.hslHue = roundLayout (V.hue color)
          , IR.hslSaturation = roundLayout (V.saturation color)
          , IR.hslLightness = roundLayout (V.lightness color)
          }
    _ -> Nothing

tokenField :: String -> [VS.ConcreteStyleField] -> Maybe String
tokenField name fields =
  case concreteField name fields of
    Just (VS.ConcreteToken value) -> Just value
    _                             -> Nothing

concreteField :: String -> [VS.ConcreteStyleField] -> Maybe VS.ConcreteStyleValue
concreteField name fields =
  VS.concreteStyleFieldValue
    <$> find ((== name) . VS.concreteStyleFieldName) fields

compileStyleTrace :: VS.NodeStyle -> IR.StyleVariableTrace
compileStyleTrace style =
  IR.StyleVariableTrace
    { IR.traceTop = fieldVariables "top"
    , IR.traceLeft = fieldVariables "left"
    , IR.traceWidth = fieldVariables "width"
    , IR.traceHeight = fieldVariables "height"
    , IR.traceOpacity = fieldVariables "opacity"
    , IR.traceZIndex = fieldVariables "zIndex"
    , IR.tracePadding = fieldVariables "padding"
    , IR.traceFontSize = fieldVariables "fontSize"
    , IR.traceRadius = fieldVariables "radius"
    , IR.traceStrokeWidth = fieldVariables "strokeWidth"
    , IR.traceAlpha = fieldVariables "alpha"
    , IR.traceFill = fieldVariables "fill"
    , IR.traceStroke = fieldVariables "stroke"
    , IR.traceFontFamily = fieldVariables "fontFamily"
    , IR.traceFontWeight = fieldVariables "fontWeight"
    , IR.traceFontStyle = fieldVariables "fontStyle"
    , IR.traceTextAlign = fieldVariables "textAlign"
    , IR.traceBorderStyle = fieldVariables "borderStyle"
    , IR.traceWhiteSpace = fieldVariables "whiteSpace"
    }
  where
    numericEntries =
      VS.mapNodeStyleExprLeaves
        (\name expr -> (rootField name, expressionVariableIds expr))
        style
    choiceEntries = concatMap choiceFieldEntry (VS.nodeStyleFields style)
    entries = numericEntries ++ choiceEntries
    fieldVariables name = nub (concat [ids | (field, ids) <- entries, field == name])

choiceFieldEntry :: VS.AnyStyleField -> [(String, [IR.CspVariableId])]
choiceFieldEntry field =
  case field of
    VS.AnyStyleField proxy value ->
      [ ( VS.styleFieldName proxy
        , map IR.CspVariableId (VS.styleValueChoiceNames proxy value))
      ]

rootField :: String -> String
rootField = takeWhile (/= '.')

expressionVariableIds :: S.Expr ty -> [IR.CspVariableId]
expressionVariableIds = map IR.CspVariableId . nub . expressionVariableNames . S.exprView

expressionVariableNames :: S.ExprView -> [String]
expressionVariableNames expression =
  case expression of
    S.ExprVar _ name   -> [name]
    S.ExprLit _        -> []
    S.ExprAdd lhs rhs  -> both lhs rhs
    S.ExprSub lhs rhs  -> both lhs rhs
    S.ExprMul lhs rhs  -> both lhs rhs
    S.ExprDiv lhs rhs  -> both lhs rhs
    S.ExprNeg inner    -> expressionVariableNames inner
    S.ExprAbs inner    -> expressionVariableNames inner
    S.ExprSignum inner -> expressionVariableNames inner
    S.ExprPow lhs rhs  -> both lhs rhs
    S.ExprMin lhs rhs  -> both lhs rhs
    S.ExprMax lhs rhs  -> both lhs rhs
  where
    both lhs rhs = expressionVariableNames lhs ++ expressionVariableNames rhs

--------------------------------------------------------------------------------
-- Complete scene snapshots
--------------------------------------------------------------------------------

type ElementLookup = Map Int [IR.VisualElement]
type ElementKey = (Int, String)

elementLookup :: [IR.VisualElement] -> ElementLookup
elementLookup =
  foldl
    (\lookup' element ->
       Map.insertWith (++) (IR.elementNodeId element) [element] lookup')
    Map.empty

data SceneState = SceneState
  { sceneLineage  :: Map ElementKey IR.RenderInstanceId
  , sceneInstances :: Map IR.RenderInstanceId IR.VisualInstance
  }

emptySceneState :: SceneState
emptySceneState = SceneState Map.empty Map.empty

type CompileM = StateT SceneState (Either String)

compileFrames :: ElementLookup -> [[V.RenderIntent]] -> CompileM [IR.VisualizationFrame]
compileFrames lookup' = traverse (compileFrame lookup')

compileFrame :: ElementLookup -> [V.RenderIntent] -> CompileM IR.VisualizationFrame
compileFrame lookup' intents = do
  modify clearOrigins
  mapM_ (applyIntent lookup') intents
  instances <- gets (sortInstances lookup' . Map.elems . sceneInstances)
  pure IR.VisualizationFrame {IR.frameDurationMs = 300, IR.frameInstances = instances}

clearOrigins :: SceneState -> SceneState
clearOrigins scene =
  scene
    { sceneInstances =
        Map.map (\instance' -> instance' {IR.instanceOrigin = Nothing}) (sceneInstances scene)
    }

applyIntent :: ElementLookup -> V.RenderIntent -> CompileM ()
applyIntent lookup' intent =
  case intent of
    V.RenderFresh ref              -> requireElements lookup' ref >>= mapM_ createElement
    V.RenderRemove ref             -> requireElements lookup' ref >>= mapM_ destroyElement
    V.RenderContinue source target -> continueRef lookup' source target
    V.RenderFork source target     -> forkRef lookup' source target

continueRef :: ElementLookup -> V.ViewRef source -> V.ViewRef target -> CompileM ()
continueRef lookup' sourceRef targetRef = do
  source <- requireElements lookup' sourceRef
  target <- requireElements lookup' targetRef
  mapM_ (continueTarget source) target
  mapM_ destroyElement (sourceOnly source target)

continueTarget :: [IR.VisualElement] -> IR.VisualElement -> CompileM ()
continueTarget source target =
  case matchingElement target source of
    Nothing -> createElement target
    Just previous -> do
      instanceId <- requireLineage previous
      modify
        (\scene ->
           scene
             { sceneLineage =
                 Map.insert
                   (elementKey target)
                   instanceId
                   (Map.delete (elementKey previous) (sceneLineage scene))
             , sceneInstances =
                 Map.insert
                   instanceId
                   (IR.VisualInstance instanceId (IR.elementId target) Nothing)
                   (sceneInstances scene)
             })

forkRef :: ElementLookup -> V.ViewRef source -> V.ViewRef target -> CompileM ()
forkRef lookup' sourceRef targetRef = do
  source <- requireElements lookup' sourceRef
  target <- requireElements lookup' targetRef
  mapM_ (forkElement source) target

forkElement :: [IR.VisualElement] -> IR.VisualElement -> CompileM ()
forkElement source target = do
  origin <-
    case matchingElement target source of
      Nothing -> pure Nothing
      Just previous -> do
        instanceId <- requireLineage previous
        pure (Just (IR.InstanceOrigin instanceId (IR.elementId previous)))
  createElementWithOrigin origin target

createElement :: IR.VisualElement -> CompileM ()
createElement = createElementWithOrigin Nothing

createElementWithOrigin :: Maybe IR.InstanceOrigin -> IR.VisualElement -> CompileM ()
createElementWithOrigin origin element = do
  let instanceId = instanceIdFor element
  modify
    (\scene ->
       scene
         { sceneLineage = Map.insert (elementKey element) instanceId (sceneLineage scene)
         , sceneInstances =
             Map.insert
               instanceId
               (IR.VisualInstance instanceId (IR.elementId element) origin)
               (sceneInstances scene)
         })

destroyElement :: IR.VisualElement -> CompileM ()
destroyElement element = do
  instanceId <- requireLineage element
  modify
    (\scene ->
       scene
         { sceneLineage = Map.delete (elementKey element) (sceneLineage scene)
         , sceneInstances = Map.delete instanceId (sceneInstances scene)
         })

requireLineage :: IR.VisualElement -> CompileM IR.RenderInstanceId
requireLineage element = do
  lineage <- gets sceneLineage
  case Map.lookup (elementKey element) lineage of
    Just instanceId -> pure instanceId
    Nothing -> lift (Left ("no render lineage for " ++ show (IR.elementId element)))

requireElements :: ElementLookup -> V.ViewRef tag -> CompileM [IR.VisualElement]
requireElements lookup' ref = pure (Map.findWithDefault [] (V.viewRefInt ref) lookup')

matchingElement :: IR.VisualElement -> [IR.VisualElement] -> Maybe IR.VisualElement
matchingElement target = find ((== IR.elementNodeKey target) . IR.elementNodeKey)

sourceOnly :: [IR.VisualElement] -> [IR.VisualElement] -> [IR.VisualElement]
sourceOnly source target =
  filter
    (\sourceElement ->
       IR.elementNodeKey sourceElement `notElem` map IR.elementNodeKey target)
    source

elementKey :: IR.VisualElement -> ElementKey
elementKey element = (IR.elementNodeId element, IR.elementNodeKey element)

instanceIdFor :: IR.VisualElement -> IR.RenderInstanceId
instanceIdFor element =
  IR.RenderInstanceId
    ("lineage." ++ show (IR.elementNodeId element) ++ "." ++ IR.elementNodeKey element)

sortInstances :: ElementLookup -> [IR.VisualInstance] -> [IR.VisualInstance]
sortInstances lookup' = sortOn sortKey
  where
    elementsById =
      Map.fromList
        [ (IR.elementId element, element)
        | elements <- Map.elems lookup'
        , element <- elements
        ]
    sortKey instance' =
      case Map.lookup (IR.instanceElementId instance') elementsById of
        Nothing -> (0, 0)
        Just element ->
          ( fromMaybe 0 (IR.visualZIndex (IR.elementStyle element))
          , IR.elementNodeId element
          )

roundLayout :: Double -> Double
roundLayout value =
  let rounded = fromIntegral (round (value * 1000) :: Integer) / 1000
   in if abs rounded < 0.0005 then 0 else rounded
