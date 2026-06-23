{-# LANGUAGE ConstraintKinds         #-}
{-# LANGUAGE DataKinds               #-}
{-# LANGUAGE FlexibleContexts        #-}
{-# LANGUAGE FlexibleInstances       #-}
{-# LANGUAGE GADTs                   #-}
{-# LANGUAGE LinearTypes             #-}
{-# LANGUAGE NoImplicitPrelude       #-}
{-# LANGUAGE OverloadedLabels        #-}
{-# LANGUAGE RebindableSyntax        #-}
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

instance Traceable Match where
  payloadView _ payload =
    case payload of
      LBool matched
        {- HLINT ignore "Use if" -}
       ->
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
  MoreElement :: Int -> BlockHandle Value %1 -> Elements %1 -> Elements

data Comparison where
  IsMatch :: BlockHandle Value %1 -> BlockHandle Value %1 -> Comparison
  IsNotMatch :: BlockHandle Value %1 -> BlockHandle Value %1 -> Comparison

data SearchState where
  SearchState :: BlockHandle Value %1 -> Elements %1 -> SearchState

data PrepareComparisonOutput where
  PrepareComparisonOutput
    :: BlockHandle Value
       %1 -> BlockHandle Value
       %1 -> BlockHandle Value
       %1 -> BlockHandle Value
       %1 -> PrepareComparisonOutput

data PrepareComparisonObligations where
  PrepareComparisonObligations
    :: Obligation (Copy Value)
       %1 -> Obligation (Copy Value)
       %1 -> PrepareComparisonObligations

data CompareValuesObligations where
  CompareValuesObligations
    :: Obligation (Use Value)
       %1 -> Obligation (Use Value)
       %1 -> Obligation (Compute Match)
       %1 -> CompareValuesObligations

data DestroyPairObligations where
  DestroyPairObligations
    :: Obligation (Destroy Value)
       %1 -> Obligation (Destroy Value)
       %1 -> DestroyPairObligations

linearSearch :: SearchInput %1 -> Program ()
linearSearch (SearchInput targetPayload valuePayloads) =
  manifest $ do
    target <-
      phase
        "Create target"
        (createValueTagged (#int <> #target) targetPayload)
        renderCreatedTarget
    elements <- createElements valuePayloads
    loop (SearchState target elements) searchIteration

createElements :: InputValues %1 -> Program Elements
createElements = createElementsFrom 0

createElementsFrom :: Int -> InputValues %1 -> Program Elements
createElementsFrom index inputs =
  case inputs of
    NoInputValues -> return NoElements
    MoreInputValue payload rest -> do
      element <-
        phase
          "Create element"
          (createValueTagged
             (#int <> #array (#values :: Query) <> #index index)
             payload)
          renderCreatedElement
      elements <- createElementsFrom (index + 1) rest
      return (MoreElement index element elements)

searchIteration :: SearchState %1 -> Program (LoopResult SearchState ())
searchIteration searchState =
  case searchState of
    SearchState target elements ->
      case elements of
        NoElements -> do
          phase "Search exhausted" (destroyValue target) renderRemove
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

compareElement ::
     BlockHandle Value %1 -> Int -> BlockHandle Value %1 -> Program Comparison
compareElement target index element = do
  PrepareComparisonOutput targetAfter elementAfter targetProbe elementProbe <-
    phase
      "Prepare comparison"
      (prepareComparison target index element)
      renderPrepareComparison
  matchBlock <-
    phase
      "Compare target and element"
      (compareValues targetProbe elementProbe)
      renderCompareValues
  branchOn
    (decideMatch matchBlock)
    (BranchCase "Found target" renderRemove)
    (BranchCase "Not this element" renderRejectedDecision)
    (comparisonBranch targetAfter elementAfter)

comparisonBranch ::
     BlockHandle Value
     %1 -> BlockHandle Value
     %1 -> BranchDecision
     %1 -> Program Comparison
comparisonBranch targetAfter elementAfter branch =
  case branch of
    BranchTrue  -> return (IsMatch targetAfter elementAfter)
    BranchFalse -> return (IsNotMatch targetAfter elementAfter)

discardChecked :: BlockHandle Value %1 -> Program ()
discardChecked element = do
  phase "Discard checked element" (destroyValue element) renderRemove

finishFound :: BlockHandle Value %1 -> BlockHandle Value %1 -> Program ()
finishFound target element = do
  phase "Finish found target" (destroyPair target element) renderDestroyPair

discardRemaining :: Elements %1 -> Program ()
discardRemaining elements =
  case elements of
    NoElements -> return ()
    MoreElement _ element rest -> do
      phase "Discard remaining element" (destroyValue element) renderRemove
      discardRemaining rest

createValueTagged ::
     Query
  -> Payload Value
     %1 -> Fragment (StepResult (BlockHandle Value) (Obligation (Create Value)))
createValueTagged facts payload = do
  Created block obligation <- createTaggedAs facts payload
  return (StepResult block obligation)

destroyValue ::
     BlockHandle Value
     %1 -> Fragment (StepResult () (Obligation (Destroy Value)))
destroyValue block = do
  Destroyed obligation <- destroyAs block
  return (StepResult () obligation)

destroyPair ::
     BlockHandle Value
     %1 -> BlockHandle Value
     %1 -> Fragment (StepResult () DestroyPairObligations)
destroyPair target element = do
  Destroyed targetVisual <- destroyAs target
  Destroyed elementVisual <- destroyAs element
  return (StepResult () (DestroyPairObligations targetVisual elementVisual))

prepareComparison ::
     BlockHandle Value
     %1 -> Int
  -> BlockHandle Value
     %1 -> Fragment
       (StepResult PrepareComparisonOutput PrepareComparisonObligations)
prepareComparison target index element = do
  Copied targetAfter targetProbe targetCopy <-
    copyTaggedAs (#int <> #probe (#target :: Query)) target
  Copied elementAfter elementProbe elementCopy <-
    copyTaggedAs (#int <> #probe (#element :: Query) <> #index index) element
  return
    (StepResult
       (PrepareComparisonOutput
          targetAfter
          elementAfter
          targetProbe
          elementProbe)
       (PrepareComparisonObligations targetCopy elementCopy))

compareValues ::
     BlockHandle Value
     %1 -> BlockHandle Value
     %1 -> Fragment (StepResult (BlockHandle Match) CompareValuesObligations)
compareValues targetProbe elementProbe = do
  Used targetPayload targetVisual <- useAs targetProbe
  Used elementPayload elementVisual <- useAs elementProbe
  Computed matchBlock matchVisual <-
    computeTaggedAs
      (#decision <> #match)
      (sameValue <$> targetPayload <*> elementPayload)
  return
    (StepResult
       matchBlock
       (CompareValuesObligations targetVisual elementVisual matchVisual))

decideMatch :: BlockHandle Match %1 -> Fragment (Decided Match)
decideMatch = decideAs (\(LBool answer) -> answer)

renderCreatedTarget :: Obligation (Create Value) %1 -> RenderRecipe ()
renderCreatedTarget = renderFreshMatched

renderCreatedElement :: Obligation (Create Value) %1 -> RenderRecipe ()
renderCreatedElement obligation = do
  renderFreshMatched obligation
  renderCheckpoint

renderPrepareComparison :: PrepareComparisonObligations %1 -> RenderRecipe ()
renderPrepareComparison obligations =
  case obligations of
    PrepareComparisonObligations targetCopy elementCopy -> do
      renderForkCopyMatched targetCopy
      renderForkCopyMatched elementCopy
      renderCheckpoint

renderCompareValues :: CompareValuesObligations %1 -> RenderRecipe ()
renderCompareValues obligations =
  case obligations of
    CompareValuesObligations targetVisual elementVisual matchVisual -> do
      renderFreshMatched matchVisual
      renderCheckpoint
      renderRemove targetVisual
      renderRemove elementVisual

renderRejectedDecision :: Obligation (Decide Match) %1 -> RenderRecipe ()
renderRejectedDecision obligation = do
  renderRemove obligation
  renderCheckpoint

renderDestroyPair :: DestroyPairObligations %1 -> RenderRecipe ()
renderDestroyPair obligations =
  case obligations of
    DestroyPairObligations targetVisual elementVisual -> do
      renderRemove targetVisual
      renderRemove elementVisual

--------------------------------------------------------------------------------
-- Visualisation
--------------------------------------------------------------------------------
visualization :: MatchSpec
visualization =
  visualize $ do
    layout $ do
      constrain $ (#cell :: Span) =|= by 76
      constrain $ (#gap :: Span) =|= half #cell
      constrain $ at 0 =| targetInsetX |= #target_x
      constrain $ at 0 =| targetInsetY |= #target_y
      constrain $ at 0 =| rowInset |= #row_x
      constrain $ (#row_y :: Coord) =| rowInset |= at 600
      constrain $ (#target_x :: Coord) =| 211 |= #probe_target_x
      constrain $ (#probe_target_x :: Coord) =| probeGap |= #probe_element_x
      constrain $ (#target_y :: Coord) =| probeOffsetY |= #probe_y
      constrain $ (#probe_y :: Coord) <| probeRowClearance |> #row_y
      constrain
        $ (#match_x :: Coord) =|= midpoint #probe_target_x #probe_element_x
      constrain $ (#probe_y :: Coord) =| matchOffsetY |= #match_y
      constrain $ (#match_y :: Coord) <| matchRowClearance |> #row_y
    match
      ((#int <> #target) :: Query)
      ((node $ do
          centerText
          fill (tone #target_hue 0.64 0.84)
          stroke (tone #target_hue 0.76 0.36)
          strokeWidth (cellBy 0.05)
          radius (cellBy 0.24)
          fontSize (cellBy 0.62)
          position (vec2 #target_x #target_y)
          width targetWidth
          height targetHeight) :: NodeDefinition Value)
    matchAs
      ((#int <> #probe (#target :: Query)) :: Query)
      ((#int <> #target) :: Query)
      ((node $ do
          centerText
          fill (tone #probe_hue 0.5 0.88)
          stroke (tone #probe_hue 0.78 0.34)
          strokeWidth (cellBy 0.035)
          zIndex 3
          radius (cellBy 0.22)
          fontSize (cellBy 0.56)
          position (vec2 #probe_target_x #probe_y)
          width probeSize
          height probeSize) :: NodeDefinition Value)
    match
      (#int <> #array (#values :: Query) <> #index (#i :: PatternInt) :: Pattern)
      ((node $ do
          centerText
          fill (tone #list_hue 0.34 0.92)
          stroke (tone #list_hue 0.58 0.42)
          strokeWidth (cellBy 0.035)
          radius (cellBy 0.18)
          fontSize (cellBy 0.5)
          width #cell
          height #cell) :: NodeDefinition Value)
    matchLayout
      (#int <> #array (#values :: Query) <> #index (0 :: Int) :: Pattern)
      ((\first -> do
          constrain $ left first =| half #cell |= #row_x
          constrain $ top first =| half #cell |= #row_y) :: MatchedNode -> ViewLayout
                                                                             ())
    matchAs
      (#int <> #probe (#element :: Query) <> #index (#i :: PatternInt) :: Pattern)
      (#int <> #array (#values :: Query) <> #index (#i :: PatternInt) :: Pattern)
      ((node $ do
          centerText
          fill (tone #probe_hue 0.5 0.88)
          stroke (tone #probe_hue 0.78 0.34)
          strokeWidth (cellBy 0.035)
          zIndex 3
          radius (cellBy 0.22)
          fontSize (cellBy 0.56)
          position (vec2 #probe_element_x #probe_y)
          width probeSize
          height probeSize) :: NodeDefinition Value)
    match
      ( #int <> #array (#values :: Query) <> #index (#i :: PatternInt) :: Pattern
      , #int
          <> #array (#values :: Query)
          <> #index (((#i :: PatternInt) + (1 :: Int)) :: PatternInt) :: Pattern)
      ((\(previous, next) -> do
          constrain $ right previous =| gapBy 2 |= left next
          constrain $ top previous =|= top next
          constrain $ height previous =|= height next) :: ( MatchedNode
                                                          , MatchedNode) -> ViewLayout
                                                                              ())
    match
      ((#decision <> #match) :: Query)
      ((node $ do
          centerText
          fill (tone #match_hue 0.6 0.86)
          stroke (tone #match_hue 0.82 0.32)
          strokeWidth (cellBy 0.05)
          zIndex 4
          radius (cellBy 0.26)
          fontSize (cellBy 0.34)
          position (vec2 #match_x #match_y)
          width matchWidth
          height matchHeight) :: NodeDefinition Match)

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------
cellBy :: Scalar -> Span
cellBy scale = #cell * scale

gapBy :: Scalar -> Span
gapBy scale = #gap * scale

tone :: HueExpr -> UnitExpr -> UnitExpr -> HslExpr
tone = Hsl

targetWidth :: Span
targetWidth = cellBy 2.1 |+| #gap

targetHeight :: Span
targetHeight = #cell |+| gapBy 0.8

probeSize :: Span
probeSize = cellBy 1.08

matchWidth :: Span
matchWidth = probeSize * 2 |+| #gap

matchHeight :: Span
matchHeight = cellBy 0.72

matchGap :: Span
matchGap = gapBy 0.7

half :: Span -> Span
half value = value / 2

midpoint :: Coord -> Coord -> Coord
midpoint lhs rhs = lhs + half (asSpan (rhs - lhs))

targetInsetX :: Span
targetInsetX = #gap |+| half targetWidth

targetInsetY :: Span
targetInsetY = #gap |+| half targetHeight

rowInset :: Span
rowInset = #gap |+| half #cell

probeOffsetY :: Span
probeOffsetY = half targetHeight |+| #gap |+| half probeSize

probeGap :: Span
probeGap = probeSize |+| #gap

probeRowClearance :: Span
probeRowClearance = half probeSize |+| #gap |+| half #cell

matchOffsetY :: Span
matchOffsetY = half probeSize |+| matchGap |+| half matchHeight

matchRowClearance :: Span
matchRowClearance = half matchHeight |+| matchGap |+| half #cell
