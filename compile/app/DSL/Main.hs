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
import           LinearTrace.Core        ( Block
                                         , Computed(..)
                                         , Copied(..)
                                         , Created(..)
                                         , Decided(..)
                                         , Destroyed(..)
                                         , EvidenceList(..)
                                         , LBool(..)
                                         , LInt(..)
                                         , Payload
                                         , PayloadView(..)
                                         , Traceable(..)
                                         , Used(..)
                                         , buildGraph
                                         , compute
                                         , copy
                                         , create
                                         , decide
                                         , destroy
                                         , use
                                         , (<$>)
                                         , (<*>)
                                         )
import           LinearTrace.View        ( BoxDefinition
                                         , BoxVisual
                                         , EmptyStyleDraft
                                         , FontWeight(..)
                                         , Hsl(..)
                                         , HueExpr
                                         , LayoutExpr
                                         , LayoutUse(..)
                                         , LiveVisual
                                         , Style
                                         , TextAlign(..)
                                         , ViewBuilder
                                         , ViewTokens(..)
                                         , VisualTraceBuilder
                                         , VisualTraceGraph
                                         , WhiteSpace(..)
                                         , boxDefinition
                                         , checkpoint
                                         , complete
                                         , computeVisual
                                         , copyVisual
                                         , createVisual
                                         , decideVisual
                                         , destroyVisual
                                         , ensure
                                         , explain
                                         , finalizeStyle
                                         , forkCopy
                                         , fresh
                                         , global
                                         , num
                                         , remove
                                         , setCssClassOnce
                                         , setFillOnce
                                         , setFontFamilyOnce
                                         , setFontSizeOnce
                                         , setFontWeightOnce
                                         , setRadiusOnce
                                         , setStrokeOnce
                                         , setStrokeWidthOnce
                                         , setTextAlignOnce
                                         , setWhiteSpaceOnce
                                         , setZIndexOnce
                                         , takeHeight
                                         , takeLeft
                                         , takeTop
                                         , takeWidth
                                         , useVisual
                                         , (|>)
                                         , (@*@)
                                         , (@+@)
                                         , (@<=@)
                                         , (@==@)
                                         )
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
      Created target targetEvidence <- create targetPayload
      explain
        "Create target"
        (targetEvidence :~ Done)
        \(VCons targetToken VNil) -> do
          targetVisual <- createVisual targetToken
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
      Created element elementEvidence <- create payload
      explain
        "Create element"
        (elementEvidence :~ Done)
        \(VCons elementToken VNil) -> do
          elementVisual <- createVisual elementToken
          renderedElement <-
            fresh (valueViewDefinition (ListValue index)) elementVisual
          complete renderedElement
      elements <- createElementsFrom (index + 1) rest
      return (MoreElement element elements)

searchElements :: Block Value %1 -> Elements %1 -> VisualTraceBuilder ()
searchElements target elements =
  case elements of
    NoElements -> do
      Destroyed targetEvidence <- destroy target
      explain
        "Search exhausted"
        (targetEvidence :~ Done)
        \(VCons targetToken VNil) -> do
          targetVisual <- destroyVisual targetToken
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
  Copied targetAfter targetProbe targetCopyEvidence <- copy target
  Copied elementAfter elementProbe elementCopyEvidence <- copy element
  explain
    "Prepare comparison"
    (targetCopyEvidence :~ elementCopyEvidence :~ Done)
    \(VCons targetToken (VCons elementToken VNil)) -> do
      targetCopy <- copyVisual targetToken
      elementCopy <- copyVisual elementToken
      (target1, renderedTargetProbe) <-
        forkCopy targetProbeViewDefinition targetCopy
      (element1, renderedElementProbe) <-
        forkCopy elementProbeViewDefinition elementCopy
      complete target1
      complete element1
      complete renderedTargetProbe
      complete renderedElementProbe
  Used targetPayload targetUseEvidence <- use targetProbe
  Used elementPayload elementUseEvidence <- use elementProbe
  Computed match matchEvidence <-
    compute (sameValue <$> targetPayload <*> elementPayload)
  explain
    "Compare target and element"
    (targetUseEvidence :~ elementUseEvidence :~ matchEvidence :~ Done)
    \(VCons targetToken (VCons elementToken (VCons matchToken VNil))) -> do
      targetVisual <- useVisual targetToken
      elementVisual <- useVisual elementToken
      matchVisual <- computeVisual matchToken
      renderedMatch <- fresh matchViewDefinition matchVisual
      checkpoint
      remove targetVisual
      remove elementVisual
      complete renderedMatch
  decision <- decide (\(LBool answer) -> answer) match
  case decision of
    DecidedTrue foundEvidence -> do
      explain
        "Found target"
        (foundEvidence :~ Done)
        \(VCons matchToken VNil) -> do
          matchVisual <- decideVisual matchToken
          remove matchVisual
      return (IsMatch targetAfter elementAfter)
    DecidedFalse notThisEvidence -> do
      explain
        "Not this element"
        (notThisEvidence :~ Done)
        \(VCons matchToken VNil) -> do
          matchVisual <- decideVisual matchToken
          remove matchVisual
      return (IsNotMatch targetAfter elementAfter)

discardChecked :: Block Value %1 -> VisualTraceBuilder ()
discardChecked element = do
  Destroyed elementEvidence <- destroy element
  explain
    "Discard checked element"
    (elementEvidence :~ Done)
    \(VCons elementToken VNil) -> do
      elementVisual <- destroyVisual elementToken
      remove elementVisual

finishFound :: Block Value %1 -> Block Value %1 -> VisualTraceBuilder ()
finishFound target element = do
  Destroyed targetEvidence <- destroy target
  Destroyed elementEvidence <- destroy element
  explain
    "Finish found target"
    (targetEvidence :~ elementEvidence :~ Done)
    \(VCons targetToken (VCons elementToken VNil)) -> do
      targetVisual <- destroyVisual targetToken
      elementVisual <- destroyVisual elementToken
      remove targetVisual
      remove elementVisual

discardRemaining :: Elements %1 -> VisualTraceBuilder ()
discardRemaining elements =
  case elements of
    NoElements -> return ()
    MoreElement element rest -> do
      Destroyed elementEvidence <- destroy element
      explain
        "Discard remaining element"
        (elementEvidence :~ Done)
        \(VCons elementToken VNil) -> do
          elementVisual <- destroyVisual elementToken
          remove elementVisual
      discardRemaining rest

-- View model
--------------------------------------------------------------------------------
data ValuePlacement
  = TargetValue
  | ListValue Int

layoutCell :: LayoutExpr
layoutCell = global "linear-search.cell"

layoutGap :: LayoutExpr
layoutGap = global "linear-search.gap"

layoutTargetLeft :: LayoutExpr
layoutTargetLeft = global "linear-search.target-left"

layoutTargetTop :: LayoutExpr
layoutTargetTop = global "linear-search.target-top"

layoutRowLeft :: LayoutExpr
layoutRowLeft = global "linear-search.row-left"

layoutRowTop :: LayoutExpr
layoutRowTop = global "linear-search.row-top"

layoutStep :: LayoutExpr
layoutStep = layoutCell @+@ layoutGap

layoutProbeTop :: LayoutExpr
layoutProbeTop = global "linear-search.probe-top"

targetProbeLeft :: LayoutExpr
targetProbeLeft = global "linear-search.target-probe-left"

elementProbeLeft :: LayoutExpr
elementProbeLeft = global "linear-search.element-probe-left"

layoutMatchLeft :: LayoutExpr
layoutMatchLeft = global "linear-search.match-left"

layoutMatchTop :: LayoutExpr
layoutMatchTop = global "linear-search.match-top"

valueFontSize :: LayoutExpr
valueFontSize = layoutCell @*@ (num 0.46 :: LayoutExpr)

probeFontSize :: LayoutExpr
probeFontSize = valueFontSize

valueRadius :: LayoutExpr
valueRadius = layoutCell @*@ (num 0.11 :: LayoutExpr)

probeRadius :: LayoutExpr
probeRadius = valueRadius

layoutStrokeWidth :: LayoutExpr
layoutStrokeWidth = layoutCell @*@ (num 0.04 :: LayoutExpr)

valueHue :: HueExpr
valueHue = global "linear-search.value-hue"

decisionHue :: HueExpr
decisionHue = global "linear-search.decision-hue"

matchWidth :: LayoutExpr
matchWidth = layoutCell @+@ layoutCell @+@ layoutCell @+@ layoutGap

matchHeight :: LayoutExpr
matchHeight = layoutCell

matchFontSize :: LayoutExpr
matchFontSize = valueFontSize

layoutOrigin :: LayoutExpr
layoutOrigin = num 0

constrainScale :: ViewBuilder ()
constrainScale = do
  ensure (layoutOrigin @<=@ layoutCell)
  ensure (layoutOrigin @<=@ layoutGap)

constrainTargetFlow :: ViewBuilder ()
constrainTargetFlow = do
  constrainScale
  ensure (layoutOrigin @<=@ layoutTargetLeft)
  ensure (layoutOrigin @<=@ layoutTargetTop)
  ensure (layoutOrigin @<=@ layoutRowTop)
  ensure (layoutTargetTop @+@ layoutCell @+@ layoutGap @<=@ layoutRowTop)

constrainProbeFlow :: ViewBuilder ()
constrainProbeFlow = do
  ensure (layoutOrigin @<=@ targetProbeLeft)
  ensure (layoutOrigin @<=@ elementProbeLeft)
  ensure (layoutOrigin @<=@ layoutProbeTop)
  ensure (layoutTargetTop @+@ layoutCell @+@ layoutGap @<=@ layoutProbeTop)
  ensure (targetProbeLeft @+@ layoutCell @+@ layoutGap @<=@ elementProbeLeft)

constrainMatchFlow :: ViewBuilder ()
constrainMatchFlow = do
  ensure (layoutOrigin @<=@ layoutMatchLeft)
  ensure (layoutOrigin @<=@ layoutMatchTop)
  ensure (layoutProbeTop @+@ layoutCell @+@ layoutGap @<=@ layoutMatchTop)
  ensure (layoutMatchTop @+@ matchHeight @+@ layoutGap @<=@ layoutRowTop)
  ensure (targetProbeLeft @<=@ layoutMatchLeft)
  ensure (layoutMatchLeft @+@ matchWidth @<=@ elementProbeLeft @+@ layoutCell)

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
      layoutRowLeft @+@ ((num (fromIntegral index) :: LayoutExpr) @*@ layoutStep)

valueSize :: LayoutExpr
valueSize = layoutCell

valueHeight :: LayoutExpr
valueHeight = valueSize

valueNodeStyle :: EmptyStyleDraft %1 -> Style
valueNodeStyle draft =
  draft
    |> setFillOnce (Hsl valueHue (num 0.22) (num 0.93))
    |> setStrokeOnce (Hsl valueHue (num 0.5) (num 0.34))
    |> setStrokeWidthOnce layoutStrokeWidth
    |> setRadiusOnce valueRadius
    |> setFontSizeOnce valueFontSize
    |> setFontFamilyOnce "ui-monospace, SFMono-Regular, Menlo, monospace"
    |> setFontWeightOnce FontWeightBold
    |> setTextAlignOnce TextAlignCenter
    |> setWhiteSpaceOnce WhiteSpaceNoWrap
    |> setCssClassOnce "trace-value-block"
    |> finalizeStyle

probeNodeStyle :: EmptyStyleDraft %1 -> Style
probeNodeStyle draft =
  draft
    |> setFillOnce (Hsl valueHue (num 0.22) (num 0.93))
    |> setStrokeOnce (Hsl valueHue (num 0.5) (num 0.34))
    |> setStrokeWidthOnce layoutStrokeWidth
    |> setZIndexOnce (num 1)
    |> setRadiusOnce probeRadius
    |> setFontSizeOnce probeFontSize
    |> setFontFamilyOnce "ui-monospace, SFMono-Regular, Menlo, monospace"
    |> setFontWeightOnce FontWeightBold
    |> setTextAlignOnce TextAlignCenter
    |> setWhiteSpaceOnce WhiteSpaceNoWrap
    |> setCssClassOnce "trace-value-block"
    |> finalizeStyle

matchNodeStyle :: EmptyStyleDraft %1 -> Style
matchNodeStyle draft =
  draft
    |> setFillOnce (Hsl decisionHue (num 0.66) (num 0.9))
    |> setStrokeOnce (Hsl decisionHue (num 0.74) (num 0.34))
    |> setStrokeWidthOnce layoutStrokeWidth
    |> setZIndexOnce (num 2)
    |> setRadiusOnce valueRadius
    |> setFontSizeOnce matchFontSize
    |> setFontFamilyOnce "ui-monospace, SFMono-Regular, Menlo, monospace"
    |> setFontWeightOnce FontWeightBold
    |> setTextAlignOnce TextAlignCenter
    |> setWhiteSpaceOnce WhiteSpaceNoWrap
    |> setCssClassOnce "trace-decision-block"
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
  ensure (valueWidthX @==@ valueSize)
  ensure (valueHeightY @==@ valueHeight)
  return visual4

constrainValueFlow :: ValuePlacement -> ViewBuilder ()
constrainValueFlow placement =
  case placement of
    TargetValue -> constrainTargetFlow
    ListValue index ->
      case index of
        0 -> ensure (layoutOrigin @<=@ layoutRowLeft)
        _ -> return ()

defineTargetProbeNode ::
     LiveVisual Value %1 -> ViewBuilder (BoxVisual Value)
defineTargetProbeNode visual0 = do
  LayoutUse visual1 probeLeftX <- takeLeft visual0
  LayoutUse visual2 probeTopY <- takeTop visual1
  LayoutUse visual3 probeWidthX <- takeWidth visual2
  LayoutUse visual4 probeHeightY <- takeHeight visual3
  ensure (probeLeftX @==@ targetProbeLeft)
  ensure (probeTopY @==@ layoutProbeTop)
  ensure (probeWidthX @==@ valueSize)
  ensure (probeHeightY @==@ valueHeight)
  return visual4

defineElementProbeNode ::
     LiveVisual Value %1 -> ViewBuilder (BoxVisual Value)
defineElementProbeNode visual0 = do
  LayoutUse visual1 probeLeftX <- takeLeft visual0
  LayoutUse visual2 probeTopY <- takeTop visual1
  LayoutUse visual3 probeWidthX <- takeWidth visual2
  LayoutUse visual4 probeHeightY <- takeHeight visual3
  constrainProbeFlow
  ensure (probeLeftX @==@ elementProbeLeft)
  ensure (probeTopY @==@ layoutProbeTop)
  ensure (probeWidthX @==@ valueSize)
  ensure (probeHeightY @==@ valueHeight)
  return visual4

defineMatchNode ::
     LiveVisual Match %1 -> ViewBuilder (BoxVisual Match)
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
valueViewDefinition placement = boxDefinition valueNodeStyle (defineValueNode placement)

targetProbeViewDefinition :: BoxDefinition Value
targetProbeViewDefinition = boxDefinition probeNodeStyle defineTargetProbeNode

elementProbeViewDefinition :: BoxDefinition Value
elementProbeViewDefinition = boxDefinition probeNodeStyle defineElementProbeNode

matchViewDefinition :: BoxDefinition Match
matchViewDefinition = boxDefinition matchNodeStyle defineMatchNode
