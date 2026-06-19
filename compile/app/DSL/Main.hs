{-# LANGUAGE ConstraintKinds         #-}
{-# LANGUAGE DataKinds               #-}
{-# LANGUAGE FlexibleContexts        #-}
{-# LANGUAGE FlexibleInstances       #-}
{-# LANGUAGE GADTs                   #-}
{-# LANGUAGE LinearTypes             #-}
{-# LANGUAGE NoImplicitPrelude       #-}
{-# LANGUAGE RebindableSyntax        #-}
{-# LANGUAGE TypeFamilies            #-}
{-# LANGUAGE TypeOperators           #-}
{-# LANGUAGE UndecidableInstances    #-}
{-# LANGUAGE UndecidableSuperClasses #-}

module DSL.Main
  ( example
  , run
  ) where

import           Control.Functor.Linear hiding (ask, (<$>), (<*>))
import           LinearTrace.Core
import           LinearTrace.Print      (PrintEvent (..))
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
      LBool matched ->
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

example :: TraceBuilder Events ()
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

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
data CreateTarget =
  CreateTarget

type instance Actions CreateTarget = '[ Create Value]

data CreateElement =
  CreateElement

type instance Actions CreateElement = '[ Create Value]

data Compare =
  Compare

data PrepareCompare =
  PrepareCompare

type instance Actions PrepareCompare = '[ Copy Value, Copy Value]

type instance Actions Compare = '[ Use Value, Use Value, Compute Match]

data Found =
  Found

type instance Actions Found = '[ Decide Match]

data NotThisOne =
  NotThisOne

type instance Actions NotThisOne = '[ Decide Match]

data DiscardChecked =
  DiscardChecked

type instance Actions DiscardChecked = '[ Destroy Value]

data FinishFound =
  FinishFound

type instance Actions FinishFound = '[ Destroy Value, Destroy Value]

data DiscardRemaining =
  DiscardRemaining

type instance Actions DiscardRemaining = '[ Destroy Value]

data SearchExhausted =
  SearchExhausted

type instance Actions SearchExhausted = '[ Destroy Value]

type Events
  = '[ CreateTarget
     , CreateElement
     , PrepareCompare
     , Compare
     , Found
     , NotThisOne
     , DiscardChecked
     , FinishFound
     , DiscardRemaining
     , SearchExhausted
     ]

--------------------------------------------------------------------------------
-- Search program
--------------------------------------------------------------------------------
data Elements where
  NoElements :: Elements
  MoreElement :: Block Value %1 -> Elements %1 -> Elements

data Comparison where
  IsMatch :: Block Value %1 -> Block Value %1 -> Comparison
  IsNotMatch :: Block Value %1 -> Block Value %1 -> Comparison

run :: TraceBuilder Events () -> TraceGraph Events
run = buildGraph

linearSearch :: SearchInput %1 -> TraceBuilder Events ()
linearSearch input =
  case input of
    SearchInput targetPayload valuePayloads -> do
      Created target targetEvidence <- create targetPayload
      explain CreateTarget (targetEvidence :~ Done)
      elements <- createElements valuePayloads
      searchElements target elements

createElements :: InputValues %1 -> TraceBuilder Events Elements
createElements inputs =
  case inputs of
    NoInputValues -> return NoElements
    MoreInputValue payload rest -> do
      Created element elementEvidence <- create payload
      explain CreateElement (elementEvidence :~ Done)
      elements <- createElements rest
      return (MoreElement element elements)

searchElements :: Block Value %1 -> Elements %1 -> TraceBuilder Events ()
searchElements target elements =
  case elements of
    NoElements -> do
      Destroyed targetEvidence <- destroy target
      explain SearchExhausted (targetEvidence :~ Done)
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
     Block Value %1 -> Block Value %1 -> TraceBuilder Events Comparison
compareElement target element = do
  Copied targetAfter targetProbe targetCopyEvidence <- copy target
  Copied elementAfter elementProbe elementCopyEvidence <- copy element
  explain PrepareCompare (targetCopyEvidence :~ elementCopyEvidence :~ Done)
  Used targetPayload targetUseEvidence <- use targetProbe
  Used elementPayload elementUseEvidence <- use elementProbe
  Computed match matchEvidence <-
    compute (sameValue <$> targetPayload <*> elementPayload)
  explain
    Compare
    (targetUseEvidence :~ elementUseEvidence :~ matchEvidence :~ Done)
  decision <-
    decide
      (\payload ->
         case payload of
           LBool answer -> answer)
      match
  case decision of
    DecidedTrue foundEvidence -> do
      explain Found (foundEvidence :~ Done)
      return (IsMatch targetAfter elementAfter)
    DecidedFalse notThisEvidence -> do
      explain NotThisOne (notThisEvidence :~ Done)
      return (IsNotMatch targetAfter elementAfter)

discardChecked :: Block Value %1 -> TraceBuilder Events ()
discardChecked element = do
  Destroyed elementEvidence <- destroy element
  explain DiscardChecked (elementEvidence :~ Done)

finishFound :: Block Value %1 -> Block Value %1 -> TraceBuilder Events ()
finishFound target element = do
  Destroyed targetEvidence <- destroy target
  Destroyed elementEvidence <- destroy element
  explain FinishFound (targetEvidence :~ elementEvidence :~ Done)

discardRemaining :: Elements %1 -> TraceBuilder Events ()
discardRemaining elements =
  case elements of
    NoElements -> return ()
    MoreElement element rest -> do
      Destroyed elementEvidence <- destroy element
      explain DiscardRemaining (elementEvidence :~ Done)
      discardRemaining rest

--------------------------------------------------------------------------------
-- Printing
--------------------------------------------------------------------------------
instance PrintEvent CreateTarget where
  printEvent event =
    case event of
      CreateTarget -> "Create target"

instance PrintEvent CreateElement where
  printEvent event =
    case event of
      CreateElement -> "Create element"

instance PrintEvent Compare where
  printEvent event =
    case event of
      Compare -> "Compare"

instance PrintEvent PrepareCompare where
  printEvent event =
    case event of
      PrepareCompare -> "Prepare compare"

instance PrintEvent Found where
  printEvent event =
    case event of
      Found -> "Found"

instance PrintEvent NotThisOne where
  printEvent event =
    case event of
      NotThisOne -> "Not this one"

instance PrintEvent DiscardChecked where
  printEvent event =
    case event of
      DiscardChecked -> "Discard checked"

instance PrintEvent FinishFound where
  printEvent event =
    case event of
      FinishFound -> "Finish found"

instance PrintEvent DiscardRemaining where
  printEvent event =
    case event of
      DiscardRemaining -> "Discard remaining"

instance PrintEvent SearchExhausted where
  printEvent event =
    case event of
      SearchExhausted -> "Search exhausted"

--------------------------------------------------------------------------------
-- View constants
--------------------------------------------------------------------------------
layoutCanvasWidth :: LayoutExpr
layoutCanvasWidth = num 800

layoutCanvasHeight :: LayoutExpr
layoutCanvasHeight = num 600

layoutAvailableWidthValue :: Double
layoutAvailableWidthValue = 760

layoutMaxCellValue :: Double
layoutMaxCellValue = 88

layoutMaxGapValue :: Double
layoutMaxGapValue = 24

layoutAvailableWidth :: LayoutExpr
layoutAvailableWidth = num layoutAvailableWidthValue

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
layoutMaxCell = num layoutMaxCellValue

layoutLargeMinCell :: LayoutExpr
layoutLargeMinCell = layoutMaxCell @*@ (num 0.86 :: LayoutExpr)

layoutMinCell :: LayoutExpr
layoutMinCell = num 10

layoutMaxGap :: LayoutExpr
layoutMaxGap = num layoutMaxGapValue

layoutLargeMinGap :: LayoutExpr
layoutLargeMinGap = layoutMaxGap @*@ (num 0.62 :: LayoutExpr)

layoutGapRatio :: LayoutExpr
layoutGapRatio = num 0.16

layoutUsesMaxSize :: Bool
layoutUsesMaxSize = layoutMaxSizedRowWidthValue <= layoutAvailableWidthValue

layoutElementCountValue :: Int
layoutElementCountValue =
  case exampleElementCount <= 0 of
    True  -> 1
    False -> exampleElementCount

layoutGapCountValue :: Int
layoutGapCountValue =
  case exampleElementCount <= 1 of
    True  -> 0
    False -> exampleElementCount - 1

layoutMaxSizedRowWidthValue :: Double
layoutMaxSizedRowWidthValue =
  (fromIntegral layoutElementCountValue * layoutMaxCellValue)
    + (fromIntegral layoutGapCountValue * layoutMaxGapValue)

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

layoutStep :: LayoutExpr
layoutStep = layoutCell @+@ layoutGap

layoutProbeSize :: LayoutExpr
layoutProbeSize = layoutCell @*@ (num 1.22 :: LayoutExpr)

layoutProbeGap :: LayoutExpr
layoutProbeGap = layoutProbeSize @*@ (num 0.36 :: LayoutExpr)

targetProbeLeft :: LayoutExpr
targetProbeLeft =
  layoutStageCenter @-@ layoutProbeSize @-@ (layoutProbeGap @/@ (num 2 :: LayoutExpr))

elementProbeLeft :: LayoutExpr
elementProbeLeft = layoutStageCenter @+@ (layoutProbeGap @/@ (num 2 :: LayoutExpr))

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
matchWidth = (layoutCell @*@ (num 1.88 :: LayoutExpr)) @+@ (num 28 :: LayoutExpr)

matchHeight :: LayoutExpr
matchHeight = layoutCell @*@ (num 0.68 :: LayoutExpr)

matchFontSize :: LayoutExpr
matchFontSize = matchHeight @*@ (num 0.38 :: LayoutExpr)

matchGap :: LayoutExpr
matchGap = layoutCell @*@ (num 0.42 :: LayoutExpr)

constrainSearchLayout :: ViewBuilder events ()
constrainSearchLayout = do
  ensure ((layoutCanvasWidth @*@ (num 0.43 :: LayoutExpr)) @<=@ layoutStageCenter)
  ensure (layoutStageCenter @<=@ (layoutCanvasWidth @*@ (num 0.57 :: LayoutExpr)))
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
  ensure
    (layoutRowWidth
       @==@ ((layoutElementCount @*@ layoutCell)
               @+@ (layoutGapCount @*@ layoutGap)))
  ensure
    (layoutRowLeft
       @+@ (layoutRowWidth @/@ (num 2 :: LayoutExpr))
       @==@ layoutStageCenter)
  ensure (layoutHorizontalInset @<=@ layoutRowLeft)
  ensure (layoutRowLeft @+@ layoutRowWidth @<=@ layoutRightInset)
  ensure (layoutTargetTop @+@ layoutCell @<=@ layoutProbeTop)
  ensure (layoutProbeTop @+@ layoutProbeSize @<=@ layoutMatchTop)
  ensure (layoutMatchTop @+@ matchHeight @<=@ layoutListTop)
  ensure (layoutListTop @+@ layoutCell @<=@ layoutCanvasHeight)
  ensure (layoutHorizontalInset @<=@ targetProbeLeft)
  ensure (elementProbeLeft @+@ layoutProbeSize @<=@ layoutRightInset)
  case layoutUsesMaxSize of
    True -> do
      ensure (layoutLargeMinCell @<=@ layoutCell)
      case exampleElementCount <= 1 of
        True  -> ensure (layoutGap @==@ (num 0 :: LayoutExpr))
        False -> ensure (layoutLargeMinGap @<=@ layoutGap)
    False -> do
      ensure (layoutGap @==@ layoutCell @*@ layoutGapRatio)
      ensure (layoutRowWidth @==@ layoutAvailableWidth)

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
     BlockRef Value
  -> LiveVisual Value
     %1 -> ViewBuilder events (BoxVisual Value)
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
     BlockRef Value
  -> LiveVisual Value
     %1 -> ViewBuilder events (BoxVisual Value)
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
     BlockRef Value
  -> LiveVisual Value
     %1 -> ViewBuilder events (BoxVisual Value)
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
     BlockRef Match
  -> LiveVisual Match
     %1 -> ViewBuilder events (SizeVisual Match)
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

--------------------------------------------------------------------------------
-- View events
--------------------------------------------------------------------------------
instance ViewEvent CreateTarget where
  viewEvent event tokens =
    case event of
      CreateTarget ->
        case tokens of
          VCons targetToken VNil -> do
            target <- createVisual targetToken
            renderedTarget <- fresh valueViewDefinition target
            complete renderedTarget

instance ViewEvent CreateElement where
  viewEvent event tokens =
    case event of
      CreateElement ->
        case tokens of
          VCons elementToken VNil -> do
            element <- createVisual elementToken
            renderedElement <- fresh valueViewDefinition element
            complete renderedElement

instance ViewEvent PrepareCompare where
  viewEvent event tokens =
    case event of
      PrepareCompare ->
        case tokens of
          VCons targetToken (VCons elementToken VNil) -> do
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

instance ViewEvent Compare where
  viewEvent event tokens =
    case event of
      Compare ->
        case tokens of
          VCons targetToken (VCons elementToken (VCons matchToken VNil)) -> do
            target <- useVisual targetToken
            element <- useVisual elementToken
            match <- computeVisual matchToken
            renderedMatch <- fresh matchViewDefinition match
            LayoutUse renderedMatch1 matchCenterX <- takeCenterX renderedMatch
            LayoutUse renderedMatch2 matchTop <- takeTop renderedMatch1
            LayoutUse element1 elementBottom <- takeBottom element
            ensure (matchCenterX @==@ layoutStageCenter)
            ensure (matchTop @==@ elementBottom @+@ matchGap)
            checkpoint
            remove target
            remove element1
            complete renderedMatch2

instance ViewEvent Found where
  viewEvent event tokens =
    case event of
      Found ->
        case tokens of
          VCons matchToken VNil -> do
            match <- decideVisual matchToken
            remove match

instance ViewEvent NotThisOne where
  viewEvent event tokens =
    case event of
      NotThisOne ->
        case tokens of
          VCons matchToken VNil -> do
            match <- decideVisual matchToken
            remove match

instance ViewEvent DiscardChecked where
  viewEvent event tokens =
    case event of
      DiscardChecked ->
        case tokens of
          VCons elementToken VNil -> do
            element <- destroyVisual elementToken
            remove element

instance ViewEvent FinishFound where
  viewEvent event tokens =
    case event of
      FinishFound ->
        case tokens of
          VCons targetToken (VCons elementToken VNil) -> do
            target <- destroyVisual targetToken
            element <- destroyVisual elementToken
            remove target
            remove element

instance ViewEvent DiscardRemaining where
  viewEvent event tokens =
    case event of
      DiscardRemaining ->
        case tokens of
          VCons elementToken VNil -> do
            element <- destroyVisual elementToken
            remove element

instance ViewEvent SearchExhausted where
  viewEvent event tokens =
    case event of
      SearchExhausted ->
        case tokens of
          VCons targetToken VNil -> do
            target <- destroyVisual targetToken
            remove target
