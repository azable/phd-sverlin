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

module DSL.Main
  ( example
  , run
  ) where

import           Control.Functor.Linear   hiding (ask, (<$>), (<&>), (<*>))
import           LinearTrace.Choreography
import           Prelude.Linear           hiding (fromInteger, fromRational,
                                           (*), (+), (-), (/), (/=), (<>))

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

example :: Program ()
example = linearSearch (searchInput exampleSpec)

run :: Program () -> VisualTraceGraph
run = runProgramWith visualization

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
       %1 -> PreparedComparison

linearSearch :: SearchInput %1 -> Program ()
linearSearch (SearchInput targetPayload valuePayloads) = do
  target <- create (#target <&> #source) targetPayload
  elements <- createElements valuePayloads
  loop (SearchState target NoProcessedElements elements) searchIteration

createElements :: InputValues %1 -> Program Elements
createElements = createElementsFrom 0

createElementsFrom :: Int -> InputValues %1 -> Program Elements
createElementsFrom index inputs =
  case inputs of
    NoInputValues -> return NoElements
    MoreInputValue valuePayload rest -> do
      element <- create (#array <&> #index index) valuePayload
      elements <- createElementsFrom (index + 1) rest
      return (MoreElement index element elements)

searchIteration :: SearchState %1 -> Program (LoopResult SearchState ())
searchIteration searchState =
  case searchState of
    SearchState target processed elements ->
      case elements of
        NoElements -> do
          destroy target
          destroyProcessed processed
          checkpoint "Search exhausted"
          return (Finish ())
        MoreElement index element rest -> do
          PreparedComparison targetAfter elementAfter targetProbe elementProbe <-
            prepareComparison target index element
          checkpoint "Prepare comparison"
          matchBlock <- compareValues targetProbe elementProbe
          branch <- decide (\(LBool answer) -> answer) matchBlock
          case branch of
            BranchTrue -> do
              checkpoint "Found target"
              finishSearch targetAfter elementAfter processed rest
              checkpoint "Search complete"
              return (Finish ())
            BranchFalse -> do
              processedElement <- markProcessed index elementAfter
              checkpoint "Not this element"
              return
                (Continue
                   (SearchState
                      targetAfter
                      (MoreProcessedElement processedElement processed)
                      rest))

destroyProcessed :: ProcessedElements %1 -> Program ()
destroyProcessed processed =
  case processed of
    NoProcessedElements -> return ()
    MoreProcessedElement element rest -> do
      destroy element
      destroyProcessed rest

destroyRemaining :: Elements %1 -> Program ()
destroyRemaining elements =
  case elements of
    NoElements -> return ()
    MoreElement _ element rest -> do
      destroy element
      destroyRemaining rest

finishSearch ::
     Block Value
     %1 -> Block Value
     %1 -> ProcessedElements
     %1 -> Elements
     %1 -> Program ()
finishSearch target foundElement processed remaining = do
  destroy target
  destroy foundElement
  destroyProcessed processed
  destroyRemaining remaining

markProcessed :: Int -> Block Value %1 -> Program (Block Value)
markProcessed index = retag (#array <&> #processed <&> #index index)

prepareComparison ::
     Block Value %1 -> Int -> Block Value %1 -> Program PreparedComparison
prepareComparison target index element = do
  (targetAfter, targetProbe) <- copy (#target <&> #probe) target
  (elementAfter, elementProbe) <- copy (#index index <&> #probe) element
  return (PreparedComparison targetAfter elementAfter targetProbe elementProbe)

compareValues :: Block Value %1 -> Block Value %1 -> Program (Block Match)
compareValues targetProbe elementProbe = do
  targetPayload <- use targetProbe
  elementPayload <- use elementProbe
  compute #result (sameValue <$> targetPayload <*> elementPayload)

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
    Variable probeSize <- variable @Span (cell * 1.08)
    Variable targetSize <- variable @Span
    ensure $ targetSize .>=. by 80
    ensure $ targetSize .<=. by 208
    ensure $ targetSize .>=. cell
    ensure $ targetSize .<=. cell * (2 :: Scalar)
    Variable valueHue <- variable @Hue
    Bound v <- bindContent
    Bound i <- bindInt
    -- Every value has the same visual representation. Probe copies only scale
    -- this base shape up slightly while they are being compared.
    Selected valueContent <- select @Value (payload v)
    let valueRadius = cell * 0.12
    style valueContent $ do
      content v
      centerText
      fill (Hsl valueHue 0.24 0.9)
      stroke (Hsl valueHue 0.46 0.34)
      strokeWidth (by 3)
      padding (cell * 0.08)
      radius valueRadius
      fontSize (cell * 0.44)
      zIndex 2
      width cell
      height cell
    -- Target row: a source value that anchors the rest of the layout.
    Selected targetSource <- select @Value (#target <&> #source)
    style targetSource $ do
      width targetSize
      height targetSize
      fontSize (targetSize * 0.44)
      strokeWidth (by 6)
    -- Probe row: the copied target and current array element sit side by side.
    Selected targetProbe <- select @Value (#target <&> #probe)
    Selected probe <- select @Value #probe
    Selected probes <- node probe
    Selected probeItem <- select @Value (#probe <&> #index @: i)
    style probe $ do
      zIndex 3
      width probeSize
      height probeSize
    -- Result row: a compact badge records the branch decision.
    Variable resultWidth <- variable @Span (probeSize * 2 |+| gap)
    Variable resultHeight <- variable @Span (cell * 0.68)
    Selected result <- select @Match #result
    Selected resultTrue <- select @Match (#result <&> payload True)
    Selected resultFalse <- select @Match (#result <&> payload False)
    style result $ do
      centerText
      fill (Hsl 214 0.06 0.94)
      stroke (Hsl 214 0.12 0.52)
      strokeWidth (cell * 0.035)
      padding (cell * 0.05)
      zIndex 4
      radius (cell * 0.14)
      fontSize (cell * 0.26)
      width resultWidth
      height resultHeight
    style resultTrue $ do
      content "MATCH"
      fill (Hsl 142 0.52 0.84)
      stroke (Hsl 142 0.72 0.32)
    style resultFalse $ do
      content "NO MATCH"
      fill (Hsl 8 0.44 0.9)
      stroke (Hsl 8 0.62 0.38)
    -- Array row: unprocessed values stay prominent; consumed values recede.
    Selected arrayItems <- select @Value #array
    Selected array <- node arrayItems
    Selected arrayItem <- select @Value (#array <&> #index @: i)
    Selected nextArrayItem <- select @Value (#array <&> #index @: (i + 1))
    let arrayBackground = Hsl valueHue 0.14 0.95
    style array $ do
      zIndex 0
      padding gap
      radius (valueRadius * 1.3)
      fill arrayBackground
      stroke arrayBackground
    Selected processedItem <- select @AnyPayload #processed
    let processedColor :: HslExpr
        processedColor = Hsl valueHue 0.16 0.78
    style processedItem $ do
      fill processedColor
      stroke processedColor
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
