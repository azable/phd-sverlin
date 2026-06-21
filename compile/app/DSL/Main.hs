{-# LANGUAGE ConstraintKinds         #-}
{-# LANGUAGE DataKinds               #-}
{-# LANGUAGE FlexibleContexts        #-}
{-# LANGUAGE FlexibleInstances       #-}
{-# LANGUAGE GADTs                   #-}
{-# LANGUAGE LinearTypes             #-}
{-# LANGUAGE NoImplicitPrelude       #-}
{-# LANGUAGE RebindableSyntax        #-}
{-# LANGUAGE TypeFamilies            #-}
{-# LANGUAGE UndecidableInstances    #-}
{-# LANGUAGE UndecidableSuperClasses #-}

module DSL.Main
  ( example
  , run
  ) where

import           Control.Functor.Linear   hiding (ask, (<$>), (<*>))
import           LinearTrace.Choreography
import           Prelude.Linear           hiding ((*), (+), (-), (/))

--------------------------------------------------------------------------------
-- Payload tags
--------------------------------------------------------------------------------
data Value

type instance Payload Value = LInt Value

instance Traceable Value

data Match

type instance Payload Match = LBool Match

instance Traceable Match where
  payloadView _ payload =
    case payload of
      LBool matched
        {- HLINT ignore "Use if" -}
       ->
        case matched of
          True  -> PayloadView "Decision" "MATCH"
          False -> PayloadView "Decision" "NO MATCH"

sameValue :: Payload Value %1 -> Payload Value %1 -> Payload Match
sameValue lhsPayload rhsPayload =
  case lhsPayload of
    LInt lhs ->
      case rhsPayload of
        LInt rhs -> LBool (lhs == rhs)

--------------------------------------------------------------------------------
-- Editable input boundary
--------------------------------------------------------------------------------
data SearchInput where
  SearchInput :: Payload Value %1 -> InputValues %1 -> SearchInput

data InputValues where
  NoInputValues :: InputValues
  MoreInputValue :: Payload Value %1 -> InputValues %1 -> InputValues

data ExampleSpec where
  ExampleSpec :: Int -> ExampleValues -> ExampleSpec

data ExampleValues where
  NoExampleValues :: ExampleValues
  MoreExampleValue :: Int -> ExampleValues -> ExampleValues

exampleSpec :: ExampleSpec
exampleSpec =
  ExampleSpec
    7
    (MoreExampleValue
       4
       (MoreExampleValue
          9
          (MoreExampleValue
             2
             (MoreExampleValue 7 (MoreExampleValue 1 NoExampleValues)))))

example :: Program ()
example = linearSearch (searchInput exampleSpec)

searchInput :: ExampleSpec -> SearchInput
searchInput spec =
  case spec of
    ExampleSpec target values -> SearchInput (LInt target) (inputValues values)

inputValues :: ExampleValues -> InputValues
inputValues values =
  case values of
    NoExampleValues -> NoInputValues
    MoreExampleValue value rest ->
      MoreInputValue (LInt value) (inputValues rest)

-- Search program
--------------------------------------------------------------------------------
data Elements where
  NoElements :: Elements
  MoreElement :: BlockHandle Value %1 -> Elements %1 -> Elements

data Comparison where
  IsMatch :: BlockHandle Value %1 -> BlockHandle Value %1 -> Comparison
  IsNotMatch :: BlockHandle Value %1 -> BlockHandle Value %1 -> Comparison

data SearchState where
  SearchState :: BlockHandle Value %1 -> Elements %1 -> SearchState

data PrepareComparisonOutput where
  PrepareComparisonOutput
    :: BlockHandle Value
       %1 -> BlockHandle Value
       %1 -> BlockHandle Value
       %1 -> BlockHandle Value
       %1 -> PrepareComparisonOutput

data PrepareComparisonObligations where
  PrepareComparisonObligations
    :: Obligation (Copy Value)
       %1 -> Obligation (Copy Value)
       %1 -> PrepareComparisonObligations

data CompareValuesObligations where
  CompareValuesObligations
    :: Obligation (Use Value)
       %1 -> Obligation (Use Value)
       %1 -> Obligation (Compute Match)
       %1 -> CompareValuesObligations

data DestroyPairObligations where
  DestroyPairObligations
    :: Obligation (Destroy Value)
       %1 -> Obligation (Destroy Value)
       %1 -> DestroyPairObligations

run :: Program () -> VisualTraceGraph
run = runProgram

linearSearch :: SearchInput %1 -> Program ()
linearSearch (SearchInput targetPayload valuePayloads) =
  manifest $ do
    target <-
      phase "Create target" (createValue targetPayload) renderCreatedTarget
    elements <- createElements valuePayloads
    loop (SearchState target elements) searchIteration

createElements :: InputValues %1 -> Program Elements
createElements = createElementsFrom 0

createElementsFrom :: Int -> InputValues %1 -> Program Elements
createElementsFrom index inputs =
  case inputs of
    NoInputValues -> return NoElements
    MoreInputValue payload rest -> do
      element <-
        phase
          "Create element"
          (createValue payload)
          (renderCreatedElement index)
      elements <- createElementsFrom (index + 1) rest
      return (MoreElement element elements)

searchIteration :: SearchState %1 -> Program (LoopResult SearchState ())
searchIteration searchState =
  case searchState of
    SearchState target elements ->
      case elements of
        NoElements -> do
          phase "Search exhausted" (destroyValue target) renderRemove
          return (Finish ())
        MoreElement element rest -> do
          comparison <- compareElement target element
          case comparison of
            IsMatch targetAfter elementAfter -> do
              finishFound targetAfter elementAfter
              discardRemaining rest
              return (Finish ())
            IsNotMatch targetAfter elementAfter -> do
              discardChecked elementAfter
              return (Continue (SearchState targetAfter rest))

compareElement ::
     BlockHandle Value %1 -> BlockHandle Value %1 -> Program Comparison
compareElement target element = do
  PrepareComparisonOutput targetAfter elementAfter targetProbe elementProbe <-
    phase
      "Prepare comparison"
      (prepareComparison target element)
      renderPrepareComparison
  match <-
    phase
      "Compare target and element"
      (compareValues targetProbe elementProbe)
      renderCompareValues
  branchOn
    (decideMatch match)
    (BranchCase "Found target" renderRemove)
    (BranchCase "Not this element" renderRejectedDecision)
    (comparisonBranch targetAfter elementAfter)

comparisonBranch ::
     BlockHandle Value
     %1 -> BlockHandle Value
     %1 -> BranchDecision
     %1 -> Program Comparison
comparisonBranch targetAfter elementAfter branch =
  case branch of
    BranchTrue  -> return (IsMatch targetAfter elementAfter)
    BranchFalse -> return (IsNotMatch targetAfter elementAfter)

discardChecked :: BlockHandle Value %1 -> Program ()
discardChecked element = do
  phase "Discard checked element" (destroyValue element) renderRemove

finishFound :: BlockHandle Value %1 -> BlockHandle Value %1 -> Program ()
finishFound target element = do
  phase "Finish found target" (destroyPair target element) renderDestroyPair

discardRemaining :: Elements %1 -> Program ()
discardRemaining elements =
  case elements of
    NoElements -> return ()
    MoreElement element rest -> do
      phase "Discard remaining element" (destroyValue element) renderRemove
      discardRemaining rest

createValue ::
     Payload Value
     %1 -> Fragment (StepResult (BlockHandle Value) (Obligation (Create Value)))
createValue payload = do
  Created block obligation <- createAs payload
  return (StepResult block obligation)

destroyValue ::
     BlockHandle Value
     %1 -> Fragment (StepResult () (Obligation (Destroy Value)))
destroyValue block = do
  Destroyed obligation <- destroyAs block
  return (StepResult () obligation)

destroyPair ::
     BlockHandle Value
     %1 -> BlockHandle Value
     %1 -> Fragment (StepResult () DestroyPairObligations)
destroyPair target element = do
  Destroyed targetVisual <- destroyAs target
  Destroyed elementVisual <- destroyAs element
  return (StepResult () (DestroyPairObligations targetVisual elementVisual))

prepareComparison ::
     BlockHandle Value
     %1 -> BlockHandle Value
     %1 -> Fragment
       (StepResult PrepareComparisonOutput PrepareComparisonObligations)
prepareComparison target element = do
  Copied targetAfter targetProbe targetCopy <- copyAs target
  Copied elementAfter elementProbe elementCopy <- copyAs element
  return
    (StepResult
       (PrepareComparisonOutput
          targetAfter
          elementAfter
          targetProbe
          elementProbe)
       (PrepareComparisonObligations targetCopy elementCopy))

compareValues ::
     BlockHandle Value
     %1 -> BlockHandle Value
     %1 -> Fragment (StepResult (BlockHandle Match) CompareValuesObligations)
compareValues targetProbe elementProbe = do
  Used targetPayload targetVisual <- useAs targetProbe
  Used elementPayload elementVisual <- useAs elementProbe
  Computed match matchVisual <-
    computeAs (sameValue <$> targetPayload <*> elementPayload)
  return
    (StepResult
       match
       (CompareValuesObligations targetVisual elementVisual matchVisual))

decideMatch :: BlockHandle Match %1 -> Fragment (Decided Match)
decideMatch = decideAs (\(LBool answer) -> answer)

renderCreatedTarget :: Obligation (Create Value) %1 -> RenderRecipe ()
renderCreatedTarget obligation = do
  renderedValue <- renderFresh targetValueDefinition obligation
  renderComplete renderedValue

renderCreatedElement :: Int -> Obligation (Create Value) %1 -> RenderRecipe ()
renderCreatedElement index obligation = do
  renderedElement <- renderFresh (listValueDefinition index) obligation
  renderCheckpoint
  renderComplete renderedElement

renderPrepareComparison :: PrepareComparisonObligations %1 -> RenderRecipe ()
renderPrepareComparison obligations =
  case obligations of
    PrepareComparisonObligations targetCopy elementCopy -> do
      (target1, renderedTargetProbe) <-
        renderForkCopy targetProbeViewDefinition targetCopy
      (element1, renderedElementProbe) <-
        renderForkCopy elementProbeViewDefinition elementCopy
      renderComplete target1
      renderComplete element1
      renderComplete renderedTargetProbe
      renderComplete renderedElementProbe
      renderCheckpoint

renderCompareValues :: CompareValuesObligations %1 -> RenderRecipe ()
renderCompareValues obligations =
  case obligations of
    CompareValuesObligations targetVisual elementVisual matchVisual -> do
      renderedMatch <- renderFresh matchViewDefinition matchVisual
      renderCheckpoint
      renderRemove targetVisual
      renderRemove elementVisual
      renderComplete renderedMatch

renderRejectedDecision :: Obligation (Decide Match) %1 -> RenderRecipe ()
renderRejectedDecision obligation = do
  renderRemove obligation
  renderCheckpoint

renderDestroyPair :: DestroyPairObligations %1 -> RenderRecipe ()
renderDestroyPair obligations =
  case obligations of
    DestroyPairObligations targetVisual elementVisual -> do
      renderRemove targetVisual
      renderRemove elementVisual

cell :: Span
cell = globalSpan "cell"

gap :: Span
gap = globalSpan "gap"

targetX :: Coord
targetX = globalCoord "target.x"

targetY :: Coord
targetY = globalCoord "target.y"

rowX :: Coord
rowX = globalCoord "row.x"

rowY :: Coord
rowY = globalCoord "row.y"

stride :: Span
stride = cell |+| gap

probeY :: Coord
probeY = globalCoord "probe.y"

targetProbeX :: Coord
targetProbeX = globalCoord "probe.target.x"

elementProbeX :: Coord
elementProbeX = globalCoord "probe.element.x"

matchX :: Coord
matchX = globalCoord "match.x"

matchY :: Coord
matchY = globalCoord "match.y"

targetHue :: HueExpr
targetHue = global "target.hue"

listHue :: HueExpr
listHue = global "list.hue"

probeHue :: HueExpr
probeHue = global "probe.hue"

matchHue :: HueExpr
matchHue = global "match.hue"

cellBy :: Double -> Span
cellBy scale = cell * num scale

tone :: HueExpr -> Double -> Double -> HslExpr
tone hueExpr saturation lightness = Hsl hueExpr (num saturation) (num lightness)

targetWidth :: Span
targetWidth = cellBy 2.1 |+| gap

targetHeight :: Span
targetHeight = cell |+| gap * num 0.8

probeSize :: Span
probeSize = cellBy 1.08

matchWidth :: Span
matchWidth = probeSize * num 2 |+| gap

matchHeight :: Span
matchHeight = cellBy 0.72

listSpan :: Span
listSpan = num 5 * cell |+| num 4 * gap

matchGap :: Span
matchGap = gap * num 0.7

constrainScale :: ViewLayout ()
constrainScale = do
  constrain (by 72 <|> cell <|> by 86)
  constrain (by 26 <|> gap <|> by 44)

constrainTargetFlow :: ViewLayout ()
constrainTargetFlow = do
  constrainScale
  constrain (at 40 <|> targetX <|> at 128)
  constrain (at 32 <|> targetY <|> at 86)
  constrain (targetX <| targetWidth |> num 180)
  constrain (targetY <| targetHeight |> num 188)
  constrain (at 64 <|> rowX <|> at 112)
  constrain (at 430 <|> rowY <|> at 500)
  constrain (rowX <| listSpan |> num 760)
  constrain (rowY <| cell |> num 560)

constrainProbeFlow :: ViewLayout ()
constrainProbeFlow = do
  constrainTargetFlow
  constrain (at 210 <|> targetProbeX <|> at 300)
  constrain (at 520 <|> elementProbeX <|> at 640)
  constrain (at 205 <|> probeY <|> at 270)
  constrain (targetY =| targetHeight |+| gap |> probeY)
  constrain (probeY =| probeSize |+| gap |> rowY)
  constrain (targetProbeX =| probeSize |+| gap * num 2 |> elementProbeX)

constrainMatchFlow :: ViewLayout ()
constrainMatchFlow = do
  constrainProbeFlow
  constrain (at 330 <|> matchX <|> at 415)
  constrain (probeY =| probeSize |+| matchGap |> matchY)
  constrain (matchY =| matchHeight |+| matchGap |> rowY)
  constrain (targetProbeX <|> matchX)
  constrain (matchX <| matchWidth |> elementProbeX + probeSize)

listValueLeft :: Int -> Coord
listValueLeft index = rowX + num (fromIntegral index) * stride

valueText :: NodeRecipe ()
valueText = do
  fontFamily "Inter, ui-sans-serif, system-ui, sans-serif"
  bold
  centerText
  noWrap

targetChrome :: NodeRecipe ()
targetChrome = do
  fill (tone targetHue 0.64 0.84)
  stroke (tone targetHue 0.76 0.36)
  strokeWidth (cellBy 0.05)
  radius (cellBy 0.24)
  fontSize (cellBy 0.62)

listChrome :: NodeRecipe ()
listChrome = do
  fill (tone listHue 0.34 0.92)
  stroke (tone listHue 0.58 0.42)
  strokeWidth (cellBy 0.035)
  radius (cellBy 0.18)
  fontSize (cellBy 0.5)

probeChrome :: NodeRecipe ()
probeChrome = do
  fill (tone probeHue 0.5 0.88)
  stroke (tone probeHue 0.78 0.34)
  strokeWidth (cellBy 0.035)
  zIndex (num 3)
  radius (cellBy 0.22)
  fontSize (cellBy 0.56)

matchChrome :: NodeRecipe ()
matchChrome = do
  fill (tone matchHue 0.6 0.86)
  stroke (tone matchHue 0.82 0.32)
  strokeWidth (cellBy 0.05)
  zIndex (num 4)
  radius (cellBy 0.26)
  fontSize (cellBy 0.34)

targetValueDefinition :: NodeDefinition Value
targetValueDefinition =
  node $ do
    valueText
    targetChrome
    placed targetX targetY targetWidth targetHeight
    require constrainTargetFlow

listValueDefinition :: Int -> NodeDefinition Value
listValueDefinition index =
  node $ do
    valueText
    listChrome
    position (Vec2 (listValueLeft index) rowY)
    size (Vec2 cell cell)
    requireListFlow index

requireListFlow :: Int -> NodeRecipe ()
requireListFlow index =
  case index of
    0 -> require constrainTargetFlow
    _ -> return ()

targetProbeViewDefinition :: NodeDefinition Value
targetProbeViewDefinition =
  node $ do
    valueText
    probeChrome
    placed targetProbeX probeY probeSize probeSize
    require constrainProbeFlow

elementProbeViewDefinition :: NodeDefinition Value
elementProbeViewDefinition =
  node $ do
    valueText
    probeChrome
    placed elementProbeX probeY probeSize probeSize
    require constrainProbeFlow

matchViewDefinition :: NodeDefinition Match
matchViewDefinition =
  node $ do
    valueText
    matchChrome
    placed matchX matchY matchWidth matchHeight
    require constrainMatchFlow
