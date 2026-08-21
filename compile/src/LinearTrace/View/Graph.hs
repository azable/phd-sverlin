{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs             #-}

-- | Symbolic view graph representation. Choreography and build code construct
-- these nodes; solving consumes their constraints; visualization compilation
-- converts them directly to concrete IR data after solving.
module LinearTrace.View.Graph
  ( -- * Identity and content
    ViewId(..)
  , viewIdInt
  , ViewRef(..)
  , viewRefId
  , viewRefInt
  , viewRefFromId
  , ViewLabel(..)
  , ViewTagValue(..)
  , ViewTags(..)
  , viewTagsToList
  , ContentMode(..)
  , -- * Graph data
    -- | Symbolic graph, node, and render-intent records shared by the view
    -- builder, solver, and materializer.
    ViewGraph(..)
  , ViewNode(..)
  , Node(..)
  , NodeOrigin(..)
  , GeneratedMeta(..)
  , NodeStructure(..)
  , CompoundFit(..)
  , NodeChild(..)
  , NodeVarRoot(..)
  , ViewStep(..)
  , RenderIntent(..)
  , splitRenderIntents
  , LayoutAttr(..)
  , AnyTraceNode(..)
  , AnyLayoutView(..)
  , -- * Lookups and helpers
    -- | Accessors and stable key helpers used by choreography matching and
    -- compile identity tracking.
    traceNodeTags
  , generatedNodeMeta
  , styleForRef
  , traceNodeRoot
  , generatedNodeRoot
  , generatedNodeId
  , styleForNodeRoot
  , nodeVarName
  , nodeVar
  , nodeChildFromTraceNode
  , viewTraceNodes
  ) where

import           LinearTrace.View.Primitives (Bounds (..), BoundsExpr,
                                              HasBounds (..))
import           LinearTrace.View.Style      (NodeStyle, nodeStyleBounds,
                                              nodeStyleWithBounds)
import qualified Prelude                     as P
import qualified Solver                      as S
import           Solver                      (ChoiceConstraint, Constraint,
                                              Expr, SymbolicType)

newtype ViewId =
  ViewId P.Int
  deriving (P.Eq, P.Ord, P.Show)

viewIdInt :: ViewId -> P.Int
viewIdInt viewId =
  case viewId of
    ViewId value -> value

newtype ViewRef tag =
  ViewRef ViewId
  deriving (P.Eq, P.Ord, P.Show)

viewRefId :: ViewRef tag -> ViewId
viewRefId viewRef =
  case viewRef of
    ViewRef viewId -> viewId

viewRefInt :: ViewRef tag -> P.Int
viewRefInt = viewIdInt P.. viewRefId

viewRefFromId :: P.Int -> ViewRef tag
viewRefFromId = ViewRef P.. ViewId

newtype ViewLabel = ViewLabel
  { viewLabelKind :: P.String
  } deriving (P.Eq, P.Show)

data ViewTagValue
  = ViewTagAtom
  | ViewTagInt P.Int
  deriving (P.Eq, P.Ord, P.Show)

newtype ViewTags =
  ViewTags [(P.String, ViewTagValue)]
  deriving (P.Eq, P.Show)

viewTagsToList :: ViewTags -> [(P.String, ViewTagValue)]
viewTagsToList tags =
  case tags of
    ViewTags values -> values

data ContentMode
  = ContentEmpty
  | ContentText P.String
  deriving (P.Eq, P.Show)

data Node tag = Node
  { nodeRef         :: ViewRef tag
  , nodeLabel       :: ViewLabel
  , nodeContent     :: ContentMode
  , nodeStyle       :: NodeStyle
  , nodeOrigin      :: NodeOrigin
  , nodeStructure   :: NodeStructure
  , nodeConstraints :: [Constraint]
  }

data NodeOrigin
  = TraceOrigin ViewTags
  | GeneratedOrigin GeneratedMeta

data GeneratedMeta = GeneratedMeta
  { generatedKey      :: P.String
  , generatedQueryKey :: P.String
  }

data NodeStructure
  = LeafNode
  | CompoundNode CompoundFit [NodeChild]

data CompoundFit =
  ShrinkWrapChildren

data NodeChild = NodeChild
  { nodeChildId     :: ViewId
  , nodeChildBounds :: BoundsExpr
  }

newtype NodeVarRoot =
  NodeVarRoot [P.String]

instance HasBounds (Node tag) where
  top node = top (nodeStyle node)
  left node = left (nodeStyle node)
  width node = width (nodeStyle node)
  height node = height (nodeStyle node)

data ViewNode where
  ViewNode :: Node tag -> ViewNode

data ViewGraph = ViewGraph
  { viewCanvasWidth       :: P.Double
  , viewCanvasHeight      :: P.Double
  , viewNodes             :: [ViewNode]
  , viewConstraints       :: [Constraint]
  , viewChoiceConstraints :: [ChoiceConstraint]
  , viewSteps             :: [ViewStep]
  }

data ViewStep = ViewStep
  { viewStepLabel   :: P.String
  , viewStepIntents :: [RenderIntent]
  }

data RenderIntent where
  RenderFresh :: ViewRef tag -> RenderIntent
  RenderContinue :: ViewRef old -> ViewRef tag -> RenderIntent
  RenderFork :: ViewRef old -> ViewRef tag -> RenderIntent
  RenderRemove :: ViewRef tag -> RenderIntent

splitRenderIntents :: [RenderIntent] -> ([RenderIntent], [RenderIntent])
splitRenderIntents intents =
  case intents of
    [] -> ([], [])
    intent:rest ->
      case splitRenderIntents rest of
        (introductions, removals) ->
          case intent of
            RenderRemove _ -> (introductions, intent : removals)
            _              -> (intent : introductions, removals)

data LayoutAttr
  = AttrLeft
  | AttrRight
  | AttrWidth
  | AttrCenterX
  | AttrTop
  | AttrBottom
  | AttrHeight
  | AttrCenterY

data AnyTraceNode where
  AnyTraceNode :: Node tag -> AnyTraceNode

data AnyLayoutView where
  AnyLayoutView :: Node tag -> AnyLayoutView

traceNodeTags :: Node tag -> P.Maybe ViewTags
traceNodeTags node =
  case nodeOrigin node of
    TraceOrigin tags  -> P.Just tags
    GeneratedOrigin _ -> P.Nothing

generatedNodeMeta :: Node tag -> P.Maybe GeneratedMeta
generatedNodeMeta node =
  case nodeOrigin node of
    TraceOrigin _        -> P.Nothing
    GeneratedOrigin meta -> P.Just meta

nodeChildFromTraceNode :: AnyTraceNode -> NodeChild
nodeChildFromTraceNode anyNode =
  case anyNode of
    AnyTraceNode node ->
      NodeChild
        { nodeChildId = viewRefId (nodeRef node)
        , nodeChildBounds = nodeStyleBounds (nodeStyle node)
        }

viewTraceNodes :: [ViewNode] -> [AnyTraceNode]
viewTraceNodes nodes =
  case nodes of
    [] -> []
    node:rest ->
      case node of
        ViewNode viewNode ->
          case nodeOrigin viewNode of
            TraceOrigin _     -> AnyTraceNode viewNode : viewTraceNodes rest
            GeneratedOrigin _ -> viewTraceNodes rest

styleForRef :: ViewRef tag -> NodeStyle
styleForRef ref = styleForNodeRoot (traceNodeRoot ref)

styleForNodeRoot :: NodeVarRoot -> NodeStyle
styleForNodeRoot root =
  nodeStyleWithBounds
    (Bounds
       (nodeVar root [] "top")
       (nodeVar root [] "left")
       (nodeVar root [] "width")
       (nodeVar root [] "height"))

traceNodeRoot :: ViewRef tag -> NodeVarRoot
traceNodeRoot ref = NodeVarRoot ["B" P.++ P.show (viewRefInt ref)]

generatedNodeRoot :: P.String -> P.String -> NodeVarRoot
generatedNodeRoot key queryKey' = NodeVarRoot ["V", key, safeKey queryKey']

generatedNodeId :: P.String -> P.String -> P.Int
generatedNodeId key queryKey' =
  P.negate (1 P.+ positiveHash (key P.++ ":" P.++ queryKey'))

nodeVarName :: NodeVarRoot -> [P.String] -> P.String -> P.String
nodeVarName root path field =
  case root of
    NodeVarRoot rootPath -> joinPath (rootPath P.++ path P.++ [field])

nodeVar :: SymbolicType ty => NodeVarRoot -> [P.String] -> P.String -> Expr ty
nodeVar root path field = S.var (nodeVarName root path field)

positiveHash :: P.String -> P.Int
positiveHash = positiveHashFrom 5381

positiveHashFrom :: P.Int -> P.String -> P.Int
positiveHashFrom current text =
  case text of
    [] -> P.abs current
    char:rest ->
      positiveHashFrom
        ((current P.* 33 P.+ P.fromEnum char) `P.mod` 1000000000)
        rest

joinPath :: [P.String] -> P.String
joinPath parts =
  case parts of
    []        -> ""
    [part]    -> part
    part:rest -> part P.++ "." P.++ joinPath rest

safeKey :: P.String -> P.String
safeKey value =
  case value of
    [] -> []
    ch:rest ->
      let safeChar
            {- HLINT ignore "Use if" -}
           =
            case isSafeKeyChar ch of
              P.True  -> ch
              P.False -> '_'
       in safeChar : safeKey rest

isSafeKeyChar :: P.Char -> P.Bool
isSafeKeyChar ch = ch `P.elem` safeKeyChars

safeKeyChars :: [P.Char]
safeKeyChars = ['a' .. 'z'] P.++ ['A' .. 'Z'] P.++ ['0' .. '9'] P.++ "_-"
