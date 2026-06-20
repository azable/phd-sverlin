{-# LANGUAGE BlockArguments          #-}
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

import           Control.Functor.Linear hiding (ask, (<$>), (<*>))
import           LinearTrace.Core       (Block, Computed (..), Copied (..),
                                         Created (..), Decided (..),
                                         Destroyed (..), ExplainTokens (..),
                                         LBool (..), LInt (..), Payload,
                                         PayloadView (..), Traceable (..),
                                         Used (..), buildGraph, compute, copy,
                                         create, decide, destroy, use, (<$>),
                                         (<*>))
import           LinearTrace.View       (BoxDefinition, BoxVisual,
                                         EmptyStyleDraft, ExplainedVisuals (..),
                                         FontWeight (..), Hsl (..), HueExpr,
                                         LayoutExpr, LayoutUse (..), LiveVisual,
                                         Style, TextAlign (..), ViewBuilder,
                                         VisualTraceBuilder, VisualTraceGraph,
                                         WhiteSpace (..), boxDefinition,
                                         checkpoint, complete, ensure, explain,
                                         finalizeStyle, forkCopy, fresh, global,
                                         num, remove, setCssClassOnce,
                                         setFillOnce, setFontFamilyOnce,
                                         setFontSizeOnce, setFontWeightOnce,
                                         setRadiusOnce, setStrokeOnce,
                                         setStrokeWidthOnce, setTextAlignOnce,
                                         setWhiteSpaceOnce, setZIndexOnce,
                                         takeHeight, takeLeft, takeTop,
                                         takeWidth, (@*@), (@+@), (@<=@),
                                         (@==@), (|>))
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

example :: VisualTraceBuilder ()
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
  MoreElement :: Block Value %1 -> Elements %1 -> Elements

data Comparison where
  IsMatch :: Block Value %1 -> Block Value %1 -> Comparison
  IsNotMatch :: Block Value %1 -> Block Value %1 -> Comparison

run :: VisualTraceBuilder () -> VisualTraceGraph
run = buildGraph

linearSearch :: SearchInput %1 -> VisualTraceBuilder ()
linearSearch input =
  case input of
    SearchInput targetPayload valuePayloads -> do
      Created target targetExplainToken <- create targetPayload
      explain
        "Create target"
        (targetExplainToken :~ Done)
        \(targetVisual :& End) -> do
          renderedTarget <- fresh (valueViewDefinition TargetValue) targetVisual
          complete renderedTarget
      elements <- createElements valuePayloads
      searchElements target elements

createElements :: InputValues %1 -> VisualTraceBuilder Elements
createElements = createElementsFrom 0

createElementsFrom :: Int -> InputValues %1 -> VisualTraceBuilder Elements
createElementsFrom index inputs =
  case inputs of
    NoInputValues -> return NoElements
    MoreInputValue payload rest -> do
      Created element elementExplainToken <- create payload
      explain
        "Create element"
        (elementExplainToken :~ Done)
        \(elementVisual :& End) -> do
          renderedElement <-
            fresh (valueViewDefinition (ListValue index)) elementVisual
          complete renderedElement
      elements <- createElementsFrom (index + 1) rest
      return (MoreElement element elements)

searchElements :: Block Value %1 -> Elements %1 -> VisualTraceBuilder ()
searchElements target elements =
  case elements of
    NoElements -> do
      Destroyed targetExplainToken <- destroy target
      explain
        "Search exhausted"
        (targetExplainToken :~ Done)
        \(targetVisual :& End) -> do
          remove targetVisual
    MoreElement element rest -> do
      comparison <- compareElement target element
      case comparison of
        IsMatch targetAfter elementAfter -> do
          finishFound targetAfter elementAfter
          discardRemaining rest
        IsNotMatch targetAfter elementAfter -> do
          discardChecked elementAfter
          searchElements targetAfter rest

compareElement ::
     Block Value %1 -> Block Value %1 -> VisualTraceBuilder Comparison
compareElement target element = do
  Copied targetAfter targetProbe targetCopyExplainToken <- copy target
  Copied elementAfter elementProbe elementCopyExplainToken <- copy element
  explain
    "Prepare comparison"
    (targetCopyExplainToken :~ elementCopyExplainToken :~ Done)
    \(targetCopy :& elementCopy :& End) -> do
      (target1, renderedTargetProbe) <-
        forkCopy targetProbeViewDefinition targetCopy
      (element1, renderedElementProbe) <-
        forkCopy elementProbeViewDefinition elementCopy
      complete target1
      complete element1
      complete renderedTargetProbe
      complete renderedElementProbe
  Used targetPayload targetUseExplainToken <- use targetProbe
  Used elementPayload elementUseExplainToken <- use elementProbe
  Computed match matchExplainToken <-
    compute (sameValue <$> targetPayload <*> elementPayload)
  explain
    "Compare target and element"
    (targetUseExplainToken
       :~ elementUseExplainToken
       :~ matchExplainToken
       :~ Done)
    \(targetVisual :& elementVisual :& matchVisual :& End) -> do
      renderedMatch <- fresh matchViewDefinition matchVisual
      checkpoint
      remove targetVisual
      remove elementVisual
      complete renderedMatch
  decision <- decide (\(LBool answer) -> answer) match
  case decision of
    DecidedTrue foundExplainToken -> do
      explain
        "Found target"
        (foundExplainToken :~ Done)
        \(matchVisual :& End) -> do
          remove matchVisual
      return (IsMatch targetAfter elementAfter)
    DecidedFalse notThisExplainToken -> do
      explain
        "Not this element"
        (notThisExplainToken :~ Done)
        \(matchVisual :& End) -> do
          remove matchVisual
      return (IsNotMatch targetAfter elementAfter)

discardChecked :: Block Value %1 -> VisualTraceBuilder ()
discardChecked element = do
  Destroyed elementExplainToken <- destroy element
  explain
    "Discard checked element"
    (elementExplainToken :~ Done)
    \(elementVisual :& End) -> do
      remove elementVisual

finishFound :: Block Value %1 -> Block Value %1 -> VisualTraceBuilder ()
finishFound target element = do
  Destroyed targetExplainToken <- destroy target
  Destroyed elementExplainToken <- destroy element
  explain
    "Finish found target"
    (targetExplainToken :~ elementExplainToken :~ Done)
    \(targetVisual :& elementVisual :& End) -> do
      remove targetVisual
      remove elementVisual

discardRemaining :: Elements %1 -> VisualTraceBuilder ()
discardRemaining elements =
  case elements of
    NoElements -> return ()
    MoreElement element rest -> do
      Destroyed elementExplainToken <- destroy element
      explain
        "Discard remaining element"
        (elementExplainToken :~ Done)
        \(elementVisual :& End) -> do
          remove elementVisual
      discardRemaining rest

-- View model
--------------------------------------------------------------------------------
data ValuePlacement
  = TargetValue
  | ListValue Int

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

valueWidth :: ValuePlacement -> LayoutExpr
valueWidth placement =
  case placement of
    TargetValue -> targetWidth
    ListValue _ -> layoutCell

valueHeight :: ValuePlacement -> LayoutExpr
valueHeight placement =
  case placement of
    TargetValue -> targetHeight
    ListValue _ -> layoutCell

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

constrainScale :: ViewBuilder ()
constrainScale = do
  ensure ((num 72 :: LayoutExpr) @<=@ layoutCell)
  ensure (layoutCell @<=@ (num 86 :: LayoutExpr))
  ensure ((num 26 :: LayoutExpr) @<=@ layoutGap)
  ensure (layoutGap @<=@ (num 44 :: LayoutExpr))

constrainTargetFlow :: ViewBuilder ()
constrainTargetFlow = do
  constrainScale
  ensure (layoutOuterLeft @<=@ layoutTargetLeft)
  ensure (layoutTargetLeft @<=@ (num 128 :: LayoutExpr))
  ensure (layoutOuterTop @<=@ layoutTargetTop)
  ensure (layoutTargetTop @<=@ (num 86 :: LayoutExpr))
  ensure (layoutTargetLeft @+@ targetWidth @<=@ (num 380 :: LayoutExpr))
  ensure (layoutTargetTop @+@ targetHeight @<=@ (num 188 :: LayoutExpr))
  ensure ((num 64 :: LayoutExpr) @<=@ layoutRowLeft)
  ensure (layoutRowLeft @<=@ (num 112 :: LayoutExpr))
  ensure ((num 430 :: LayoutExpr) @<=@ layoutRowTop)
  ensure (layoutRowTop @<=@ (num 500 :: LayoutExpr))
  ensure (layoutRowLeft @+@ listSpan @<=@ layoutOuterRight)
  ensure (layoutRowTop @+@ layoutCell @<=@ layoutOuterBottom)

constrainProbeFlow :: ViewBuilder ()
constrainProbeFlow = do
  constrainTargetFlow
  ensure ((num 210 :: LayoutExpr) @<=@ targetProbeLeft)
  ensure (targetProbeLeft @<=@ (num 300 :: LayoutExpr))
  ensure ((num 520 :: LayoutExpr) @<=@ elementProbeLeft)
  ensure (elementProbeLeft @<=@ (num 640 :: LayoutExpr))
  ensure ((num 205 :: LayoutExpr) @<=@ layoutProbeTop)
  ensure (layoutProbeTop @<=@ (num 270 :: LayoutExpr))
  ensure (layoutTargetTop @+@ targetHeight @+@ layoutGap @<=@ layoutProbeTop)
  ensure (layoutProbeTop @+@ probeHeight @+@ layoutGap @<=@ layoutRowTop)
  ensure
    (targetProbeLeft
       @+@ probeSize
       @+@ (layoutGap @*@ (num 2 :: LayoutExpr))
       @<=@ elementProbeLeft)

constrainMatchFlow :: ViewBuilder ()
constrainMatchFlow = do
  constrainProbeFlow
  ensure ((num 330 :: LayoutExpr) @<=@ layoutMatchLeft)
  ensure (layoutMatchLeft @<=@ (num 415 :: LayoutExpr))
  ensure
    (layoutProbeTop
       @+@ probeHeight
       @+@ (layoutGap @*@ (num 0.7 :: LayoutExpr))
       @<=@ layoutMatchTop)
  ensure
    (layoutMatchTop
       @+@ matchHeight
       @+@ (layoutGap @*@ (num 0.7 :: LayoutExpr))
       @<=@ layoutRowTop)
  ensure (targetProbeLeft @<=@ layoutMatchLeft)
  ensure (layoutMatchLeft @+@ matchWidth @<=@ elementProbeLeft @+@ probeSize)

valueTop :: ValuePlacement -> LayoutExpr
valueTop placement =
  case placement of
    TargetValue -> layoutTargetTop
    ListValue _ -> layoutRowTop

valueLeft :: ValuePlacement -> LayoutExpr
valueLeft placement =
  case placement of
    TargetValue -> layoutTargetLeft
    ListValue index ->
      layoutRowLeft
        @+@ ((num (fromIntegral index) :: LayoutExpr) @*@ layoutStep)

valueNodeStyle :: ValuePlacement -> EmptyStyleDraft %1 -> Style
valueNodeStyle placement draft =
  case placement of
    TargetValue -> targetNodeStyle draft
    ListValue _ -> listNodeStyle draft

targetNodeStyle :: EmptyStyleDraft %1 -> Style
targetNodeStyle draft =
  draft
    |> setFillOnce (Hsl targetHue (num 0.64) (num 0.84))
    |> setStrokeOnce (Hsl targetHue (num 0.76) (num 0.36))
    |> setStrokeWidthOnce emphasisStrokeWidth
    |> setRadiusOnce targetRadius
    |> setFontSizeOnce targetFontSize
    |> setFontFamilyOnce "Inter, ui-sans-serif, system-ui, sans-serif"
    |> setFontWeightOnce FontWeightBold
    |> setTextAlignOnce TextAlignCenter
    |> setWhiteSpaceOnce WhiteSpaceNoWrap
    |> setCssClassOnce "trace-target-card"
    |> finalizeStyle

listNodeStyle :: EmptyStyleDraft %1 -> Style
listNodeStyle draft =
  draft
    |> setFillOnce (Hsl listHue (num 0.34) (num 0.92))
    |> setStrokeOnce (Hsl listHue (num 0.58) (num 0.42))
    |> setStrokeWidthOnce layoutStrokeWidth
    |> setRadiusOnce listRadius
    |> setFontSizeOnce listFontSize
    |> setFontFamilyOnce "Inter, ui-sans-serif, system-ui, sans-serif"
    |> setFontWeightOnce FontWeightBold
    |> setTextAlignOnce TextAlignCenter
    |> setWhiteSpaceOnce WhiteSpaceNoWrap
    |> setCssClassOnce "trace-list-chip"
    |> finalizeStyle

probeNodeStyle :: EmptyStyleDraft %1 -> Style
probeNodeStyle draft =
  draft
    |> setFillOnce (Hsl probeHue (num 0.5) (num 0.88))
    |> setStrokeOnce (Hsl probeHue (num 0.78) (num 0.34))
    |> setStrokeWidthOnce layoutStrokeWidth
    |> setZIndexOnce (num 3)
    |> setRadiusOnce probeRadius
    |> setFontSizeOnce probeFontSize
    |> setFontFamilyOnce "Inter, ui-sans-serif, system-ui, sans-serif"
    |> setFontWeightOnce FontWeightBold
    |> setTextAlignOnce TextAlignCenter
    |> setWhiteSpaceOnce WhiteSpaceNoWrap
    |> setCssClassOnce "trace-probe-chip"
    |> finalizeStyle

matchNodeStyle :: EmptyStyleDraft %1 -> Style
matchNodeStyle draft =
  draft
    |> setFillOnce (Hsl decisionHue (num 0.6) (num 0.86))
    |> setStrokeOnce (Hsl decisionHue (num 0.82) (num 0.32))
    |> setStrokeWidthOnce emphasisStrokeWidth
    |> setZIndexOnce (num 4)
    |> setRadiusOnce decisionRadius
    |> setFontSizeOnce matchFontSize
    |> setFontFamilyOnce "Inter, ui-sans-serif, system-ui, sans-serif"
    |> setFontWeightOnce FontWeightBold
    |> setTextAlignOnce TextAlignCenter
    |> setWhiteSpaceOnce WhiteSpaceNoWrap
    |> setCssClassOnce "trace-decision-pill"
    |> finalizeStyle

defineValueNode ::
     ValuePlacement -> LiveVisual Value %1 -> ViewBuilder (BoxVisual Value)
defineValueNode placement visual0 = do
  LayoutUse visual1 valueLeftX <- takeLeft visual0
  LayoutUse visual2 valueTopY <- takeTop visual1
  LayoutUse visual3 valueWidthX <- takeWidth visual2
  LayoutUse visual4 valueHeightY <- takeHeight visual3
  constrainValueFlow placement
  ensure (valueLeftX @==@ valueLeft placement)
  ensure (valueTopY @==@ valueTop placement)
  ensure (valueWidthX @==@ valueWidth placement)
  ensure (valueHeightY @==@ valueHeight placement)
  return visual4

constrainValueFlow :: ValuePlacement -> ViewBuilder ()
constrainValueFlow placement =
  case placement of
    TargetValue -> constrainTargetFlow
    ListValue index ->
      case index of
        0 -> constrainTargetFlow
        _ -> return ()

defineTargetProbeNode :: LiveVisual Value %1 -> ViewBuilder (BoxVisual Value)
defineTargetProbeNode visual0 = do
  LayoutUse visual1 probeLeftX <- takeLeft visual0
  LayoutUse visual2 probeTopY <- takeTop visual1
  LayoutUse visual3 probeWidthX <- takeWidth visual2
  LayoutUse visual4 probeHeightY <- takeHeight visual3
  constrainProbeFlow
  ensure (probeLeftX @==@ targetProbeLeft)
  ensure (probeTopY @==@ layoutProbeTop)
  ensure (probeWidthX @==@ probeSize)
  ensure (probeHeightY @==@ probeHeight)
  return visual4

defineElementProbeNode :: LiveVisual Value %1 -> ViewBuilder (BoxVisual Value)
defineElementProbeNode visual0 = do
  LayoutUse visual1 probeLeftX <- takeLeft visual0
  LayoutUse visual2 probeTopY <- takeTop visual1
  LayoutUse visual3 probeWidthX <- takeWidth visual2
  LayoutUse visual4 probeHeightY <- takeHeight visual3
  constrainProbeFlow
  ensure (probeLeftX @==@ elementProbeLeft)
  ensure (probeTopY @==@ layoutProbeTop)
  ensure (probeWidthX @==@ probeSize)
  ensure (probeHeightY @==@ probeHeight)
  return visual4

defineMatchNode :: LiveVisual Match %1 -> ViewBuilder (BoxVisual Match)
defineMatchNode visual0 = do
  LayoutUse visual1 matchLeftX <- takeLeft visual0
  LayoutUse visual2 matchTopY <- takeTop visual1
  LayoutUse visual3 matchWidthX <- takeWidth visual2
  LayoutUse visual4 matchHeightY <- takeHeight visual3
  constrainMatchFlow
  ensure (matchLeftX @==@ layoutMatchLeft)
  ensure (matchTopY @==@ layoutMatchTop)
  ensure (matchWidthX @==@ matchWidth)
  ensure (matchHeightY @==@ matchHeight)
  return visual4

valueViewDefinition :: ValuePlacement -> BoxDefinition Value
valueViewDefinition placement =
  boxDefinition (valueNodeStyle placement) (defineValueNode placement)

targetProbeViewDefinition :: BoxDefinition Value
targetProbeViewDefinition = boxDefinition probeNodeStyle defineTargetProbeNode

elementProbeViewDefinition :: BoxDefinition Value
elementProbeViewDefinition = boxDefinition probeNodeStyle defineElementProbeNode

matchViewDefinition :: BoxDefinition Match
matchViewDefinition = boxDefinition matchNodeStyle defineMatchNode
