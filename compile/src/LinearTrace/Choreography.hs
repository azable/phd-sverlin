{-# LANGUAGE AllowAmbiguousTypes    #-}
{-# LANGUAGE DataKinds              #-}
{-# LANGUAGE FlexibleContexts       #-}
{-# LANGUAGE FlexibleInstances      #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE GADTs                  #-}
{-# LANGUAGE LinearTypes            #-}
{-# LANGUAGE NoImplicitPrelude      #-}
{-# LANGUAGE RebindableSyntax       #-}
{-# LANGUAGE ScopedTypeVariables    #-}
{-# LANGUAGE TypeApplications       #-}
{-# LANGUAGE TypeFamilies           #-}
{-# LANGUAGE UndecidableInstances   #-}

-- | Public choreography DSL. This is the intentionally thin user-facing layer
-- that couples core lifecycle events to symbolic view construction through
-- queries, match specs, tags, and view patches. It depends on 'LinearTrace.Core',
-- 'LinearTrace.Core.Events', 'LinearTrace.Choreography.Query',
-- 'LinearTrace.Choreography.Match', and the internal 'LinearTrace.View' facade.
module LinearTrace.Choreography
  ( -- * Program layer
    -- | Program execution and graph-building API. The core trace graph is built
    -- alongside a symbolic view graph, then solved through the view solver.
    Program
  , VisualTraceGraph
  , ViewGraph
  , visualTraceCore
  , buildViewGraph
  , solveViewGraphWithSeed
  , viewGraphStats
  , RandomSeed(..)
  , runProgram
  , runProgramWith
  , BranchDecision(..)
  , LoopResult(..)
  , create
  , copy
  , use
  , compute
  , computeWithTags
  , replace
  , retag
  , destroy
  , decide
  , checkpoint
  , loop
  , -- * Handles
    -- | Linear handles that track core payload lifecycle and allow the DSL to
    -- attach view behavior to block/event lifetimes.
    Block
  , SlotHandle
  , PayloadHandle
  , -- * Payloads and trace tags
    -- | Core payload/fact vocabulary plus choreography query and selection
    -- types. These are the stable DSL names for matching trace blocks and
    -- binding view nodes to them.
    Payload
  , FactValue(..)
  , Fact(..)
  , Facts(..)
  , emptyFacts
  , factAtom
  , factSymbol
  , factInt
  , factsUnion
  , factsToList
  , PayloadView(..)
  , Traceable(..)
  , LUnit(..)
  , LBool(..)
  , LInt(..)
  , LDouble(..)
  , LString(..)
  , type Create
  , type Observe
  , type Use
  , type Copy
  , type Replace
  , type Compute
  , type Destroy
  , type Seal
  , type Unseal
  , type Decide
  , (<$>)
  , (<*>)
  , Query
  , MatchSpec
  , QueryInt
  , queryIndex
  , TraceQuery
  , Selected
  , Variable(..)
  , Categorical(..)
  , Bound(..)
  , NodeBinding(..)
  , AnyPayload
  , Node
  , Select
  , select
  , VisualizationBuilder
  , QueryAppend
  , visualize
  , emptyQuery
  , queryAtom
  , queryInt
  , queryFacts
  , (<&>)
  , -- * Component and layout layer
    -- | Symbolic view/style DSL. These names ultimately lower to
    -- 'LinearTrace.View' primitives, patches, style fields, and solver
    -- constraints.
    NodeRecipe
  , NodeStyle
  , Opacity
  , ZIndex
  , Padding
  , FontSize
  , Radius
  , StrokeWidth
  , Alpha
  , Fill
  , Stroke
  , StyleChoice(..)
  , BorderStyle(..)
  , Bounds(..)
  , FontFamily(..)
  , FontWeight(..)
  , FontStyle(..)
  , Hsl(..)
  , Free
  , Unit
  , Angle
  , Color
  , Coord
  , Span
  , Offset
  , Scalar
  , Vec2(..)
  , TextAlign(..)
  , WhiteSpace(..)
  , Left
  , Top
  , Right
  , Bottom
  , Width
  , Height
  , X
  , Y
  , ContentValue
  , asUnit
  , asCoord
  , asSpan
  , at
  , bottom
  , bounds
  , by
  , bindContent
  , bindInt
  , center
  , content
  , payload
  , text
  , ensure
  , variable
  , variableFrom
  , choice
  , encourage
  , fromLabel
  , global
  , height
  , left
  , node
  , num
  , fromInteger
  , fromRational
  , pos
  , position
  , render
  , right
  , style
  , styleOf
  , sat
  , shift
  , size
  , top
  , vec2
  , width
  , x
  , y
  , (+)
  , (-)
  , (*)
  , (/)
  , (@:)
  , (.<=.)
  , (.>=.)
  , (.==.)
  , (=|)
  , (=/)
  , (|+|)
  , (|=)
  , (/=)
  ) where

import           Control.Functor.Linear                hiding ((<$>), (<&>),
                                                        (<*>))
import qualified Control.Functor.Linear.Internal.State as LinearState
import qualified Data.Functor.Linear                   as DFL
import           GHC.OverloadedLabels                  (IsLabel (..))
import           LinearTrace.Choreography.Match        (CategoryEndpoint,
                                                        CategoryRelation (..),
                                                        ConstraintStrength (..),
                                                        LayoutRelation (..),
                                                        MatchSpec,
                                                        NodeSelection (..),
                                                        ValueEndpoint,
                                                        buildMatchedViewGraph,
                                                        emptyMatchSpec,
                                                        matchCategoryRelation,
                                                        matchSpecAppend,
                                                        matchValueDirectedBridge,
                                                        matchValueRelation,
                                                        matchValueSymmetricBridge,
                                                        matchedNodeOutput,
                                                        rawCategoryEndpoint,
                                                        rawValueEndpoint,
                                                        selectionCategoryEndpoint,
                                                        selectionValueEndpoint,
                                                        traceNodeOfEventBlock)
import           LinearTrace.Choreography.Node         (Node, QueryAppend,
                                                        Select, content, node,
                                                        nodeSelection, payload,
                                                        render, select,
                                                        setNodeSpecWith,
                                                        visualize, (<&>))
import           LinearTrace.Choreography.Query        (Query, QueryInt (..),
                                                        emptyQuery, queryAtom,
                                                        queryFacts, queryInt,
                                                        queryIntAdd,
                                                        queryIntConst,
                                                        queryIntVar)
import           LinearTrace.Choreography.Style        (StyleChoice (..), sat,
                                                        style, styleOf)
import           LinearTrace.Choreography.Types
import           LinearTrace.Core                      (Block, Fact (..),
                                                        FactValue (..),
                                                        Facts (..), LBool (..),
                                                        LDouble (..), LInt (..),
                                                        LString (..),
                                                        LUnit (..), Payload,
                                                        PayloadView (..),
                                                        Traceable (..),
                                                        emptyFacts, factAtom,
                                                        factInt, factSymbol,
                                                        factsToList, factsUnion,
                                                        (<$>), (<*>))
import qualified LinearTrace.Core                      as C
import qualified LinearTrace.Core.Events               as E
import           LinearTrace.View                      (BorderStyle (..),
                                                        FontFamily (..),
                                                        FontStyle (..),
                                                        FontWeight (..),
                                                        NodeStyle,
                                                        TextAlign (..),
                                                        WhiteSpace (..))
import qualified LinearTrace.View                      as V
import           LinearTrace.View.Access               (CategoryAccess,
                                                        LayoutAttr (..),
                                                        ValueAccess,
                                                        layoutValueAccess)
import           LinearTrace.View.Primitives           (Angle, Bounds (..),
                                                        BoundsExpr, Color, Free,
                                                        Hsl (..), LayoutExpr,
                                                        Unit)
import           LinearTrace.View.Style                (Alpha, Fill, FontSize,
                                                        Opacity, Padding,
                                                        Radius, Stroke,
                                                        StrokeWidth, ZIndex)
import qualified Prelude                               as P
import           Prelude.Linear                        hiding (fromInteger,
                                                        fromRational, (*), (+),
                                                        (-), (/), (/=), (<>))
import qualified Solver                                as S
import           Solver                                (RandomSeed (..),
                                                        Vec2 (..), vec2)
import qualified Unsafe.Coerce                         as Unsafe

infixl 9 @:
data Program a where
  PureProgram :: a %1 -> Program a
  BindProgram :: Program a %1 -> (a %1 -> Program b) %1 -> Program b
  CreateProgram
    :: C.Traceable tag => C.Facts -> C.Payload tag %1 -> Program (Block tag)
  UseProgram :: C.Traceable tag => Block tag %1 -> Program (PayloadHandle tag)
  CopyProgram
    :: C.Traceable tag=> C.Facts
    -> Block tag
       %1 -> Program (Block tag, Block tag)
  ComputeProgram
    :: C.Traceable tag=> C.Facts
    -> (C.Payload tag -> C.Facts)
    -> PayloadHandle tag
       %1 -> Program (Block tag)
  ReplaceProgram
    :: C.Traceable tag => Block tag %1 -> Block tag %1 -> Program (Block tag)
  RetagProgram
    :: C.Traceable tag => C.Facts -> Block tag %1 -> Program (Block tag)
  DestroyProgram :: C.Traceable tag => Block tag %1 -> Program ()
  DecideProgram
    :: C.Traceable tag=> (C.Payload tag %1 -> Bool)
    -> Block tag
       %1 -> Program BranchDecision
  CheckpointProgram :: P.String -> Program ()
  LoopProgram
    :: state
       %1 -> (state %1 -> Program (LoopResult state output))
    -> Program output

data ViewScript acts where
  ViewScript :: V.ViewOutput -> ViewScript acts

data VisualTraceState where
  VisualTraceState
    :: Ur MatchSpec
       %1 -> Ur (E.TraceBuilderState ViewScript)
       %1 -> Ur E.EventLog
       %1 -> Ur V.ViewOutput
       %1 -> VisualTraceState

type VisualTraceBuilder a = State VisualTraceState a

instance Consumable VisualTraceState where
  consume (VisualTraceState spec coreState pendingEvents pendingOutput) =
    consume spec
      `lseq` consume coreState
      `lseq` consume pendingEvents
      `lseq` consume pendingOutput

instance Dupable VisualTraceState where
  dup2 (VisualTraceState spec coreState pendingEvents pendingOutput) =
    case dup2 spec of
      (spec1, spec2) ->
        case dup2 coreState of
          (coreState1, coreState2) ->
            case dup2 pendingEvents of
              (pendingEvents1, pendingEvents2) ->
                case dup2 pendingOutput of
                  (pendingOutput1, pendingOutput2) ->
                    ( VisualTraceState
                        spec1
                        coreState1
                        pendingEvents1
                        pendingOutput1
                    , VisualTraceState
                        spec2
                        coreState2
                        pendingEvents2
                        pendingOutput2)

data VisualTraceGraph =
  VisualTraceGraph MatchSpec (C.TraceGraphWith ViewScript)

data Retagged tag where
  Retagged
    :: C.Block tag
       %1 -> C.ExplainToken (C.Copy tag)
       %1 -> C.ExplainToken (C.Replace tag)
       %1 -> Retagged tag

type ViewGraph = V.ViewGraph

visualTraceCore :: VisualTraceGraph -> C.TraceGraphWith ViewScript
visualTraceCore graph =
  case graph of
    VisualTraceGraph _ coreGraph -> coreGraph

buildViewGraph :: VisualTraceGraph -> ViewGraph
buildViewGraph graph =
  case graph of
    VisualTraceGraph spec coreGraph ->
      let stepsOutput = viewTraceSteps (E.traceGraphSteps coreGraph)
       in buildMatchedViewGraph
            spec
            (builtSteps stepsOutput)
            (builtNodes stepsOutput)
            (builtConstraints stepsOutput)
            (builtChoiceConstraints stepsOutput)
            (builtRenderFrames stepsOutput)

solveViewGraphWithSeed :: RandomSeed -> ViewGraph -> P.IO S.Solution
solveViewGraphWithSeed = V.solveCSPWithSeed

viewGraphStats :: ViewGraph -> (P.Int, P.Int, P.Int, P.Int)
viewGraphStats graph =
  ( P.length (V.viewNodes graph)
  , P.length (V.viewSteps graph)
  , P.length (V.viewConstraints graph)
  , P.length (V.viewRenderFrames graph))

data BuiltViewStep = BuiltViewStep
  { stepView                 :: V.ViewStep
  , stepNodes                :: [V.ViewNode]
  , stepConstraints          :: [S.Constraint]
  , stepChoiceConstraints    :: [S.ChoiceConstraint]
  , stepRenderFrames         :: [[V.RenderIntent]]
  , stepPendingRenderIntents :: [V.RenderIntent]
  }

data BuiltViewSteps = BuiltViewSteps
  { builtSteps             :: [V.ViewStep]
  , builtNodes             :: [V.ViewNode]
  , builtConstraints       :: [S.Constraint]
  , builtChoiceConstraints :: [S.ChoiceConstraint]
  , builtRenderFrames      :: [[V.RenderIntent]]
  }

viewTraceSteps :: [E.TraceStepWith ViewScript] -> BuiltViewSteps
viewTraceSteps = viewTraceStepsWith viewTraceStep [] [] [] [] [] []

viewTraceStepsWith ::
     ([V.RenderIntent] -> record -> BuiltViewStep)
  -> [V.ViewStep]
  -> [V.ViewNode]
  -> [S.Constraint]
  -> [S.ChoiceConstraint]
  -> [[V.RenderIntent]]
  -> [V.RenderIntent]
  -> [record]
  -> BuiltViewSteps
viewTraceStepsWith buildStep steps nodes constraints choiceConstraints renderFrames pending records =
  case records of
    [] ->
      let finalOutput =
            V.flushViewOutput
              V.ViewOutput
                { V.emittedNodes = []
                , V.emittedConstraints = []
                , V.emittedChoiceConstraints = []
                , V.emittedRenderFrames = []
                , V.pendingRenderIntents = pending
                }
          finalFrames = renderFrames P.++ V.emittedRenderFrames finalOutput
          finalChoiceConstraints =
            choiceConstraints P.++ V.emittedChoiceConstraints finalOutput
       in BuiltViewSteps
            { builtSteps = steps
            , builtNodes = nodes
            , builtConstraints = constraints
            , builtChoiceConstraints = finalChoiceConstraints
            , builtRenderFrames = V.withImplicitInitialFrame finalFrames
            }
    record:rest ->
      let builtStep = buildStep pending record
       in viewTraceStepsWith
            buildStep
            (steps P.++ [stepView builtStep])
            (nodes P.++ stepNodes builtStep)
            (constraints P.++ stepConstraints builtStep)
            (choiceConstraints P.++ stepChoiceConstraints builtStep)
            (renderFrames P.++ stepRenderFrames builtStep)
            (stepPendingRenderIntents builtStep)
            rest

viewTraceStep :: [V.RenderIntent] -> E.TraceStepWith ViewScript -> BuiltViewStep
viewTraceStep pending step =
  case E.traceStepOutput step of
    E.ExplainedTraceStep label (ViewScript rawOutput) _plainStep ->
      let output = V.mergeInitialRenderIntents pending rawOutput
          nodes = V.emittedNodes output
          constraints = V.emittedConstraints output
          choiceConstraints = V.emittedChoiceConstraints output
          renderFrames = V.emittedRenderFrames output
       in BuiltViewStep
            { stepView = V.ViewStep label nodes constraints []
            , stepNodes = nodes
            , stepConstraints = constraints
            , stepChoiceConstraints = choiceConstraints
            , stepRenderFrames = renderFrames
            , stepPendingRenderIntents = V.pendingRenderIntents output
            }
    E.DiscardedTraceStep reason _plainStep ->
      BuiltViewStep
        { stepView = V.ViewStep ("Discarded: " P.++ reason) [] [] []
        , stepNodes = []
        , stepConstraints = []
        , stepChoiceConstraints = []
        , stepRenderFrames = []
        , stepPendingRenderIntents = pending
        }

type SlotHandle = C.Slot

type PayloadHandle tag = C.OneUse (C.Payload tag)

type Create tag = C.Create tag

type Observe tag = C.Observe tag

type Use tag = C.Use tag

type Copy tag = C.Copy tag

type Replace tag = C.Replace tag

type Compute tag = C.Compute tag

type Destroy tag = C.Destroy tag

type Seal owner tag = C.Seal owner tag

type Unseal owner tag = C.Unseal owner tag

type Decide tag = C.Decide tag

data BranchDecision
  = BranchTrue
  | BranchFalse

data LoopResult state output where
  Continue :: state %1 -> LoopResult state output
  Finish :: output %1 -> LoopResult state output

mapProgramWith :: (a %1 -> b) %1 -> a %1 -> Program b
mapProgramWith f value = PureProgram (f value)

liftProgramWith :: (a %1 -> b %1 -> c) %1 -> Program b %1 -> a %1 -> Program c
liftProgramWith f rhs leftValue =
  BindProgram rhs (finishProgramLift f leftValue)

finishProgramLift :: (a %1 -> b %1 -> c) %1 -> a %1 -> b %1 -> Program c
finishProgramLift f leftValue rightValue = PureProgram (f leftValue rightValue)

instance DFL.Functor Program where
  fmap f program = BindProgram program (mapProgramWith f)

instance Functor Program where
  fmap f program = BindProgram program (mapProgramWith f)

instance DFL.Applicative Program where
  pure = PureProgram
  liftA2 f lhs rhs = BindProgram lhs (liftProgramWith f rhs)

instance Applicative Program where
  pure = PureProgram
  liftA2 f lhs rhs = BindProgram lhs (liftProgramWith f rhs)

instance Monad Program where
  (>>=) = BindProgram

class ConstraintValue value where
  valueTerm :: value -> ValueTerm

rawValueTerm :: S.Component -> ValueTerm
rawValueTerm component = ValueTerm emptyMatchSpec [rawValueEndpoint component]

rawExprValueTerm ::
     S.SymbolicType ty => S.Expr ty -> [S.Constraint] -> ValueTerm
rawExprValueTerm expr constraints = rawValueTerm (S.component expr constraints)

selectedValueTerm :: Selected tag -> ValueAccess -> ValueTerm
selectedValueTerm selected access =
  ValueTerm
    (selectedSpec selected)
    [selectionValueEndpoint (selectedNodeSelection selected) access]

rawCategoryTerm ::
     S.ChoiceDomain value => S.ChoiceValue value -> CategoryTerm value
rawCategoryTerm value = CategoryTerm emptyMatchSpec [rawCategoryEndpoint value]

selectedCategoryTerm ::
     Selected tag -> CategoryAccess value -> CategoryTerm value
selectedCategoryTerm selected access =
  CategoryTerm
    (selectedSpec selected)
    [selectionCategoryEndpoint (selectedNodeSelection selected) access]

categoryTermSpec :: CategoryTerm value -> MatchSpec
categoryTermSpec term =
  case term of
    CategoryTerm spec _ -> spec

categoryTermEndpoints :: CategoryTerm value -> [CategoryEndpoint value]
categoryTermEndpoints term =
  case term of
    CategoryTerm _ endpoints -> endpoints

fixedCategoryTerm :: S.ChoiceDomain value => value -> CategoryTerm value
fixedCategoryTerm = rawCategoryTerm P.. S.Fixed

variableCategoryTerm ::
     S.ChoiceDomain value => Categorical value -> CategoryTerm value
variableCategoryTerm value =
  case value of
    Categorical selected -> rawCategoryTerm (S.Variable selected)

selectedCategoryValueTerm :: SelectionCategory value tag -> CategoryTerm value
selectedCategoryValueTerm selected =
  case selected of
    SelectionCategory selection access -> selectedCategoryTerm selection access

appendValueTerm :: ValueTerm -> ValueTerm -> ValueTerm
appendValueTerm lhs rhs =
  case lhs of
    ValueTerm lhsSpec lhsEndpoints ->
      case rhs of
        ValueTerm rhsSpec rhsEndpoints ->
          ValueTerm
            (lhsSpec `matchSpecAppend` rhsSpec)
            (lhsEndpoints P.++ rhsEndpoints)

instance ConstraintValue Coord where
  valueTerm value = rawExprValueTerm (coordExpr value) (coordConstraints value)

instance ConstraintValue Span where
  valueTerm value = rawExprValueTerm (spanExpr value) (spanConstraints value)

instance ConstraintValue Scalar where
  valueTerm value =
    rawExprValueTerm (scalarExpr value) (scalarConstraints value)

instance ConstraintValue Offset where
  valueTerm value =
    rawExprValueTerm (offsetExpr value) (offsetConstraints value)

instance S.SymbolicType ty => ConstraintValue (S.Expr ty) where
  valueTerm expr = rawExprValueTerm expr []

instance ConstraintValue (SelectionValue value tag) where
  valueTerm selected =
    case selected of
      SelectionValue selection access -> selectedValueTerm selection access

instance (ConstraintValue x, ConstraintValue y) => ConstraintValue (Vec2 x) where
  valueTerm value =
    case value of
      Vec2 valueX valueY -> valueTerm valueX `appendValueTerm` valueTerm valueY

instance (ConstraintValue hue, ConstraintValue unit) =>
         ConstraintValue (Hsl hue unit) where
  valueTerm value =
    valueTerm (hue value)
      `appendValueTerm` valueTerm (saturation value)
      `appendValueTerm` valueTerm (lightness value)

selectedSpec :: Selected tag -> MatchSpec
selectedSpec selected =
  case selected of
    SelectedHandle selection ->
      case selection of
        Selection _ spec -> spec

selectedNodeSelection :: Selected tag -> NodeSelection
selectedNodeSelection selected =
  case selected of
    SelectedHandle selection ->
      case selection of
        Selection handle _ -> nodeSelection handle

nonNegative :: LayoutExpr -> S.Constraint
nonNegative expr = (S.num 0 :: LayoutExpr) S.@<=@ expr

mkCoord :: LayoutExpr -> [S.Constraint] -> Coord
mkCoord expr constraints =
  LayoutValue expr (constraints P.++ [nonNegative expr])

mkSpan :: LayoutExpr -> [S.Constraint] -> Span
mkSpan expr constraints = LayoutValue expr (constraints P.++ [nonNegative expr])

mkOffset :: LayoutExpr -> [S.Constraint] -> Offset
mkOffset = LayoutValue

mkScalar :: LayoutExpr -> [S.Constraint] -> Scalar
mkScalar = LayoutValue

class NumExpr a where
  num :: P.Double -> a

class IntegerLiteral a where
  integerLiteral :: P.Integer -> a

class RationalLiteral a where
  rationalLiteral :: P.Rational -> a

fromInteger :: IntegerLiteral a => P.Integer -> a
fromInteger = integerLiteral

fromRational :: RationalLiteral a => P.Rational -> a
fromRational = rationalLiteral

instance S.SymbolicType ty => NumExpr (S.Expr ty) where
  num = S.num

instance S.SymbolicType ty => IntegerLiteral (S.Expr ty) where
  integerLiteral value = S.num (P.fromInteger value)

instance S.SymbolicType ty => RationalLiteral (S.Expr ty) where
  rationalLiteral value = S.num (P.fromRational value)

instance IntegerLiteral P.Int where
  integerLiteral = P.fromInteger

instance IntegerLiteral P.Integer where
  integerLiteral = P.fromInteger

instance IntegerLiteral P.Double where
  integerLiteral = P.fromInteger

instance RationalLiteral P.Double where
  rationalLiteral = P.fromRational

instance NumExpr Coord where
  num value = mkCoord (S.num value :: LayoutExpr) []

instance IntegerLiteral Coord where
  integerLiteral value = num (P.fromInteger value)

instance RationalLiteral Coord where
  rationalLiteral value = num (P.fromRational value)

instance NumExpr Span where
  num value = mkSpan (S.num value :: LayoutExpr) []

instance IntegerLiteral Span where
  integerLiteral value = num (P.fromInteger value)

instance RationalLiteral Span where
  rationalLiteral value = num (P.fromRational value)

instance NumExpr Offset where
  num value = mkOffset (S.num value :: LayoutExpr) []

instance IntegerLiteral Offset where
  integerLiteral value = num (P.fromInteger value)

instance RationalLiteral Offset where
  rationalLiteral value = num (P.fromRational value)

instance NumExpr Scalar where
  num value = mkScalar (S.num value :: LayoutExpr) []

instance IntegerLiteral Scalar where
  integerLiteral value = num (P.fromInteger value)

instance RationalLiteral Scalar where
  rationalLiteral value = num (P.fromRational value)

instance IntegerLiteral QueryInt where
  integerLiteral value = queryIntConst (P.fromInteger value)

queryIndex :: P.Int -> QueryInt
queryIndex = queryIntConst

(@:) :: (QueryInt -> query) -> QueryInt -> query
(@:) buildField = buildField

at :: P.Double -> Coord
at = num

by :: P.Double -> Span
by = num

shift :: P.Double -> Offset
shift = num

global :: VariableValue value => P.String -> value
global = namedVariable

globalCoord :: P.String -> Coord
globalCoord name = mkCoord (global name :: LayoutExpr) []

globalSpan :: P.String -> Span
globalSpan name = mkSpan (global name :: LayoutExpr) []

queryIntExpr :: S.SymbolicType ty => QueryInt -> S.Expr ty
queryIntExpr queryIntValue =
  case queryIntValue of
    QueryIntConst value -> S.num (P.fromIntegral value)
    QueryIntVar name -> V.global name
    QueryIntAdd base offset ->
      queryIntExpr base S.@+@ S.num (P.fromIntegral offset)

asUnit :: QueryInt -> Unit
asUnit = queryIntExpr

asCoord :: Offset -> Coord
asCoord value = mkCoord (offsetExpr value) (offsetConstraints value)

asSpan :: Offset -> Span
asSpan value = mkSpan (offsetExpr value) (offsetConstraints value)

class AddExpr lhs rhs result
  | lhs rhs -> result
  , lhs result -> rhs
  , result -> lhs rhs
  where
  addExpr :: lhs -> rhs -> result

instance S.SymbolicType ty => AddExpr (S.Expr ty) (S.Expr ty) (S.Expr ty) where
  addExpr = (S.@+@)

instance AddExpr P.Int P.Int P.Int where
  addExpr = (P.+)

instance AddExpr P.Integer P.Integer P.Integer where
  addExpr = (P.+)

instance AddExpr P.Double P.Double P.Double where
  addExpr = (P.+)

instance AddExpr QueryInt P.Int QueryInt where
  addExpr = queryIntAdd

instance AddExpr Coord Span Coord where
  addExpr lhs rhs =
    mkCoord
      (coordExpr lhs S.@+@ spanExpr rhs)
      (coordConstraints lhs P.++ spanConstraints rhs)

instance AddExpr Offset Span Offset where
  addExpr lhs rhs =
    mkOffset
      (offsetExpr lhs S.@+@ spanExpr rhs)
      (offsetConstraints lhs P.++ spanConstraints rhs)

class SubExpr lhs rhs result | lhs rhs -> result where
  subExpr :: lhs -> rhs -> result

instance S.SymbolicType ty => SubExpr (S.Expr ty) (S.Expr ty) (S.Expr ty) where
  subExpr = (S.@-@)

instance SubExpr P.Int P.Int P.Int where
  subExpr = (P.-)

instance SubExpr P.Integer P.Integer P.Integer where
  subExpr = (P.-)

instance SubExpr P.Double P.Double P.Double where
  subExpr = (P.-)

instance SubExpr Coord Span Offset where
  subExpr lhs rhs =
    mkOffset
      (coordExpr lhs S.@-@ spanExpr rhs)
      (coordConstraints lhs P.++ spanConstraints rhs)

instance SubExpr Coord Coord Offset where
  subExpr lhs rhs =
    mkOffset
      (coordExpr lhs S.@-@ coordExpr rhs)
      (coordConstraints lhs P.++ coordConstraints rhs)

instance SubExpr Span Span Offset where
  subExpr lhs rhs =
    mkOffset
      (spanExpr lhs S.@-@ spanExpr rhs)
      (spanConstraints lhs P.++ spanConstraints rhs)

instance SubExpr Offset Span Offset where
  subExpr lhs rhs =
    mkOffset
      (offsetExpr lhs S.@-@ spanExpr rhs)
      (offsetConstraints lhs P.++ spanConstraints rhs)

instance SubExpr Offset Offset Offset where
  subExpr lhs rhs =
    mkOffset
      (offsetExpr lhs S.@-@ offsetExpr rhs)
      (offsetConstraints lhs P.++ offsetConstraints rhs)

class MulExpr lhs rhs result
  | lhs rhs -> result
  , lhs result -> rhs
  , rhs result -> lhs
  , result -> lhs rhs
  where
  mulExpr :: lhs -> rhs -> result

instance S.SymbolicType ty => MulExpr (S.Expr ty) (S.Expr ty) (S.Expr ty) where
  mulExpr = (S.@*@)

instance MulExpr P.Int P.Int P.Int where
  mulExpr = (P.*)

instance MulExpr P.Integer P.Integer P.Integer where
  mulExpr = (P.*)

instance MulExpr P.Double P.Double P.Double where
  mulExpr = (P.*)

instance MulExpr Span Scalar Span where
  mulExpr lhs rhs =
    mkSpan
      (spanExpr lhs S.@*@ scalarExpr rhs)
      (spanConstraints lhs P.++ scalarConstraints rhs)

instance MulExpr Offset Scalar Offset where
  mulExpr lhs rhs =
    mkOffset
      (offsetExpr lhs S.@*@ scalarExpr rhs)
      (offsetConstraints lhs P.++ scalarConstraints rhs)

instance MulExpr Scalar Scalar Scalar where
  mulExpr lhs rhs =
    mkScalar
      (scalarExpr lhs S.@*@ scalarExpr rhs)
      (scalarConstraints lhs P.++ scalarConstraints rhs)

class DivExpr lhs rhs result
  | lhs rhs -> result
  , lhs result -> rhs
  , result -> lhs rhs
  where
  divExpr :: lhs -> rhs -> result

instance S.SymbolicType ty => DivExpr (S.Expr ty) (S.Expr ty) (S.Expr ty) where
  divExpr = (S.@/@)

instance DivExpr P.Double P.Double P.Double where
  divExpr = (P./)

instance DivExpr Span Scalar Span where
  divExpr lhs rhs =
    mkSpan
      (spanExpr lhs S.@/@ scalarExpr rhs)
      (spanConstraints lhs P.++ scalarConstraints rhs)

instance DivExpr Offset Scalar Offset where
  divExpr lhs rhs =
    mkOffset
      (offsetExpr lhs S.@/@ scalarExpr rhs)
      (offsetConstraints lhs P.++ scalarConstraints rhs)

instance DivExpr Scalar Scalar Scalar where
  divExpr lhs rhs =
    mkScalar
      (scalarExpr lhs S.@/@ scalarExpr rhs)
      (scalarConstraints lhs P.++ scalarConstraints rhs)

infixl 6 +
infixl 6 -
infixl 6 |+|
infixl 7 *
infixl 7 /
(+) :: AddExpr lhs rhs result => lhs -> rhs -> result
(+) = addExpr

(-) :: SubExpr lhs rhs result => lhs -> rhs -> result
(-) = subExpr

(*) :: MulExpr lhs rhs result => lhs -> rhs -> result
(*) = mulExpr

(/) :: DivExpr lhs rhs result => lhs -> rhs -> result
(/) = divExpr

(|+|) :: Span -> Span -> Span
lhs |+| rhs =
  mkSpan
    (spanExpr lhs S.@+@ spanExpr rhs)
    (spanConstraints lhs P.++ spanConstraints rhs)

class RelateValues lhs rhs where
  relateValues :: LayoutRelation -> lhs -> rhs -> VisualConstraint

instance {-# OVERLAPPABLE #-} (ConstraintValue lhs, ConstraintValue rhs) =>
         RelateValues lhs rhs where
  relateValues relation lhs rhs =
    VisualValueRelation (valueTerm lhs) relation (valueTerm rhs)

relateCategories ::
     S.ChoiceDomain value
  => LayoutRelation
  -> CategoryTerm value
  -> CategoryTerm value
  -> VisualConstraint
relateCategories relation lhs rhs =
  case relation of
    LayoutEqual -> VisualCategoryRelation lhs CategoryEqual rhs
    LayoutLessOrEqual ->
      P.error "Categorical values do not support ordered relations."

instance S.ChoiceDomain value => RelateValues (Categorical value) value where
  relateValues relation lhs rhs =
    relateCategories relation (variableCategoryTerm lhs) (fixedCategoryTerm rhs)

instance S.ChoiceDomain value =>
         RelateValues (Categorical value) (Categorical value) where
  relateValues relation lhs rhs =
    relateCategories
      relation
      (variableCategoryTerm lhs)
      (variableCategoryTerm rhs)

instance S.ChoiceDomain value =>
         RelateValues (SelectionCategory value tag) value where
  relateValues relation lhs rhs =
    relateCategories
      relation
      (selectedCategoryValueTerm lhs)
      (fixedCategoryTerm rhs)

instance S.ChoiceDomain value =>
         RelateValues (SelectionCategory value tag) (Categorical value) where
  relateValues relation lhs rhs =
    relateCategories
      relation
      (selectedCategoryValueTerm lhs)
      (variableCategoryTerm rhs)

instance S.ChoiceDomain value =>
         RelateValues
           (SelectionCategory value lhsTag)
           (SelectionCategory value rhsTag) where
  relateValues relation lhs rhs =
    relateCategories
      relation
      (selectedCategoryValueTerm lhs)
      (selectedCategoryValueTerm rhs)

data DirectedBridge =
  DirectedBridge ValueTerm ValueTerm

class OpenDirectedBridge lhs gap where
  openDirectedBridge :: lhs -> gap -> DirectedBridge

instance {-# OVERLAPPABLE #-} (ConstraintValue lhs, ConstraintValue gap) =>
         OpenDirectedBridge lhs gap where
  openDirectedBridge lhs gap = DirectedBridge (valueTerm lhs) (valueTerm gap)

class CloseDirectedBridge bridge rhs where
  closeDirectedBridge :: bridge -> rhs -> VisualConstraint

instance {-# OVERLAPPABLE #-} ConstraintValue rhs =>
         CloseDirectedBridge DirectedBridge rhs where
  closeDirectedBridge bridge rhs =
    case bridge of
      DirectedBridge lhs gap -> VisualDirectedBridge lhs gap (valueTerm rhs)

data SymmetricBridge =
  SymmetricBridge ValueTerm ValueTerm

class OpenSymmetricBridge lhs delta where
  openSymmetricBridge :: lhs -> delta -> SymmetricBridge

instance {-# OVERLAPPABLE #-} (ConstraintValue lhs, ConstraintValue delta) =>
         OpenSymmetricBridge lhs delta where
  openSymmetricBridge lhs delta =
    SymmetricBridge (valueTerm lhs) (valueTerm delta)

class CloseSymmetricBridge bridge rhs where
  closeSymmetricBridge :: bridge -> rhs -> VisualConstraint

instance {-# OVERLAPPABLE #-} ConstraintValue rhs =>
         CloseSymmetricBridge SymmetricBridge rhs where
  closeSymmetricBridge bridge rhs =
    case bridge of
      SymmetricBridge lhs delta ->
        VisualSymmetricBridge lhs delta (valueTerm rhs)

class NotEqualOrClose lhs rhs where
  notEqualOrClose :: lhs -> rhs -> VisualConstraint

instance {-# OVERLAPPABLE #-} CloseSymmetricBridge bridge rhs =>
         NotEqualOrClose bridge rhs where
  notEqualOrClose = closeSymmetricBridge

differentCategories ::
     S.ChoiceDomain value
  => CategoryTerm value
  -> CategoryTerm value
  -> VisualConstraint
differentCategories lhs = VisualCategoryRelation lhs CategoryDifferent

instance S.ChoiceDomain value => NotEqualOrClose (Categorical value) value where
  notEqualOrClose lhs rhs =
    differentCategories (variableCategoryTerm lhs) (fixedCategoryTerm rhs)

instance S.ChoiceDomain value =>
         NotEqualOrClose (Categorical value) (Categorical value) where
  notEqualOrClose lhs rhs =
    differentCategories (variableCategoryTerm lhs) (variableCategoryTerm rhs)

instance S.ChoiceDomain value =>
         NotEqualOrClose (SelectionCategory value tag) value where
  notEqualOrClose lhs rhs =
    differentCategories (selectedCategoryValueTerm lhs) (fixedCategoryTerm rhs)

instance S.ChoiceDomain value =>
         NotEqualOrClose (SelectionCategory value tag) (Categorical value) where
  notEqualOrClose lhs rhs =
    differentCategories
      (selectedCategoryValueTerm lhs)
      (variableCategoryTerm rhs)

instance S.ChoiceDomain value =>
         NotEqualOrClose
           (SelectionCategory value lhsTag)
           (SelectionCategory value rhsTag) where
  notEqualOrClose lhs rhs =
    differentCategories
      (selectedCategoryValueTerm lhs)
      (selectedCategoryValueTerm rhs)

infixl 4 .<=.
infixl 4 .>=.
infixl 4 .==.
infixl 4 =|
infixl 4 |=
infixl 4 =/
infixl 4 /=
(.<=.) :: RelateValues lhs rhs => lhs -> rhs -> VisualConstraint
(.<=.) = relateValues LayoutLessOrEqual

(.>=.) :: RelateValues rhs lhs => lhs -> rhs -> VisualConstraint
lhs .>=. rhs = relateValues LayoutLessOrEqual rhs lhs

(.==.) :: RelateValues lhs rhs => lhs -> rhs -> VisualConstraint
(.==.) = relateValues LayoutEqual

(=|) :: OpenDirectedBridge lhs gap => lhs -> gap -> DirectedBridge
lhs =| rhs = openDirectedBridge lhs rhs

(|=) :: CloseDirectedBridge bridge rhs => bridge -> rhs -> VisualConstraint
lhs |= rhs = closeDirectedBridge lhs rhs

(=/) :: OpenSymmetricBridge lhs delta => lhs -> delta -> SymmetricBridge
lhs =/ delta = openSymmetricBridge lhs delta

(/=) :: NotEqualOrClose lhs rhs => lhs -> rhs -> VisualConstraint
lhs /= rhs = notEqualOrClose lhs rhs

unsafeUr :: forall a. a %1 -> Ur a
unsafeUr = Unsafe.unsafeCoerce (Ur :: a -> Ur a)

initialVisualTraceState :: MatchSpec -> VisualTraceState
initialVisualTraceState spec =
  VisualTraceState
    (Ur spec)
    (Ur E.emptyTraceBuilderState)
    (Ur E.emptyEventLog)
    (Ur V.emptyViewOutput)

runVisualTraceBuilder :: MatchSpec -> VisualTraceBuilder () -> VisualTraceGraph
runVisualTraceBuilder spec builder =
  let (_result, finalState) = runState builder (initialVisualTraceState spec)
      VisualTraceState _spec (Ur coreState) _pendingEvents _pendingOutput =
        finalState
   in VisualTraceGraph spec (E.traceBuilderStateGraph coreState)

runCoreBuilder :: C.TraceBuilderWith ViewScript a -> VisualTraceBuilder a
runCoreBuilder builder =
  LinearState.state
    (\(VisualTraceState spec (Ur coreState) pendingEvents pendingOutput) ->
       let (result, nextCoreState) =
             E.runTraceBuilderWithState builder coreState
        in ( result
           , VisualTraceState
               spec
               (Ur nextCoreState)
               pendingEvents
               pendingOutput))

retagCore ::
     C.Traceable tag
  => C.Facts
  -> C.Block tag
     %1 -> C.TraceBuilderWith ViewScript (Retagged tag)
retagCore facts block = do
  C.Copied original incoming copyToken <- C.copyTagged facts block
  C.Replaced output replaceToken <- C.replace original incoming
  return (Retagged output copyToken replaceToken)

appendPendingEvent :: E.EventToken act -> VisualTraceBuilder ()
appendPendingEvent eventToken = do
  VisualTraceState spec coreState (Ur pendingEvents) pendingOutput <- get
  put
    (VisualTraceState
       spec
       coreState
       (Ur (E.appendEventToken pendingEvents eventToken))
       pendingOutput)

takePendingEvents :: VisualTraceBuilder (Ur E.EventLog)
takePendingEvents = do
  VisualTraceState spec coreState (Ur pendingEvents) pendingOutput <- get
  put (VisualTraceState spec coreState (Ur E.emptyEventLog) pendingOutput)
  return (Ur pendingEvents)

appendViewOutput :: V.ViewOutput -> VisualTraceBuilder ()
appendViewOutput newOutput = do
  VisualTraceState spec coreState pendingEvents (Ur oldOutput) <- get
  put
    (VisualTraceState
       spec
       coreState
       pendingEvents
       (Ur (V.appendViewOutput oldOutput newOutput)))

takePendingOutput :: VisualTraceBuilder (Ur V.ViewOutput)
takePendingOutput = do
  VisualTraceState spec coreState pendingEvents (Ur pendingOutput) <- get
  put (VisualTraceState spec coreState pendingEvents (Ur V.emptyViewOutput))
  return (Ur pendingOutput)

recordExplainEvent ::
     C.ExplainToken act %1 -> VisualTraceBuilder (E.TraceEvent act)
recordExplainEvent explainToken =
  case E.eventTokenFromExplainToken explainToken of
    Ur eventToken -> do
      appendPendingEvent eventToken
      return (E.eventTokenEvent eventToken)

appendExplainEvent :: C.ExplainToken act %1 -> VisualTraceBuilder ()
appendExplainEvent explainToken =
  case E.eventTokenFromExplainToken explainToken of
    Ur eventToken -> appendPendingEvent eventToken

appendMatchedBlock ::
     C.Traceable tag => E.EventBlock tag -> VisualTraceBuilder ()
appendMatchedBlock block =
  LinearState.state
    (\(VisualTraceState (Ur spec) coreState pendingEvents (Ur oldOutput)) ->
       let nextOutput =
             V.appendViewOutput oldOutput (matchedNodeOutput spec block)
        in ( ()
           , VisualTraceState (Ur spec) coreState pendingEvents (Ur nextOutput)))

appendRenderIntent :: V.RenderIntent -> VisualTraceBuilder ()
appendRenderIntent intent = appendViewOutput (V.renderIntentOutput intent)

checkpointTrace :: P.String -> VisualTraceBuilder ()
checkpointTrace label = do
  Ur eventLog <- takePendingEvents
  Ur output <- takePendingOutput
  let output' = V.flushViewOutput output
  runCoreBuilder (E.explainEventLogWith label (ViewScript output') eventLog)

runProgram :: Program () -> VisualTraceGraph
runProgram = runProgramWith emptyMatchSpec

runProgramWith :: MatchSpec -> Program () -> VisualTraceGraph
runProgramWith spec program =
  runVisualTraceBuilder spec (interpretProgram program)

create ::
     forall tag. C.Traceable tag
  => Query
  -> C.Payload tag
     %1 -> Program (Block tag)
create query = CreateProgram (queryFacts query)

use ::
     forall tag. C.Traceable tag
  => Block tag
     %1 -> Program (PayloadHandle tag)
use = UseProgram

copy ::
     forall tag. C.Traceable tag
  => Query
  -> Block tag
     %1 -> Program (Block tag, Block tag)
copy query = CopyProgram (queryFacts query)

compute ::
     forall tag. C.Traceable tag
  => Query
  -> PayloadHandle tag
     %1 -> Program (Block tag)
compute query = computeWithTags query (P.const emptyQuery)

computeWithTags ::
     forall tag. C.Traceable tag
  => Query
  -> (Payload tag -> Query)
  -> PayloadHandle tag
     %1 -> Program (Block tag)
computeWithTags query selectQuery =
  ComputeProgram (queryFacts query) selectFacts
  where
    selectFacts outputPayload = queryFacts (selectQuery outputPayload)

replace ::
     forall tag. C.Traceable tag
  => Block tag
     %1 -> Block tag
     %1 -> Program (Block tag)
replace = ReplaceProgram

retag ::
     forall tag. C.Traceable tag
  => Query
  -> Block tag
     %1 -> Program (Block tag)
retag query = RetagProgram (queryFacts query)

destroy ::
     forall tag. C.Traceable tag
  => Block tag
     %1 -> Program ()
destroy = DestroyProgram

decide ::
     forall tag. C.Traceable tag
  => (C.Payload tag %1 -> Bool)
  -> Block tag
     %1 -> Program BranchDecision
decide = DecideProgram

checkpoint :: P.String -> Program ()
checkpoint = CheckpointProgram

loop ::
     state
     %1 -> (state %1 -> Program (LoopResult state output))
  -> Program output
loop = LoopProgram

interpretProgram :: Program a %1 -> VisualTraceBuilder a
interpretProgram program =
  case program of
    PureProgram value -> return value
    BindProgram first next -> do
      value <- interpretProgram first
      interpretProgram (next value)
    CreateProgram facts createPayload -> do
      case unsafeUr createPayload of
        Ur payloadValue -> do
          C.Created block explainToken <-
            runCoreBuilder (C.createTagged facts payloadValue)
          event <- recordExplainEvent explainToken
          case event of
            E.TraceCreate eventBlock -> do
              let viewNode = traceNodeOfEventBlock eventBlock
              appendMatchedBlock eventBlock
              appendRenderIntent (V.RenderFresh (V.nodeRef viewNode))
              return block
    UseProgram block -> do
      case unsafeUr block of
        Ur block' -> do
          C.Used usedPayload explainToken <- runCoreBuilder (C.use block')
          event <- recordExplainEvent explainToken
          case event of
            E.TraceUse eventBlock -> do
              let viewNode = traceNodeOfEventBlock eventBlock
              appendRenderIntent (V.RenderRemove (V.nodeRef viewNode))
              return usedPayload
    CopyProgram facts block -> do
      case unsafeUr block of
        Ur block' -> do
          C.Copied original copy' explainToken <-
            runCoreBuilder (C.copyTagged facts block')
          event <- recordExplainEvent explainToken
          case event of
            E.TraceCopy originalEvent copyEvent -> do
              let originalNode = traceNodeOfEventBlock originalEvent
              let copyNode = traceNodeOfEventBlock copyEvent
              appendMatchedBlock copyEvent
              appendRenderIntent
                (V.RenderFork (V.nodeRef originalNode) (V.nodeRef copyNode))
              return (original, copy')
    ComputeProgram facts selectFacts computePayload -> do
      case unsafeUr computePayload of
        Ur payloadValue -> do
          C.Computed block explainToken <-
            runCoreBuilder (C.computeTaggedWith facts selectFacts payloadValue)
          event <- recordExplainEvent explainToken
          case event of
            E.TraceCompute eventBlock -> do
              let viewNode = traceNodeOfEventBlock eventBlock
              appendMatchedBlock eventBlock
              appendRenderIntent (V.RenderFresh (V.nodeRef viewNode))
              return block
    ReplaceProgram oldBlock incomingBlock -> do
      case unsafeUr oldBlock of
        Ur oldBlock' ->
          case unsafeUr incomingBlock of
            Ur incomingBlock' -> do
              C.Replaced output explainToken <-
                runCoreBuilder (C.replace oldBlock' incomingBlock')
              event <- recordExplainEvent explainToken
              case event of
                E.TraceReplace oldEvent incomingEvent outputEvent -> do
                  let oldView = traceNodeOfEventBlock oldEvent
                  let incomingView = traceNodeOfEventBlock incomingEvent
                  let outputView = traceNodeOfEventBlock outputEvent
                  appendMatchedBlock outputEvent
                  appendRenderIntent
                    (V.RenderContinue (V.nodeRef oldView) (V.nodeRef outputView))
                  appendRenderIntent (V.RenderRemove (V.nodeRef incomingView))
                  return output
    RetagProgram facts block -> do
      case unsafeUr block of
        Ur block' -> do
          Retagged output copyToken explainToken <-
            runCoreBuilder (retagCore facts block')
          appendExplainEvent copyToken
          event <- recordExplainEvent explainToken
          case event of
            E.TraceReplace oldEvent _incomingEvent outputEvent -> do
              let oldView = traceNodeOfEventBlock oldEvent
              let outputView = traceNodeOfEventBlock outputEvent
              appendMatchedBlock outputEvent
              appendRenderIntent
                (V.RenderContinue (V.nodeRef oldView) (V.nodeRef outputView))
              return output
    DestroyProgram block -> do
      case unsafeUr block of
        Ur block' -> do
          C.Destroyed explainToken <- runCoreBuilder (C.destroy block')
          event <- recordExplainEvent explainToken
          case event of
            E.TraceDestroy eventBlock -> do
              let viewNode = traceNodeOfEventBlock eventBlock
              appendRenderIntent (V.RenderRemove (V.nodeRef viewNode))
              return ()
    DecideProgram predicate block -> do
      decision <-
        case unsafeUr block of
          Ur block' -> runCoreBuilder (C.decide predicate block')
      case decision of
        C.DecidedTrue explainToken -> do
          event <- recordExplainEvent explainToken
          case event of
            E.TraceDecide eventBlock -> do
              let viewNode = traceNodeOfEventBlock eventBlock
              appendRenderIntent (V.RenderRemove (V.nodeRef viewNode))
              return BranchTrue
        C.DecidedFalse explainToken -> do
          event <- recordExplainEvent explainToken
          case event of
            E.TraceDecide eventBlock -> do
              let viewNode = traceNodeOfEventBlock eventBlock
              appendRenderIntent (V.RenderRemove (V.nodeRef viewNode))
              return BranchFalse
    CheckpointProgram label -> checkpointTrace label
    LoopProgram loopState body -> interpretLoop loopState body

interpretLoop ::
     state
     %1 -> (state %1 -> Program (LoopResult state output))
  -> VisualTraceBuilder output
interpretLoop loopState body = do
  result <- interpretProgram (body loopState)
  case result of
    Continue nextState -> interpretLoop nextState body
    Finish output      -> return output

ensure :: VisualConstraint -> VisualizationBuilder ()
ensure = emitConstraint EnsureConstraint

encourage :: VisualConstraint -> VisualizationBuilder ()
encourage = emitConstraint EncourageConstraint

emitConstraint ::
     ConstraintStrength -> VisualConstraint -> VisualizationBuilder ()
emitConstraint strength constraint =
  emitVisualizationBuilder () (visualConstraintSpec strength constraint)

visualConstraintSpec :: ConstraintStrength -> VisualConstraint -> MatchSpec
visualConstraintSpec strength constraint =
  case constraint of
    VisualValueRelation lhs relation rhs ->
      valueTermSpec lhs
        `matchSpecAppend` valueTermSpec rhs
        `matchSpecAppend` matchValueRelation
                            strength
                            (valueTermEndpoints lhs)
                            relation
                            (valueTermEndpoints rhs)
    VisualCategoryRelation lhs relation rhs ->
      categoryTermSpec lhs
        `matchSpecAppend` categoryTermSpec rhs
        `matchSpecAppend` matchCategoryRelation
                            strength
                            (categoryTermEndpoints lhs)
                            relation
                            (categoryTermEndpoints rhs)
    VisualDirectedBridge lhs gap rhs ->
      valueTermSpec lhs
        `matchSpecAppend` valueTermSpec gap
        `matchSpecAppend` valueTermSpec rhs
        `matchSpecAppend` matchValueDirectedBridge
                            strength
                            (valueTermEndpoints lhs)
                            (valueTermEndpoints gap)
                            (valueTermEndpoints rhs)
    VisualSymmetricBridge lhs delta rhs ->
      valueTermSpec lhs
        `matchSpecAppend` valueTermSpec delta
        `matchSpecAppend` valueTermSpec rhs
        `matchSpecAppend` matchValueSymmetricBridge
                            strength
                            (valueTermEndpoints lhs)
                            (valueTermEndpoints delta)
                            (valueTermEndpoints rhs)

valueTermSpec :: ValueTerm -> MatchSpec
valueTermSpec term =
  case term of
    ValueTerm spec _ -> spec

valueTermEndpoints :: ValueTerm -> [ValueEndpoint]
valueTermEndpoints term =
  case term of
    ValueTerm _ endpoints -> endpoints

class VariableValue value where
  namedVariable :: P.String -> value

instance VariableValue Coord where
  namedVariable = globalCoord

instance VariableValue Span where
  namedVariable = globalSpan

instance VariableValue Offset where
  namedVariable name = mkOffset (global name :: LayoutExpr) []

instance VariableValue Scalar where
  namedVariable name = mkScalar (global name :: LayoutExpr) []

instance S.SymbolicType ty => VariableValue (S.Expr ty) where
  namedVariable = V.global

instance S.ChoiceDomain value => VariableValue (Categorical value) where
  namedVariable = Categorical P.. S.choice

bindInt :: VisualizationBuilder (Bound QueryInt)
bindInt = freshVisualizationValue "view.bind." (Bound P.. queryIntVar)

bindContent :: VisualizationBuilder (Bound ContentValue)
bindContent =
  freshVisualizationValue "view.bind." (Bound P.. ContentBinding P.. Binding)

variable ::
     forall value. VariableValue value
  => VisualizationBuilder (Variable value)
variable =
  freshVisualizationValue "view.var." (Variable P.. namedVariable @value)

variableFrom :: forall value. value -> VisualizationBuilder (Variable value)
variableFrom rhs = emptyVisualizationBuilder (Variable rhs)

choice ::
     forall value. S.ChoiceDomain value
  => VisualizationBuilder (Variable (Categorical value))
choice = variable @(Categorical value)

class Left input output | input -> output, output -> input where
  left :: input -> output

class Top input output | input -> output, output -> input where
  top :: input -> output

class Width input output | input -> output, output -> input where
  width :: input -> output

class Height input output | input -> output, output -> input where
  height :: input -> output

class Right input output | input -> output, output -> input where
  right :: input -> output

class Bottom input output | input -> output, output -> input where
  bottom :: input -> output

class X input output | input -> output, output -> input where
  x :: input -> output

class Y input output | input -> output, output -> input where
  y :: input -> output

instance Left Coord (NodeRecipe ()) where
  left value = setNodeSpecWith (\spec -> spec {nodeSpecLeft = Just value})

instance Top Coord (NodeRecipe ()) where
  top value = setNodeSpecWith (\spec -> spec {nodeSpecTop = Just value})

instance Width Span (NodeRecipe ()) where
  width value = setNodeSpecWith (\spec -> spec {nodeSpecWidth = Just value})

instance Height Span (NodeRecipe ()) where
  height value = setNodeSpecWith (\spec -> spec {nodeSpecHeight = Just value})

instance Right Coord (NodeRecipe ()) where
  right value = setNodeSpecWith (\spec -> spec {nodeSpecRight = Just value})

instance Bottom Coord (NodeRecipe ()) where
  bottom value = setNodeSpecWith (\spec -> spec {nodeSpecBottom = Just value})

instance Left (Selected tag) (SelectionValue Coord tag) where
  left selection = SelectionValue selection (layoutValueAccess AttrLeft)

instance Top (Selected tag) (SelectionValue Coord tag) where
  top selection = SelectionValue selection (layoutValueAccess AttrTop)

instance Width (Selected tag) (SelectionValue Span tag) where
  width selection = SelectionValue selection (layoutValueAccess AttrWidth)

instance Height (Selected tag) (SelectionValue Span tag) where
  height selection = SelectionValue selection (layoutValueAccess AttrHeight)

instance Right (Selected tag) (SelectionValue Coord tag) where
  right selection = SelectionValue selection (layoutValueAccess AttrRight)

instance Bottom (Selected tag) (SelectionValue Coord tag) where
  bottom selection = SelectionValue selection (layoutValueAccess AttrBottom)

instance X Coord (NodeRecipe ()) where
  x value = setNodeSpecWith (\spec -> spec {nodeSpecX = Just value})

instance Y Coord (NodeRecipe ()) where
  y value = setNodeSpecWith (\spec -> spec {nodeSpecY = Just value})

instance X (Selected tag) (SelectionValue Coord tag) where
  x selection = SelectionValue selection (layoutValueAccess AttrCenterX)

instance Y (Selected tag) (SelectionValue Coord tag) where
  y selection = SelectionValue selection (layoutValueAccess AttrCenterY)

pos :: (Left input value, Top input value) => input -> Vec2 value
pos selection = vec2 (left selection) (top selection)

center :: (X input value, Y input value) => input -> Vec2 value
center selection = vec2 (x selection) (y selection)

size :: (Width input value, Height input value) => input -> Vec2 value
size selection = vec2 (width selection) (height selection)

position :: Vec2 Coord -> NodeRecipe ()
position value =
  case value of
    Vec2 valueX valueY -> do
      x valueX
      y valueY

bounds :: BoundsExpr -> NodeRecipe ()
bounds value =
  case value of
    Bounds topExpr leftExpr widthExpr heightExpr -> do
      top (mkCoord topExpr [])
      left (mkCoord leftExpr [])
      width (mkSpan widthExpr [])
      height (mkSpan heightExpr [])
