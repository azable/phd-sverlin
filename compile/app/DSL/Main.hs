{-# LANGUAGE ConstraintKinds        #-}
{-# LANGUAGE DataKinds              #-}
{-# LANGUAGE FlexibleContexts       #-}
{-# LANGUAGE FlexibleInstances      #-}
{-# LANGUAGE GADTs                  #-}
{-# LANGUAGE LinearTypes            #-}
{-# LANGUAGE NoImplicitPrelude      #-}
{-# LANGUAGE RebindableSyntax       #-}
{-# LANGUAGE TypeFamilies           #-}
{-# LANGUAGE TypeOperators          #-}
{-# LANGUAGE UndecidableInstances   #-}
{-# LANGUAGE UndecidableSuperClasses #-}

module DSL.Main
  ( example
  , run
  ) where

import           LinearTrace.Core
import           LinearTrace.Print (PrintEvent(..))
import           LinearTrace.View
import           Control.Functor.Linear hiding (ask, (<$>), (<*>))
import           Prelude.Linear

--------------------------------------------------------------------------------
-- Payload tags
--------------------------------------------------------------------------------

data Value

type instance Payload Value = LInt Value

instance Traceable Value

data Match

type instance Payload Match = LBool Match

instance Traceable Match

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
    MoreExampleValue value rest -> MoreInputValue (LInt value) (inputValues rest)

exampleElementCount :: Int
exampleElementCount =
  case exampleSpec of
    ExampleSpec _ values -> countExampleValues values

countExampleValues :: ExampleValues -> Int
countExampleValues values =
  case values of
    NoExampleValues -> 0
    MoreExampleValue _ rest -> 1 + countExampleValues rest

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

data CreateTarget =
  CreateTarget

type instance Actions CreateTarget = '[Create Value]

data CreateElement =
  CreateElement

type instance Actions CreateElement = '[Create Value]

data Compare =
  Compare

type instance Actions Compare = '[Inspect Value, Inspect Value, Compute Match]

data Found =
  Found

type instance Actions Found = '[Decide Match]

data NotThisOne =
  NotThisOne

type instance Actions NotThisOne = '[Decide Match]

data DiscardChecked =
  DiscardChecked

type instance Actions DiscardChecked = '[Destroy Value]

data FinishFound =
  FinishFound

type instance Actions FinishFound = '[Destroy Value, Destroy Value]

data DiscardRemaining =
  DiscardRemaining

type instance Actions DiscardRemaining = '[Destroy Value]

data SearchExhausted =
  SearchExhausted

type instance Actions SearchExhausted = '[Destroy Value]

type Events =
  '[ CreateTarget
   , CreateElement
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
     Block Value
     %1 -> Block Value
     %1 -> TraceBuilder Events Comparison
compareElement target element = do
  Inspected targetAfter targetPayload targetEvidence <- inspect target
  Inspected elementAfter elementPayload elementEvidence <- inspect element
  Computed match matchEvidence <-
    compute (sameValue <$> targetPayload <*> elementPayload)
  explain Compare (targetEvidence :~ elementEvidence :~ matchEvidence :~ Done)
  decision <- decide (\payload -> case payload of LBool answer -> answer) match
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

finishFound ::
     Block Value
     %1 -> Block Value
     %1 -> TraceBuilder Events ()
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

layoutAvailableWidth :: LayoutExpr
layoutAvailableWidth = num 704

layoutTargetTop :: LayoutExpr
layoutTargetTop = num 88

layoutListTop :: LayoutExpr
layoutListTop = num 244

layoutMaxCell :: LayoutExpr
layoutMaxCell = num 58

layoutMinCell :: LayoutExpr
layoutMinCell = num 12

layoutMaxGap :: LayoutExpr
layoutMaxGap = num 12

layoutGapRatio :: LayoutExpr
layoutGapRatio = num 0.16

layoutUsesMaxSize :: Bool
layoutUsesMaxSize = exampleElementCount <= 10

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

layoutCenter :: LayoutExpr
layoutCenter = layoutCanvasWidth @/@ num 2

layoutHorizontalInset :: LayoutExpr
layoutHorizontalInset = (layoutCanvasWidth @-@ layoutAvailableWidth) @/@ num 2

layoutRightInset :: LayoutExpr
layoutRightInset = layoutCanvasWidth @-@ layoutHorizontalInset

valueFontSize :: LayoutExpr
valueFontSize = layoutCell @*@ num 0.34

valueRadius :: LayoutExpr
valueRadius = layoutCell @*@ num 0.11

matchWidth :: LayoutExpr
matchWidth = layoutCell @+@ num 20

matchHeight :: LayoutExpr
matchHeight = layoutCell @*@ num 0.7

matchFontSize :: LayoutExpr
matchFontSize = matchHeight @*@ num 0.42

matchGap :: LayoutExpr
matchGap = layoutCell @*@ num 0.38

constrainSearchLayout :: ViewBuilder events ()
constrainSearchLayout = do
  between layoutMinCell layoutCell layoutMaxCell
  between (num 0) layoutGap layoutMaxGap
  ensure
    (layoutRowWidth @==@
     ((layoutElementCount @*@ layoutCell) @+@
      (layoutGapCount @*@ layoutGap)))
  ensure (layoutRowLeft @+@ (layoutRowWidth @/@ num 2) @==@ layoutCenter)
  ensure (layoutHorizontalInset @<=@ layoutRowLeft)
  ensure (layoutRowLeft @+@ layoutRowWidth @<=@ layoutRightInset)
  case layoutUsesMaxSize of
    True -> do
      ensure (layoutCell @==@ layoutMaxCell)
      case exampleElementCount <= 1 of
        True  -> ensure (layoutGap @==@ num 0)
        False -> ensure (layoutGap @==@ layoutMaxGap)
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
        0 -> layoutCenter @-@ (layoutCell @/@ num 2)
        _ ->
          layoutRowLeft @+@
          (num (fromIntegral (blockId - 1)) @*@ layoutStep)

valueSize :: LayoutExpr
valueSize = layoutCell

valueHeight :: LayoutExpr
valueHeight = valueSize

valueNodeStyle :: Style -> Style
valueNodeStyle base =
  let style1 = setFill (Hsl (num 205) (num 0.2) (num 0.95)) base
      style2 = setStroke (Hsl (num 205) (num 0.5) (num 0.34)) style1
      style3 = setStrokeWidth (num 2) style2
      style4 = setRadius valueRadius style3
      style5 = setFontSize valueFontSize style4
      style6 = setFontFamily "ui-monospace, SFMono-Regular, Menlo, monospace" style5
      style7 = setFontWeight FontWeightBold style6
      style8 = setTextAlign TextAlignCenter style7
      style9 = setWhiteSpace WhiteSpaceNoWrap style8
   in setCssClass "trace-value-block" style9

matchNodeStyle :: Style -> Style
matchNodeStyle base =
  let style1 = setFill (Hsl (num 142) (num 0.38) (num 0.9)) base
      style2 = setStroke (Hsl (num 142) (num 0.48) (num 0.32)) style1
      style3 = setStrokeWidth (num 2) style2
      style4 = setRadius valueRadius style3
      style5 = setFontSize matchFontSize style4
      style6 = setFontFamily "ui-monospace, SFMono-Regular, Menlo, monospace" style5
      style7 = setFontWeight FontWeightBold style6
      style8 = setTextAlign TextAlignCenter style7
      style9 = setWhiteSpace WhiteSpaceNoWrap style8
   in setCssClass "trace-match-block" style9

defineValueNode :: BlockView Value -> ViewBuilder events ()
defineValueNode block = do
  constrainSearchLayout
  ensure (left block @==@ valueLeft (blockRef block))
  ensure (top block @==@ valueTop (blockRef block))
  ensure (width block @==@ valueSize)
  ensure (height block @==@ valueHeight)

defineMatchNode :: BlockView Match -> ViewBuilder events ()
defineMatchNode block = do
  constrainSearchLayout
  ensure (width block @==@ matchWidth)
  ensure (height block @==@ matchHeight)

instance ViewBlock Value where
  styleBlock _ = valueNodeStyle
  viewBlock = defineValueNode

instance ViewBlock Match where
  styleBlock _ = matchNodeStyle
  viewBlock = defineMatchNode

--------------------------------------------------------------------------------
-- View events
--------------------------------------------------------------------------------

instance ViewEvent CreateTarget where
  viewEvent event tokens =
    case event of
      CreateTarget ->
        case tokens of
          VCons targetToken VNil -> do
            Ur target <- createVisual targetToken
            Ur renderedTarget <- fresh target
            discard renderedTarget

instance ViewEvent CreateElement where
  viewEvent event tokens =
    case event of
      CreateElement ->
        case tokens of
          VCons elementToken VNil -> do
            Ur element <- createVisual elementToken
            Ur renderedElement <- fresh element
            discard renderedElement

instance ViewEvent Compare where
  viewEvent event tokens =
    case event of
      Compare ->
        case tokens of
          VCons targetToken (VCons elementToken (VCons matchToken VNil)) -> do
            Ur target <- inspectVisual targetToken
            Ur element <- inspectVisual elementToken
            Ur match <- computeVisual matchToken
            Ur renderedMatch <- fresh match
            ensure (centerX renderedMatch @==@ centerX element)
            ensure (top renderedMatch @==@ bottom element @+@ matchGap)
            discard target
            discard element
            discard renderedMatch

instance ViewEvent Found where
  viewEvent event tokens =
    case event of
      Found ->
        case tokens of
          VCons matchToken VNil -> do
            Ur match <- decideVisual matchToken
            discard match

instance ViewEvent NotThisOne where
  viewEvent event tokens =
    case event of
      NotThisOne ->
        case tokens of
          VCons matchToken VNil -> do
            Ur match <- decideVisual matchToken
            remove match

instance ViewEvent DiscardChecked where
  viewEvent event tokens =
    case event of
      DiscardChecked ->
        case tokens of
          VCons elementToken VNil -> do
            Ur element <- destroyVisual elementToken
            remove element

instance ViewEvent FinishFound where
  viewEvent event tokens =
    case event of
      FinishFound ->
        case tokens of
          VCons targetToken (VCons elementToken VNil) -> do
            Ur target <- destroyVisual targetToken
            Ur element <- destroyVisual elementToken
            discard target
            discard element

instance ViewEvent DiscardRemaining where
  viewEvent event tokens =
    case event of
      DiscardRemaining ->
        case tokens of
          VCons elementToken VNil -> do
            Ur element <- destroyVisual elementToken
            remove element

instance ViewEvent SearchExhausted where
  viewEvent event tokens =
    case event of
      SearchExhausted ->
        case tokens of
          VCons targetToken VNil -> do
            Ur target <- destroyVisual targetToken
            discard target
