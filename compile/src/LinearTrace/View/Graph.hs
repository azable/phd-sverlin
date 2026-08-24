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
  , CodeWrapMode(..)
  , CodeRange(..)
  , CodeContentSpec(..)
  , -- * Graph data
    -- | Symbolic graph, node, and render-intent records shared by the view
    -- builder, solver, and materializer.
    ViewGraph(..)
  , ViewNode(..)
  , Node(..)
  , NodeOrigin(..)
  , CanvasMeta(..)
  , GeneratedMeta(..)
  , ContentFit(..)
  , Axis(..)
  , RelativeLayoutAttr(..)
  , RelativeLayoutPin(..)
  , ViewDiagnostic(..)
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
  , boxForRef
  , styleForRef
  , traceNodeRoot
  , generatedNodeRoot
  , canvasNodeRoot
  , canvasViewId
  , generatedNodeId
  , boxForNodeRoot
  , styleForNodeRoot
  , nodeVarName
  , nodeVar
  , stableKey
  , viewTraceNodes
  ) where

import           Data.List                   (stripPrefix)
import           LinearTrace.View.Box        (NodeBox, nodeBoxWithBounds)
import           LinearTrace.View.Primitives (Bounds (..), HasBounds (..))
import           LinearTrace.View.Style      (NodeStyle, emptyNodeStyle)
import qualified Prelude                     as P
import qualified Solver                      as S
import           Solver                      (ChoiceConstraint, Constraint,
                                              Expr, SymbolicType)
import           Text.Read                   (readMaybe)

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
  | ContentFitText P.String
  | ContentCode CodeContentSpec
  deriving (P.Eq, P.Show)

data CodeWrapMode
  = CodeNoWrap
  | CodeSoftWrap
  deriving (P.Eq, P.Show)

-- | Half-open Unicode character offsets in authored code. Visualization
-- compilation converts these into canonical UTF-8 byte ranges.
data CodeRange = CodeRange
  { codeRangeStart :: P.Int
  , codeRangeEnd   :: P.Int
  } deriving (P.Eq, P.Show)

data CodeContentSpec = CodeContentSpec
  { codeContentSource   :: P.String
  , codeContentWrapMode :: CodeWrapMode
  , codeContentLanguage :: P.Maybe P.String
  , codeContentEmphasis :: [(P.String, [CodeRange])]
  } deriving (P.Eq, P.Show)

data Node tag = Node
  { nodeRef               :: ViewRef tag
  , nodeLabel             :: ViewLabel
  , nodeContent           :: ContentMode
  , nodeBox               :: NodeBox
  , nodeStyle             :: NodeStyle
  , nodeOrigin            :: NodeOrigin
  , nodeDeclaration       :: P.String
  , nodeSelectionBindings :: [(P.String, [(P.String, P.Int)])]
  , nodeParent            :: P.Maybe ViewId
  , nodeHorizontalFit     :: ContentFit
  , nodeVerticalFit       :: ContentFit
  , nodeRelativePins      :: [RelativeLayoutPin]
  , nodeConstraints       :: [Constraint]
  }

data NodeOrigin
  = CanvasOrigin CanvasMeta
  | TraceOrigin ViewTags
  | GeneratedOrigin GeneratedMeta

data CanvasMeta = CanvasMeta
  { canvasWidthExplicit  :: P.Bool
  , canvasHeightExplicit :: P.Bool
  }

newtype GeneratedMeta = GeneratedMeta
  { generatedKey :: P.String
  }

data ContentFit
  = Hug
  | Contain
  deriving (P.Eq, P.Show)

data Axis
  = Horizontal
  | Vertical
  | Both
  deriving (P.Eq, P.Show)

data RelativeLayoutAttr
  = RelativeCenterX
  | RelativeCenterY
  | RelativeWidth
  | RelativeHeight
  deriving (P.Eq, P.Show)

data RelativeLayoutPin = RelativeLayoutPin
  { relativeLayoutAttr  :: RelativeLayoutAttr
  , relativeLayoutRatio :: P.Double
  } deriving (P.Eq, P.Show)

data ViewDiagnostic = ViewDiagnostic
  { viewDiagnosticCode        :: P.String
  , viewDiagnosticMessage     :: P.String
  , viewDiagnosticDeclaration :: P.String
  , viewDiagnosticReason      :: P.String
  , viewDiagnosticMatched     :: P.Int
  , viewDiagnosticVisible     :: P.Int
  } deriving (P.Eq, P.Show)

newtype NodeVarRoot =
  NodeVarRoot [P.String]

instance HasBounds (Node tag) where
  top node = top (nodeBox node)
  left node = left (nodeBox node)
  width node = width (nodeBox node)
  height node = height (nodeBox node)

data ViewNode where
  ViewNode :: Node tag -> ViewNode

data ViewGraph = ViewGraph
  { viewNodes             :: [ViewNode]
  , viewConstraints       :: [Constraint]
  , viewChoiceConstraints :: [ChoiceConstraint]
  , viewSteps             :: [ViewStep]
  , viewDiagnostics       :: [ViewDiagnostic]
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
    CanvasOrigin _    -> P.Nothing
    TraceOrigin tags  -> P.Just tags
    GeneratedOrigin _ -> P.Nothing

generatedNodeMeta :: Node tag -> P.Maybe GeneratedMeta
generatedNodeMeta node =
  case nodeOrigin node of
    CanvasOrigin _       -> P.Nothing
    TraceOrigin _        -> P.Nothing
    GeneratedOrigin meta -> P.Just meta

viewTraceNodes :: [ViewNode] -> [AnyTraceNode]
viewTraceNodes nodes =
  case nodes of
    [] -> []
    node:rest ->
      case node of
        ViewNode viewNode ->
          case nodeOrigin viewNode of
            CanvasOrigin _    -> viewTraceNodes rest
            TraceOrigin _     -> AnyTraceNode viewNode : viewTraceNodes rest
            GeneratedOrigin _ -> viewTraceNodes rest

styleForRef :: ViewRef tag -> NodeStyle
styleForRef _ = emptyNodeStyle

styleForNodeRoot :: NodeVarRoot -> NodeStyle
styleForNodeRoot _ = emptyNodeStyle

boxForRef :: ViewRef tag -> NodeBox
boxForRef ref = boxForNodeRoot (traceNodeRoot ref)

boxForNodeRoot :: NodeVarRoot -> NodeBox
boxForNodeRoot root =
  nodeBoxWithBounds
    (Bounds
       (nodeVar root [] "top")
       (nodeVar root [] "left")
       (nodeVar root [] "width")
       (nodeVar root [] "height"))

traceNodeRoot :: ViewRef tag -> NodeVarRoot
traceNodeRoot ref = NodeVarRoot ["B" P.++ P.show (viewRefInt ref)]

generatedNodeRoot :: P.String -> NodeVarRoot
generatedNodeRoot key = NodeVarRoot ["V", safeKey key]

canvasNodeRoot :: NodeVarRoot
canvasNodeRoot = NodeVarRoot ["C"]

canvasViewId :: ViewId
canvasViewId = ViewId (-1)

generatedNodeId :: P.String -> P.Int
generatedNodeId key =
  case stripPrefix "generated-node-" key P.>>= readMaybe of
    P.Just counter -> P.negate (2 P.+ counter)
    P.Nothing      -> P.error ("Invalid internal generated-node key: " P.++ key)

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

stableKey :: P.String -> P.String
stableKey value = safeKey value P.++ "-" P.++ P.show (positiveHash value)

isSafeKeyChar :: P.Char -> P.Bool
isSafeKeyChar ch = ch `P.elem` safeKeyChars

safeKeyChars :: [P.Char]
safeKeyChars = ['a' .. 'z'] P.++ ['A' .. 'Z'] P.++ ['0' .. '9'] P.++ "_-"
