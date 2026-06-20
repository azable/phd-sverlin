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
import           LinearTrace.Core
import           LinearTrace.View
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

exampleElementCount :: Int
exampleElementCount =
  case exampleSpec of
    ExampleSpec _ values -> countExampleValues values

countExampleValues :: ExampleValues -> Int
countExampleValues values =
  case values of
    NoExampleValues         -> 0
    MoreExampleValue _ rest -> 1 + countExampleValues rest

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
          renderedTarget <- fresh valueViewDefinition targetVisual
          complete renderedTarget
      elements <- createElements valuePayloads
      searchElements target elements

createElements :: InputValues %1 -> VisualTraceBuilder Elements
createElements inputs =
  case inputs of
    NoInputValues -> return NoElements
    MoreInputValue payload rest -> do
      Created element elementEvidence <- create payload
      explain
        "Create element"
        (elementEvidence :~ Done)
        \(VCons elementToken VNil) -> do
          elementVisual <- createVisual elementToken
          renderedElement <- fresh valueViewDefinition elementVisual
          complete renderedElement
      elements <- createElements rest
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
      LayoutUse renderedMatch1 matchCenterX <- takeCenterX renderedMatch
      LayoutUse renderedMatch2 matchTop <- takeTop renderedMatch1
      LayoutUse element1 elementBottom <- takeBottom elementVisual
      ensure (matchCenterX @==@ layoutStageCenter)
      ensure (matchTop @==@ elementBottom @+@ matchGap)
      checkpoint
      remove targetVisual
      remove element1
      complete renderedMatch2
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

-- View constants
--------------------------------------------------------------------------------
layoutCanvasWidth :: LayoutExpr
layoutCanvasWidth = num 800

layoutCanvasHeight :: LayoutExpr
layoutCanvasHeight = num 600

layoutAvailableWidth :: LayoutExpr
layoutAvailableWidth = num 760

layoutStageCenter :: LayoutExpr
layoutStageCenter = global "linear-search.stage-center"

layoutTargetTop :: LayoutExpr
layoutTargetTop = global "linear-search.target-top"

layoutVerticalGap :: LayoutExpr
layoutVerticalGap = layoutCell @*@ (num 0.82 :: LayoutExpr)

layoutProbeTop :: LayoutExpr
layoutProbeTop = layoutTargetTop @+@ layoutCell @+@ layoutVerticalGap

layoutMatchTop :: LayoutExpr
layoutMatchTop = layoutProbeTop @+@ layoutProbeSize @+@ matchGap

layoutListTop :: LayoutExpr
layoutListTop = layoutMatchTop @+@ matchHeight @+@ layoutVerticalGap

layoutMaxCell :: LayoutExpr
layoutMaxCell = num 88

layoutMinCell :: LayoutExpr
layoutMinCell = num 10

layoutMaxGap :: LayoutExpr
layoutMaxGap = num 24

layoutGapRatio :: LayoutExpr
layoutGapRatio = num 0.27

layoutElementCountValue :: Int
layoutElementCountValue
  {- HLINT ignore "Use if" -}
 =
  case exampleElementCount <= 0 of
    True  -> 1
    False -> exampleElementCount

layoutGapCountValue :: Int
layoutGapCountValue
  {- HLINT ignore "Use if" -}
 =
  case exampleElementCount <= 1 of
    True  -> 0
    False -> exampleElementCount - 1

layoutElementCount :: LayoutExpr
layoutElementCount = num (fromIntegral layoutElementCountValue)

layoutGapCount :: LayoutExpr
layoutGapCount = num (fromIntegral layoutGapCountValue)

layoutCell :: LayoutExpr
layoutCell = global "linear-search.cell"

layoutGap :: LayoutExpr
layoutGap = global "linear-search.gap"

layoutRowLeft :: LayoutExpr
layoutRowLeft = global "linear-search.row-left"

layoutRowWidth :: LayoutExpr
layoutRowWidth = global "linear-search.row-width"

layoutMinExpr :: LayoutExpr -> LayoutExpr -> LayoutExpr
layoutMinExpr lhs rhs =
  ((lhs @+@ rhs) @-@ absExpr (lhs @-@ rhs)) @/@ (num 2 :: LayoutExpr)

layoutWidthLimitedCell :: LayoutExpr
layoutWidthLimitedCell =
  layoutAvailableWidth
    @/@ (layoutElementCount @+@ (layoutGapCount @*@ layoutGapRatio))

layoutPreferredCell :: LayoutExpr
layoutPreferredCell = layoutMinExpr layoutMaxCell layoutWidthLimitedCell

layoutPreferredGap :: LayoutExpr
layoutPreferredGap = layoutCell @*@ layoutGapRatio

layoutStep :: LayoutExpr
layoutStep = layoutCell @+@ layoutGap

layoutProbeSize :: LayoutExpr
layoutProbeSize = layoutCell @*@ (num 1.22 :: LayoutExpr)

layoutProbeGap :: LayoutExpr
layoutProbeGap = layoutProbeSize @*@ (num 0.36 :: LayoutExpr)

targetProbeLeft :: LayoutExpr
targetProbeLeft =
  layoutStageCenter
    @-@ layoutProbeSize
    @-@ (layoutProbeGap @/@ (num 2 :: LayoutExpr))

elementProbeLeft :: LayoutExpr
elementProbeLeft =
  layoutStageCenter @+@ (layoutProbeGap @/@ (num 2 :: LayoutExpr))

layoutHorizontalInset :: LayoutExpr
layoutHorizontalInset =
  (layoutCanvasWidth @-@ layoutAvailableWidth) @/@ (num 2 :: LayoutExpr)

layoutRightInset :: LayoutExpr
layoutRightInset = layoutCanvasWidth @-@ layoutHorizontalInset

valueFontSize :: LayoutExpr
valueFontSize = layoutCell @*@ (num 0.34 :: LayoutExpr)

probeFontSize :: LayoutExpr
probeFontSize = layoutProbeSize @*@ (num 0.34 :: LayoutExpr)

valueRadius :: LayoutExpr
valueRadius = layoutCell @*@ (num 0.11 :: LayoutExpr)

probeRadius :: LayoutExpr
probeRadius = layoutProbeSize @*@ (num 0.11 :: LayoutExpr)

valueHue :: HueExpr
valueHue = global "linear-search.value-hue"

valueFillLightness :: UnitExpr
valueFillLightness = global "linear-search.value-fill-lightness"

decisionHue :: HueExpr
decisionHue = global "linear-search.decision-hue"

decisionFillLightness :: UnitExpr
decisionFillLightness = global "linear-search.decision-fill-lightness"

matchWidth :: LayoutExpr
matchWidth =
  (layoutCell @*@ (num 1.88 :: LayoutExpr)) @+@ (num 28 :: LayoutExpr)

matchHeight :: LayoutExpr
matchHeight = layoutCell @*@ (num 0.68 :: LayoutExpr)

matchFontSize :: LayoutExpr
matchFontSize = matchHeight @*@ (num 0.38 :: LayoutExpr)

matchGap :: LayoutExpr
matchGap = layoutCell @*@ (num 0.42 :: LayoutExpr)

constrainSearchLayout :: ViewBuilder ()
constrainSearchLayout = do
  ensure
    ((layoutCanvasWidth @*@ (num 0.43 :: LayoutExpr)) @<=@ layoutStageCenter)
  ensure
    (layoutStageCenter @<=@ (layoutCanvasWidth @*@ (num 0.57 :: LayoutExpr)))
  ensure ((num 24 :: LayoutExpr) @<=@ layoutTargetTop)
  ensure (layoutTargetTop @<=@ (num 52 :: LayoutExpr))
  ensure ((num 198 :: HueExpr) @<=@ valueHue)
  ensure (valueHue @<=@ (num 214 :: HueExpr))
  ensure ((num 0.92 :: UnitExpr) @<=@ valueFillLightness)
  ensure (valueFillLightness @<=@ (num 0.98 :: UnitExpr))
  ensure ((num 40 :: HueExpr) @<=@ decisionHue)
  ensure (decisionHue @<=@ (num 56 :: HueExpr))
  ensure ((num 0.88 :: UnitExpr) @<=@ decisionFillLightness)
  ensure (decisionFillLightness @<=@ (num 0.94 :: UnitExpr))
  ensure (layoutMinCell @<=@ layoutCell)
  ensure (layoutCell @<=@ layoutMaxCell)
  ensure ((num 0 :: LayoutExpr) @<=@ layoutGap)
  ensure (layoutGap @<=@ layoutMaxGap)
  ensure (layoutCell @==@ layoutPreferredCell)
  ensure (layoutGap @==@ layoutPreferredGap)
  ensure
    (layoutRowWidth
       @==@ ((layoutElementCount @*@ layoutCell)
               @+@ (layoutGapCount @*@ layoutGap)))
  ensure
    (layoutRowLeft
       @+@ (layoutRowWidth @/@ (num 2 :: LayoutExpr))
       @==@ layoutStageCenter)
  ensure (layoutRowWidth @<=@ layoutAvailableWidth)
  ensure (layoutHorizontalInset @<=@ layoutRowLeft)
  ensure (layoutRowLeft @+@ layoutRowWidth @<=@ layoutRightInset)
  ensure (layoutTargetTop @+@ layoutCell @<=@ layoutProbeTop)
  ensure (layoutProbeTop @+@ layoutProbeSize @<=@ layoutMatchTop)
  ensure (layoutMatchTop @+@ matchHeight @<=@ layoutListTop)
  ensure (layoutListTop @+@ layoutCell @<=@ layoutCanvasHeight)
  ensure (layoutHorizontalInset @<=@ targetProbeLeft)
  ensure (elementProbeLeft @+@ layoutProbeSize @<=@ layoutRightInset)

valueTop :: BlockRef Value -> LayoutExpr
valueTop ref =
  case ref of
    BlockRef blockId ->
      case blockId of
        0 -> layoutTargetTop
        _ -> layoutListTop

valueLeft :: BlockRef Value -> LayoutExpr
valueLeft ref =
  case ref of
    BlockRef blockId ->
      case blockId of
        0 -> layoutStageCenter @-@ (layoutCell @/@ (num 2 :: LayoutExpr))
        _ ->
          layoutRowLeft
            @+@ ((num (fromIntegral (blockId - 1)) :: LayoutExpr) @*@ layoutStep)

valueSize :: LayoutExpr
valueSize = layoutCell

valueHeight :: LayoutExpr
valueHeight = valueSize

valueNodeStyle :: EmptyStyleDraft %1 -> Style
valueNodeStyle draft =
  draft
    |> setFillOnce (Hsl valueHue (num 0.2) valueFillLightness)
    |> setStrokeOnce (Hsl valueHue (num 0.5) (num 0.34))
    |> setStrokeWidthOnce (num 2)
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
    |> setFillOnce (Hsl valueHue (num 0.2) valueFillLightness)
    |> setStrokeOnce (Hsl valueHue (num 0.5) (num 0.34))
    |> setStrokeWidthOnce (num 2)
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
    |> setFillOnce (Hsl decisionHue (num 0.78) decisionFillLightness)
    |> setStrokeOnce (Hsl decisionHue (num 0.74) (num 0.34))
    |> setStrokeWidthOnce (num 2)
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
     BlockRef Value -> LiveVisual Value %1 -> ViewBuilder (BoxVisual Value)
defineValueNode ref visual0 = do
  constrainSearchLayout
  LayoutUse visual1 valueLeftX <- takeLeft visual0
  LayoutUse visual2 valueTopY <- takeTop visual1
  LayoutUse visual3 valueWidthX <- takeWidth visual2
  LayoutUse visual4 valueHeightY <- takeHeight visual3
  ensure (valueLeftX @==@ valueLeft ref)
  ensure (valueTopY @==@ valueTop ref)
  ensure (valueWidthX @==@ valueSize)
  ensure (valueHeightY @==@ valueHeight)
  return visual4

defineTargetProbeNode ::
     BlockRef Value -> LiveVisual Value %1 -> ViewBuilder (BoxVisual Value)
defineTargetProbeNode _ref visual0 = do
  constrainSearchLayout
  LayoutUse visual1 probeLeftX <- takeLeft visual0
  LayoutUse visual2 probeTopY <- takeTop visual1
  LayoutUse visual3 probeWidthX <- takeWidth visual2
  LayoutUse visual4 probeHeightY <- takeHeight visual3
  ensure (probeLeftX @==@ targetProbeLeft)
  ensure (probeTopY @==@ layoutProbeTop)
  ensure (probeWidthX @==@ layoutProbeSize)
  ensure (probeHeightY @==@ layoutProbeSize)
  return visual4

defineElementProbeNode ::
     BlockRef Value -> LiveVisual Value %1 -> ViewBuilder (BoxVisual Value)
defineElementProbeNode _ref visual0 = do
  constrainSearchLayout
  LayoutUse visual1 probeLeftX <- takeLeft visual0
  LayoutUse visual2 probeTopY <- takeTop visual1
  LayoutUse visual3 probeWidthX <- takeWidth visual2
  LayoutUse visual4 probeHeightY <- takeHeight visual3
  ensure (probeLeftX @==@ elementProbeLeft)
  ensure (probeTopY @==@ layoutProbeTop)
  ensure (probeWidthX @==@ layoutProbeSize)
  ensure (probeHeightY @==@ layoutProbeSize)
  return visual4

defineMatchNode ::
     BlockRef Match -> LiveVisual Match %1 -> ViewBuilder (SizeVisual Match)
defineMatchNode _ref visual0 = do
  constrainSearchLayout
  LayoutUse visual1 matchWidthX <- takeWidth visual0
  LayoutUse visual2 matchHeightY <- takeHeight visual1
  ensure (matchWidthX @==@ matchWidth)
  ensure (matchHeightY @==@ matchHeight)
  return visual2

valueViewDefinition :: BoxDefinition Value
valueViewDefinition = boxDefinition valueNodeStyle defineValueNode

targetProbeViewDefinition :: BoxDefinition Value
targetProbeViewDefinition = boxDefinition probeNodeStyle defineTargetProbeNode

elementProbeViewDefinition :: BoxDefinition Value
elementProbeViewDefinition = boxDefinition probeNodeStyle defineElementProbeNode

matchViewDefinition :: SizeDefinition Match
matchViewDefinition = sizeDefinition matchNodeStyle defineMatchNode
