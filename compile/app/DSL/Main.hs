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

import           Control.Functor.Linear   hiding (ask, (<$>), (<*>))
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
  target <- create (#target <&&> #source) targetPayload
  elements <- createElements valuePayloads
  loop (SearchState target NoProcessedElements elements) searchIteration

createElements :: InputValues %1 -> Program Elements
createElements = createElementsFrom 0

createElementsFrom :: Int -> InputValues %1 -> Program Elements
createElementsFrom index inputs =
  case inputs of
    NoInputValues -> return NoElements
    MoreInputValue valuePayload rest -> do
      element <- create (#array <&&> #index index) valuePayload
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
markProcessed index = retag (#array <&&> #processed <&&> #index index)

prepareComparison ::
     Block Value %1 -> Int -> Block Value %1 -> Program PreparedComparison
prepareComparison target index element = do
  (targetAfter, targetProbe) <- copy (#target <&&> #probe) target
  (elementAfter, elementProbe) <- copy (#probe <&&> #index index) element
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
    -- Geometry is sized for the default 800x600 canvas. Container nodes carry
    -- the row anchors, so constraints read in terms of the shapes they place.
    Variable cell <- variable @Span (by 104)
    Variable gap <- variable @Span (cell / 3.5)
    let rowGap :: Span
        rowGap = cell / (2.8 :: Scalar)
    let sectionGap :: Span
        sectionGap = cell / (2 :: Scalar)
    Variable probeSize <- variable @Span (cell * 1.05)
    Bound v <- bindContent
    Bound i <- bindInt
    -- Shared payload styling: every value block renders its payload. More
    -- specific styles below decide how each block participates in the step.
    Selected valueContent <- select @Value (payload v)
    style valueContent $ do
      content v
      centerText
    -- Target row: a wide source value that anchors the rest of the layout.
    Variable targetWidth <- variable @Span (probeSize * 2 |+| gap)
    Variable targetHeight <- variable @Span (cell * 0.82)
    Selected targetSource <- select @Value (#target <&&> #source)
    style targetSource $ do
      fill (Hsl 42 0.62 0.86)
      stroke (Hsl 38 0.75 0.38)
      strokeWidth (cell * 0.04)
      radius (cell * 0.16)
      fontSize (cell * 0.46)
      zIndex 2
      width targetWidth
      height targetHeight
    -- Probe row: the copied target and current array element sit side by side.
    Selected targetProbe <- select @Value (#target <&&> #probe)
    Selected probe <- select @Value #probe
    Selected probes <- node probe
    Selected probeItem <- select @Value (#probe <&&> #index @: i)
    style probes $ do
      fill (Hsl 204 0.12 0.96)
      stroke (Hsl 204 0.24 0.72)
      strokeWidth (cell * 0.022)
      radius (cell * 0.18)
      zIndex 1
    style probe $ do
      fill (Hsl 204 0.44 0.9)
      stroke (Hsl 204 0.62 0.36)
      strokeWidth (cell * 0.035)
      zIndex 3
      radius (cell * 0.16)
      fontSize (cell * 0.44)
      width probeSize
      height probeSize
    -- Result row: a compact badge records the branch decision.
    Variable resultWidth <- variable @Span (probeSize * 2 |+| gap)
    Variable resultHeight <- variable @Span (cell * 0.68)
    Selected result <- select @Match #result
    Selected results <- node result
    Selected resultTrue <- select @Match (#result <&&> payload True)
    Selected resultFalse <- select @Match (#result <&&> payload False)
    style results $ do
      fill (Hsl 214 0.08 0.97)
      stroke (Hsl 214 0.16 0.78)
      strokeWidth (cell * 0.022)
      radius (cell * 0.16)
      zIndex 1
    style result $ do
      centerText
      fill (Hsl 214 0.06 0.94)
      stroke (Hsl 214 0.12 0.52)
      strokeWidth (cell * 0.035)
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
    Selected arrayItem <- select @Value (#array <&&> #index @: i)
    Selected nextArrayItem <- select @Value (#array <&&> #index @: (i + 1))
    style array $ do
      -- fill (Hsl 166 0.12 0.95)
      -- stroke (Hsl 166 0.28 0.64)
      -- strokeWidth (cell * 0.022)
      -- radius (cell * 0.18)
      zIndex 0
    style arrayItem $ do
      fill (Hsl 166 (0.2 + asUnit i * 0.08) 0.88)
      stroke (Hsl 166 0.46 0.38)
      strokeWidth (cell * 0.035)
      radius (cell * 0.12)
      fontSize (cell * 0.44)
      zIndex 2
      width cell
      height cell
    Selected processedItem <- select @AnyPayload #processed
    let processedGrey :: HslExpr
        processedGrey = Hsl 0 0 0.8
    -- Bounds keep the composition on-canvas. Encouragements make those bands
    -- preferences rather than hidden anchor variables.
    ensure $ fill processedItem .==. processedGrey
    ensure $ stroke processedItem .==. processedGrey
    ensure $ at 56 .<=. left targetSource
    ensure $ left targetSource .<=. at 88
    ensure $ at 36 .<=. top targetSource
    ensure $ top targetSource .<=. at 52
    ensure $ at 174 .<=. top probes
    ensure $ top probes .<=. at 198
    ensure $ at 336 .<=. top results
    ensure $ top results .<=. at 368
    ensure $ at 446 .<=. top array
    ensure $ top array .<=. at 474
    encourage $ left targetSource .==. at 72
    encourage $ top targetSource .==. at 44
    encourage $ top probes .==. at 184
    encourage $ top results .==. at 352
    encourage $ top array .==. at 462
    -- Row alignment and item spacing are exact; vertical gaps are minimums.
    ensure $ bottom targetSource <| rowGap |> top probes
    ensure $ left probes .==. left targetSource
    ensure $ top probe .==. top probes
    ensure $ left targetProbe .==. left probes
    ensure $ right targetProbe =| gap |= left probeItem
    ensure $ bottom probes <| sectionGap |> top results
    ensure $ left results .==. left probes
    ensure $ top result .==. top results
    ensure $ left result .==. left results
    ensure $ bottom results <| rowGap |> top array
    ensure $ left array .==. left targetSource
    ensure $ top arrayItem .==. top array
    ensure $ right arrayItem =| gap |= left nextArrayItem
