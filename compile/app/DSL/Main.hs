{-# LANGUAGE ConstraintKinds         #-}
{-# LANGUAGE DataKinds               #-}
{-# LANGUAGE FlexibleContexts        #-}
{-# LANGUAGE FlexibleInstances       #-}
{-# LANGUAGE GADTs                   #-}
{-# LANGUAGE LinearTypes             #-}
{-# LANGUAGE NoImplicitPrelude       #-}
{-# LANGUAGE OverloadedLabels        #-}
{-# LANGUAGE OverloadedStrings       #-}
{-# LANGUAGE RebindableSyntax        #-}
{-# LANGUAGE TypeApplications        #-}
{-# LANGUAGE TypeFamilies            #-}
{-# LANGUAGE UndecidableInstances    #-}
{-# LANGUAGE UndecidableSuperClasses #-}

-- | Current editable choreography example used by the compile executable. It
-- depends only on the public 'LinearTrace.Choreography' DSL and returns the
-- graph consumed by 'App'.
module DSL.Main
  ( -- * Example program
    -- | Linear-search example program kept as the current app-shaped
    -- visualization fixture.
    example
  , -- * Runner
    -- | Convert an example program into the visual trace graph expected by the
    -- executable workflow.
    run
  ) where

import           Control.Functor.Linear   hiding (ask, (<$>), (<&>), (<*>))
import           LinearTrace.Choreography
import           Prelude.Linear           hiding (fromInteger, fromRational,
                                           (*), (+), (-), (/), (/=), (<>), (==))
import qualified Prelude.Linear           as Linear

--------------------------------------------------------------------------------
-- Payload tags
--------------------------------------------------------------------------------
data Value

type instance Payload Value = LInt Value

data Match

type instance Payload Match = LBool Match

data EqualValue =
  EqualValue

type instance Payload EqualValue = LOperator EqualValue EqualValue

instance CoreOperator EqualValue where
  operatorPayloadText EqualValue = "=="
  persistOperatorPayload EqualValue = Ur EqualValue

instance Applicable2 EqualValue Value Value where
  type Apply2Result EqualValue Value Value = Match
  applyPayload2 (LOperator EqualValue) = applyLinear2Into (Linear.==)

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
    1
    (MoreExampleValue
       4
       (MoreExampleValue
          9
          (MoreExampleValue
             2
             (MoreExampleValue
                7
                (MoreExampleValue
                   1
                   (MoreExampleValue 6 NoExampleValues))))))

example :: Choreography ()
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
  MoreElement :: Int -> Block Value %1 -> Elements %1 -> Elements

data SearchResult where
  SearchResult :: Block Value %1 -> Elements %1 -> SearchResult

data PreparedComparison where
  PreparedComparison
    :: Block Value
       %1 -> Block Value
       %1 -> Block Value
       %1 -> Block Value
       %1 -> PreparedComparison

data ComparedValues where
  ValuesMatched :: ComparedValues
  ValuesDifferent :: ComparedValues

linearSearch :: SearchInput %1 -> Choreography ()
linearSearch (SearchInput targetPayload valuePayloads) = do
  Create targetPending <- create targetPayload
  target <- materialize (#target <&> #source) targetPending
  checkpoint "Create target"
  elements <- createElements valuePayloads
  SearchResult targetAfter searchedElements <- searchIteration target elements
  destroySearchResult targetAfter searchedElements

createElements :: InputValues %1 -> Choreography Elements
createElements = createElementsFrom 0

createElementsFrom :: Int -> InputValues %1 -> Choreography Elements
createElementsFrom index inputs =
  case inputs of
    NoInputValues -> return NoElements
    MoreInputValue valuePayload rest -> do
      Create elementPending <- create valuePayload
      element <- materialize (#array <&> #index index) elementPending
      checkpoint "Create element"
      elements <- createElementsFrom (index + 1) rest
      return (MoreElement index element elements)

searchIteration :: Block Value %1 -> Elements %1 -> Choreography SearchResult
searchIteration target elements =
  case elements of
    NoElements -> do
      checkpoint "Search exhausted"
      return (SearchResult target NoElements)
    MoreElement index element rest -> do
      PreparedComparison targetAfter elementAfter targetProbe elementProbe <-
        prepareComparison target index element
      checkpoint "Prepare comparison"
      comparison <- compareValues targetProbe elementProbe
      case comparison of
        ValuesMatched -> do
          checkpoint "Found target"
          return
            (SearchResult targetAfter (MoreElement index elementAfter rest))
        ValuesDifferent -> do
          processedElement <- markProcessed index elementAfter
          checkpoint "Not this element"
          SearchResult finalTarget finalRest <- searchIteration targetAfter rest
          return
            (SearchResult
               finalTarget
               (MoreElement index processedElement finalRest))

destroySearchResult :: Block Value %1 -> Elements %1 -> Choreography ()
destroySearchResult target elements = do
  Destroy <- destroy target
  destroyElements elements
  checkpoint "Search complete"

destroyElements :: Elements %1 -> Choreography ()
destroyElements elements =
  case elements of
    NoElements -> return ()
    MoreElement _ element rest -> do
      Destroy <- destroy element
      destroyElements rest

markProcessed :: Int -> Block Value %1 -> Choreography (Block Value)
markProcessed index element = do
  Copy original processedPending <- copy element
  Replace processedPending' <- replace original processedPending
  materialize (#array <&> #processed <&> #index index) processedPending'

prepareComparison ::
     Block Value %1 -> Int -> Block Value %1 -> Choreography PreparedComparison
prepareComparison target index element = do
  Copy targetAfter targetProbePending <- copy target
  targetProbe <- materialize (#target <&> #probe) targetProbePending
  Copy elementOriginal currentPending <- copy element
  Replace currentPending' <- replace elementOriginal currentPending
  currentElement <-
    materialize (#array <&> #current <&> #index index) currentPending'
  Copy elementAfter elementProbePending <- copy currentElement
  elementProbe <- materialize (#index index <&> #probe) elementProbePending
  return (PreparedComparison targetAfter elementAfter targetProbe elementProbe)

compareValues :: Block Value %1 -> Block Value %1 -> Choreography ComparedValues
compareValues targetProbe elementProbe = do
  Create equalPending <- create @EqualValue (LOperator EqualValue)
  equalOp <- materialize #operator equalPending
  Apply2 matchPending <- apply2 equalOp targetProbe elementProbe
  matchBlock <- materialize #result matchPending
  Use matchPayload <- use matchBlock
  case matchPayload of
    OneUse (LBool answer) ->
      case answer of
        True  -> return ValuesMatched
        False -> return ValuesDifferent

--------------------------------------------------------------------------------
-- Visualisation
--------------------------------------------------------------------------------
run :: Choreography () -> VisualTraceGraph
run =
  runChoreographyWith
    $ visualize $ do
    -- Geometry uses relative relationships only; the view layer already keeps
    -- every node on-canvas, so the solver can vary placement between runs.
    Variable cell <- variable @Span
    -- Keep cells in a useful range and softly prefer the larger end while
    -- still leaving some seed-driven variation in the solved layout.
    ensure $ cell .>=. by 56
    ensure $ cell .<=. by 76
    encourage $ cell .>=. by 68
    Variable gap <- variable @Span
    ensure $ gap .>=. by 8
    ensure $ gap .<=. by 16
    encourage $ gap .>=. by 12
    Variable horizontalCenter <- variable @Coord
    Variable targetSize <- variable @Span
    ensure $ targetSize .>=. by 80
    ensure $ targetSize .<=. by 208
    ensure $ targetSize .>=. cell
    ensure $ targetSize .<=. cell * (2 :: Scalar)
    let valueHue = 214
    Bound v <- bindContent
    Bound i <- bindInt
    -- Every value has the same visual representation. Comparison copies remain
    -- in the linear trace but are hidden in favor of highlighting the current
    -- array element directly.
    Variable ff <- choice @FontFamily
    Selected valueContent <- select @Value (payload v)
    let valueRadius = cell * 0.12
    render valueContent $ do
      content v
      style @TextAlign (FixedStyle TextAlignCenter)
      style @FontFamily (VariableStyle ff)
      style @Fill (Hsl valueHue 0.24 0.9)
      style @Stroke (Hsl valueHue 0.46 0.34)
      style @StrokeWidth (by 3)
      style @Padding (cell * 0.08)
      style @Radius valueRadius
      style @FontSize (cell * 0.44)
      style @ZIndex 2
      width cell
      height cell
    Selected comparisonProbe <- select @Value #probe
    render comparisonProbe $ do
      style @Opacity 0
    -- Target row: a source value that anchors the rest of the layout.
    Selected targetSource <- select @Value (#target <&> #source)
    render targetSource $ do
      width targetSize
      height targetSize
      style @FontSize (targetSize * 0.44)
      style @StrokeWidth (by 6)
    -- Result row: a compact badge records the branch decision.
    Variable resultWidth <- variableFrom @Span (cell * 2 |+| gap)
    Variable resultHeight <- variableFrom @Span (cell * 0.68)
    Selected result <- select @Match #result
    Selected resultTrue <- select @Match (#result <&> payload True)
    Selected resultFalse <- select @Match (#result <&> payload False)
    render result $ do
      style @TextAlign (FixedStyle TextAlignCenter)
      style @Fill (Hsl 214 0.06 0.94)
      style @Stroke (Hsl 214 0.12 0.52)
      style @StrokeWidth (cell * 0.035)
      style @Padding (cell * 0.05)
      style @ZIndex 4
      style @Radius (cell * 0.14)
      style @FontSize (cell * 0.26)
      width resultWidth
      height resultHeight
    render resultTrue $ do
      content "MATCH"
      style @Fill (Hsl 142 0.52 0.84)
      style @Stroke (Hsl 142 0.72 0.32)
    render resultFalse $ do
      content "NO MATCH"
      style @Fill (Hsl 8 0.44 0.9)
      style @Stroke (Hsl 8 0.62 0.38)
    -- Array row: unprocessed values stay prominent, the current value receives
    -- a strong border, and previously considered values recede.
    Selected arrayItems <- select @Value #array
    Selected array <- node arrayItems
    Selected arrayItem <- select @Value (#array <&> #index @: i)
    Selected nextArrayItem <- select @Value (#array <&> #index @: (i + 1))
    let arrayBackground = Hsl valueHue 0.14 0.95
    render array $ do
      style @ZIndex 0
      style @Padding gap
      style @Radius (valueRadius * 1.3)
      style @Fill arrayBackground
      style @Stroke (Hsl 0 0 0)
      style @StrokeWidth (by 3)
    Selected currentItem <- select @Value (#array <&> #current)
    render currentItem $ do
      style @Stroke (Hsl 32 0.88 0.42)
      style @StrokeWidth (by 7)
      style @ZIndex 3
    Selected processedItem <- select @AnyPayload #processed
    let processedColor :: Color
        processedColor = Hsl valueHue 0.16 0.78
    render processedItem $ do
      style @Fill processedColor
      style @Stroke processedColor
    -- Rows share one horizontal center. Comparison copies do not participate in
    -- the visible layout.
    ensure $ bottom targetSource =| gap |= top result
    ensure $ bottom result =| gap |= top array
    ensure $ x targetSource .==. horizontalCenter
    ensure $ x result .==. horizontalCenter
    ensure $ x array .==. horizontalCenter
    -- The array container describes row membership; children spread
    -- horizontally in index order.
    ensure $ y arrayItem .==. y array
    ensure $ right arrayItem =| gap |= left nextArrayItem
