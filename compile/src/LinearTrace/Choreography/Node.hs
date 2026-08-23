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

-- | Hierarchical node declarations, selections, and shared builder values.
module LinearTrace.Choreography.Node
  ( ContentValue(..)
  , content
  , fitText
  , codeContent
  , codeWrap
  , highlightCode
  , CodeRange
  , codeRange
  , emphasizeCode
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
  , GeneratedNode
  , CanvasNode
  , NodeRef(..)
  , VisualizationResult(..)
  , VisualizationBuilder(..)
  , preferLater
  , text
  , emptyVisualizationBuilder
  , emitVisualizationBuilder
  , freshVisualizationValue
  , editCurrentNode
  , Node
  , node
  , self
  , canvas
  , Select
  , SelectQuery
  , select
  , visualize
  , QueryAppend
  , (<&>)
  , nodeSelection
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
                                                 ParentRef (..),
                                                 declareGeneratedNode,
                                                 declareTraceNode,
                                                 editNodeDeclaration,
                                                 emptyMatchSpec,
                                                 matchSpecAppend,
                                                 registerAnyQuerySelection,
                                                 registerQuerySelection,
                                                 validateMatchSpec)
import           LinearTrace.Core               (LBool, LDouble, LInt, LString,
                                                 LUnit, MatchBindings, Payload,
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
import qualified LinearTrace.View.Primitives    as Primitives
import qualified LinearTrace.View.Style         as VS
import qualified LinearTrace.View.Template      as VT
import qualified Prelude                        as P
import           Prelude.Linear
import qualified Solver                         as S

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
layoutValueExpr (LayoutValue expression _) = expression

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

data GeneratedNode

data CanvasNode

data NodeRef tag where
  TraceNodeRef :: P.String -> NodeRef tag
  GeneratedNodeRef :: P.String -> NodeRef GeneratedNode
  CanvasNodeRef :: NodeRef CanvasNode

data Selected tag where
  SelectedHandle :: Selection (NodeRef tag) -> Selected tag

data Variable a where
  Variable :: a %Many -> Variable a

data Bound a where
  Bound :: a %Many -> Bound a

data NodeBinding a where
  Selected :: a %Many -> NodeBinding a

selectedNodeBinding :: NodeRef tag -> NodeBinding (Selected tag)
selectedNodeBinding nodeRef = Selected (SelectedHandle (Selection nodeRef))

data Selection a where
  Selection :: a %1 -> Selection a

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

data BuilderContext
  = RootContext
  | TraceNodeContext P.String ParentRef
  | GeneratedNodeContext P.String ParentRef

data VisualizationResult a where
  VisualizationResult :: a %1 -> P.Int -> MatchSpec -> VisualizationResult a

data VisualizationBuilder a where
  VisualizationBuilder
    :: (BuilderContext -> P.Int -> VisualizationResult a)
       %1 -> VisualizationBuilder a

emptyVisualizationBuilder :: a %1 -> VisualizationBuilder a
emptyVisualizationBuilder value =
  VisualizationBuilder
    (\_context counter -> VisualizationResult value counter emptyMatchSpec)

emitVisualizationBuilder :: a -> MatchSpec -> VisualizationBuilder a
emitVisualizationBuilder value spec =
  VisualizationBuilder
    (\_context counter -> VisualizationResult value counter spec)

freshVisualizationValue :: P.String -> (P.String -> a) -> VisualizationBuilder a
freshVisualizationValue prefix build =
  VisualizationBuilder
    (\_context counter ->
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
    (\context counter0 ->
       case run context counter0 of
         VisualizationResult value counter1 spec ->
           VisualizationResult (f value) counter1 spec)

visualizationBuilderMapControl ::
     (a %1 -> b) %1 -> VisualizationBuilder a %1 -> VisualizationBuilder b
visualizationBuilderMapControl f (VisualizationBuilder run) =
  VisualizationBuilder
    (\context counter0 ->
       case run context counter0 of
         VisualizationResult value counter1 spec ->
           VisualizationResult (f value) counter1 spec)

visualizationBuilderAp ::
     (a %1 -> b %1 -> c)
     %1 -> VisualizationBuilder a
     %1 -> VisualizationBuilder b
     %1 -> VisualizationBuilder c
visualizationBuilderAp f (VisualizationBuilder runLeft) (VisualizationBuilder runRight) =
  VisualizationBuilder
    (\context counter0 ->
       case runLeft context counter0 of
         VisualizationResult leftValue counter1 first ->
           case runRight context counter1 of
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
    (\context counter0 ->
       case runFirst context counter0 of
         VisualizationResult value counter1 first ->
           case next value of
             VisualizationBuilder runSecond ->
               case runSecond context counter1 of
                 VisualizationResult output counter2 second ->
                   VisualizationResult
                     output
                     counter2
                     (matchSpecAppend first second))

preferLater :: Maybe a -> Maybe a -> Maybe a
preferLater earlier Nothing = earlier
preferLater _ later         = later

editCurrentNode ::
     P.String
  -> (MatchBindings -> VT.NodeTemplate -> VT.NodeTemplate)
  -> VisualizationBuilder ()
editCurrentNode property update =
  VisualizationBuilder
    (\context counter ->
       case context of
         RootContext ->
           P.error (property P.++ " must be declared inside a node body")
         TraceNodeContext declaration _ ->
           VisualizationResult
             ()
             counter
             (editNodeDeclaration declaration property update)
         GeneratedNodeContext declaration _ ->
           VisualizationResult
             ()
             counter
             (editNodeDeclaration declaration property update))

infixr 6 <&>
content :: ContentValue -> VisualizationBuilder ()
content value =
  editCurrentNode
    "content"
    (\bindings template ->
       template {VT.templateContent = Just (contentMode bindings value)})

fitText :: ContentValue -> VisualizationBuilder ()
fitText value =
  editCurrentNode
    "content"
    (\bindings template ->
       template {VT.templateContent = Just (fitContentMode bindings value)})

codeContent :: ContentValue -> VisualizationBuilder ()
codeContent value =
  editCurrentNode
    "content"
    (\bindings template ->
       template
         { VT.templateStyle =
             VS.setStyleField @VS.FontFamily
               (S.Fixed VS.FontJetBrainsMonoNL)
               (VT.templateStyle template)
         , VT.templateContent =
             Just
               (V.ContentCode
                  V.CodeContentSpec
                    { V.codeContentSource = contentSource bindings value
                    , V.codeContentWrapMode = V.CodeNoWrap
                    , V.codeContentLanguage = Nothing
                    , V.codeContentEmphasis = []
                    })
         })

codeWrap :: VisualizationBuilder () %1 -> VisualizationBuilder ()
codeWrap inner =
  inner CF.>>= \() ->
    editCurrentNode
      "content.wrap"
      (P.const
         (updateCodeTemplate
            "codeWrap"
            (\code -> code {V.codeContentWrapMode = V.CodeSoftWrap})))

highlightCode ::
     P.String -> VisualizationBuilder () %1 -> VisualizationBuilder ()
highlightCode language inner =
  inner CF.>>= \() ->
    editCurrentNode
      "content.language"
      (P.const
         (updateCodeTemplate
            "highlightCode"
            (\code -> code {V.codeContentLanguage = Just language})))

type CodeRange = V.CodeRange

codeRange :: P.Int -> P.Int -> CodeRange
codeRange = V.CodeRange

emphasizeCode ::
     P.String
  -> [CodeRange]
  -> VisualizationBuilder ()
     %1 -> VisualizationBuilder ()
emphasizeCode stepLabel ranges inner =
  inner CF.>>= \() ->
    editCurrentNode
      ("content.emphasis." P.++ stepLabel)
      (P.const
         (updateCodeTemplate
            "emphasizeCode"
            (\code ->
               code
                 { V.codeContentEmphasis =
                     V.codeContentEmphasis code P.++ [(stepLabel, ranges)]
                 })))

updateCodeTemplate ::
     P.String
  -> (V.CodeContentSpec -> V.CodeContentSpec)
  -> VT.NodeTemplate
  -> VT.NodeTemplate
updateCodeTemplate helper transform = VT.updateTemplateContent helper update
  where
    update mode =
      case mode of
        V.ContentCode code -> V.ContentCode (transform code)
        _                  -> P.error (helper P.++ " must wrap codeContent")

payload ::
     forall tag selector. PayloadSelector tag selector
  => selector
  -> TraceQuery tag
payload selector = TraceQuery emptyQuery (Just (payloadSelector @tag selector))

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
    VisualizationBuilder
      (\_context counter ->
         let key = selectionKey counter
          in VisualizationResult
               (selectedNodeBinding (TraceNodeRef key))
               (counter P.+ 1)
               (registerAnyQuerySelection key query))

instance C.Traceable tag => Select tag (TraceQuery tag) where
  selectWithPayload selector =
    VisualizationBuilder
      (\_context counter ->
         let key = selectionKey counter
          in VisualizationResult
               (selectedNodeBinding (TraceNodeRef key))
               (counter P.+ 1)
               (registerQuerySelection @tag
                  key
                  (traceQueryQuery selector)
                  (traceQueryPayloadPattern selector)))

select ::
     forall payload. Select payload (SelectQuery payload)
  => SelectQuery payload
  -> VisualizationBuilder (NodeBinding (Selected payload))
select = selectWithPayload @payload @(SelectQuery payload)

instance Node
           (Selected child)
           (VisualizationBuilder () -> VisualizationBuilder ()) where
  node = declareSelectedNode

instance Node
           (NodeBinding (Selected child))
           (VisualizationBuilder () -> VisualizationBuilder ()) where
  node (Selected selected) = declareSelectedNode selected

instance Node
           (VisualizationBuilder ())
           (VisualizationBuilder (NodeBinding (Selected GeneratedNode))) where
  node = declareGeneratedParent

declareSelectedNode ::
     Selected tag -> VisualizationBuilder () -> VisualizationBuilder ()
declareSelectedNode selected (VisualizationBuilder runBody) =
  VisualizationBuilder
    (\outerContext counter0 ->
       let declaration = traceDeclarationKey counter0
           parent = childParent outerContext
        in case runBody (TraceNodeContext declaration parent) (counter0 P.+ 1) of
             VisualizationResult () counter1 bodySpec ->
               VisualizationResult
                 ()
                 counter1
                 (declareTraceNode declaration (selectedKey selected) parent
                    `matchSpecAppend` bodySpec))

declareGeneratedParent ::
     VisualizationBuilder ()
  -> VisualizationBuilder (NodeBinding (Selected GeneratedNode))
declareGeneratedParent (VisualizationBuilder runBody) =
  VisualizationBuilder
    (\outerContext counter0 ->
       let key = generatedDeclarationKey counter0
           parent = childParent outerContext
        in case runBody (GeneratedNodeContext key parent) (counter0 P.+ 1) of
             VisualizationResult () counter1 bodySpec ->
               VisualizationResult
                 (selectedNodeBinding (GeneratedNodeRef key))
                 counter1
                 (declareGeneratedNode key parent `matchSpecAppend` bodySpec))

childParent :: BuilderContext -> ParentRef
childParent context =
  case context of
    RootContext -> CanvasParent
    GeneratedNodeContext key _ -> GeneratedParent key
    TraceNodeContext declaration _ ->
      P.error
        ("Trace-selected node "
           P.++ declaration
           P.++ " is terminal and cannot contain child nodes")

self :: VisualizationBuilder (NodeBinding (Selected GeneratedNode))
self =
  VisualizationBuilder
    (\context counter ->
       case context of
         GeneratedNodeContext key _ ->
           VisualizationResult
             (selectedNodeBinding (GeneratedNodeRef key))
             counter
             emptyMatchSpec
         RootContext ->
           P.error "self is only available inside an anonymous node body"
         TraceNodeContext _ _ ->
           P.error "self is only available inside an anonymous node body")

canvas :: Selected CanvasNode
canvas = SelectedHandle (Selection CanvasNodeRef)

selectedKey :: Selected tag -> P.String
selectedKey selected =
  case selected of
    SelectedHandle (Selection ref) ->
      case ref of
        TraceNodeRef key -> key
        GeneratedNodeRef key -> key
        CanvasNodeRef -> P.error "The canvas cannot be emitted as a child node"

nodeSelection :: NodeRef tag -> NodeSelection
nodeSelection handle =
  case handle of
    TraceNodeRef key     -> NodeSelection key
    GeneratedNodeRef key -> NodeSelection key
    CanvasNodeRef        -> CanvasSelection

selectionKey :: P.Int -> P.String
selectionKey counter = "selection-" P.++ P.show counter

traceDeclarationKey :: P.Int -> P.String
traceDeclarationKey counter = "trace-node-" P.++ P.show counter

generatedDeclarationKey :: P.Int -> P.String
generatedDeclarationKey counter = "generated-node-" P.++ P.show counter

visualize :: VisualizationBuilder () -> MatchSpec
visualize (VisualizationBuilder run) =
  case run RootContext 0 of
    VisualizationResult () _ spec -> validateMatchSpec spec

contentMode :: MatchBindings -> ContentValue -> V.ContentMode
contentMode _ (ContentLiteral value) = V.ContentText value
contentMode bindings (ContentBinding binding) =
  V.ContentText (bindingContent bindings binding)

fitContentMode :: MatchBindings -> ContentValue -> V.ContentMode
fitContentMode _ (ContentLiteral value) = V.ContentFitText value
fitContentMode bindings (ContentBinding binding) =
  V.ContentFitText (bindingContent bindings binding)

contentSource :: MatchBindings -> ContentValue -> P.String
contentSource _ (ContentLiteral value) = value
contentSource bindings (ContentBinding binding) =
  bindingContent bindings binding

bindingContent :: MatchBindings -> Binding -> P.String
bindingContent bindings (Binding name) =
  case matchBindingValue name bindings of
    Nothing -> P.error ("Unbound view binding #" P.++ name P.++ " in content")
    Just value -> value

coordPin :: Coord -> VT.LayoutPin
coordPin value = VT.LayoutPin (coordExpr value) (coordConstraints value)

spanPin :: Span -> VT.LayoutPin
spanPin value = VT.LayoutPin (spanExpr value) (spanConstraints value)

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
