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
-- queries, match specs, tags, and view patches. It depends on
-- 'LinearTrace.Core', 'LinearTrace.Choreography.Query',
-- 'LinearTrace.Choreography.Match', and the internal 'LinearTrace.View' facade.
module LinearTrace.Choreography
  ( -- * Defined here: choreography and view graph facade
    -- | Direct choreography builder API. Core lifecycle helpers return pending
    -- block obligations; materialization attaches visual facts and checkpoints
    -- attach materialized events to view output.
    Choreography
  , VisualTraceGraph
  , ViewGraph
  , visualTraceCore
  , buildViewGraph
  , solveViewGraphWithSeed
  , viewGraphStats
  , runChoreography
  , runChoreographyWith
  , create
  , copy
  , use
  , apply1
  , apply2
  , replace
  , materialize
  , materializeWithTags
  , commit
  , destroy
  , checkpoint
  , -- * Re-exported or aliased from LinearTrace.Core
    -- | Core linear handles, payload/fact vocabulary, event-token aliases,
    -- traceable payload classes, and linear functor operators used directly by
    -- the DSL.
    Block
  , SlotHandle
  , Payload
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
  , Traceable
  , LUnit(..)
  , LBool(..)
  , LInt(..)
  , LDouble(..)
  , LString(..)
  , LOperator(..)
  , CoreOperator(..)
  , LinearPayload(..)
  , applyLinear1
  , applyLinear1Into
  , applyLinear2
  , applyLinear2Into
  , Applicable1(..)
  , Applicable2(..)
  , Pending
  , OneUse(..)
  , Create(..)
  , Observe(..)
  , Use(..)
  , Copy(..)
  , Replace(..)
  , Apply1(..)
  , Apply2(..)
  , Destroy(..)
  , Seal(..)
  , Unseal(..)
  , (<$>)
  , (<*>)
  , -- * Re-exported from LinearTrace.Choreography.Query
    -- | Query syntax and query-derived facts used to match trace blocks and
    -- generated nodes.
    Query
  , QueryInt
  , emptyQuery
  , queryAtom
  , queryInt
  , queryFacts
  , -- * Re-exported from LinearTrace.Choreography.Match
    -- | Compiled query/patch/constraint rules consumed by the view graph
    -- builder.
    MatchSpec
  , -- * Re-exported from LinearTrace.Choreography.Types
    -- | Shared choreography handles, selections, recipes, variables, and DSL
    -- values.
    TraceQuery
  , Selected
  , Variable(..)
  , Categorical(..)
  , Bound(..)
  , NodeBinding(..)
  , AnyPayload
  , VisualizationBuilder
  , Coord
  , Span
  , Offset
  , Scalar
  , NodeRecipe
  , ContentValue
  , text
  , -- * Re-exported from LinearTrace.Choreography.Node
    -- | Selection, content, grouping, rendering, and query composition helpers.
    Node
  , Select
  , select
  , QueryAppend
  , visualize
  , content
  , payload
  , node
  , render
  , (<&>)
  , -- * Re-exported from LinearTrace.Choreography.Style
    -- | Type-applied style assignment and selected-style access.
    StyleChoice(..)
  , style
  , styleOf
  , sat
  , -- * Re-exported from LinearTrace.View.Style
    -- | Style field marker types and concrete style choice domains from the
    -- view layer.
    NodeStyle
  , Opacity
  , ZIndex
  , Padding
  , FontSize
  , Radius
  , StrokeWidth
  , Alpha
  , Fill
  , Stroke
  , BorderStyle(..)
  , FontFamily(..)
  , FontWeight(..)
  , FontStyle(..)
  , TextAlign(..)
  , WhiteSpace(..)
  , -- * Re-exported from LinearTrace.View.Primitives
    -- | Solver-backed view primitive domains and compound values.
    Bounds(..)
  , Hsl(..)
  , Free
  , Unit
  , Angle
  , Color
  , -- * Re-exported from Solver
    -- | Solver-facing random seed and vector constructor used by the public DSL.
    RandomSeed(..)
  , Vec2(..)
  , vec2
  , -- * Re-exported from GHC.OverloadedLabels
    -- | Overloaded label entrypoint used by the query/tag DSL.
    fromLabel
  , -- * Defined here: layout, variables, and constraints
    -- | Choreography-level constructors, overloaded layout accessors, and
    -- visual relation operators.
    Left
  , Top
  , Right
  , Bottom
  , Width
  , Height
  , X
  , Y
  , Center(..)
  , asUnit
  , asCoord
  , asSpan
  , at
  , queryIndex
  , bottom
  , bounds
  , by
  , bindContent
  , bindInt
  , ensure
  , variable
  , variableFrom
  , choice
  , encourage
  , global
  , height
  , left
  , num
  , fromInteger
  , fromRational
  , right
  , shift
  , size
  , top
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

import           Control.Functor.Linear         hiding ((<$>), (<&>), (<*>))
import           GHC.OverloadedLabels           (IsLabel (..))
import           LinearTrace.Choreography.Match (CategoryEndpoint,
                                                 CategoryRelation (..),
                                                 ConstraintStrength (..),
                                                 LayoutRelation (..), MatchSpec,
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
import           LinearTrace.Choreography.Node  (Node, QueryAppend, Select,
                                                 content, node, nodeSelection,
                                                 payload, render, select,
                                                 setNodeSpecWith, visualize,
                                                 (<&>))
import           LinearTrace.Choreography.Query (Query, QueryInt (..),
                                                 emptyQuery, queryAtom,
                                                 queryFacts, queryInt,
                                                 queryIntAdd, queryIntConst,
                                                 queryIntVar)
import           LinearTrace.Choreography.Style (StyleChoice (..), sat, style,
                                                 styleOf)
import           LinearTrace.Choreography.Types
import           LinearTrace.Core               (Applicable1 (..),
                                                 Applicable2 (..), Apply1 (..),
                                                 Apply2 (..), Block, Copy (..),
                                                 CoreOperator (..), Create (..),
                                                 Destroy (..), Fact (..),
                                                 FactValue (..), Facts (..),
                                                 LBool (..), LDouble (..),
                                                 LInt (..), LOperator (..),
                                                 LString (..), LUnit (..),
                                                 LinearPayload (..),
                                                 Observe (..), OneUse (..),
                                                 Payload, PayloadView (..),
                                                 Pending, Replace (..),
                                                 Seal (..), Traceable,
                                                 Unseal (..), Use (..),
                                                 applyLinear1, applyLinear1Into,
                                                 applyLinear2, applyLinear2Into,
                                                 emptyFacts, factAtom, factInt,
                                                 factSymbol, factsToList,
                                                 factsUnion, (<$>), (<*>))
import qualified LinearTrace.Core               as C
import           LinearTrace.View               (BorderStyle (..),
                                                 FontFamily (..),
                                                 FontStyle (..),
                                                 FontWeight (..), NodeStyle,
                                                 TextAlign (..),
                                                 WhiteSpace (..))
import qualified LinearTrace.View               as V
import           LinearTrace.View.Access        (CategoryAccess,
                                                 LayoutAttr (..), ValueAccess,
                                                 layoutValueAccess)
import           LinearTrace.View.Primitives    (Angle, Bounds (..), BoundsExpr,
                                                 Color, Free, Hsl (..),
                                                 LayoutExpr, Unit)
import           LinearTrace.View.Style         (Alpha, Fill, FontSize, Opacity,
                                                 Padding, Radius, Stroke,
                                                 StrokeWidth, ZIndex)
import qualified Prelude                        as P
import           Prelude.Linear                 hiding (fromInteger,
                                                 fromRational, (*), (+), (-),
                                                 (/), (/=), (<>), (==))
import qualified Solver                         as S
import           Solver                         (RandomSeed (..), Vec2 (..),
                                                 vec2)

infixl 9 @:
type Choreography a = C.TraceBuilder a

data VisualTraceGraph =
  VisualTraceGraph MatchSpec C.TraceGraph

type ViewGraph = V.ViewGraph

visualTraceCore :: VisualTraceGraph -> C.TraceGraph
visualTraceCore graph =
  case graph of
    VisualTraceGraph _ coreGraph -> coreGraph

buildViewGraph :: VisualTraceGraph -> ViewGraph
buildViewGraph graph =
  case graph of
    VisualTraceGraph spec coreGraph ->
      let stepsOutput = viewTraceSteps spec (C.traceGraphSteps coreGraph)
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

viewTraceSteps :: MatchSpec -> [C.TraceStep] -> BuiltViewSteps
viewTraceSteps spec = viewTraceStepsWith (viewTraceStep spec) [] [] [] [] [] []

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

viewTraceStep :: MatchSpec -> [V.RenderIntent] -> C.TraceStep -> BuiltViewStep
viewTraceStep spec pending = C.foldTraceStep onCheckpoint onDiscarded
  where
    onCheckpoint label _payload events =
      let rawOutput = V.flushViewOutput (buildTraceEventsOutput spec events)
          output = V.mergeInitialRenderIntents pending rawOutput
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
    onDiscarded reason _events =
      BuiltViewStep
        { stepView = V.ViewStep ("Discarded: " P.++ reason) [] [] []
        , stepNodes = []
        , stepConstraints = []
        , stepChoiceConstraints = []
        , stepRenderFrames = []
        , stepPendingRenderIntents = pending
        }

type SlotHandle = C.Slot

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

instance ConstraintValue x => ConstraintValue (Vec2 x) where
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

buildTraceEventsOutput :: MatchSpec -> C.TraceEvents -> V.ViewOutput
buildTraceEventsOutput spec =
  C.foldTraceEvents
    (\output event -> V.appendViewOutput output (viewOutputForEvent spec event))
    V.emptyViewOutput

viewOutputForEvent :: MatchSpec -> C.TraceEvent -> V.ViewOutput
viewOutputForEvent spec event =
  case event of
    C.TraceCreate block ->
      V.appendViewOutput
        (matchedNodeOutput spec block)
        (renderEventBlock V.RenderFresh block)
    C.TraceObserve _block -> V.emptyViewOutput
    C.TraceUse block -> renderEventBlock V.RenderRemove block
    C.TraceCopy originalBlock copyBlock ->
      V.appendViewOutput
        (matchedNodeOutput spec copyBlock)
        (renderEventBlocks V.RenderFork originalBlock copyBlock)
    C.TraceReplace oldBlock outputBlock ->
      V.appendViewOutput
        (matchedNodeOutput spec outputBlock)
        (renderEventBlocks V.RenderContinue oldBlock outputBlock)
    C.TraceApply1 opBlock argBlock outputBlock ->
      V.appendViewOutput
        (matchedNodeOutput spec outputBlock)
        (V.appendViewOutput
           (renderEventBlock V.RenderFresh outputBlock)
           (V.appendViewOutput
              (renderEventBlock V.RenderRemove opBlock)
              (renderEventBlock V.RenderRemove argBlock)))
    C.TraceApply2 opBlock lhsBlock rhsBlock outputBlock ->
      V.appendViewOutput
        (matchedNodeOutput spec outputBlock)
        (V.appendViewOutput
           (renderEventBlock V.RenderFresh outputBlock)
           (V.appendViewOutput
              (renderEventBlock V.RenderRemove opBlock)
              (V.appendViewOutput
                 (renderEventBlock V.RenderRemove lhsBlock)
                 (renderEventBlock V.RenderRemove rhsBlock))))
    C.TraceDestroy block -> renderEventBlock V.RenderRemove block
    C.TraceSeal _ownerBlock _childBlock -> V.emptyViewOutput
    C.TraceUnseal _ownerBlock _childBlock -> V.emptyViewOutput

renderEventBlock ::
     (V.ViewRef tag -> V.RenderIntent) -> C.BlockSnapshot tag -> V.ViewOutput
renderEventBlock makeIntent block =
  V.renderIntentOutput (makeIntent (eventBlockViewRef block))

renderEventBlocks ::
     (V.ViewRef source -> V.ViewRef target -> V.RenderIntent)
  -> C.BlockSnapshot source
  -> C.BlockSnapshot target
  -> V.ViewOutput
renderEventBlocks makeIntent sourceBlock targetBlock =
  V.renderIntentOutput
    (makeIntent (eventBlockViewRef sourceBlock) (eventBlockViewRef targetBlock))

eventBlockViewRef :: C.BlockSnapshot tag -> V.ViewRef tag
eventBlockViewRef block = V.nodeRef (traceNodeOfEventBlock block)

runChoreography :: Choreography () -> VisualTraceGraph
runChoreography = runChoreographyWith emptyMatchSpec

runChoreographyWith :: MatchSpec -> Choreography () -> VisualTraceGraph
runChoreographyWith spec builder = VisualTraceGraph spec (C.buildGraph builder)

create ::
     forall tag. C.Traceable tag
  => C.Payload tag
     %1 -> Choreography (C.Create tag)
create = C.create

use ::
     forall tag. C.Traceable tag
  => Block tag
     %1 -> Choreography (C.Use tag)
use = C.use

copy ::
     forall tag. C.Traceable tag
  => Block tag
     %1 -> Choreography (C.Copy tag)
copy = C.copy

apply1 ::
     forall op arg.
     ( C.Applicable1 op arg
     , C.Traceable op
     , C.Traceable arg
     , C.Traceable (C.Apply1Result op arg)
     )
  => Block op
     %1 -> Block arg
     %1 -> Choreography (C.Apply1 op arg)
apply1 = C.apply1

apply2 ::
     forall op lhs rhs.
     ( C.Applicable2 op lhs rhs
     , C.Traceable op
     , C.Traceable lhs
     , C.Traceable rhs
     , C.Traceable (C.Apply2Result op lhs rhs)
     )
  => Block op
     %1 -> Block lhs
     %1 -> Block rhs
     %1 -> Choreography (C.Apply2 op lhs rhs)
apply2 = C.apply2

replace ::
     forall tag. C.Traceable tag
  => Block tag
     %1 -> C.Pending tag
     %1 -> Choreography (C.Replace tag)
replace = C.replace

materialize ::
     forall tag. C.Traceable tag
  => Query
  -> C.Pending tag
     %1 -> Choreography (Block tag)
materialize query = C.materializeTagged (queryFacts query)

materializeWithTags ::
     forall tag. C.Traceable tag
  => Query
  -> (Payload tag -> Query)
  -> C.Pending tag
     %1 -> Choreography (Block tag)
materializeWithTags query selectQuery =
  C.materializeTaggedWith (queryFacts query) selectFacts
  where
    selectFacts outputPayload = queryFacts (selectQuery outputPayload)

commit ::
     forall tag. C.Traceable tag
  => C.Pending tag
     %1 -> Choreography (Block tag)
commit = C.commit

destroy ::
     forall tag. C.Traceable tag
  => Block tag
     %1 -> Choreography (C.Destroy tag)
destroy = C.destroy

checkpoint :: P.String -> Choreography ()
checkpoint = C.checkpoint

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

class Center input where
  type CenterOutput input
  center :: input -> CenterOutput input

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

instance Center (Selected tag) where
  type CenterOutput (Selected tag) = Vec2 (SelectionValue Coord tag)
  center selection = vec2 (x selection) (y selection)

instance Center (Vec2 Coord) where
  type CenterOutput (Vec2 Coord) = NodeRecipe ()
  center value =
    case value of
      Vec2 valueX valueY -> do
        x valueX
        y valueY

size :: (Width input value, Height input value) => input -> Vec2 value
size selection = vec2 (width selection) (height selection)

bounds :: BoundsExpr -> NodeRecipe ()
bounds value =
  case value of
    Bounds topExpr leftExpr widthExpr heightExpr -> do
      top (mkCoord topExpr [])
      left (mkCoord leftExpr [])
      width (mkSpan widthExpr [])
      height (mkSpan heightExpr [])
