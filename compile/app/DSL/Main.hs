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
import           Prelude.Linear

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

layoutCell :: LayoutExpr
layoutCell = global "linear-search.stage.cell"

layoutGap :: LayoutExpr
layoutGap = global "linear-search.stage.gap"

layoutTargetLeft :: LayoutExpr
layoutTargetLeft = global "linear-search.stage.target-left"

layoutTargetTop :: LayoutExpr
layoutTargetTop = global "linear-search.stage.target-top"

layoutRowLeft :: LayoutExpr
layoutRowLeft = global "linear-search.stage.row-left"

layoutRowTop :: LayoutExpr
layoutRowTop = global "linear-search.stage.row-top"

layoutStep :: LayoutExpr
layoutStep = layoutCell @+@ layoutGap

layoutProbeTop :: LayoutExpr
layoutProbeTop = global "linear-search.stage.probe-top"

targetProbeLeft :: LayoutExpr
targetProbeLeft = global "linear-search.stage.target-probe-left"

elementProbeLeft :: LayoutExpr
elementProbeLeft = global "linear-search.stage.element-probe-left"

layoutMatchLeft :: LayoutExpr
layoutMatchLeft = global "linear-search.stage.match-left"

layoutMatchTop :: LayoutExpr
layoutMatchTop = global "linear-search.stage.match-top"

layoutOuterLeft :: LayoutExpr
layoutOuterLeft = num 40

layoutOuterTop :: LayoutExpr
layoutOuterTop = num 32

layoutOuterRight :: LayoutExpr
layoutOuterRight = num 760

layoutOuterBottom :: LayoutExpr
layoutOuterBottom = num 560

targetWidth :: LayoutExpr
targetWidth = (layoutCell @*@ (num 2.1 :: LayoutExpr)) @+@ layoutGap

targetHeight :: LayoutExpr
targetHeight = layoutCell @+@ (layoutGap @*@ (num 0.8 :: LayoutExpr))

probeSize :: LayoutExpr
probeSize = layoutCell @*@ (num 1.08 :: LayoutExpr)

probeHeight :: LayoutExpr
probeHeight = probeSize

targetFontSize :: LayoutExpr
targetFontSize = layoutCell @*@ (num 0.62 :: LayoutExpr)

listFontSize :: LayoutExpr
listFontSize = layoutCell @*@ (num 0.5 :: LayoutExpr)

probeFontSize :: LayoutExpr
probeFontSize = layoutCell @*@ (num 0.56 :: LayoutExpr)

targetRadius :: LayoutExpr
targetRadius = layoutCell @*@ (num 0.24 :: LayoutExpr)

listRadius :: LayoutExpr
listRadius = layoutCell @*@ (num 0.18 :: LayoutExpr)

probeRadius :: LayoutExpr
probeRadius = layoutCell @*@ (num 0.22 :: LayoutExpr)

decisionRadius :: LayoutExpr
decisionRadius = layoutCell @*@ (num 0.26 :: LayoutExpr)

layoutStrokeWidth :: LayoutExpr
layoutStrokeWidth = layoutCell @*@ (num 0.035 :: LayoutExpr)

emphasisStrokeWidth :: LayoutExpr
emphasisStrokeWidth = layoutCell @*@ (num 0.05 :: LayoutExpr)

targetHue :: HueExpr
targetHue = global "linear-search.palette.target-hue"

listHue :: HueExpr
listHue = global "linear-search.palette.list-hue"

probeHue :: HueExpr
probeHue = global "linear-search.palette.probe-hue"

decisionHue :: HueExpr
decisionHue = global "linear-search.palette.decision-hue"

matchWidth :: LayoutExpr
matchWidth = (probeSize @*@ (num 2 :: LayoutExpr)) @+@ layoutGap

matchHeight :: LayoutExpr
matchHeight = layoutCell @*@ (num 0.72 :: LayoutExpr)

matchFontSize :: LayoutExpr
matchFontSize = layoutCell @*@ (num 0.34 :: LayoutExpr)

listValueCount :: LayoutExpr
listValueCount = num 5

listGapCount :: LayoutExpr
listGapCount = num 4

listSpan :: LayoutExpr
listSpan = (listValueCount @*@ layoutCell) @+@ (listGapCount @*@ layoutGap)

constrainScale :: ViewLayout ()
constrainScale = do
  constrain ((num 72 :: LayoutExpr) @<=@ layoutCell)
  constrain (layoutCell @<=@ (num 86 :: LayoutExpr))
  constrain ((num 26 :: LayoutExpr) @<=@ layoutGap)
  constrain (layoutGap @<=@ (num 44 :: LayoutExpr))

constrainTargetFlow :: ViewLayout ()
constrainTargetFlow = do
  constrainScale
  constrain (layoutOuterLeft @<=@ layoutTargetLeft)
  constrain (layoutTargetLeft @<=@ (num 128 :: LayoutExpr))
  constrain (layoutOuterTop @<=@ layoutTargetTop)
  constrain (layoutTargetTop @<=@ (num 86 :: LayoutExpr))
  constrain (layoutTargetLeft @+@ targetWidth @<=@ (num 380 :: LayoutExpr))
  constrain (layoutTargetTop @+@ targetHeight @<=@ (num 188 :: LayoutExpr))
  constrain ((num 64 :: LayoutExpr) @<=@ layoutRowLeft)
  constrain (layoutRowLeft @<=@ (num 112 :: LayoutExpr))
  constrain ((num 430 :: LayoutExpr) @<=@ layoutRowTop)
  constrain (layoutRowTop @<=@ (num 500 :: LayoutExpr))
  constrain (layoutRowLeft @+@ listSpan @<=@ layoutOuterRight)
  constrain (layoutRowTop @+@ layoutCell @<=@ layoutOuterBottom)

constrainProbeFlow :: ViewLayout ()
constrainProbeFlow = do
  constrainTargetFlow
  constrain ((num 210 :: LayoutExpr) @<=@ targetProbeLeft)
  constrain (targetProbeLeft @<=@ (num 300 :: LayoutExpr))
  constrain ((num 520 :: LayoutExpr) @<=@ elementProbeLeft)
  constrain (elementProbeLeft @<=@ (num 640 :: LayoutExpr))
  constrain ((num 205 :: LayoutExpr) @<=@ layoutProbeTop)
  constrain (layoutProbeTop @<=@ (num 270 :: LayoutExpr))
  constrain (layoutTargetTop @+@ targetHeight @+@ layoutGap @<=@ layoutProbeTop)
  constrain (layoutProbeTop @+@ probeHeight @+@ layoutGap @<=@ layoutRowTop)
  constrain
    (targetProbeLeft
       @+@ probeSize
       @+@ (layoutGap @*@ (num 2 :: LayoutExpr))
       @<=@ elementProbeLeft)

constrainMatchFlow :: ViewLayout ()
constrainMatchFlow = do
  constrainProbeFlow
  constrain ((num 330 :: LayoutExpr) @<=@ layoutMatchLeft)
  constrain (layoutMatchLeft @<=@ (num 415 :: LayoutExpr))
  constrain
    (layoutProbeTop
       @+@ probeHeight
       @+@ (layoutGap @*@ (num 0.7 :: LayoutExpr))
       @<=@ layoutMatchTop)
  constrain
    (layoutMatchTop
       @+@ matchHeight
       @+@ (layoutGap @*@ (num 0.7 :: LayoutExpr))
       @<=@ layoutRowTop)
  constrain (targetProbeLeft @<=@ layoutMatchLeft)
  constrain (layoutMatchLeft @+@ matchWidth @<=@ elementProbeLeft @+@ probeSize)

listValueLeft :: Int -> LayoutExpr
listValueLeft index =
  layoutRowLeft @+@ ((num (fromIntegral index) :: LayoutExpr) @*@ layoutStep)

valueText :: NodeRecipe ()
valueText = do
  fontFamily "Inter, ui-sans-serif, system-ui, sans-serif"
  bold
  centerText
  noWrap

targetChrome :: NodeRecipe ()
targetChrome = do
  fill (Hsl targetHue (num 0.64) (num 0.84))
  stroke (Hsl targetHue (num 0.76) (num 0.36))
  strokeWidth emphasisStrokeWidth
  radius targetRadius
  fontSize targetFontSize
  cssClass "trace-target-card"

listChrome :: NodeRecipe ()
listChrome = do
  fill (Hsl listHue (num 0.34) (num 0.92))
  stroke (Hsl listHue (num 0.58) (num 0.42))
  strokeWidth layoutStrokeWidth
  radius listRadius
  fontSize listFontSize
  cssClass "trace-list-chip"

probeChrome :: NodeRecipe ()
probeChrome = do
  fill (Hsl probeHue (num 0.5) (num 0.88))
  stroke (Hsl probeHue (num 0.78) (num 0.34))
  strokeWidth layoutStrokeWidth
  zIndex (num 3)
  radius probeRadius
  fontSize probeFontSize
  cssClass "trace-probe-chip"

matchChrome :: NodeRecipe ()
matchChrome = do
  fill (Hsl decisionHue (num 0.6) (num 0.86))
  stroke (Hsl decisionHue (num 0.82) (num 0.32))
  strokeWidth emphasisStrokeWidth
  zIndex (num 4)
  radius decisionRadius
  fontSize matchFontSize
  cssClass "trace-decision-pill"

targetValueDefinition :: NodeDefinition Value
targetValueDefinition =
  node $ do
    valueText
    targetChrome
    placed layoutTargetLeft layoutTargetTop targetWidth targetHeight
    require constrainTargetFlow

listValueDefinition :: Int -> NodeDefinition Value
listValueDefinition index =
  node $ do
    valueText
    listChrome
    position (Vec2 (listValueLeft index) layoutRowTop)
    size (Vec2 layoutCell layoutCell)
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
    placed targetProbeLeft layoutProbeTop probeSize probeHeight
    require constrainProbeFlow

elementProbeViewDefinition :: NodeDefinition Value
elementProbeViewDefinition =
  node $ do
    valueText
    probeChrome
    placed elementProbeLeft layoutProbeTop probeSize probeHeight
    require constrainProbeFlow

matchViewDefinition :: NodeDefinition Match
matchViewDefinition =
  node $ do
    valueText
    matchChrome
    placed layoutMatchLeft layoutMatchTop matchWidth matchHeight
    require constrainMatchFlow
