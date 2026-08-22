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

import qualified Control.Functor.Linear         as CF
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
import           LinearTrace.View.Access        (CategoryAccess, ValueAccess)
import qualified LinearTrace.View.Graph         as V
import qualified LinearTrace.View.Patch         as VP
import qualified LinearTrace.View.Primitives    as Primitives
import qualified LinearTrace.View.Style         as VS
import qualified Prelude                        as P
import           Prelude.Linear
import qualified Solver                         as S
import qualified Solver.Expr                    as SolverExpr
import qualified Text.Read                      as Read

{-# ANN module "HLint: ignore Eta reduce" #-}

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
layoutValueExpr (LayoutValue expr _) = expr

layoutValueConstraints :: LayoutValue tag -> [S.Constraint]
layoutValueConstraints (LayoutValue _ constraints) = constraints

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

selectedNodeBinding :: NodeRef tag -> NodeBinding (Selected tag)
selectedNodeBinding nodeRef =
  Selected (SelectedHandle (Selection nodeRef emptyMatchSpec))

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

nodeRecipePure :: a %1 -> NodeRecipe a
nodeRecipePure value = NodeRecipe value (P.const VP.emptyNodePatch)

nodeRecipeMapData :: (a %1 -> b) -> NodeRecipe a %1 -> NodeRecipe b
nodeRecipeMapData f (NodeRecipe value patch) = NodeRecipe (f value) patch

nodeRecipeMapControl :: (a %1 -> b) %1 -> NodeRecipe a %1 -> NodeRecipe b
nodeRecipeMapControl f (NodeRecipe value patch) = NodeRecipe (f value) patch

nodeRecipeAp ::
     (a %1 -> c %1 -> b)
     %1 -> NodeRecipe a
     %1 -> NodeRecipe c
     %1 -> NodeRecipe b
nodeRecipeAp f (NodeRecipe leftValue first) (NodeRecipe rightValue second) =
  NodeRecipe (f leftValue rightValue) (appendNodePatch first second)

nodeRecipeBind :: NodeRecipe a %1 -> (a %1 -> NodeRecipe b) %1 -> NodeRecipe b
nodeRecipeBind (NodeRecipe value patch) next =
  case next value of
    NodeRecipe output second -> NodeRecipe output (appendNodePatch patch second)

instance DFL.Functor NodeRecipe where
  fmap = nodeRecipeMapData

instance CF.Functor NodeRecipe where
  fmap = nodeRecipeMapControl

instance DFL.Applicative NodeRecipe where
  pure value = nodeRecipePure value
  liftA2 f lhs rhs = nodeRecipeAp f lhs rhs

instance CF.Applicative NodeRecipe where
  pure = nodeRecipePure
  liftA2 = nodeRecipeAp

instance CF.Monad NodeRecipe where
  (>>=) = nodeRecipeBind

data VisualizationResult a where
  VisualizationResult :: a %1 -> P.Int -> MatchSpec -> VisualizationResult a

data VisualizationBuilder a where
  VisualizationBuilder
    :: (P.Int -> VisualizationResult a) %1 -> VisualizationBuilder a

emptyVisualizationBuilder :: a %1 -> VisualizationBuilder a
emptyVisualizationBuilder value =
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
  fmap = visualizationBuilderMapData

instance CF.Functor VisualizationBuilder where
  fmap = visualizationBuilderMapControl

instance DFL.Applicative VisualizationBuilder where
  pure value = emptyVisualizationBuilder value
  liftA2 f lhs rhs = visualizationBuilderAp f lhs rhs

instance CF.Applicative VisualizationBuilder where
  pure = emptyVisualizationBuilder
  liftA2 = visualizationBuilderAp

instance CF.Monad VisualizationBuilder where
  (>>=) = visualizationBuilderBind

visualizationBuilderMapData ::
     (a %1 -> b) -> VisualizationBuilder a %1 -> VisualizationBuilder b
visualizationBuilderMapData f (VisualizationBuilder run) =
  VisualizationBuilder
    (\counter0 ->
       case run counter0 of
         VisualizationResult value counter1 spec ->
           VisualizationResult (f value) counter1 spec)

visualizationBuilderMapControl ::
     (a %1 -> b) %1 -> VisualizationBuilder a %1 -> VisualizationBuilder b
visualizationBuilderMapControl f (VisualizationBuilder run) =
  VisualizationBuilder
    (\counter0 ->
       case run counter0 of
         VisualizationResult value counter1 spec ->
           VisualizationResult (f value) counter1 spec)

visualizationBuilderAp ::
     (a %1 -> b %1 -> c)
     %1 -> VisualizationBuilder a
     %1 -> VisualizationBuilder b
     %1 -> VisualizationBuilder c
visualizationBuilderAp f (VisualizationBuilder runLeft) (VisualizationBuilder runRight) =
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

visualizationBuilderBind ::
     VisualizationBuilder a
     %1 -> (a %1 -> VisualizationBuilder b)
     %1 -> VisualizationBuilder b
visualizationBuilderBind (VisualizationBuilder runFirst) next =
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

preferLater :: Maybe a -> Maybe a -> Maybe a
preferLater earlier Nothing = earlier
preferLater _ later         = later

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
      (selectedNodeBinding (AnyNodeRef query))
      emptyMatchSpec

instance C.Traceable tag => Select tag (TraceQuery tag) where
  selectWithPayload query =
    emitVisualizationBuilder
      (selectedNodeBinding (TraceNodeRef query))
      emptyMatchSpec

select ::
     forall payload. Select payload (SelectQuery payload)
  => SelectQuery payload
  -> VisualizationBuilder (NodeBinding (Selected payload))
select = selectWithPayload @payload @(SelectQuery payload)

nodePatch :: MatchBindings -> NodeRecipe () -> VP.NodePatch
nodePatch bindings (NodeRecipe () spec) =
  let patch = spec bindings
   in patch
        { VP.nodePatchStyleUpdate =
            substituteStyleBindings bindings P.. VP.nodePatchStyleUpdate patch
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
substituteLayoutBindings bindings (LayoutValue expr constraints) =
  LayoutValue
    (SolverExpr.substituteExprVars (bindingExprSubstitutions bindings) expr)
    constraints

bindingExprSubstitutions :: MatchBindings -> [(P.String, P.Double)]
bindingExprSubstitutions [] = []
bindingExprSubstitutions (MatchBinding name value:rest) =
  case Read.readMaybe value of
    Nothing -> bindingExprSubstitutions rest
    Just numericValue ->
      ("global." P.++ name, numericValue) : bindingExprSubstitutions rest

contentMode :: MatchBindings -> ContentValue -> V.ContentMode
contentMode _bindings (ContentLiteral value) = V.ContentText value
contentMode bindings (ContentBinding binding) =
  V.ContentText (bindingContent bindings binding)

bindingContent :: MatchBindings -> Binding -> P.String
bindingContent bindings (Binding name) =
  case matchBindingValue name bindings of
    Nothing -> P.error ("Unbound view binding #" P.++ name P.++ " in content")
    Just value -> value

coordPin :: Coord -> VP.LayoutPin
coordPin value = VP.LayoutPin (coordExpr value) (coordConstraints value)

spanPin :: Span -> VP.LayoutPin
spanPin value = VP.LayoutPin (spanExpr value) (spanConstraints value)

instance Node
           (Selected child)
           (VisualizationBuilder (NodeBinding (Selected GroupNode))) where
  node (SelectedHandle (Selection child childSpec)) =
    let query = nodeRefQuery child
     in VisualizationBuilder
          (\counter ->
             let key = groupNodeKey counter
                 groupSpec = matchGroupNode key query VP.emptyNodePatch
              in VisualizationResult
                   (Selected
                      (SelectedHandle
                         (Selection (GroupNodeRef key query) emptyMatchSpec)))
                   (counter P.+ 1)
                   (matchSpecAppend childSpec groupSpec))

instance Node
           (NodeBinding (Selected child))
           (VisualizationBuilder (NodeBinding (Selected GroupNode))) where
  node (Selected children) = node children

instance Node
           (VisualizationBuilder (NodeBinding (Selected child)))
           (VisualizationBuilder (NodeBinding (Selected GroupNode))) where
  node (VisualizationBuilder runFirst) =
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
render (SelectedHandle (Selection handle spec)) recipe =
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
visualize (VisualizationBuilder run) =
  case run 0 of
    VisualizationResult () _ spec -> spec

class PayloadSelector tag selector where
  payloadSelector :: selector -> PayloadPattern tag

instance C.Traceable tag => PayloadSelector tag ContentValue where
  payloadSelector (ContentBinding (Binding name)) = payloadBindingPattern name
  payloadSelector (ContentLiteral _) =
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
traceQueryQuery (TraceQuery query _) = query

traceQueryPayloadPattern :: TraceQuery tag -> PayloadPattern tag
traceQueryPayloadPattern (TraceQuery _ Nothing) = anyPayloadPattern
traceQueryPayloadPattern (TraceQuery _ (Just payloadPattern)) = payloadPattern

traceQueryAppend :: TraceQuery tag -> TraceQuery tag -> TraceQuery tag
traceQueryAppend (TraceQuery leftQuery leftPayload) (TraceQuery rightQuery rightPayload) =
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
