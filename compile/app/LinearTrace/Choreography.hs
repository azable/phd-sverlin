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

module LinearTrace.Choreography
  ( -- * Program layer
    Program
  , ViewLayout
  , VisualTraceGraph
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
    Block
  , SlotHandle
  , PayloadHandle
  , -- * Payloads and trace tags
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
  , Selection
  , Selected
  , Variable(..)
  , Bound(..)
  , NodeBinding(..)
  , NodeRef
  , AnyPayload
  , Node
  , StyleTarget
  , Select
  , select
  , VisualizationBuilder
  , QueryAppend
  , visualize
  , layout
  , emptyQuery
  , queryAtom
  , queryInt
  , queryFacts
  , (<&&>)
  , -- * Component and layout layer
    BoxDefinition
  , BoxVisual
  , NodeDefinition
  , NodeRecipe
  , NodeVisual
  , LiveVisual
  , LayoutUse(..)
  , OneExpr
  , OneConstraint
  , Style
  , BorderStyle(..)
  , Bounds(..)
  , BoundsExpr
  , FontWeight(..)
  , FontStyle(..)
  , Hsl(..)
  , FreeExpr
  , HslExpr
  , Hue
  , HueExpr
  , LayoutExpr
  , Coord
  , Span
  , Offset
  , Scalar
  , UnitExpr
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
  , alpha
  , asUnit
  , asCoord
  , asSpan
  , at
  , bold
  , bottom
  , bounds
  , by
  , borderStyle
  , boxDefinition
  , bindContent
  , bindInt
  , centerText
  , center
  , content
  , defineNode
  , payload
  , text
  , ensure
  , variable
  , encourage
  , fill
  , fontFamily
  , fontSize
  , fontStyle
  , fontWeight
  , fromLabel
  , global
  , height
  , left
  , noWrap
  , node
  , num
  , fromInteger
  , fromRational
  , opacity
  , pos
  , placeBox
  , position
  , radius
  , require
  , right
  , stroke
  , strokeWidth
  , style
  , sat
  , shift
  , size
  , takeHeight
  , takeLeft
  , takeRight
  , takeTop
  , takeWidth
  , textAlign
  , top
  , vec2
  , whiteSpace
  , width
  , x
  , y
  , zIndex
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

import           Control.Functor.Linear hiding ((<$>), (<*>))
import qualified Data.Functor.Linear    as DFL
import           Data.Proxy             (Proxy (..))
import           GHC.Exts               (Multiplicity (Many))
import           GHC.OverloadedLabels   (IsLabel (..))
import           GHC.TypeLits           (KnownSymbol)
import           LinearTrace.Core       (Block, Fact (..), FactValue (..),
                                         Facts (..), LBool (..), LDouble (..),
                                         LInt (..), LString (..), LUnit (..),
                                         Payload, PayloadView (..),
                                         Traceable (..), emptyFacts, factAtom,
                                         factInt, factSymbol, factsToList,
                                         factsUnion, (<$>), (<*>))
import qualified LinearTrace.Core       as C
import           LinearTrace.Solver     (Vec2 (..), vec2)
import qualified LinearTrace.Solver     as S
import           LinearTrace.View       (BorderStyle (..), Bounds (..),
                                         BoundsExpr, BoxDefinition, BoxVisual,
                                         ConstraintStrength (..),
                                         FontStyle (..), FontWeight (..),
                                         FreeExpr, Hsl (..), HslExpr,
                                         HslPart (..), Hue, HueExpr,
                                         LayoutAttr (..), LayoutExpr,
                                         LayoutRelation (..), LayoutUse (..),
                                         LiveVisual, MatchBindings, MatchSpec,
                                         NodeSelection (..), OneConstraint (..),
                                         OneExpr (..), PayloadPattern, Query,
                                         QueryInt (..), Style,
                                         StyleColorAttr (..),
                                         StyleFreeAttr (..),
                                         StyleLayoutAttr (..),
                                         StyleUnitAttr (..), TextAlign (..),
                                         UnitExpr, ValueAccess, ValueComponent,
                                         ValueEndpoint, WhiteSpace (..),
                                         anyPayloadPattern, boxDefinition,
                                         emptyMatchSpec, emptyQuery, global,
                                         layoutValueAccess, matchAnyQueryNode,
                                         matchBindingValue,
                                         matchContextBindings,
                                         matchGlobalLayout,
                                         matchQueryPayloadNode, matchSpecAppend,
                                         matchValueDirectedBridge,
                                         matchValueRelation,
                                         matchValueSymmetricBridge,
                                         matchVirtualNode,
                                         payloadBindingPattern,
                                         payloadBoolPattern,
                                         payloadDoublePattern,
                                         payloadIntPattern,
                                         payloadStringPattern,
                                         payloadUnitPattern, queryAppend,
                                         queryAtom, queryFacts, queryInt,
                                         queryIntAdd, queryIntConst,
                                         queryIntVar, rawValueEndpoint,
                                         selectionValueEndpoint,
                                         styleColorPartValueAccess,
                                         styleFreeValueAccess,
                                         styleLayoutValueAccess,
                                         styleUnitValueAccess, takeHeight,
                                         takeLeft, takeRight, takeTop,
                                         takeWidth, valueComponent)
import qualified LinearTrace.View       as V
import qualified LinearTrace.View.Style as VS
import qualified Prelude                as P
import           Prelude.Linear         hiding (fromInteger, fromRational, (*),
                                         (+), (-), (/), (/=), (<>))
import qualified Text.Read              as Read

infixr 6 <&&>
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

data Coord =
  Coord LayoutExpr [S.Constraint]
  deriving (P.Eq, P.Show)

data Span =
  Span LayoutExpr [S.Constraint]
  deriving (P.Eq, P.Show)

data Offset =
  Offset LayoutExpr [S.Constraint]
  deriving (P.Eq, P.Show)

data Scalar =
  Scalar LayoutExpr [S.Constraint]
  deriving (P.Eq, P.Show)

newtype Binding =
  Binding P.String
  deriving (P.Eq, P.Show)

data TraceQuery tag =
  TraceQuery Query (Maybe (PayloadPattern tag))

data Selection a where
  Selection :: a %1 -> MatchSpec -> Selection a

data AnyPayload

data NodeRef tag where
  TraceNodeRef :: C.Traceable tag => TraceQuery tag -> NodeRef tag
  AnyNodeRef :: Query -> NodeRef AnyPayload
  VirtualNodeRef :: P.String -> Query -> NodeRef tag

type Selected tag = Selection (NodeRef tag)

data Variable a where
  Variable :: a %Many -> Variable a

data Bound a where
  Bound :: a %Many -> Bound a

data NodeBinding a where
  Selected :: a %Many -> NodeBinding a

data SelectedExpr ty tag =
  SelectedExpr (Selected tag) ValueAccess

data LiftedConstraint where
  LiftedValueRelation
    :: ValueTerm -> LayoutRelation -> ValueTerm -> LiftedConstraint
  LiftedDirectedBridge
    :: ValueTerm -> ValueTerm -> ValueTerm -> LiftedConstraint
  LiftedSymmetricBridge
    :: ValueTerm -> ValueTerm -> ValueTerm -> LiftedConstraint

data ValueTerm =
  ValueTerm MatchSpec [ValueEndpoint]

data ContentValue
  = ContentLiteral P.String
  | ContentBinding Binding

text :: P.String -> ContentValue
text = ContentLiteral

payload ::
     forall tag selector. PayloadSelector tag selector
  => selector
  -> TraceQuery tag
payload selector = TraceQuery emptyQuery (Just (payloadSelector @tag selector))

instance IsString ContentValue where
  fromString = ContentLiteral

data ContentSpec
  = LiteralContent P.String
  | BoundContent Binding

data NodeSpec = NodeSpec
  { nodeSpecStyleUpdate  :: Style -> Style
  , nodeSpecContent      :: Maybe ContentSpec
  , nodeSpecLeft         :: Maybe Coord
  , nodeSpecTop          :: Maybe Coord
  , nodeSpecWidth        :: Maybe Span
  , nodeSpecHeight       :: Maybe Span
  , nodeSpecRight        :: Maybe Coord
  , nodeSpecBottom       :: Maybe Coord
  , nodeSpecX            :: Maybe Coord
  , nodeSpecY            :: Maybe Coord
  , nodeSpecRequirements :: [ViewLayout ()]
  }

data NodeRecipe a where
  NodeRecipe :: a %1 -> NodeSpec -> NodeRecipe a

data VisualizationResult a where
  VisualizationResult :: a %1 -> P.Int -> MatchSpec -> VisualizationResult a

data VisualizationBuilder a where
  VisualizationBuilder
    :: (P.Int -> VisualizationResult a) %1 -> VisualizationBuilder a

type ViewLayout a = V.ViewBuilder a

type VisualTraceGraph = V.VisualTraceGraph

type NodeDefinition tag = BoxDefinition tag

type NodeVisual tag = BoxVisual tag

type StyleRecipe = NodeRecipe

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

emptyNodeSpec :: NodeSpec
emptyNodeSpec =
  NodeSpec
    { nodeSpecStyleUpdate = P.id
    , nodeSpecContent = Nothing
    , nodeSpecLeft = Nothing
    , nodeSpecTop = Nothing
    , nodeSpecWidth = Nothing
    , nodeSpecHeight = Nothing
    , nodeSpecRight = Nothing
    , nodeSpecBottom = Nothing
    , nodeSpecX = Nothing
    , nodeSpecY = Nothing
    , nodeSpecRequirements = []
    }

composeStyleUpdates :: (Style -> Style) -> (Style -> Style) -> Style -> Style
composeStyleUpdates first second style0 = second (first style0)

preferLater :: Maybe a -> Maybe a -> Maybe a
preferLater earlier later =
  case later of
    Nothing -> earlier
    Just _  -> later

appendNodeSpec :: NodeSpec -> NodeSpec -> NodeSpec
appendNodeSpec first second =
  NodeSpec
    { nodeSpecStyleUpdate =
        composeStyleUpdates
          (nodeSpecStyleUpdate first)
          (nodeSpecStyleUpdate second)
    , nodeSpecContent =
        preferLater (nodeSpecContent first) (nodeSpecContent second)
    , nodeSpecLeft = preferLater (nodeSpecLeft first) (nodeSpecLeft second)
    , nodeSpecTop = preferLater (nodeSpecTop first) (nodeSpecTop second)
    , nodeSpecWidth = preferLater (nodeSpecWidth first) (nodeSpecWidth second)
    , nodeSpecHeight =
        preferLater (nodeSpecHeight first) (nodeSpecHeight second)
    , nodeSpecRight = preferLater (nodeSpecRight first) (nodeSpecRight second)
    , nodeSpecBottom =
        preferLater (nodeSpecBottom first) (nodeSpecBottom second)
    , nodeSpecX = preferLater (nodeSpecX first) (nodeSpecX second)
    , nodeSpecY = preferLater (nodeSpecY first) (nodeSpecY second)
    , nodeSpecRequirements =
        nodeSpecRequirements first P.++ nodeSpecRequirements second
    }

bindNodeRecipe :: NodeRecipe a %1 -> (a %1 -> NodeRecipe b) %1 -> NodeRecipe b
bindNodeRecipe recipe next =
  case recipe of
    NodeRecipe value first ->
      case next value of
        NodeRecipe output second ->
          NodeRecipe output (appendNodeSpec first second)

instance DFL.Functor NodeRecipe where
  fmap f recipe =
    case recipe of
      NodeRecipe value spec -> NodeRecipe (f value) spec

instance Functor NodeRecipe where
  fmap f recipe =
    case recipe of
      NodeRecipe value spec -> NodeRecipe (f value) spec

instance DFL.Applicative NodeRecipe where
  pure value = NodeRecipe value emptyNodeSpec
  liftA2 f lhs rhs =
    case lhs of
      NodeRecipe leftValue first ->
        case rhs of
          NodeRecipe rightValue second ->
            NodeRecipe (f leftValue rightValue) (appendNodeSpec first second)

instance Applicative NodeRecipe where
  pure value = NodeRecipe value emptyNodeSpec
  liftA2 f lhs rhs =
    case lhs of
      NodeRecipe leftValue first ->
        case rhs of
          NodeRecipe rightValue second ->
            NodeRecipe (f leftValue rightValue) (appendNodeSpec first second)

instance Monad NodeRecipe where
  (>>=) = bindNodeRecipe

bindVisualizationBuilder ::
     VisualizationBuilder a
     %1 -> (a %1 -> VisualizationBuilder b)
     %1 -> VisualizationBuilder b
bindVisualizationBuilder builder next =
  case builder of
    VisualizationBuilder runFirst ->
      VisualizationBuilder
        (\counter0 ->
           case runFirst counter0 of
             VisualizationResult value counter1 first ->
               case next value of
                 VisualizationBuilder runSecond ->
                   case runSecond counter1 of
                     VisualizationResult output counter2 second ->
                       VisualizationResult
                         output
                         counter2
                         (matchSpecAppend first second))

emptyVisualizationBuilder :: a -> VisualizationBuilder a
emptyVisualizationBuilder value =
  VisualizationBuilder
    (\counter -> VisualizationResult value counter emptyMatchSpec)

emptyVisualizationBuilderLinear :: a %1 -> VisualizationBuilder a
emptyVisualizationBuilderLinear value =
  VisualizationBuilder
    (\counter -> VisualizationResult value counter emptyMatchSpec)

emitVisualizationBuilder :: a -> MatchSpec -> VisualizationBuilder a
emitVisualizationBuilder value spec =
  VisualizationBuilder (\counter -> VisualizationResult value counter spec)

freshVisualizationValue :: P.String -> (P.String -> a) -> VisualizationBuilder a
freshVisualizationValue prefix build =
  VisualizationBuilder
    (\counter ->
       VisualizationResult
         (build (prefix P.++ P.show counter))
         (counter P.+ 1)
         emptyMatchSpec)

instance DFL.Functor VisualizationBuilder where
  fmap f builder =
    case builder of
      VisualizationBuilder run ->
        VisualizationBuilder
          (\counter0 ->
             case run counter0 of
               VisualizationResult value counter1 spec ->
                 VisualizationResult (f value) counter1 spec)

instance Functor VisualizationBuilder where
  fmap f builder =
    case builder of
      VisualizationBuilder run ->
        VisualizationBuilder
          (\counter0 ->
             case run counter0 of
               VisualizationResult value counter1 spec ->
                 VisualizationResult (f value) counter1 spec)

instance DFL.Applicative VisualizationBuilder where
  pure = emptyVisualizationBuilder
  liftA2 f lhs rhs =
    case lhs of
      VisualizationBuilder runLeft ->
        case rhs of
          VisualizationBuilder runRight ->
            VisualizationBuilder
              (\counter0 ->
                 case runLeft counter0 of
                   VisualizationResult leftValue counter1 first ->
                     case runRight counter1 of
                       VisualizationResult rightValue counter2 second ->
                         VisualizationResult
                           (f leftValue rightValue)
                           counter2
                           (matchSpecAppend first second))

instance Applicative VisualizationBuilder where
  pure = emptyVisualizationBuilderLinear
  liftA2 f lhs rhs =
    case lhs of
      VisualizationBuilder runLeft ->
        case rhs of
          VisualizationBuilder runRight ->
            VisualizationBuilder
              (\counter0 ->
                 case runLeft counter0 of
                   VisualizationResult leftValue counter1 first ->
                     case runRight counter1 of
                       VisualizationResult rightValue counter2 second ->
                         VisualizationResult
                           (f leftValue rightValue)
                           counter2
                           (matchSpecAppend first second))

instance Monad VisualizationBuilder where
  (>>=) = bindVisualizationBuilder

bindSelection :: Selection a %1 -> (a %1 -> Selection b) %1 -> Selection b
bindSelection selection next =
  case selection of
    Selection value first ->
      case next value of
        Selection output second ->
          Selection output (matchSpecAppend first second)

instance DFL.Functor Selection where
  fmap f selection =
    case selection of
      Selection value spec -> Selection (f value) spec

instance Functor Selection where
  fmap f selection =
    case selection of
      Selection value spec -> Selection (f value) spec

instance DFL.Applicative Selection where
  pure value = Selection value emptyMatchSpec
  liftA2 f lhs rhs =
    case lhs of
      Selection leftValue first ->
        case rhs of
          Selection rightValue second ->
            Selection (f leftValue rightValue) (matchSpecAppend first second)

instance Applicative Selection where
  pure value = Selection value emptyMatchSpec
  liftA2 f lhs rhs =
    case lhs of
      Selection leftValue first ->
        case rhs of
          Selection rightValue second ->
            Selection (f leftValue rightValue) (matchSpecAppend first second)

instance Monad Selection where
  (>>=) = bindSelection

coordExpr :: Coord -> LayoutExpr
coordExpr value =
  case value of
    Coord expr _ -> expr

spanExpr :: Span -> LayoutExpr
spanExpr value =
  case value of
    Span expr _ -> expr

offsetExpr :: Offset -> LayoutExpr
offsetExpr value =
  case value of
    Offset expr _ -> expr

scalarExpr :: Scalar -> LayoutExpr
scalarExpr value =
  case value of
    Scalar expr _ -> expr

coordConstraints :: Coord -> [S.Constraint]
coordConstraints value =
  case value of
    Coord _ constraints -> constraints

spanConstraints :: Span -> [S.Constraint]
spanConstraints value =
  case value of
    Span _ constraints -> constraints

offsetConstraints :: Offset -> [S.Constraint]
offsetConstraints value =
  case value of
    Offset _ constraints -> constraints

scalarConstraints :: Scalar -> [S.Constraint]
scalarConstraints value =
  case value of
    Scalar _ constraints -> constraints

class ConstraintValue value where
  valueTerm :: value -> ValueTerm

rawValueTerm :: ValueComponent -> ValueTerm
rawValueTerm component = ValueTerm emptyMatchSpec [rawValueEndpoint component]

rawExprValueTerm ::
     S.SymbolicType ty => S.Expr ty -> [S.Constraint] -> ValueTerm
rawExprValueTerm expr constraints =
  rawValueTerm (valueComponent expr constraints)

selectedValueTerm :: Selected tag -> ValueAccess -> ValueTerm
selectedValueTerm selected access =
  ValueTerm
    (selectedSpec selected)
    [selectionValueEndpoint (selectedNodeSelection selected) access]

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

instance ConstraintValue (SelectedExpr ty tag) where
  valueTerm selected =
    case selected of
      SelectedExpr selection access -> selectedValueTerm selection access

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
    Selection _ spec -> spec

selectedNodeSelection :: Selected tag -> NodeSelection
selectedNodeSelection selected =
  case selected of
    Selection handle _ -> nodeSelection handle

nonNegative :: LayoutExpr -> S.Constraint
nonNegative expr = (S.num 0 :: LayoutExpr) S.@<=@ expr

mkCoord :: LayoutExpr -> [S.Constraint] -> Coord
mkCoord expr constraints = Coord expr (constraints P.++ [nonNegative expr])

mkSpan :: LayoutExpr -> [S.Constraint] -> Span
mkSpan expr constraints = Span expr (constraints P.++ [nonNegative expr])

mkOffset :: LayoutExpr -> [S.Constraint] -> Offset
mkOffset = Offset

mkScalar :: LayoutExpr -> [S.Constraint] -> Scalar
mkScalar = Scalar

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

globalCoord :: P.String -> Coord
globalCoord name = mkCoord (global name :: LayoutExpr) []

globalSpan :: P.String -> Span
globalSpan name = mkSpan (global name :: LayoutExpr) []

queryIntExpr :: S.SymbolicType ty => QueryInt -> S.Expr ty
queryIntExpr queryIntValue =
  case queryIntValue of
    QueryIntConst value -> S.num (P.fromIntegral value)
    QueryIntVar name -> global name
    QueryIntAdd base offset ->
      queryIntExpr base S.@+@ S.num (P.fromIntegral offset)

asUnit :: QueryInt -> UnitExpr
asUnit = queryIntExpr

asCoord :: Offset -> Coord
asCoord value =
  case value of
    Offset expr constraints -> mkCoord expr constraints

asSpan :: Offset -> Span
asSpan value =
  case value of
    Offset expr constraints -> mkSpan expr constraints

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
  relateValues :: LayoutRelation -> lhs -> rhs -> LiftedConstraint

instance {-# OVERLAPPABLE #-} (ConstraintValue lhs, ConstraintValue rhs) =>
         RelateValues lhs rhs where
  relateValues relation lhs rhs =
    LiftedValueRelation (valueTerm lhs) relation (valueTerm rhs)

instance {-# OVERLAPPING #-} S.SymbolicType ty =>
         RelateValues (SelectedExpr ty tag) (S.Expr ty) where
  relateValues relation lhs rhs =
    LiftedValueRelation (valueTerm lhs) relation (valueTerm rhs)

instance {-# OVERLAPPING #-} S.SymbolicType ty =>
         RelateValues (S.Expr ty) (SelectedExpr ty tag) where
  relateValues relation lhs rhs =
    LiftedValueRelation (valueTerm lhs) relation (valueTerm rhs)

instance {-# OVERLAPPING #-} RelateValues
           (Hsl (SelectedExpr S.Angle tag) (SelectedExpr S.Unit tag))
           HslExpr where
  relateValues relation lhs rhs =
    LiftedValueRelation (valueTerm lhs) relation (valueTerm rhs)

instance {-# OVERLAPPING #-} RelateValues
           HslExpr
           (Hsl (SelectedExpr S.Angle tag) (SelectedExpr S.Unit tag)) where
  relateValues relation lhs rhs =
    LiftedValueRelation (valueTerm lhs) relation (valueTerm rhs)

data DirectedBridge =
  DirectedBridge ValueTerm ValueTerm

class OpenDirectedBridge lhs gap where
  openDirectedBridge :: lhs -> gap -> DirectedBridge

instance {-# OVERLAPPABLE #-} (ConstraintValue lhs, ConstraintValue gap) =>
         OpenDirectedBridge lhs gap where
  openDirectedBridge lhs gap = DirectedBridge (valueTerm lhs) (valueTerm gap)

class CloseDirectedBridge bridge rhs where
  closeDirectedBridge :: bridge -> rhs -> LiftedConstraint

instance {-# OVERLAPPABLE #-} ConstraintValue rhs =>
         CloseDirectedBridge DirectedBridge rhs where
  closeDirectedBridge bridge rhs =
    case bridge of
      DirectedBridge lhs gap -> LiftedDirectedBridge lhs gap (valueTerm rhs)

data SymmetricBridge =
  SymmetricBridge ValueTerm ValueTerm

class OpenSymmetricBridge lhs delta where
  openSymmetricBridge :: lhs -> delta -> SymmetricBridge

instance {-# OVERLAPPABLE #-} (ConstraintValue lhs, ConstraintValue delta) =>
         OpenSymmetricBridge lhs delta where
  openSymmetricBridge lhs delta =
    SymmetricBridge (valueTerm lhs) (valueTerm delta)

instance {-# OVERLAPPING #-} S.SymbolicType ty =>
         OpenSymmetricBridge (SelectedExpr ty tag) (S.Expr ty) where
  openSymmetricBridge lhs delta =
    SymmetricBridge (valueTerm lhs) (valueTerm delta)

instance {-# OVERLAPPING #-} OpenSymmetricBridge
           (Hsl (SelectedExpr S.Angle tag) (SelectedExpr S.Unit tag))
           HslExpr where
  openSymmetricBridge lhs delta =
    SymmetricBridge (valueTerm lhs) (valueTerm delta)

class CloseSymmetricBridge bridge rhs where
  closeSymmetricBridge :: bridge -> rhs -> LiftedConstraint

instance {-# OVERLAPPABLE #-} ConstraintValue rhs =>
         CloseSymmetricBridge SymmetricBridge rhs where
  closeSymmetricBridge bridge rhs =
    case bridge of
      SymmetricBridge lhs delta ->
        LiftedSymmetricBridge lhs delta (valueTerm rhs)

instance {-# OVERLAPPING #-} S.SymbolicType ty =>
         CloseSymmetricBridge SymmetricBridge (S.Expr ty) where
  closeSymmetricBridge bridge rhs =
    case bridge of
      SymmetricBridge lhs delta ->
        LiftedSymmetricBridge lhs delta (valueTerm rhs)

infixl 4 .<=.
infixl 4 .>=.
infixl 4 .==.
infixl 4 =|
infixl 4 |=
infixl 4 =/
infixl 4 /=
(.<=.) :: RelateValues lhs rhs => lhs -> rhs -> LiftedConstraint
(.<=.) = relateValues LayoutLessOrEqual

(.>=.) :: RelateValues rhs lhs => lhs -> rhs -> LiftedConstraint
lhs .>=. rhs = relateValues LayoutLessOrEqual rhs lhs

(.==.) :: RelateValues lhs rhs => lhs -> rhs -> LiftedConstraint
(.==.) = relateValues LayoutEqual

(=|) :: OpenDirectedBridge lhs gap => lhs -> gap -> DirectedBridge
lhs =| rhs = openDirectedBridge lhs rhs

(|=) :: CloseDirectedBridge bridge rhs => bridge -> rhs -> LiftedConstraint
lhs |= rhs = closeDirectedBridge lhs rhs

(=/) :: OpenSymmetricBridge lhs delta => lhs -> delta -> SymmetricBridge
lhs =/ delta = openSymmetricBridge lhs delta

(/=) :: CloseSymmetricBridge bridge rhs => bridge -> rhs -> LiftedConstraint
lhs /= rhs = closeSymmetricBridge lhs rhs

runProgram :: Program () -> VisualTraceGraph
runProgram program = V.buildGraph (interpretProgram program)

runProgramWith :: MatchSpec -> Program () -> VisualTraceGraph
runProgramWith spec program =
  V.buildGraphWithSpec spec (interpretProgram program)

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

interpretProgram :: Program a %1 -> V.VisualTraceBuilder a
interpretProgram program =
  case program of
    PureProgram value -> return value
    BindProgram first next -> do
      value <- interpretProgram first
      interpretProgram (next value)
    CreateProgram facts createPayload -> do
      V.Created block token <- V.createTagged facts createPayload
      V.appendTraceView (V.freshMatched token)
      return block
    UseProgram block -> do
      V.Used usedPayload token <- V.use block
      V.appendTraceView (V.remove token)
      return usedPayload
    CopyProgram facts block -> do
      V.Copied original copy' token <- V.copyTagged facts block
      V.appendTraceView (V.forkCopyMatched token)
      return (original, copy')
    ComputeProgram facts selectFacts computePayload -> do
      V.Computed block token <-
        V.computeTaggedWith facts selectFacts computePayload
      V.appendTraceView (V.freshMatched token)
      return block
    ReplaceProgram oldBlock incomingBlock -> do
      V.Replaced output token <- V.replace oldBlock incomingBlock
      V.appendTraceView (V.replaceMatched token)
      return output
    RetagProgram facts block -> do
      V.Copied original incoming copyToken <- V.copyTagged facts block
      V.Replaced output token <- V.replace original incoming
      V.appendTraceView $ do
        V.completeCopy copyToken
        V.replaceMatchedOutput token
      return output
    DestroyProgram block -> do
      V.Destroyed token <- V.destroy block
      V.appendTraceView (V.remove token)
      return ()
    DecideProgram predicate block -> do
      decision <- V.decide predicate block
      case decision of
        V.DecidedTrue token -> do
          V.appendTraceView (V.remove token)
          return BranchTrue
        V.DecidedFalse token -> do
          V.appendTraceView (V.remove token)
          return BranchFalse
    CheckpointProgram label -> V.checkpointTrace label
    LoopProgram loopState body -> interpretLoop loopState body

interpretLoop ::
     state
     %1 -> (state %1 -> Program (LoopResult state output))
  -> V.VisualTraceBuilder output
interpretLoop loopState body = do
  result <- interpretProgram (body loopState)
  case result of
    Continue nextState -> interpretLoop nextState body
    Finish output      -> return output

class Ensure constraint where
  ensure :: constraint -> VisualizationBuilder ()

instance Ensure OneConstraint where
  ensure = emitConstraint EnsureConstraint

instance Ensure LiftedConstraint where
  ensure = emitConstraint EnsureConstraint

class Encourage objective where
  encourage :: objective -> VisualizationBuilder ()

instance Encourage (S.Expr ty) where
  encourage objective = layout (V.encourage objective)

instance Encourage OneConstraint where
  encourage = emitConstraint EncourageConstraint

instance Encourage LiftedConstraint where
  encourage = emitConstraint EncourageConstraint

class EmitConstraint constraint where
  emitConstraint :: ConstraintStrength -> constraint -> VisualizationBuilder ()

instance EmitConstraint OneConstraint where
  emitConstraint strength constraint =
    case strength of
      EnsureConstraint    -> layout (V.ensure constraint)
      EncourageConstraint -> layout (V.encourageConstraint constraint)

instance EmitConstraint LiftedConstraint where
  emitConstraint strength constraint =
    emitVisualizationBuilder () (liftedConstraintSpec strength constraint)

liftedConstraintSpec :: ConstraintStrength -> LiftedConstraint -> MatchSpec
liftedConstraintSpec strength constraint =
  case constraint of
    LiftedValueRelation lhs relation rhs ->
      valueTermSpec lhs
        `matchSpecAppend` valueTermSpec rhs
        `matchSpecAppend` matchValueRelation
                            strength
                            (valueTermEndpoints lhs)
                            relation
                            (valueTermEndpoints rhs)
    LiftedDirectedBridge lhs gap rhs ->
      valueTermSpec lhs
        `matchSpecAppend` valueTermSpec gap
        `matchSpecAppend` valueTermSpec rhs
        `matchSpecAppend` matchValueDirectedBridge
                            strength
                            (valueTermEndpoints lhs)
                            (valueTermEndpoints gap)
                            (valueTermEndpoints rhs)
    LiftedSymmetricBridge lhs delta rhs ->
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
  namedVariable = global

bindInt :: VisualizationBuilder (Bound QueryInt)
bindInt = freshVisualizationValue "view.bind." (Bound P.. queryIntVar)

bindContent :: VisualizationBuilder (Bound ContentValue)
bindContent =
  freshVisualizationValue "view.bind." (Bound P.. ContentBinding P.. Binding)

class VariableSource value result where
  variable :: result

instance VariableValue value =>
         VariableSource value (VisualizationBuilder (Variable value)) where
  variable = freshVisualizationValue "view.var." (Variable P.. namedVariable)

instance (VariableValue value, arg ~ value) =>
         VariableSource value (arg -> VisualizationBuilder (Variable value)) where
  variable rhs = emptyVisualizationBuilder (Variable rhs)

class StyleTarget target result | target -> result where
  style :: target -> result

instance StyleTarget (StyleRecipe ()) (Style -> Style) where
  style = styleDefinition

styleDefinition :: StyleRecipe () -> Style -> Style
styleDefinition recipe =
  case recipe of
    NodeRecipe () spec -> nodeSpecStyleUpdate spec

setStyleWith :: (Style -> Style) -> NodeRecipe ()
setStyleWith update = NodeRecipe () emptyNodeSpec {nodeSpecStyleUpdate = update}

setStyleWithConstraints :: [S.Constraint] -> (Style -> Style) -> NodeRecipe ()
setStyleWithConstraints constraints update =
  NodeRecipe
    ()
    emptyNodeSpec
      { nodeSpecStyleUpdate = update
      , nodeSpecRequirements = [constrainRaw (S.All constraints)]
      }

class Opacity input output | input -> output, output -> input where
  opacity :: input -> output

class ZIndex input output | input -> output, output -> input where
  zIndex :: input -> output

class FontSize input output | input -> output, output -> input where
  fontSize :: input -> output

class Radius input output | input -> output, output -> input where
  radius :: input -> output

class StrokeWidth input output | input -> output, output -> input where
  strokeWidth :: input -> output

class Alpha input output | input -> output, output -> input where
  alpha :: input -> output

class Fill input output | input -> output, output -> input where
  fill :: input -> output

class Stroke input output | input -> output, output -> input where
  stroke :: input -> output

instance Opacity UnitExpr (NodeRecipe ()) where
  opacity value = setStyleWith (VS.setOpacity value)

instance Opacity (Selection (NodeRef tag)) (SelectedExpr S.Unit tag) where
  opacity selection = SelectedExpr selection (styleUnitValueAccess StyleOpacity)

instance ZIndex FreeExpr (NodeRecipe ()) where
  zIndex value = setStyleWith (VS.setZIndex value)

instance ZIndex (Selection (NodeRef tag)) (SelectedExpr S.Free tag) where
  zIndex selection = SelectedExpr selection (styleFreeValueAccess StyleZIndex)

instance FontSize Span (NodeRecipe ()) where
  fontSize value =
    setStyleWithConstraints
      (spanConstraints value)
      (VS.setFontSize (spanExpr value))

instance FontSize (Selection (NodeRef tag)) (SelectedExpr S.Layout tag) where
  fontSize selection =
    SelectedExpr selection (styleLayoutValueAccess StyleFontSize)

instance Radius Span (NodeRecipe ()) where
  radius value =
    setStyleWithConstraints
      (spanConstraints value)
      (VS.setRadius (spanExpr value))

instance Radius (Selection (NodeRef tag)) (SelectedExpr S.Layout tag) where
  radius selection = SelectedExpr selection (styleLayoutValueAccess StyleRadius)

instance StrokeWidth Span (NodeRecipe ()) where
  strokeWidth value =
    setStyleWithConstraints
      (spanConstraints value)
      (VS.setStrokeWidth (spanExpr value))

instance StrokeWidth (Selection (NodeRef tag)) (SelectedExpr S.Layout tag) where
  strokeWidth selection =
    SelectedExpr selection (styleLayoutValueAccess StyleStrokeWidth)

instance Alpha UnitExpr (NodeRecipe ()) where
  alpha value = setStyleWith (VS.setAlpha value)

instance Alpha (Selection (NodeRef tag)) (SelectedExpr S.Unit tag) where
  alpha selection = SelectedExpr selection (styleUnitValueAccess StyleAlpha)

instance Fill HslExpr (NodeRecipe ()) where
  fill value = setStyleWith (VS.setFill value)

instance Fill
           (Selection (NodeRef tag))
           (Hsl (SelectedExpr S.Angle tag) (SelectedExpr S.Unit tag)) where
  fill selection =
    Hsl
      (SelectedExpr selection (styleColorPartValueAccess StyleFill HslHue))
      (SelectedExpr
         selection
         (styleColorPartValueAccess StyleFill HslSaturation))
      (SelectedExpr selection (styleColorPartValueAccess StyleFill HslLightness))

instance Stroke HslExpr (NodeRecipe ()) where
  stroke value = setStyleWith (VS.setStroke value)

instance Stroke
           (Selection (NodeRef tag))
           (Hsl (SelectedExpr S.Angle tag) (SelectedExpr S.Unit tag)) where
  stroke selection =
    Hsl
      (SelectedExpr selection (styleColorPartValueAccess StyleStroke HslHue))
      (SelectedExpr
         selection
         (styleColorPartValueAccess StyleStroke HslSaturation))
      (SelectedExpr
         selection
         (styleColorPartValueAccess StyleStroke HslLightness))

sat :: Hsl hue unit -> unit
sat = saturation

fontFamily :: P.String -> NodeRecipe ()
fontFamily value = setStyleWith (VS.setFontFamily value)

fontWeight :: FontWeight -> NodeRecipe ()
fontWeight value = setStyleWith (VS.setFontWeight value)

fontStyle :: FontStyle -> NodeRecipe ()
fontStyle value = setStyleWith (VS.setFontStyle value)

textAlign :: TextAlign -> NodeRecipe ()
textAlign value = setStyleWith (VS.setTextAlign value)

borderStyle :: BorderStyle -> NodeRecipe ()
borderStyle value = setStyleWith (VS.setBorderStyle value)

whiteSpace :: WhiteSpace -> NodeRecipe ()
whiteSpace value = setStyleWith (VS.setWhiteSpace value)

bold :: NodeRecipe ()
bold = fontWeight FontWeightBold

centerText :: NodeRecipe ()
centerText = textAlign TextAlignCenter

content :: ContentValue -> NodeRecipe ()
content value =
  setNodeSpecWith
    (\spec -> spec {nodeSpecContent = Just (contentValueSpec value)})

contentValueSpec :: ContentValue -> ContentSpec
contentValueSpec value =
  case value of
    ContentLiteral textValue -> LiteralContent textValue
    ContentBinding binding   -> BoundContent binding

noWrap :: NodeRecipe ()
noWrap = whiteSpace WhiteSpaceNoWrap

setNodeSpecWith :: (NodeSpec -> NodeSpec) -> NodeRecipe ()
setNodeSpecWith update = NodeRecipe () (update emptyNodeSpec)

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

instance Left (Selection (NodeRef tag)) (SelectedExpr S.Layout tag) where
  left selection = SelectedExpr selection (layoutValueAccess AttrLeft)

instance Top (Selection (NodeRef tag)) (SelectedExpr S.Layout tag) where
  top selection = SelectedExpr selection (layoutValueAccess AttrTop)

instance Width (Selection (NodeRef tag)) (SelectedExpr S.Layout tag) where
  width selection = SelectedExpr selection (layoutValueAccess AttrWidth)

instance Height (Selection (NodeRef tag)) (SelectedExpr S.Layout tag) where
  height selection = SelectedExpr selection (layoutValueAccess AttrHeight)

instance Right (Selection (NodeRef tag)) (SelectedExpr S.Layout tag) where
  right selection = SelectedExpr selection (layoutValueAccess AttrRight)

instance Bottom (Selection (NodeRef tag)) (SelectedExpr S.Layout tag) where
  bottom selection = SelectedExpr selection (layoutValueAccess AttrBottom)

instance X Coord (NodeRecipe ()) where
  x value = setNodeSpecWith (\spec -> spec {nodeSpecX = Just value})

instance Y Coord (NodeRecipe ()) where
  y value = setNodeSpecWith (\spec -> spec {nodeSpecY = Just value})

instance X (Selection (NodeRef tag)) (SelectedExpr S.Layout tag) where
  x selection = SelectedExpr selection (layoutValueAccess AttrCenterX)

instance Y (Selection (NodeRef tag)) (SelectedExpr S.Layout tag) where
  y selection = SelectedExpr selection (layoutValueAccess AttrCenterY)

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

require :: ViewLayout () -> NodeRecipe ()
require action =
  setNodeSpecWith
    (\spec ->
       spec {nodeSpecRequirements = nodeSpecRequirements spec P.++ [action]})

data VirtualNode

class Node input result | input -> result where
  node :: input -> result

type family SelectQuery payload where
  SelectQuery AnyPayload = Query
  SelectQuery payload = TraceQuery payload

class Select payload query where
  selectWithPayload ::
       query -> VisualizationBuilder (NodeBinding (Selected payload))

instance Select AnyPayload Query where
  selectWithPayload query =
    emitVisualizationBuilder
      (Selected (Selection (AnyNodeRef query) emptyMatchSpec))
      emptyMatchSpec

instance C.Traceable tag => Select tag (TraceQuery tag) where
  selectWithPayload query =
    emitVisualizationBuilder
      (Selected (Selection (TraceNodeRef query) emptyMatchSpec))
      emptyMatchSpec

select ::
     forall payload. Select payload (SelectQuery payload)
  => SelectQuery payload
  -> VisualizationBuilder (NodeBinding (Selected payload))
select = selectWithPayload @payload @(SelectQuery payload)

defineNode :: NodeRecipe () -> NodeDefinition tag
defineNode = nodeDefinition

nodeDefinition :: NodeRecipe () -> NodeDefinition tag
nodeDefinition recipe =
  case recipe of
    NodeRecipe () spec ->
      boxDefinition (nodeSpecStyleUpdate spec) (layoutNode spec)

nodePatch :: MatchBindings -> NodeRecipe () -> V.NodePatch
nodePatch bindings recipe =
  case recipe of
    NodeRecipe () spec ->
      V.NodePatch
        { V.nodePatchStyleUpdate =
            substituteStyleBindings bindings P.. nodeSpecStyleUpdate spec
        , V.nodePatchContent =
            P.fmap (contentMode bindings) (nodeSpecContent spec)
        , V.nodePatchLeft =
            P.fmap
              (coordPin P.. substituteCoordBindings bindings)
              (nodeSpecLeft spec)
        , V.nodePatchTop =
            P.fmap
              (coordPin P.. substituteCoordBindings bindings)
              (nodeSpecTop spec)
        , V.nodePatchWidth =
            P.fmap
              (spanPin P.. substituteSpanBindings bindings)
              (nodeSpecWidth spec)
        , V.nodePatchHeight =
            P.fmap
              (spanPin P.. substituteSpanBindings bindings)
              (nodeSpecHeight spec)
        , V.nodePatchRight =
            P.fmap
              (coordPin P.. substituteCoordBindings bindings)
              (nodeSpecRight spec)
        , V.nodePatchBottom =
            P.fmap
              (coordPin P.. substituteCoordBindings bindings)
              (nodeSpecBottom spec)
        , V.nodePatchX =
            P.fmap
              (coordPin P.. substituteCoordBindings bindings)
              (nodeSpecX spec)
        , V.nodePatchY =
            P.fmap
              (coordPin P.. substituteCoordBindings bindings)
              (nodeSpecY spec)
        , V.nodePatchRequirements = nodeSpecRequirements spec
        }

substituteStyleBindings :: MatchBindings -> Style -> Style
substituteStyleBindings bindings =
  VS.mapStyleExprs (S.substituteExprVars (bindingExprSubstitutions bindings))

substituteCoordBindings :: MatchBindings -> Coord -> Coord
substituteCoordBindings bindings value =
  case value of
    Coord expr constraints ->
      Coord
        (S.substituteExprVars (bindingExprSubstitutions bindings) expr)
        constraints

substituteSpanBindings :: MatchBindings -> Span -> Span
substituteSpanBindings bindings value =
  case value of
    Span expr constraints ->
      Span
        (S.substituteExprVars (bindingExprSubstitutions bindings) expr)
        constraints

bindingExprSubstitutions :: MatchBindings -> [(P.String, P.Double)]
bindingExprSubstitutions bindings =
  case bindings of
    [] -> []
    V.MatchBinding name value:rest ->
      case Read.readMaybe value of
        Nothing -> bindingExprSubstitutions rest
        Just numericValue ->
          ("global." P.++ name, numericValue) : bindingExprSubstitutions rest

contentMode :: MatchBindings -> ContentSpec -> V.ContentMode
contentMode bindings spec =
  case spec of
    LiteralContent value -> V.ContentText value
    BoundContent binding -> V.ContentText (bindingContent bindings binding)

bindingContent :: MatchBindings -> Binding -> P.String
bindingContent bindings binding =
  case binding of
    Binding name ->
      case matchBindingValue name bindings of
        Nothing ->
          P.error ("Unbound view binding #" P.++ name P.++ " in content")
        Just value -> value

coordPin :: Coord -> V.LayoutPin
coordPin value =
  case value of
    Coord expr constraints -> V.LayoutPin expr constraints

spanPin :: Span -> V.LayoutPin
spanPin value =
  case value of
    Span expr constraints -> V.LayoutPin expr constraints

instance Node
           (Selected child)
           (VisualizationBuilder (NodeBinding (Selected VirtualNode))) where
  node children =
    case children of
      Selection child childSpec ->
        let query = nodeRefQuery child
         in VisualizationBuilder
              (\counter ->
                 let key = virtualNodeKey counter
                     virtualSpec = matchVirtualNode key query V.emptyNodePatch
                  in VisualizationResult
                       (Selected
                          (Selection (VirtualNodeRef key query) emptyMatchSpec))
                       (counter P.+ 1)
                       (matchSpecAppend childSpec virtualSpec))

instance Node
           (NodeBinding (Selected child))
           (VisualizationBuilder (NodeBinding (Selected VirtualNode))) where
  node binding =
    case binding of
      Selected children -> node children

instance Node
           (VisualizationBuilder (NodeBinding (Selected child)))
           (VisualizationBuilder (NodeBinding (Selected VirtualNode))) where
  node childrenBuilder =
    case childrenBuilder of
      VisualizationBuilder runFirst ->
        VisualizationBuilder
          (\counter0 ->
             case runFirst counter0 of
               VisualizationResult binding counter1 first ->
                 case node binding of
                   VisualizationBuilder runSecond ->
                     case runSecond counter1 of
                       VisualizationResult selected counter2 second ->
                         VisualizationResult
                           selected
                           counter2
                           (matchSpecAppend first second))

instance StyleTarget (Selected tag) (NodeRecipe () -> VisualizationBuilder ()) where
  style selection recipe =
    case selection of
      Selection handle spec ->
        VisualizationBuilder
          (\counter ->
             VisualizationResult
               ()
               counter
               (matchSpecAppend spec (nodeRefStyleSpec handle recipe)))

nodeRefStyleSpec :: NodeRef tag -> NodeRecipe () -> MatchSpec
nodeRefStyleSpec handle recipe =
  case handle of
    AnyNodeRef query -> matchAnyQueryNode query (`nodePatch` recipe)
    TraceNodeRef selector ->
      matchQueryPayloadNode
        (traceQueryQuery selector)
        (traceQueryPayloadPattern selector)
        (\context -> nodePatch (matchContextBindings context) recipe)
    VirtualNodeRef key query -> matchVirtualNode key query (nodePatch [] recipe)

nodeRefQuery :: NodeRef tag -> Query
nodeRefQuery handle =
  case handle of
    AnyNodeRef query       -> query
    TraceNodeRef selector  -> traceQueryQuery selector
    VirtualNodeRef _ query -> query

nodeSelection :: NodeRef tag -> NodeSelection
nodeSelection handle =
  case handle of
    AnyNodeRef query         -> TraceSelection query
    TraceNodeRef selector    -> TraceSelection (traceQueryQuery selector)
    VirtualNodeRef key query -> VirtualSelection key query

virtualNodeKey :: P.Int -> P.String
virtualNodeKey counter = "virtual-node-" P.++ P.show counter

visualize :: VisualizationBuilder () -> MatchSpec
visualize builder =
  case builder of
    VisualizationBuilder run ->
      case run 0 of
        VisualizationResult () _ spec -> spec

layout :: ViewLayout () -> VisualizationBuilder ()
layout body = emitVisualizationBuilder () (matchGlobalLayout body)

class PayloadSelector tag selector where
  payloadSelector :: selector -> PayloadPattern tag

instance PayloadSelector tag ContentValue where
  payloadSelector selector =
    case selector of
      ContentBinding binding ->
        case binding of
          Binding name -> payloadBindingPattern name
      ContentLiteral _ ->
        P.error "Literal content cannot be used as a payload binding selector"

instance (Payload tag ~ LBool tag) => PayloadSelector tag P.Bool where
  payloadSelector = payloadBoolPattern

instance (Payload tag ~ LInt tag) => PayloadSelector tag P.Int where
  payloadSelector = payloadIntPattern

instance (Payload tag ~ LDouble tag) => PayloadSelector tag P.Double where
  payloadSelector = payloadDoublePattern

instance (Payload tag ~ LString tag) => PayloadSelector tag P.String where
  payloadSelector = payloadStringPattern

instance (Payload tag ~ LUnit tag) => PayloadSelector tag () where
  payloadSelector = payloadUnitPattern

traceQueryQuery :: TraceQuery tag -> Query
traceQueryQuery query =
  case query of
    TraceQuery query' _ -> query'

traceQueryPayloadPattern :: TraceQuery tag -> PayloadPattern tag
traceQueryPayloadPattern query =
  case query of
    TraceQuery _ Nothing               -> anyPayloadPattern
    TraceQuery _ (Just payloadPattern) -> payloadPattern

traceQueryAppend :: TraceQuery tag -> TraceQuery tag -> TraceQuery tag
traceQueryAppend lhs rhs =
  case lhs of
    TraceQuery leftQuery leftPayload ->
      case rhs of
        TraceQuery rightQuery rightPayload ->
          TraceQuery
            (queryAppend leftQuery rightQuery)
            (preferLater leftPayload rightPayload)

instance KnownSymbol name => IsLabel name (TraceQuery tag) where
  fromLabel = TraceQuery (queryAtom (S.labelName (Proxy @name))) Nothing

instance KnownSymbol name => IsLabel name (QueryInt -> TraceQuery tag) where
  fromLabel value =
    TraceQuery (queryInt (S.labelName (Proxy @name)) value) Nothing

class QueryAppend query where
  appendQuery :: query -> query -> query

instance QueryAppend Query where
  appendQuery = queryAppend

instance QueryAppend (TraceQuery tag) where
  appendQuery = traceQueryAppend

(<&&>) :: QueryAppend query => query -> query -> query
(<&&>) = appendQuery

layoutNode :: NodeSpec -> LiveVisual tag %1 -> ViewLayout (NodeVisual tag)
layoutNode spec visual0 = do
  LayoutUse visual1 leftVar <- takeLeft visual0
  LayoutUse visual2 topVar <- takeTop visual1
  LayoutUse visual3 widthVar <- takeWidth visual2
  LayoutUse visual4 heightVar <- takeHeight visual3
  case leftVar of
    OneExpr (Ur leftExpr) ->
      case topVar of
        OneExpr (Ur topExpr) ->
          case widthVar of
            OneExpr (Ur widthExpr) ->
              case heightVar of
                OneExpr (Ur heightExpr) -> do
                  runRequirements (nodeSpecRequirements spec)
                  constrainGeometry spec leftExpr topExpr widthExpr heightExpr
                  return visual4

runRequirements :: [ViewLayout ()] -> ViewLayout ()
runRequirements actions =
  case actions of
    [] -> return ()
    action:rest -> do
      action
      runRequirements rest

constrainGeometry ::
     NodeSpec
  -> LayoutExpr
  -> LayoutExpr
  -> LayoutExpr
  -> LayoutExpr
  -> ViewLayout ()
constrainGeometry spec leftExpr topExpr widthExpr heightExpr = do
  constrainMaybeCoord leftExpr (nodeSpecLeft spec)
  constrainMaybeCoord topExpr (nodeSpecTop spec)
  constrainMaybeSpan widthExpr (nodeSpecWidth spec)
  constrainMaybeSpan heightExpr (nodeSpecHeight spec)
  constrainMaybeCoord (leftExpr S.@+@ widthExpr) (nodeSpecRight spec)
  constrainMaybeCoord (topExpr S.@+@ heightExpr) (nodeSpecBottom spec)
  constrainMaybeCoord
    (leftExpr S.@+@ (widthExpr S.@/@ (S.num 2 :: LayoutExpr)))
    (nodeSpecX spec)
  constrainMaybeCoord
    (topExpr S.@+@ (heightExpr S.@/@ (S.num 2 :: LayoutExpr)))
    (nodeSpecY spec)

constrainMaybeCoord :: LayoutExpr -> Maybe Coord -> ViewLayout ()
constrainMaybeCoord expr maybeTarget =
  case maybeTarget of
    Nothing -> return ()
    Just target ->
      constrainRaw
        (S.All (coordConstraints target P.++ [expr S.@==@ coordExpr target]))

constrainMaybeSpan :: LayoutExpr -> Maybe Span -> ViewLayout ()
constrainMaybeSpan expr maybeTarget =
  case maybeTarget of
    Nothing -> return ()
    Just target ->
      constrainRaw
        (S.All (spanConstraints target P.++ [expr S.@==@ spanExpr target]))

constrainRaw :: S.Constraint -> ViewLayout ()
constrainRaw constraint = V.ensure (OneConstraint (Ur constraint))

placeBox ::
     LayoutExpr
  -> LayoutExpr
  -> LayoutExpr
  -> LayoutExpr
  -> LiveVisual tag
     %1 -> ViewLayout (BoxVisual tag)
placeBox leftExpr topExpr widthExpr heightExpr visual0 = do
  LayoutUse visual1 leftVar <- takeLeft visual0
  LayoutUse visual2 topVar <- takeTop visual1
  LayoutUse visual3 widthVar <- takeWidth visual2
  LayoutUse visual4 heightVar <- takeHeight visual3
  V.ensure (leftVar V.@==@ leftExpr)
  V.ensure (topVar V.@==@ topExpr)
  V.ensure (widthVar V.@==@ widthExpr)
  V.ensure (heightVar V.@==@ heightExpr)
  return visual4
