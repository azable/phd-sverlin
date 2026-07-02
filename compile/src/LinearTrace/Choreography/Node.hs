{-# LANGUAGE DataKinds              #-}
{-# LANGUAGE FlexibleContexts       #-}
{-# LANGUAGE FlexibleInstances      #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE GADTs                  #-}
{-# LANGUAGE LinearTypes            #-}
{-# LANGUAGE NoImplicitPrelude      #-}
{-# LANGUAGE ScopedTypeVariables    #-}
{-# LANGUAGE TypeApplications       #-}
{-# LANGUAGE TypeFamilies           #-}
{-# LANGUAGE UndecidableInstances   #-}

-- | Node recipe, selection, rendering, and query-patching implementation for
-- choreography. The public facade re-exports the DSL surface from here.
module LinearTrace.Choreography.Node
  ( ContentValue(..)
  , content
  , Binding(..)
  , CoordRole
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
  , coordPin
  , spanPin
  , payload
  , TraceQuery
  , Selected(..)
  , Variable(..)
  , Bound(..)
  , NodeBinding(..)
  , SelectionValue(..)
  , SelectionCategory(..)
  , Selection(..)
  , AnyPayload
  , NodeRef(..)
  , NodeRecipe(..)
  , VisualizationResult(..)
  , VisualizationBuilder(..)
  , preferLater
  , text
  , emptyVisualizationBuilder
  , emptyVisualizationBuilderLinear
  , emitVisualizationBuilder
  , freshVisualizationValue
  , setNodePatch
  , substituteCoordBindings
  , substituteSpanBindings
  , substituteStyleBindings
  , GroupNode
  , Node
  , node
  , Select
  , SelectQuery
  , select
  , render
  , visualize
  , QueryAppend
  , (<&>)
  , nodeSelection
  , nodeRefQuery
  , traceQueryPayloadPattern
  , traceQueryQuery
  ) where

import           Control.Functor.Linear         hiding ((<$>), (<&>), (<*>))
import qualified Data.Functor.Linear            as DFL
import           Data.Proxy                     (Proxy (..))
import           GHC.Exts                       (Multiplicity (Many))
import           GHC.OverloadedLabels           (IsLabel (fromLabel))
import           GHC.TypeLits                   (KnownSymbol)
import           LinearTrace.Choreography.Match (MatchSpec, NodeSelection (..),
                                                 emptyMatchSpec,
                                                 matchAnyQueryNode,
                                                 matchContextBindings,
                                                 matchGroupNode,
                                                 matchQueryPayloadNode,
                                                 matchSpecAppend)
import           LinearTrace.Core               (LBool, LDouble, LInt, LString,
                                                 LUnit, MatchBinding (..),
                                                 MatchBindings, Payload,
                                                 PayloadPattern, Query,
                                                 QueryInt (..),
                                                 anyPayloadPattern, emptyQuery,
                                                 labelName, matchBindingValue,
                                                 payloadBindingPattern,
                                                 payloadBoolPattern,
                                                 payloadDoublePattern,
                                                 payloadIntPattern,
                                                 payloadStringPattern,
                                                 payloadUnitPattern,
                                                 queryAppend, queryAtom,
                                                 queryInt)
import qualified LinearTrace.Core               as C
import qualified LinearTrace.View               as V
import           LinearTrace.View.Access        (CategoryAccess, ValueAccess)
import qualified LinearTrace.View.Patch         as VP
import qualified LinearTrace.View.Primitives    as Primitives
import qualified LinearTrace.View.Style         as VS
import qualified Prelude                        as P
import           Prelude.Linear
import qualified Solver                         as S
import qualified Solver.Expr                    as SolverExpr
import qualified Text.Read                      as Read

data CoordRole

data SpanRole

data OffsetRole

data ScalarRole

data LayoutValue tag =
  LayoutValue LayoutExpr [S.Constraint]
  deriving (P.Eq, P.Show)

type LayoutExpr = Primitives.LayoutExpr

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

data AnyPayload

data NodeRef tag where
  TraceNodeRef :: C.Traceable tag => TraceQuery tag -> NodeRef tag
  AnyNodeRef :: Query -> NodeRef AnyPayload
  GroupNodeRef :: P.String -> Query -> NodeRef tag

data Selected tag where
  SelectedHandle :: Selection (NodeRef tag) -> Selected tag

data Variable a where
  Variable :: a %Many -> Variable a

data Bound a where
  Bound :: a %Many -> Bound a

data NodeBinding a where
  Selected :: a %Many -> NodeBinding a

data Selection a where
  Selection :: a %1 -> MatchSpec -> Selection a

data SelectionValue value tag =
  SelectionValue (Selected tag) ValueAccess

data SelectionCategory value tag =
  SelectionCategory (Selected tag) (CategoryAccess value)

data ContentValue
  = ContentLiteral P.String
  | ContentBinding Binding

text :: P.String -> ContentValue
text = ContentLiteral

instance IsString ContentValue where
  fromString = ContentLiteral

data NodeRecipe a where
  NodeRecipe :: a %1 -> (MatchBindings -> VP.NodePatch) -> NodeRecipe a

appendNodePatch ::
     (MatchBindings -> VP.NodePatch)
  -> (MatchBindings -> VP.NodePatch)
  -> (MatchBindings -> VP.NodePatch)
appendNodePatch first second bindings =
  VP.appendNodePatch (first bindings) (second bindings)

bindNodeRecipe :: NodeRecipe a %1 -> (a %1 -> NodeRecipe b) %1 -> NodeRecipe b
bindNodeRecipe recipe next =
  case recipe of
    NodeRecipe value first ->
      case next value of
        NodeRecipe output second ->
          NodeRecipe output (appendNodePatch first second)

instance DFL.Functor NodeRecipe where
  fmap f recipe =
    case recipe of
      NodeRecipe value patch -> NodeRecipe (f value) patch

instance Functor NodeRecipe where
  fmap f recipe =
    case recipe of
      NodeRecipe value patch -> NodeRecipe (f value) patch

instance DFL.Applicative NodeRecipe where
  pure value = NodeRecipe value (P.const VP.emptyNodePatch)
  liftA2 f lhs rhs =
    case lhs of
      NodeRecipe leftValue first ->
        case rhs of
          NodeRecipe rightValue second ->
            NodeRecipe (f leftValue rightValue) (appendNodePatch first second)

instance Applicative NodeRecipe where
  pure value = NodeRecipe value (P.const VP.emptyNodePatch)
  liftA2 f lhs rhs =
    case lhs of
      NodeRecipe leftValue first ->
        case rhs of
          NodeRecipe rightValue second ->
            NodeRecipe (f leftValue rightValue) (appendNodePatch first second)

instance Monad NodeRecipe where
  (>>=) = bindNodeRecipe

data VisualizationResult a where
  VisualizationResult :: a %1 -> P.Int -> MatchSpec -> VisualizationResult a

data VisualizationBuilder a where
  VisualizationBuilder
    :: (P.Int -> VisualizationResult a) %1 -> VisualizationBuilder a

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

preferLater :: Maybe a -> Maybe a -> Maybe a
preferLater earlier later =
  case later of
    Nothing -> earlier
    Just _  -> later

infixr 6 <&>
content :: ContentValue -> NodeRecipe ()
content value =
  setNodePatch
    (\bindings ->
       VP.emptyNodePatch
         {VP.nodePatchContent = P.pure (contentMode bindings value)})

payload ::
     forall tag selector. PayloadSelector tag selector
  => selector
  -> TraceQuery tag
payload selector = TraceQuery emptyQuery (Just (payloadSelector @tag selector))

setNodePatch :: (MatchBindings -> VP.NodePatch) -> NodeRecipe ()
setNodePatch = NodeRecipe ()

data GroupNode

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
      (Selected (SelectedHandle (Selection (AnyNodeRef query) emptyMatchSpec)))
      emptyMatchSpec

instance C.Traceable tag => Select tag (TraceQuery tag) where
  selectWithPayload query =
    emitVisualizationBuilder
      (Selected (SelectedHandle (Selection (TraceNodeRef query) emptyMatchSpec)))
      emptyMatchSpec

select ::
     forall payload. Select payload (SelectQuery payload)
  => SelectQuery payload
  -> VisualizationBuilder (NodeBinding (Selected payload))
select = selectWithPayload @payload @(SelectQuery payload)

nodePatch :: MatchBindings -> NodeRecipe () -> VP.NodePatch
nodePatch bindings recipe =
  case recipe of
    NodeRecipe () spec ->
      let patch = spec bindings
       in patch
            { VP.nodePatchStyleUpdate =
                \style ->
                  substituteStyleBindings
                    bindings
                    (VP.nodePatchStyleUpdate patch style)
            }

substituteStyleBindings :: MatchBindings -> VS.NodeStyle -> VS.NodeStyle
substituteStyleBindings bindings =
  VS.mapNodeStyleExprs
    (SolverExpr.substituteExprVars (bindingExprSubstitutions bindings))

substituteCoordBindings :: MatchBindings -> Coord -> Coord
substituteCoordBindings = substituteLayoutBindings

substituteSpanBindings :: MatchBindings -> Span -> Span
substituteSpanBindings = substituteLayoutBindings

substituteLayoutBindings :: MatchBindings -> LayoutValue tag -> LayoutValue tag
substituteLayoutBindings bindings value =
  LayoutValue
    (SolverExpr.substituteExprVars
       (bindingExprSubstitutions bindings)
       (layoutValueExpr value))
    (layoutValueConstraints value)

bindingExprSubstitutions :: MatchBindings -> [(P.String, P.Double)]
bindingExprSubstitutions bindings =
  case bindings of
    [] -> []
    MatchBinding name value:rest ->
      case Read.readMaybe value of
        Nothing -> bindingExprSubstitutions rest
        Just numericValue ->
          ("global." P.++ name, numericValue) : bindingExprSubstitutions rest

contentMode :: MatchBindings -> ContentValue -> V.ContentMode
contentMode bindings spec =
  case spec of
    ContentLiteral value   -> V.ContentText value
    ContentBinding binding -> V.ContentText (bindingContent bindings binding)

bindingContent :: MatchBindings -> Binding -> P.String
bindingContent bindings binding =
  case binding of
    Binding name ->
      case matchBindingValue name bindings of
        Nothing ->
          P.error ("Unbound view binding #" P.++ name P.++ " in content")
        Just value -> value

coordPin :: Coord -> VP.LayoutPin
coordPin value = VP.LayoutPin (coordExpr value) (coordConstraints value)

spanPin :: Span -> VP.LayoutPin
spanPin value = VP.LayoutPin (spanExpr value) (spanConstraints value)

instance Node
           (Selected child)
           (VisualizationBuilder (NodeBinding (Selected GroupNode))) where
  node children =
    case children of
      SelectedHandle selection ->
        case selection of
          Selection child childSpec ->
            let query = nodeRefQuery child
             in VisualizationBuilder
                  (\counter ->
                     let key = groupNodeKey counter
                         groupSpec = matchGroupNode key query VP.emptyNodePatch
                      in VisualizationResult
                           (Selected
                              (SelectedHandle
                                 (Selection
                                    (GroupNodeRef key query)
                                    emptyMatchSpec)))
                           (counter P.+ 1)
                           (matchSpecAppend childSpec groupSpec))

instance Node
           (NodeBinding (Selected child))
           (VisualizationBuilder (NodeBinding (Selected GroupNode))) where
  node binding =
    case binding of
      Selected children -> node children

instance Node
           (VisualizationBuilder (NodeBinding (Selected child)))
           (VisualizationBuilder (NodeBinding (Selected GroupNode))) where
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

render :: Selected tag -> NodeRecipe () -> VisualizationBuilder ()
render selection recipe =
  case selection of
    SelectedHandle selected ->
      case selected of
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
    GroupNodeRef key query -> matchGroupNode key query (nodePatch [] recipe)

nodeRefQuery :: NodeRef tag -> Query
nodeRefQuery handle =
  case handle of
    AnyNodeRef query      -> query
    TraceNodeRef selector -> traceQueryQuery selector
    GroupNodeRef _ query  -> query

nodeSelection :: NodeRef tag -> NodeSelection
nodeSelection handle =
  case handle of
    AnyNodeRef query       -> TraceSelection query
    TraceNodeRef selector  -> TraceSelection (traceQueryQuery selector)
    GroupNodeRef key query -> GroupSelection key query

groupNodeKey :: P.Int -> P.String
groupNodeKey counter = "group-node-" P.++ P.show counter

visualize :: VisualizationBuilder () -> MatchSpec
visualize builder =
  case builder of
    VisualizationBuilder run ->
      case run 0 of
        VisualizationResult () _ spec -> spec

class PayloadSelector tag selector where
  payloadSelector :: selector -> PayloadPattern tag

instance C.Traceable tag => PayloadSelector tag ContentValue where
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

class QueryAppend query where
  appendQuery :: query -> query -> query

instance QueryAppend Query where
  appendQuery = queryAppend

instance QueryAppend (TraceQuery tag) where
  appendQuery = traceQueryAppend

(<&>) :: QueryAppend query => query -> query -> query
(<&>) = appendQuery
