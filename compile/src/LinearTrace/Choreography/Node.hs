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
  ( ContentValue
  , content
  , coordPin
  , spanPin
  , payload
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
  , traceQueryQuery
  , traceQueryPayloadPattern
  ) where

import           LinearTrace.Choreography.Match (MatchSpec, NodeSelection (..),
                                                 emptyMatchSpec,
                                                 matchAnyQueryNode,
                                                 matchContextBindings,
                                                 matchGroupNode,
                                                 matchQueryPayloadNode,
                                                 matchSpecAppend)
import           LinearTrace.Choreography.Types
import           LinearTrace.Core               (LBool, LDouble, LInt, LString,
                                                 LUnit, MatchBinding (..),
                                                 MatchBindings, Payload,
                                                 PayloadPattern, Query,
                                                 anyPayloadPattern, emptyQuery,
                                                 matchBindingValue,
                                                 payloadBindingPattern,
                                                 payloadBoolPattern,
                                                 payloadDoublePattern,
                                                 payloadIntPattern,
                                                 payloadStringPattern,
                                                 payloadUnitPattern,
                                                 queryAppend)
import qualified LinearTrace.Core               as C
import qualified LinearTrace.View               as V
import qualified LinearTrace.View.Patch         as VP
import qualified LinearTrace.View.Style         as VS
import qualified Prelude                        as P
import           Prelude.Linear
import qualified Solver.Expr                    as SolverExpr
import qualified Text.Read                      as Read

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
