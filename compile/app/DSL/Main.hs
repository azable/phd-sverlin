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
  let half :: Span -> Span
      half value = value / 2
      midpoint :: Coord -> Coord -> Coord
      midpoint lhs rhs = lhs + half (asSpan (rhs - lhs))
   in visualize $ do
        Variable cell <- variable @Span (by 76)
        Variable gap <- variable @Span (cell / 2)
        Variable targetWidth <- variable @Span (cell * 2.1 |+| gap)
        Variable targetHeight <- variable @Span (cell |+| gap * 0.8)
        Variable probeSize <- variable @Span (cell * 1.08)
        Variable matchWidth <- variable @Span (probeSize * 2 |+| gap)
        Variable matchHeight <- variable @Span (cell * 0.72)
        Variable matchGap <- variable @Span (gap * 0.7)
        Variable targetHue <- variable @Hue
        Variable probeHue <- variable @Hue
        Variable listHue <- variable @Hue
        Variable matchHue <- variable @Hue
        Variable notMatchedHue <- variable @Hue (matchHue + 180)
        Variable lum <- variable @UnitExpr
        Variable targetX <- variable @Coord
        Variable targetY <- variable @Coord
        Variable probeTargetX <- variable @Coord
        Variable probeElementX <- variable @Coord
        Variable matchX <- variable @Coord
        Variable probeY <- variable @Coord
        Variable matchY <- variable @Coord
        constrain $ probeTargetX =| probeSize |+| gap |= probeElementX
        constrain $ matchX =|= midpoint probeTargetX probeElementX
        constrain
          $ probeY =| half probeSize |+| matchGap |+| half matchHeight |= matchY
        Bound v <- bindContent
        Bound i <- bindInt
        Selected valueContent <- node @Value (payload @Value v)
        Selected result <- node @Match (tag #result)
        Selected resultTrue <- node @Match (withPayload @Match #result True)
        Selected resultFalse <- node @Match (withPayload @Match #result False)
        Selected targetSource <- node @Value (tag (#target <> #source))
        Selected targetProbe <- node @Value (tag (#target <> #probe))
        Selected probe <- node @Value (tag #probe)
        Selected probeItem <- node @Value (tag (#probe <> #index i))
        Selected array <- node @Array (node @Value (tag #array))
        Selected arrayItem <- node @Value (tag (#array <> #index i))
        Selected nextArrayItem <-
          node @Value (tag (#array <> #index #: (i + 1)))
        Selected processedItem <-
          node @Value (tag (#array <> #processed <> #index i))
        style valueContent $ do
          content v
          centerText
        style result $ do
          centerText
          strokeWidth (cell * 0.05)
          zIndex 4
          radius (cell * 0.26)
          fontSize (cell * 0.34)
          position (vec2 matchX matchY)
          width matchWidth
          height matchHeight
        style targetSource $ do
          fill (Hsl targetHue lum 0.84)
          stroke (Hsl targetHue 0.76 0.36)
          strokeWidth (cell * 0.05)
          radius (cell * 0.24)
          fontSize (cell * 0.62)
          position (vec2 targetX targetY)
          width targetWidth
          height targetHeight
        style probe $ do
          fill (Hsl probeHue 0.5 0.88)
          stroke (Hsl probeHue 0.78 0.34)
          strokeWidth (cell * 0.035)
          zIndex 3
          radius (cell * 0.22)
          fontSize (cell * 0.56)
          width probeSize
          height probeSize
        style targetProbe $ do
          position (vec2 probeTargetX probeY)
        style array $ do
          fill (Hsl listHue 0.08 0.96)
          stroke (Hsl listHue 0.32 0.72)
          strokeWidth (cell * 0.02)
          radius (cell * 0.24)
          zIndex 0
        style arrayItem $ do
          fill (Hsl listHue (asUnit i * 0.2) 0.92)
          stroke (Hsl listHue 0.58 0.42)
          strokeWidth (cell * 0.035)
          radius (cell * 0.18)
          fontSize (cell * 0.5)
          zIndex 2
          width cell
          height cell
        style processedItem $ do
          fill (Hsl 220 0.04 0.84)
          stroke (Hsl 220 0.08 0.58)
          strokeWidth (cell * 0.025)
          opacity 0.62
        constrain $ bottom targetSource <| gap |> top arrayItem
        constrain $ bottom targetSource <| gap |> top probeItem
        style probeItem $ do
          position (vec2 probeElementX probeY)
        constrain $ bottom probeItem <| gap |> top arrayItem
        constrain $ bottom targetProbe <| matchGap |> top result
        constrain $ bottom probeItem <| matchGap |> top result
        constrain $ bottom result <| gap |> top arrayItem
        constrain $ right arrayItem =| gap * 2 |= left nextArrayItem
        constrain $ top arrayItem =|= top nextArrayItem
        style resultTrue $ do
          content "MATCH"
          fill (Hsl matchHue 0.6 0.86)
          stroke (Hsl matchHue 0.82 0.32)
        style resultFalse $ do
          content "NO MATCH"
          fill (Hsl notMatchedHue 0.34 0.9)
          stroke (Hsl notMatchedHue 0.68 0.34)
