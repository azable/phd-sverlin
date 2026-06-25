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

data Comparison where
  IsMatch :: Block Value %1 -> Block Value %1 -> Comparison
  IsNotMatch :: Block Value %1 -> Block Value %1 -> Comparison

data SearchState where
  SearchState :: Block Value %1 -> Elements %1 -> SearchState

data PrepareComparisonOutput where
  PrepareComparisonOutput
    :: Block Value
       %1 -> Block Value
       %1 -> Block Value
       %1 -> Block Value
       %1 -> PrepareComparisonOutput

linearSearch :: SearchInput %1 -> Program ()
linearSearch (SearchInput targetPayload valuePayloads) = do
  target <- create (#int <> #target <> #source) targetPayload
  elements <- createElements valuePayloads
  loop (SearchState target elements) searchIteration

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
    SearchState target elements ->
      case elements of
        NoElements -> do
          destroy target
          checkpoint "Search exhausted"
          return (Finish ())
        MoreElement index element rest -> do
          comparison <- compareElement target index element
          case comparison of
            IsMatch targetAfter elementAfter -> do
              finishFound targetAfter elementAfter
              discardRemaining rest
              return (Finish ())
            IsNotMatch targetAfter elementAfter -> do
              discardChecked elementAfter
              return (Continue (SearchState targetAfter rest))

compareElement :: Block Value %1 -> Int -> Block Value %1 -> Program Comparison
compareElement target index element = do
  PrepareComparisonOutput targetAfter elementAfter targetProbe elementProbe <-
    prepareComparison target index element
  matchBlock <- compareValues targetProbe elementProbe
  branch <- decide (\(LBool answer) -> answer) matchBlock
  case branch of
    BranchTrue -> do
      checkpoint "Found target"
      comparisonBranch targetAfter elementAfter BranchTrue
    BranchFalse -> do
      checkpoint "Not this element"
      comparisonBranch targetAfter elementAfter BranchFalse

comparisonBranch ::
     Block Value %1 -> Block Value %1 -> BranchDecision %1 -> Program Comparison
comparisonBranch targetAfter elementAfter branch =
  case branch of
    BranchTrue  -> return (IsMatch targetAfter elementAfter)
    BranchFalse -> return (IsNotMatch targetAfter elementAfter)

discardRemaining :: Elements %1 -> Program ()
discardRemaining elements =
  case elements of
    NoElements -> return ()
    MoreElement _ element rest -> do
      destroy element
      checkpoint "Discard remaining element"
      discardRemaining rest

prepareComparison ::
     Block Value %1 -> Int -> Block Value %1 -> Program PrepareComparisonOutput
prepareComparison target index element = do
  (targetAfter, targetProbe) <- copy (#int <> #target <> #probe) target
  (elementAfter, elementProbe) <- copy (#int <> #probe <> #index index) element
  checkpoint "Prepare comparison"
  return
    (PrepareComparisonOutput targetAfter elementAfter targetProbe elementProbe)

compareValues :: Block Value %1 -> Block Value %1 -> Program (Block Match)
compareValues targetProbe elementProbe = do
  targetPayload <- use targetProbe
  elementPayload <- use elementProbe
  matchBlock <-
    computeWithTags
      (#decision <> #match)
      (\case
         LBool True -> #matched
         LBool False -> #not_matched)
      (sameValue <$> targetPayload <*> elementPayload)
  checkpoint "Compare target and element"
  return matchBlock

discardChecked :: Block Value %1 -> Program ()
discardChecked element = do
  destroy element
  checkpoint "Discard checked element"

finishFound :: Block Value %1 -> Block Value %1 -> Program ()
finishFound target element = do
  destroy target
  destroy element
  checkpoint "Finish found target"

--------------------------------------------------------------------------------
-- Visualisation
--------------------------------------------------------------------------------
visualization :: MatchSpec
visualization =
  let cell :: Span
      cell = by 76
      gap :: Span
      gap = half cell
      cellBy :: Scalar -> Span
      cellBy scale = cell * scale
      gapBy :: Scalar -> Span
      gapBy scale = gap * scale
      targetWidth :: Span
      targetWidth = cellBy 2.1 |+| gap
      targetHeight :: Span
      targetHeight = cell |+| gapBy 0.8
      probeSize :: Span
      probeSize = cellBy 1.08
      matchWidth :: Span
      matchWidth = probeSize * 2 |+| gap
      matchHeight :: Span
      matchHeight = cellBy 0.72
      matchGap :: Span
      matchGap = gapBy 0.7
      half :: Span -> Span
      half value = value / 2
      midpoint :: Coord -> Coord -> Coord
      midpoint lhs rhs = lhs + half (asSpan (rhs - lhs))
   in visualize $ do
        layout $ do
          constrain $ #probe_target_x =| probeSize |+| gap |= #probe_element_x
          constrain $ #match_x =|= midpoint #probe_target_x #probe_element_x
          constrain
            $ #probe_y
                =| half probeSize
                |+| matchGap
                |+| half matchHeight
                |= #match_y
        match @Value $ do
          contentDebug
          centerText
        match @Match $ do
          centerText
        match @Value (whereFacts (#int <> #target <> #source)) $ do
          fill (Hsl #target_hue #lum 0.84)
          stroke (Hsl #target_hue 0.76 0.36)
          strokeWidth (cellBy 0.05)
          radius (cellBy 0.24)
          fontSize (cellBy 0.62)
          position (vec2 #target_x #target_y)
          width targetWidth
          height targetHeight
        match @Value (whereFacts (#int <> #target <> #probe)) $ do
          fill (Hsl #probe_hue 0.5 0.88)
          stroke (Hsl #probe_hue 0.78 0.34)
          strokeWidth (cellBy 0.035)
          zIndex 3
          radius (cellBy 0.22)
          fontSize (cellBy 0.56)
          position (vec2 #probe_target_x #probe_y)
          width probeSize
          height probeSize
        match @Value (whereFacts (#int <> #array <> patternIntField #index #i)) $ do
          fill (Hsl #list_hue #sat 0.92)
          stroke (Hsl #list_hue 0.58 0.42)
          strokeWidth (cellBy 0.035)
          radius (cellBy 0.18)
          fontSize (cellBy 0.5)
          width cell
          height cell
        matchPair
          (#int <> #target <> #source)
          (#int <> #array <> patternIntField #index #i)
          (\target element -> constrain $ bottom target <| gap |> top element)
        matchPair
          (#int <> #target <> #source)
          (#int <> #probe <> patternIntField #index #i)
          (\target probe -> constrain $ bottom target <| gap |> top probe)
        match @Value (whereFacts (#int <> #probe <> patternIntField #index #i)) $ do
          fill (Hsl #probe_hue 0.5 0.88)
          stroke (Hsl #probe_hue 0.78 0.34)
          strokeWidth (cellBy 0.035)
          zIndex 3
          radius (cellBy 0.22)
          fontSize (cellBy 0.56)
          position (vec2 #probe_element_x #probe_y)
          width probeSize
          height probeSize
        matchPair
          (#int <> #probe <> patternIntField #index #i)
          (#int <> #array <> patternIntField #index #i)
          (\probe element -> constrain $ bottom probe <| gap |> top element)
        matchPair
          (#int <> #array <> patternIntField #index #i)
          (#int <> #array <> patternIntField #index (#i + 1))
          (\previous next -> do
             constrain $ right previous =| gapBy 2 |= left next
             constrain $ top previous =|= top next)
        match @Match (whereFacts (#decision <> #match <> #matched)) $ do
          content "MATCH"
          fill (Hsl #match_hue 0.6 0.86)
          stroke (Hsl #match_hue 0.82 0.32)
          strokeWidth (cellBy 0.05)
          zIndex 4
          radius (cellBy 0.26)
          fontSize (cellBy 0.34)
          position (vec2 #match_x #match_y)
          width matchWidth
          height matchHeight
        match @Match (whereFacts (#decision <> #match <> #not_matched)) $ do
          content "NO MATCH"
          fill (Hsl (#match_hue + 180) 0.34 0.9)
          stroke (Hsl (#match_hue + 180) 0.68 0.34)
          strokeWidth (cellBy 0.05)
          zIndex 4
          radius (cellBy 0.26)
          fontSize (cellBy 0.34)
          position (vec2 #match_x #match_y)
          width matchWidth
          height matchHeight
