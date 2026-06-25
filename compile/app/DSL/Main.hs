{-# LANGUAGE ConstraintKinds         #-}
{-# LANGUAGE DataKinds               #-}
{-# LANGUAGE FlexibleContexts        #-}
{-# LANGUAGE FlexibleInstances       #-}
{-# LANGUAGE GADTs                   #-}
{-# LANGUAGE LambdaCase              #-}
{-# LANGUAGE LinearTypes             #-}
{-# LANGUAGE NoImplicitPrelude       #-}
{-# LANGUAGE OverloadedLabels        #-}
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
  target <- create (#int <> #target <> #source) targetPayload
  elements <- createElements valuePayloads
  loop (SearchState target NoProcessedElements elements) searchIteration

createElements :: InputValues %1 -> Program Elements
createElements = createElementsFrom 0

createElementsFrom :: Int -> InputValues %1 -> Program Elements
createElementsFrom index inputs =
  case inputs of
    NoInputValues -> return NoElements
    MoreInputValue payload rest -> do
      element <- create (#int <> #array <> #index index) payload
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
markProcessed index = retag (#int <> #array <> #processed <> #index index)

prepareComparison ::
     Block Value %1 -> Int -> Block Value %1 -> Program PreparedComparison
prepareComparison target index element = do
  (targetAfter, targetProbe) <- copy (#int <> #target <> #probe) target
  (elementAfter, elementProbe) <- copy (#int <> #probe <> #index index) element
  return (PreparedComparison targetAfter elementAfter targetProbe elementProbe)

compareValues :: Block Value %1 -> Block Value %1 -> Program (Block Match)
compareValues targetProbe elementProbe = do
  targetPayload <- use targetProbe
  elementPayload <- use elementProbe
  computeWithTags
    (#decision <> #match)
    (\case
       LBool True -> #matched
       LBool False -> #not_matched)
    (sameValue <$> targetPayload <*> elementPayload)

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
        layout $ do
          deriveSpan #cell (by 76)
          deriveSpan #gap (#cell / 2)
          deriveSpan #target_width (#cell * 2.1 |+| #gap)
          deriveSpan #target_height (#cell |+| #gap * 0.8)
          deriveSpan #probe_size (#cell * 1.08)
          deriveSpan #match_width (#probe_size * 2 |+| #gap)
          deriveSpan #match_height (#cell * 0.72)
          deriveSpan #match_gap (#gap * 0.7)
          deriveHue #not_matched_hue (#match_hue + 180)
          constrain
            $ #probe_target_x =| #probe_size |+| #gap |= #probe_element_x
          constrain $ #match_x =|= midpoint #probe_target_x #probe_element_x
          constrain
            $ #probe_y
                =| half #probe_size
                |+| #match_gap
                |+| half #match_height
                |= #match_y
        match @Value $ do
          contentDebug
          centerText
        match @Match $ do
          centerText
        match @Value (whereFacts (#int <> #target <> #source)) $ do
          fill (Hsl #target_hue #lum 0.84)
          stroke (Hsl #target_hue 0.76 0.36)
          strokeWidth (#cell * 0.05)
          radius (#cell * 0.24)
          fontSize (#cell * 0.62)
          position (vec2 #target_x #target_y)
          width #target_width
          height #target_height
        match @Value (whereFacts (#int <> #target <> #probe)) $ do
          fill (Hsl #probe_hue 0.5 0.88)
          stroke (Hsl #probe_hue 0.78 0.34)
          strokeWidth (#cell * 0.035)
          zIndex 3
          radius (#cell * 0.22)
          fontSize (#cell * 0.56)
          position (vec2 #probe_target_x #probe_y)
          width #probe_size
          height #probe_size
        match @Value (whereFacts (#int <> #array <> patternIntField #index #i)) $ do
          fill (Hsl #list_hue #sat 0.92)
          stroke (Hsl #list_hue 0.58 0.42)
          strokeWidth (#cell * 0.035)
          radius (#cell * 0.18)
          fontSize (#cell * 0.5)
          width #cell
          height #cell
        match @Value
          (whereFacts
             (#int <> #array <> #processed <> patternIntField #index #i)) $ do
          fill (Hsl 220 0.04 0.84)
          stroke (Hsl 220 0.08 0.58)
          strokeWidth (#cell * 0.025)
          opacity 0.62
        matchPair
          (#int <> #target <> #source)
          (#int <> #array <> patternIntField #index #i)
          (\target element -> constrain $ bottom target <| #gap |> top element)
        matchPair
          (#int <> #target <> #source)
          (#int <> #probe <> patternIntField #index #i)
          (\target probe -> constrain $ bottom target <| #gap |> top probe)
        match @Value (whereFacts (#int <> #probe <> patternIntField #index #i)) $ do
          fill (Hsl #probe_hue 0.5 0.88)
          stroke (Hsl #probe_hue 0.78 0.34)
          strokeWidth (#cell * 0.035)
          zIndex 3
          radius (#cell * 0.22)
          fontSize (#cell * 0.56)
          position (vec2 #probe_element_x #probe_y)
          width #probe_size
          height #probe_size
        matchPair
          (#int <> #probe <> patternIntField #index #i)
          (#int <> #array <> patternIntField #index #i)
          (\probe element -> constrain $ bottom probe <| #gap |> top element)
        matchPair
          (#int <> #target <> #probe)
          (#decision <> #match)
          (\probe result -> constrain $ bottom probe <| #match_gap |> top result)
        matchPair
          (#int <> #probe <> patternIntField #index #i)
          (#decision <> #match)
          (\probe result -> constrain $ bottom probe <| #match_gap |> top result)
        matchPair
          (#decision <> #match)
          (#int <> #array <> patternIntField #index #i)
          (\result element -> constrain $ bottom result <| #gap |> top element)
        matchPair
          (#int <> #array <> patternIntField #index #i)
          (#int <> #array <> patternIntField #index (#i + 1))
          (\previous next -> do
             constrain $ right previous =| #gap * 2 |= left next
             constrain $ top previous =|= top next)
        match @Match (whereFacts (#decision <> #match <> #matched)) $ do
          content "MATCH"
          fill (Hsl #match_hue 0.6 0.86)
          stroke (Hsl #match_hue 0.82 0.32)
          strokeWidth (#cell * 0.05)
          zIndex 4
          radius (#cell * 0.26)
          fontSize (#cell * 0.34)
          position (vec2 #match_x #match_y)
          width #match_width
          height #match_height
        match @Match (whereFacts (#decision <> #match <> #not_matched)) $ do
          content "NO MATCH"
          fill (Hsl #not_matched_hue 0.34 0.9)
          stroke (Hsl #not_matched_hue 0.68 0.34)
          strokeWidth (#cell * 0.05)
          zIndex 4
          radius (#cell * 0.26)
          fontSize (#cell * 0.34)
          position (vec2 #match_x #match_y)
          width #match_width
          height #match_height
