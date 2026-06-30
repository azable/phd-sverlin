{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs             #-}
{-# LANGUAGE LinearTypes       #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE RebindableSyntax  #-}
{-# LANGUAGE TypeFamilies      #-}

-- | Internal choreography data types and builder instances shared by the public
-- facade and implementation modules.
module LinearTrace.Choreography.Types
  ( CoordRole
  , SpanRole
  , OffsetRole
  , ScalarRole
  , LayoutValue(..)
  , Coord
  , Span
  , Offset
  , Scalar
  , layoutValueExpr
  , layoutValueConstraints
  , coordExpr
  , spanExpr
  , offsetExpr
  , scalarExpr
  , coordConstraints
  , spanConstraints
  , offsetConstraints
  , scalarConstraints
  , Binding(..)
  , TraceQuery(..)
  , Selection(..)
  , AnyPayload
  , NodeRef(..)
  , Selected(..)
  , Variable(..)
  , Categorical(..)
  , Bound(..)
  , NodeBinding(..)
  , SelectionValue(..)
  , SelectionCategory(..)
  , VisualConstraint(..)
  , ValueTerm(..)
  , CategoryTerm(..)
  , ContentValue(..)
  , text
  , ContentSpec(..)
  , NodeSpec(..)
  , NodeRecipe(..)
  , VisualizationResult(..)
  , VisualizationBuilder(..)
  , emptyNodeSpec
  , appendNodeSpec
  , preferLater
  , emptyVisualizationBuilder
  , emptyVisualizationBuilderLinear
  , emitVisualizationBuilder
  , freshVisualizationValue
  ) where

import           Control.Functor.Linear         hiding ((<$>), (<*>))
import qualified Data.Functor.Linear            as DFL
import           Data.Proxy                     (Proxy (..))
import           GHC.Exts                       (Multiplicity (Many))
import           GHC.OverloadedLabels           (IsLabel (..))
import           GHC.TypeLits                   (KnownSymbol)
import           LinearTrace.Choreography.Match (CategoryEndpoint,
                                                 CategoryRelation,
                                                 LayoutRelation, MatchSpec,
                                                 ValueEndpoint, emptyMatchSpec,
                                                 matchSpecAppend)
import           LinearTrace.Choreography.Query (PayloadPattern, Query,
                                                 QueryInt, labelName, queryAtom,
                                                 queryInt)
import qualified LinearTrace.Core               as C
import           LinearTrace.View               (NodeStyle)
import           LinearTrace.View.Access        (CategoryAccess, ValueAccess)
import           LinearTrace.View.Primitives    (LayoutExpr)
import qualified Prelude                        as P
import           Prelude.Linear
import qualified Solver                         as S

data CoordRole

data SpanRole

data OffsetRole

data ScalarRole

data LayoutValue tag =
  LayoutValue LayoutExpr [S.Constraint]
  deriving (P.Eq, P.Show)

type Coord = LayoutValue CoordRole

type Span = LayoutValue SpanRole

type Offset = LayoutValue OffsetRole

type Scalar = LayoutValue ScalarRole

layoutValueExpr :: LayoutValue tag -> LayoutExpr
layoutValueExpr value =
  case value of
    LayoutValue expr _ -> expr

layoutValueConstraints :: LayoutValue tag -> [S.Constraint]
layoutValueConstraints value =
  case value of
    LayoutValue _ constraints -> constraints

coordExpr :: Coord -> LayoutExpr
coordExpr = layoutValueExpr

spanExpr :: Span -> LayoutExpr
spanExpr = layoutValueExpr

offsetExpr :: Offset -> LayoutExpr
offsetExpr = layoutValueExpr

scalarExpr :: Scalar -> LayoutExpr
scalarExpr = layoutValueExpr

coordConstraints :: Coord -> [S.Constraint]
coordConstraints = layoutValueConstraints

spanConstraints :: Span -> [S.Constraint]
spanConstraints = layoutValueConstraints

offsetConstraints :: Offset -> [S.Constraint]
offsetConstraints = layoutValueConstraints

scalarConstraints :: Scalar -> [S.Constraint]
scalarConstraints = layoutValueConstraints

newtype Binding =
  Binding P.String
  deriving (P.Eq, P.Show)

data TraceQuery tag =
  TraceQuery Query (Maybe (PayloadPattern tag))

instance KnownSymbol name => IsLabel name (TraceQuery tag) where
  fromLabel = TraceQuery (queryAtom (labelName (Proxy @name))) Nothing

instance KnownSymbol name => IsLabel name (QueryInt -> TraceQuery tag) where
  fromLabel value =
    TraceQuery (queryInt (labelName (Proxy @name)) value) Nothing

data Selection a where
  Selection :: a %1 -> MatchSpec -> Selection a

data AnyPayload

data NodeRef tag where
  TraceNodeRef :: C.Traceable tag => TraceQuery tag -> NodeRef tag
  AnyNodeRef :: Query -> NodeRef AnyPayload
  GroupNodeRef :: P.String -> Query -> NodeRef tag

data Selected tag where
  SelectedHandle :: Selection (NodeRef tag) -> Selected tag

data Variable a where
  Variable :: a %Many -> Variable a

newtype Categorical value =
  Categorical (S.Choice value)

data Bound a where
  Bound :: a %Many -> Bound a

data NodeBinding a where
  Selected :: a %Many -> NodeBinding a

data SelectionValue value tag =
  SelectionValue (Selected tag) ValueAccess

data SelectionCategory value tag =
  SelectionCategory (Selected tag) (CategoryAccess value)

data VisualConstraint where
  VisualValueRelation
    :: ValueTerm -> LayoutRelation -> ValueTerm -> VisualConstraint
  VisualCategoryRelation
    :: S.ChoiceDomain value=> CategoryTerm value
    -> CategoryRelation
    -> CategoryTerm value
    -> VisualConstraint
  VisualDirectedBridge
    :: ValueTerm -> ValueTerm -> ValueTerm -> VisualConstraint
  VisualSymmetricBridge
    :: ValueTerm -> ValueTerm -> ValueTerm -> VisualConstraint

data ValueTerm =
  ValueTerm MatchSpec [ValueEndpoint]

data CategoryTerm value =
  CategoryTerm MatchSpec [CategoryEndpoint value]

data ContentValue
  = ContentLiteral P.String
  | ContentBinding Binding

text :: P.String -> ContentValue
text = ContentLiteral

instance IsString ContentValue where
  fromString = ContentLiteral

data ContentSpec
  = LiteralContent P.String
  | BoundContent Binding

data NodeSpec = NodeSpec
  { nodeSpecStyleUpdate :: NodeStyle -> NodeStyle
  , nodeSpecContent     :: Maybe ContentSpec
  , nodeSpecLeft        :: Maybe Coord
  , nodeSpecTop         :: Maybe Coord
  , nodeSpecWidth       :: Maybe Span
  , nodeSpecHeight      :: Maybe Span
  , nodeSpecRight       :: Maybe Coord
  , nodeSpecBottom      :: Maybe Coord
  , nodeSpecX           :: Maybe Coord
  , nodeSpecY           :: Maybe Coord
  }

data NodeRecipe a where
  NodeRecipe :: a %1 -> NodeSpec -> NodeRecipe a

data VisualizationResult a where
  VisualizationResult :: a %1 -> P.Int -> MatchSpec -> VisualizationResult a

data VisualizationBuilder a where
  VisualizationBuilder
    :: (P.Int -> VisualizationResult a) %1 -> VisualizationBuilder a

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
    }

composeStyleUpdates ::
     (NodeStyle -> NodeStyle)
  -> (NodeStyle -> NodeStyle)
  -> NodeStyle
  -> NodeStyle
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
