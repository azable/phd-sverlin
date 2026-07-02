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
    7
    (MoreExampleValue
       4
       (MoreExampleValue
          9
          (MoreExampleValue
             2
             (MoreExampleValue 7 (MoreExampleValue 1 NoExampleValues)))))

example :: Choreography ()
example = linearSearch (searchInput exampleSpec)

run :: Choreography () -> VisualTraceGraph
run = runChoreographyWith visualization

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

data ProcessedElements where
  NoProcessedElements :: ProcessedElements
  MoreProcessedElement
    :: Block Value %1 -> ProcessedElements %1 -> ProcessedElements

data SearchState where
  SearchState
    :: Block Value %1 -> ProcessedElements %1 -> Elements %1 -> SearchState

data PreparedComparison where
  PreparedComparison
    :: Block Value
       %1 -> Block Value
       %1 -> Block Value
       %1 -> Block Value
       %1 -> Explain (Copy Value)
       %1 -> Explain (Copy Value)
       %1 -> PreparedComparison

data ComparedValues where
  ValuesMatched
    :: Explain (Create EqualValue)
       %1 -> Explain (Apply2 EqualValue Value Value Match)
       %1 -> Explain (Use Match)
       %1 -> ComparedValues
  ValuesDifferent
    :: Explain (Create EqualValue)
       %1 -> Explain (Apply2 EqualValue Value Value Match)
       %1 -> Explain (Use Match)
       %1 -> ComparedValues

data MarkedProcessed where
  MarkedProcessed
    :: Block Value
       %1 -> Explain (Copy Value)
       %1 -> Explain (Replace Value)
       %1 -> MarkedProcessed

linearSearch :: SearchInput %1 -> Choreography ()
linearSearch (SearchInput targetPayload valuePayloads) = do
  Created target targetCreated <- create (#target <&> #source) targetPayload
  checkpoint "Create target" (targetCreated :~ Done)
  elements <- createElements valuePayloads
  searchIteration (SearchState target NoProcessedElements elements)

createElements :: InputValues %1 -> Choreography Elements
createElements = createElementsFrom 0

createElementsFrom :: Int -> InputValues %1 -> Choreography Elements
createElementsFrom index inputs =
  case inputs of
    NoInputValues -> return NoElements
    MoreInputValue valuePayload rest -> do
      Created element elementCreated <-
        create (#array <&> #index index) valuePayload
      checkpoint "Create element" (elementCreated :~ Done)
      elements <- createElementsFrom (index + 1) rest
      return (MoreElement index element elements)

searchIteration :: SearchState %1 -> Choreography ()
searchIteration searchState =
  case searchState of
    SearchState target processed elements ->
      case elements of
        NoElements -> do
          Destroyed targetDestroyed <- destroy target
          checkpoint "Search exhausted" (targetDestroyed :~ Done)
          destroyProcessed "Search exhausted" processed
        MoreElement index element rest -> do
          PreparedComparison targetAfter elementAfter targetProbe elementProbe targetCopy elementCopy <-
            prepareComparison target index element
          checkpoint "Prepare comparison" (targetCopy :~ elementCopy :~ Done)
          comparison <- compareValues targetProbe elementProbe
          case comparison of
            ValuesMatched equalCreated matchApplied matchUse -> do
              checkpoint
                "Found target"
                (equalCreated :~ matchApplied :~ matchUse :~ Done)
              finishSearch targetAfter elementAfter processed rest
            ValuesDifferent equalCreated matchApplied matchUse -> do
              MarkedProcessed processedElement processedCopy processedReplace <-
                markProcessed index elementAfter
              checkpoint
                "Not this element"
                (equalCreated
                   :~ matchApplied
                   :~ matchUse
                   :~ processedCopy
                   :~ processedReplace
                   :~ Done)
              searchIteration
                (SearchState
                   targetAfter
                   (MoreProcessedElement processedElement processed)
                   rest)

destroyProcessed :: String -> ProcessedElements %1 -> Choreography ()
destroyProcessed label processed =
  case processed of
    NoProcessedElements -> return ()
    MoreProcessedElement element rest -> do
      Destroyed elementDestroyed <- destroy element
      checkpoint label (elementDestroyed :~ Done)
      destroyProcessed label rest

destroyRemaining :: String -> Elements %1 -> Choreography ()
destroyRemaining label elements =
  case elements of
    NoElements -> return ()
    MoreElement _ element rest -> do
      Destroyed elementDestroyed <- destroy element
      checkpoint label (elementDestroyed :~ Done)
      destroyRemaining label rest

finishSearch ::
     Block Value
     %1 -> Block Value
     %1 -> ProcessedElements
     %1 -> Elements
     %1 -> Choreography ()
finishSearch target foundElement processed remaining = do
  Destroyed targetDestroyed <- destroy target
  checkpoint "Search complete" (targetDestroyed :~ Done)
  Destroyed foundDestroyed <- destroy foundElement
  checkpoint "Search complete" (foundDestroyed :~ Done)
  destroyProcessed "Search complete" processed
  destroyRemaining "Search complete" remaining

markProcessed :: Int -> Block Value %1 -> Choreography MarkedProcessed
markProcessed index element = do
  Copied original processedCopy copyToken <-
    copy (#array <&> #processed <&> #index index) element
  Replaced processedElement replaceToken <- replace original processedCopy
  return (MarkedProcessed processedElement copyToken replaceToken)

prepareComparison ::
     Block Value %1 -> Int -> Block Value %1 -> Choreography PreparedComparison
prepareComparison target index element = do
  Copied targetAfter targetProbe targetCopy <- copy (#target <&> #probe) target
  Copied elementAfter elementProbe elementCopy <-
    copy (#index index <&> #probe) element
  return
    (PreparedComparison
       targetAfter
       elementAfter
       targetProbe
       elementProbe
       targetCopy
       elementCopy)

compareValues :: Block Value %1 -> Block Value %1 -> Choreography ComparedValues
compareValues targetProbe elementProbe = do
  Created equalOp equalCreated <-
    create @EqualValue #operator (LOperator EqualValue)
  Applied2 matchBlock matchApplied <-
    apply2 #result equalOp targetProbe elementProbe
  Used matchPayload matchUse <- use matchBlock
  case matchPayload of
    OneUse (LBool answer) ->
      case answer of
        True  -> return (ValuesMatched equalCreated matchApplied matchUse)
        False -> return (ValuesDifferent equalCreated matchApplied matchUse)

--------------------------------------------------------------------------------
-- Visualisation
--------------------------------------------------------------------------------
visualization :: MatchSpec
visualization =
  visualize $ do
    -- Geometry uses relative relationships only; the view layer already keeps
    -- every node on-canvas, so the solver can vary placement between runs.
    Variable cell <- variable @Span
    -- Keep cells in a useful range and softly prefer the larger end while
    -- still leaving some seed-driven variation in the solved layout.
    ensure $ cell .>=. by 80
    ensure $ cell .<=. by 104
    encourage $ cell .>=. by 96
    Variable gap <- variable @Span
    ensure $ gap .>=. by 8
    ensure $ gap .<=. by 16
    encourage $ gap .>=. by 12
    Variable probeSize <- variableFrom @Span (cell * 1.08)
    Variable targetSize <- variable @Span
    ensure $ targetSize .>=. by 80
    ensure $ targetSize .<=. by 208
    ensure $ targetSize .>=. cell
    ensure $ targetSize .<=. cell * (2 :: Scalar)
    Variable valueHue <- variable @Angle
    Bound v <- bindContent
    Bound i <- bindInt
    -- Every value has the same visual representation. Probe copies only scale
    -- this base shape up slightly while they are being compared.
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
    -- Target row: a source value that anchors the rest of the layout.
    Selected targetSource <- select @Value (#target <&> #source)
    render targetSource $ do
      width targetSize
      height targetSize
      style @FontSize (targetSize * 0.44)
      style @StrokeWidth (by 6)
    -- Probe row: the copied target and current array element sit side by side.
    Selected targetProbe <- select @Value (#target <&> #probe)
    Selected probe <- select @Value #probe
    Selected probes <- node probe
    Selected probeItem <- select @Value (#probe <&> #index @: i)
    render probe $ do
      style @ZIndex 3
      width probeSize
      height probeSize
    -- Result row: a compact badge records the branch decision.
    Variable resultWidth <- variableFrom @Span (probeSize * 2 |+| gap)
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
    -- Array row: unprocessed values stay prominent; consumed values recede.
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
      style @Stroke arrayBackground
    Selected processedItem <- select @AnyPayload #processed
    let processedColor :: Color
        processedColor = Hsl valueHue 0.16 0.78
    render processedItem $ do
      style @Fill processedColor
      style @Stroke processedColor
    -- Hard constraints define structure. Rows are linked by gap and centered
    -- together as a group so seed variation can move the whole cluster.
    -- Rows are ordered by minimum gaps, leaving vertical slack free.
    ensure $ bottom targetSource =| gap |= top probes
    ensure $ bottom probes =| gap |= top result
    ensure $ bottom result =| gap |= top array
    ensure $ x targetSource .==. x array
    ensure $ x probes .==. x targetSource
    ensure $ x result .==. x targetSource
    -- Containers describe row membership; children can spread horizontally.
    ensure $ y probe .==. y probes
    ensure $ y arrayItem .==. y array
    ensure $ right targetProbe =| gap |= left probeItem
    ensure $ right arrayItem =| gap |= left nextArrayItem
