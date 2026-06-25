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
                                           (*), (+), (-), (/), (<>))

--------------------------------------------------------------------------------
-- Payload tags
--------------------------------------------------------------------------------
data Value

type instance Payload Value = LInt Value

instance Traceable Value

data Match

type instance Payload Match = LBool Match

instance Traceable Match

data Array

data ProbeRow

data ResultRow

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
  target <- create (#target <> #source) targetPayload
  elements <- createElements valuePayloads
  loop (SearchState target NoProcessedElements elements) searchIteration

createElements :: InputValues %1 -> Program Elements
createElements = createElementsFrom 0

createElementsFrom :: Int -> InputValues %1 -> Program Elements
createElementsFrom index inputs =
  case inputs of
    NoInputValues -> return NoElements
    MoreInputValue valuePayload rest -> do
      element <- create (#array <> #index index) valuePayload
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
markProcessed index = retag (#array <> #processed <> #index index)

prepareComparison ::
     Block Value %1 -> Int -> Block Value %1 -> Program PreparedComparison
prepareComparison target index element = do
  (targetAfter, targetProbe) <- copy (#target <> #probe) target
  (elementAfter, elementProbe) <- copy (#probe <> #index index) element
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
    Variable cell <- variable @Span (by 70)
    Variable gap <- variable @Span (cell / 2.8)
    Variable targetWidth <- variable @Span (cell * 2.1 |+| gap)
    Variable targetHeight <- variable @Span (cell * 0.92)
    Variable probeSize <- variable @Span (cell * 1.05)
    Variable resultWidth <- variable @Span (probeSize * 2 |+| gap)
    Variable resultHeight <- variable @Span (cell * 0.58)
    Variable rowLeft <- variable @Coord (at 78)
    Variable targetTop <- variable @Coord (at 44)
    Variable targetHue <- variable @Hue
    Variable probeHue <- variable @Hue
    Variable listHue <- variable @Hue
    Variable matchHue <- variable @Hue
    Variable notMatchedHue <- variable @Hue (matchHue + 180)
    Bound v <- bindContent
    Bound i <- bindInt
    Selected valueContent <- select @Value (payload v)
    Selected result <- select @Match #result
    Selected resultTrue <- select @Match (#result <> payload True)
    Selected resultFalse <- select @Match (#result <> payload False)
    Selected targetSource <- select @Value (#target <> #source)
    Selected targetProbe <- select @Value (#target <> #probe)
    Selected probe <- select @Value #probe
    Selected probes <- node @ProbeRow probe
    Selected results <- node @ResultRow result
    Selected probeItem <- select @Value (#probe <> #index i)
    Selected arrayItems <- select @Value #array
    Selected array <- node @Array arrayItems
    Selected arrayItem <- select @Value (#array <> #index i)
    Selected nextArrayItem <- select @Value (#array <> #index #: (i + 1))
    Selected processedItem <- select @Value (#array <> #processed <> #index i)
    style valueContent $ do
      content v
      centerText
    style result $ do
      centerText
      strokeWidth (cell * 0.04)
      zIndex 4
      radius (cell * 0.18)
      fontSize (cell * 0.3)
      width resultWidth
      height resultHeight
    style targetSource $ do
      fill (Hsl targetHue 0.54 0.88)
      stroke (Hsl targetHue 0.7 0.42)
      strokeWidth (cell * 0.05)
      radius (cell * 0.2)
      fontSize (cell * 0.56)
      left rowLeft
      top targetTop
      width targetWidth
      height targetHeight
    style probe $ do
      fill (Hsl probeHue 0.42 0.9)
      stroke (Hsl probeHue 0.64 0.38)
      strokeWidth (cell * 0.04)
      zIndex 3
      radius (cell * 0.18)
      fontSize (cell * 0.48)
      width probeSize
      height probeSize
    style targetProbe $ do
      left rowLeft
    style probeItem $ do
      left (rowLeft + (probeSize |+| gap))
    style probes $ do
      fill (Hsl probeHue 0.12 0.96)
      stroke (Hsl probeHue 0.22 0.74)
      strokeWidth (cell * 0.025)
      radius (cell * 0.22)
      zIndex 1
    style results $ do
      fill (Hsl 214 0.08 0.97)
      stroke (Hsl 214 0.16 0.78)
      strokeWidth (cell * 0.025)
      radius (cell * 0.2)
      zIndex 1
    style array $ do
      fill (Hsl listHue 0.12 0.95)
      stroke (Hsl listHue 0.28 0.68)
      strokeWidth (cell * 0.025)
      radius (cell * 0.22)
      zIndex 0
    style arrayItem $ do
      fill (Hsl listHue (0.18 + asUnit i * 0.11) 0.9)
      stroke (Hsl listHue 0.42 0.46)
      strokeWidth (cell * 0.04)
      radius (cell * 0.15)
      fontSize (cell * 0.48)
      zIndex 2
      width cell
      height cell
    style processedItem $ do
      fill (Hsl 218 0.05 0.84)
      stroke (Hsl 218 0.1 0.58)
      strokeWidth (cell * 0.025)
      opacity 0.58
    constrain $ bottom targetSource =| gap |= top probes
    constrain $ top probe =|= top probes
    constrain $ bottom probes =| gap |= top results
    constrain $ left results =|= left probes
    constrain $ top result =|= top results
    constrain $ left result =|= left results
    constrain $ bottom results =| gap |= top array
    constrain $ left array =|= left targetSource
    constrain $ top arrayItem =|= top array
    constrain $ right arrayItem =| gap |= left nextArrayItem
    style resultTrue $ do
      content "MATCH"
      fill (Hsl matchHue 0.52 0.86)
      stroke (Hsl matchHue 0.72 0.34)
    style resultFalse $ do
      content "NO MATCH"
      fill (Hsl notMatchedHue 0.34 0.9)
      stroke (Hsl notMatchedHue 0.56 0.38)
