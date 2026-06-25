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
  , MatchedNode
  , Pattern
  , PatternInt
  , patternIndex
  , patternIntField
  , VisualizationBuilder
  , PairPattern(..)
  , MatchRule
  , QueryAppend
  , visualize
  , emptyMatchSpec
  , matchSpecAppend
  , matchSpecFromList
  , layout
  , match
  , part
  , whereFacts
  , matchLayout
  , matchPair
  , pair
  , adjacent
  , emptyQuery
  , queryAtom
  , queryInt
  , queryFacts
  , (<>)
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
  , EmptyStyleDraft
  , BorderStyle(..)
  , Bounds(..)
  , BoundsExpr
  , FontWeight(..)
  , FontStyle(..)
  , Hsl(..)
  , FreeExpr
  , HslExpr
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
  , alpha
  , asCoord
  , asSpan
  , at
  , bold
  , bottom
  , bounds
  , by
  , borderStyle
  , boxDefinition
  , centerText
  , content
  , contentDebug
  , constrain
  , derive
  , deriveCoord
  , deriveSpan
  , deriveOffset
  , deriveScalar
  , deriveExpr
  , deriveHue
  , Derived
  , coordExpr
  , encourage
  , fill
  , finalizeStyle
  , fontFamily
  , fontSize
  , fontStyle
  , fontWeight
  , fromLabel
  , global
  , globalCoord
  , globalSpan
  , height
  , left
  , noWrap
  , node
  , num
  , fromInteger
  , fromRational
  , offsetExpr
  , opacity
  , placeBox
  , position
  , radius
  , require
  , right
  , setFillOnce
  , setFontFamilyOnce
  , setFontSizeOnce
  , setFontWeightOnce
  , setRadiusOnce
  , setStrokeOnce
  , setStrokeWidthOnce
  , setTextAlignOnce
  , setWhiteSpaceOnce
  , setZIndexOnce
  , stroke
  , strokeWidth
  , style
  , shift
  , scalarExpr
  , spanExpr
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
  , (<|)
  , (<|>)
  , (=|)
  , (=|=)
  , (|+|)
  , (|=)
  , (|>)
  ) where

import           Control.Functor.Linear hiding ((<$>), (<*>))
import qualified Data.Functor.Linear    as DFL
import           Data.Proxy             (Proxy (..))
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
                                         EmptyStyleDraft, FontStyle (..),
                                         FontWeight (..), FreeExpr, Hsl (..),
                                         HslExpr, HueExpr, LayoutExpr,
                                         LayoutUse (..), LiveVisual, MatchSpec,
                                         MatchedNode, OneConstraint (..),
                                         OneExpr (..), PairPattern (..),
                                         Pattern, PatternInt, Query, Style,
                                         TextAlign (..), UnitExpr,
                                         WhiteSpace (..), boxDefinition,
                                         emptyMatchSpec, emptyQuery, encourage,
                                         finalizeStyle, global,
                                         matchGlobalLayout, matchPairAdjacent,
                                         matchPatternLayout, matchPatternNode,
                                         matchPatternPair, matchPatternPartNode,
                                         matchSpecAppend, matchSpecFromList,
                                         matchTagNode, patternAppend,
                                         patternIntAdd, patternIntConst,
                                         queryAppend, queryAtom, queryFacts,
                                         queryInt, setFillOnce,
                                         setFontFamilyOnce, setFontSizeOnce,
                                         setFontWeightOnce, setRadiusOnce,
                                         setStrokeOnce, setStrokeWidthOnce,
                                         setTextAlignOnce, setWhiteSpaceOnce,
                                         setZIndexOnce, takeHeight, takeLeft,
                                         takeRight, takeTop, takeWidth)
import qualified LinearTrace.View       as V
import qualified LinearTrace.View.Style as VS
import qualified Prelude                as P
import           Prelude.Linear         hiding (fromInteger, fromRational, (*),
                                         (+), (-), (/), (<>))

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

data CoordChain =
  CoordChain Coord [S.Constraint]

data BridgeRelation
  = BridgeLoose
  | BridgeExact

data CoordSpanBridge =
  CoordSpanBridge BridgeRelation Coord Span [S.Constraint]

data NodeSpec = NodeSpec
  { nodeSpecStyleUpdate  :: Style -> Style
  , nodeSpecContent      :: Maybe V.ContentMode
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

data VisualizationBuilder a where
  VisualizationBuilder :: a %1 -> MatchSpec -> VisualizationBuilder a

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
    VisualizationBuilder value first ->
      case next value of
        VisualizationBuilder output second ->
          VisualizationBuilder output (matchSpecAppend first second)

instance DFL.Functor VisualizationBuilder where
  fmap f builder =
    case builder of
      VisualizationBuilder value spec -> VisualizationBuilder (f value) spec

instance Functor VisualizationBuilder where
  fmap f builder =
    case builder of
      VisualizationBuilder value spec -> VisualizationBuilder (f value) spec

instance DFL.Applicative VisualizationBuilder where
  pure value = VisualizationBuilder value emptyMatchSpec
  liftA2 f lhs rhs =
    case lhs of
      VisualizationBuilder leftValue first ->
        case rhs of
          VisualizationBuilder rightValue second ->
            VisualizationBuilder
              (f leftValue rightValue)
              (matchSpecAppend first second)

instance Applicative VisualizationBuilder where
  pure value = VisualizationBuilder value emptyMatchSpec
  liftA2 f lhs rhs =
    case lhs of
      VisualizationBuilder leftValue first ->
        case rhs of
          VisualizationBuilder rightValue second ->
            VisualizationBuilder
              (f leftValue rightValue)
              (matchSpecAppend first second)

instance Monad VisualizationBuilder where
  (>>=) = bindVisualizationBuilder

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

instance IntegerLiteral PatternInt where
  integerLiteral value = patternIntConst (P.fromInteger value)

patternIndex :: P.Int -> PatternInt
patternIndex = patternIntConst

patternIntField :: (PatternInt -> Pattern) -> PatternInt -> Pattern
patternIntField field = field

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

instance KnownSymbol name => IsLabel name Coord where
  fromLabel = globalCoord (S.labelName (Proxy @name))

instance KnownSymbol name => IsLabel name Span where
  fromLabel = globalSpan (S.labelName (Proxy @name))

asCoord :: Offset -> Coord
asCoord value =
  case value of
    Offset expr constraints -> mkCoord expr constraints

asSpan :: Offset -> Span
asSpan value =
  case value of
    Offset expr constraints -> mkSpan expr constraints

rawOneConstraint :: [S.Constraint] -> OneConstraint
rawOneConstraint constraints = OneConstraint (Ur (S.All constraints))

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

instance AddExpr PatternInt P.Int PatternInt where
  addExpr = patternIntAdd

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

coordRelate ::
     (LayoutExpr -> LayoutExpr -> S.Constraint) -> Coord -> Coord -> CoordChain
coordRelate op lhs rhs =
  CoordChain
    rhs
    (coordConstraints lhs
       P.++ coordConstraints rhs
       P.++ [op (coordExpr lhs) (coordExpr rhs)])

openBridge :: BridgeRelation -> Coord -> Span -> CoordSpanBridge
openBridge relation lhs spanValue =
  CoordSpanBridge
    relation
    lhs
    spanValue
    (coordConstraints lhs P.++ spanConstraints spanValue)

bridgeConstraint ::
     BridgeRelation -> BridgeRelation -> Coord -> Span -> Coord -> S.Constraint
bridgeConstraint lhsRelation rhsRelation lhs spanValue rhs =
  case (lhsRelation, rhsRelation) of
    (BridgeExact, BridgeExact) ->
      (coordExpr lhs S.@+@ spanExpr spanValue) S.@==@ coordExpr rhs
    _ -> (coordExpr lhs S.@+@ spanExpr spanValue) S.@<=@ coordExpr rhs

closeBridge :: BridgeRelation -> CoordSpanBridge -> Coord -> CoordChain
closeBridge rhsRelation bridge rhs =
  case bridge of
    CoordSpanBridge lhsRelation lhs spanValue constraints ->
      CoordChain
        rhs
        (constraints
           P.++ coordConstraints rhs
           P.++ [bridgeConstraint lhsRelation rhsRelation lhs spanValue rhs])

infixl 4 <|>
infixl 4 =|=
infixl 4 <|
infixl 4 =|
infixl 4 |>
infixl 4 |=
(<|>) :: Coord -> Coord -> CoordChain
(<|>) = coordRelate (S.@<=@)

(=|=) :: Coord -> Coord -> CoordChain
(=|=) = coordRelate (S.@==@)

(<|) :: Coord -> Span -> CoordSpanBridge
lhs <| rhs = openBridge BridgeLoose lhs rhs

(=|) :: Coord -> Span -> CoordSpanBridge
lhs =| rhs = openBridge BridgeExact lhs rhs

(|>) :: CoordSpanBridge -> Coord -> CoordChain
lhs |> rhs = closeBridge BridgeLoose lhs rhs

(|=) :: CoordSpanBridge -> Coord -> CoordChain
lhs |= rhs = closeBridge BridgeExact lhs rhs

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
    selectFacts payload = queryFacts (selectQuery payload)

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
    CreateProgram facts payload -> do
      V.Created block token <- V.createTagged facts payload
      V.appendTraceView (V.freshMatched token)
      return block
    UseProgram block -> do
      V.Used payload token <- V.use block
      V.appendTraceView (V.remove token)
      return payload
    CopyProgram facts block -> do
      V.Copied original copy' token <- V.copyTagged facts block
      V.appendTraceView (V.forkCopyMatched token)
      return (original, copy')
    ComputeProgram facts selectFacts payload -> do
      V.Computed block token <- V.computeTaggedWith facts selectFacts payload
      V.appendTraceView (V.freshMatched token)
      return block
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

class ConstraintLike constraint where
  toOneConstraint :: constraint -> OneConstraint

instance ConstraintLike OneConstraint where
  toOneConstraint constraint = constraint

instance ConstraintLike CoordChain where
  toOneConstraint chain =
    case chain of
      CoordChain _ constraints -> rawOneConstraint constraints

constrain :: ConstraintLike constraint => constraint -> ViewLayout ()
constrain constraint = V.ensure (toOneConstraint constraint)

class Derived value where
  derive :: value -> value -> ViewLayout ()

deriveLayoutExpr ::
     LayoutExpr
  -> [S.Constraint]
  -> LayoutExpr
  -> [S.Constraint]
  -> ViewLayout ()
deriveLayoutExpr lhs lhsConstraints rhs rhsConstraints =
  constrainRaw
    (S.All (lhsConstraints P.++ rhsConstraints P.++ [lhs S.@==@ rhs]))

instance Derived Coord where
  derive lhs rhs =
    deriveLayoutExpr
      (coordExpr lhs)
      (coordConstraints lhs)
      (coordExpr rhs)
      (coordConstraints rhs)

instance Derived Span where
  derive lhs rhs =
    deriveLayoutExpr
      (spanExpr lhs)
      (spanConstraints lhs)
      (spanExpr rhs)
      (spanConstraints rhs)

instance Derived Offset where
  derive lhs rhs =
    deriveLayoutExpr
      (offsetExpr lhs)
      (offsetConstraints lhs)
      (offsetExpr rhs)
      (offsetConstraints rhs)

instance Derived Scalar where
  derive lhs rhs =
    deriveLayoutExpr
      (scalarExpr lhs)
      (scalarConstraints lhs)
      (scalarExpr rhs)
      (scalarConstraints rhs)

deriveCoord :: Coord -> Coord -> ViewLayout ()
deriveCoord = derive

deriveSpan :: Span -> Span -> ViewLayout ()
deriveSpan = derive

deriveOffset :: Offset -> Offset -> ViewLayout ()
deriveOffset = derive

deriveScalar :: Scalar -> Scalar -> ViewLayout ()
deriveScalar = derive

deriveExpr :: S.SymbolicType ty => S.Expr ty -> S.Expr ty -> ViewLayout ()
deriveExpr lhs rhs = constrainRaw (lhs S.@==@ rhs)

deriveHue :: HueExpr -> HueExpr -> ViewLayout ()
deriveHue = deriveExpr

style :: StyleRecipe () -> (EmptyStyleDraft %1 -> Style)
style recipe =
  case recipe of
    NodeRecipe () spec -> V.finalizeStyleWith (nodeSpecStyleUpdate spec)

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

opacity :: UnitExpr -> NodeRecipe ()
opacity value = setStyleWith (VS.setOpacity value)

zIndex :: FreeExpr -> NodeRecipe ()
zIndex value = setStyleWith (VS.setZIndex value)

fontSize :: Span -> NodeRecipe ()
fontSize value =
  setStyleWithConstraints
    (spanConstraints value)
    (VS.setFontSize (spanExpr value))

radius :: Span -> NodeRecipe ()
radius value =
  setStyleWithConstraints
    (spanConstraints value)
    (VS.setRadius (spanExpr value))

strokeWidth :: Span -> NodeRecipe ()
strokeWidth value =
  setStyleWithConstraints
    (spanConstraints value)
    (VS.setStrokeWidth (spanExpr value))

alpha :: UnitExpr -> NodeRecipe ()
alpha value = setStyleWith (VS.setAlpha value)

fill :: HslExpr -> NodeRecipe ()
fill value = setStyleWith (VS.setFill value)

stroke :: HslExpr -> NodeRecipe ()
stroke value = setStyleWith (VS.setStroke value)

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

content :: P.String -> NodeRecipe ()
content value =
  setNodeSpecWith (\spec -> spec {nodeSpecContent = Just (V.ContentText value)})

contentDebug :: NodeRecipe ()
contentDebug =
  setNodeSpecWith (\spec -> spec {nodeSpecContent = Just V.ContentDebug})

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

instance Left MatchedNode Coord where
  left matched = mkCoord (V.matchedLeft matched) []

instance Top MatchedNode Coord where
  top matched = mkCoord (V.matchedTop matched) []

instance Right MatchedNode Coord where
  right matched = mkCoord (V.matchedRight matched) []

instance Bottom MatchedNode Coord where
  bottom matched = mkCoord (V.matchedBottom matched) []

instance Width MatchedNode Span where
  width matched = mkSpan (V.matchedWidth matched) []

instance Height MatchedNode Span where
  height matched = mkSpan (V.matchedHeight matched) []

x :: Coord -> NodeRecipe ()
x value = setNodeSpecWith (\spec -> spec {nodeSpecX = Just value})

y :: Coord -> NodeRecipe ()
y value = setNodeSpecWith (\spec -> spec {nodeSpecY = Just value})

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

node :: NodeRecipe () -> NodeDefinition tag
node recipe =
  case recipe of
    NodeRecipe () spec ->
      boxDefinition
        (V.finalizeStyleWith (nodeSpecStyleUpdate spec))
        (layoutNode spec)

nodePatch :: NodeRecipe () -> V.NodePatch
nodePatch recipe =
  case recipe of
    NodeRecipe () spec ->
      V.NodePatch
        { V.nodePatchStyleUpdate = nodeSpecStyleUpdate spec
        , V.nodePatchContent = nodeSpecContent spec
        , V.nodePatchLeft = P.fmap coordPin (nodeSpecLeft spec)
        , V.nodePatchTop = P.fmap coordPin (nodeSpecTop spec)
        , V.nodePatchWidth = P.fmap spanPin (nodeSpecWidth spec)
        , V.nodePatchHeight = P.fmap spanPin (nodeSpecHeight spec)
        , V.nodePatchRight = P.fmap coordPin (nodeSpecRight spec)
        , V.nodePatchBottom = P.fmap coordPin (nodeSpecBottom spec)
        , V.nodePatchX = P.fmap coordPin (nodeSpecX spec)
        , V.nodePatchY = P.fmap coordPin (nodeSpecY spec)
        , V.nodePatchRequirements = nodeSpecRequirements spec
        }

coordPin :: Coord -> V.LayoutPin
coordPin value =
  case value of
    Coord expr constraints -> V.LayoutPin expr constraints

spanPin :: Span -> V.LayoutPin
spanPin value =
  case value of
    Span expr constraints -> V.LayoutPin expr constraints

visualize :: VisualizationBuilder () -> MatchSpec
visualize builder =
  case builder of
    VisualizationBuilder () spec -> spec

layout :: ViewLayout () -> VisualizationBuilder ()
layout body = VisualizationBuilder () (matchGlobalLayout body)

class MatchRule tag selector result | tag selector -> result where
  match :: selector -> result

instance C.Traceable tag =>
         MatchRule tag (NodeRecipe ()) (VisualizationBuilder ()) where
  match recipe =
    VisualizationBuilder () (matchTagNode @tag (\_index -> nodePatch recipe))

instance C.Traceable tag =>
         MatchRule tag Pattern (NodeRecipe () -> VisualizationBuilder ()) where
  match pattern' recipe =
    VisualizationBuilder
      ()
      (matchPatternNode @tag pattern' (\_index -> nodePatch recipe))

part ::
     forall tag. C.Traceable tag
  => P.String
  -> Pattern
  -> NodeRecipe ()
  -> VisualizationBuilder ()
part nodeKey pattern' recipe =
  VisualizationBuilder
    ()
    (matchPatternPartNode @tag pattern' nodeKey (\_index -> nodePatch recipe))

whereFacts :: Pattern -> Pattern
whereFacts pattern' = pattern'

matchLayout ::
     Pattern -> (MatchedNode -> ViewLayout ()) -> VisualizationBuilder ()
matchLayout pattern' body =
  VisualizationBuilder () (matchPatternLayout pattern' body)

matchPair ::
     Pattern
  -> Pattern
  -> (MatchedNode -> MatchedNode -> ViewLayout ())
  -> VisualizationBuilder ()
matchPair firstPattern secondPattern body =
  VisualizationBuilder () (matchPatternPair firstPattern secondPattern body)

pair :: Pattern -> Pattern -> Pattern -> PairPattern
pair firstPattern secondPattern name =
  V.PairPattern
    { V.pairFirstPattern = firstPattern
    , V.pairSecondPattern = secondPattern
    , V.pairName = V.patternKey name
    }

adjacent :: PairPattern -> Span -> VisualizationBuilder ()
adjacent pattern' gap =
  VisualizationBuilder
    ()
    (matchPairAdjacent pattern' (spanExpr gap) (spanConstraints gap))

class QueryAppend query where
  appendQuery :: query -> query -> query

instance QueryAppend Query where
  appendQuery = queryAppend

instance QueryAppend Pattern where
  appendQuery = patternAppend

(<>) :: QueryAppend query => query -> query -> query
(<>) = appendQuery

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
