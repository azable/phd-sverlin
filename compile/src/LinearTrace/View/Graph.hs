{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs             #-}
{-# LANGUAGE RankNTypes        #-}

-- | Symbolic view graph representation. Choreography and build code construct
-- these nodes; solving consumes their constraints; materialization converts
-- them to concrete render data after solving.
module LinearTrace.View.Graph
  ( -- * Graph data
    -- | Symbolic graph, node, step, and render-intent records shared by the
    -- view builder, solver, materializer, and diagnostics.
    ViewGraph(..)
  , ViewNode(..)
  , Node(..)
  , NodeOrigin(..)
  , SyntheticMeta(..)
  , NodeStructure(..)
  , CompoundFit(..)
  , NodeChild(..)
  , ViewStep(..)
  , RenderIntent(..)
  , LayoutAttr(..)
  , AnyTraceNode(..)
  , AnyLayoutView(..)
  , -- * Lookups and helpers
    -- | Accessors and stable key helpers used by choreography matching,
    -- printing, and compile identity tracking.
    traceNodeTags
  , syntheticNodeMeta
  , defaultNodeKey
  , styleForRef
  , styleForSyntheticKey
  , syntheticNodeId
  , blockVarName
  , blockVarPath
  , syntheticVarName
  , syntheticVar
  , nodeChildFromTraceNode
  , -- * Solver diagnostics
    -- | Style expression traversal helpers used by printing to show solved
    -- view values by step.
    mapNodeStyleExprLeaves
  , solvedNodeExprs
  , viewTraceNodes
  ) where

import           Data.Kind                   (Type)
import           LinearTrace.View.Primitives (Bounds (..), BoundsExpr,
                                              HasBounds (..))
import           LinearTrace.View.Style      (HasStyle (..), Style,
                                              mapStyleExprLeaves,
                                              solvedStyleExprs, styleBounds,
                                              styleWithBounds)
import           LinearTrace.View.Types      (ContentMode, ViewId, ViewLabel,
                                              ViewRef, ViewTags, viewRefId,
                                              viewRefInt)
import qualified Prelude                     as P
import qualified Solver                      as S
import           Solver                      (ChoiceConstraint, Constraint,
                                              Expr, Solution, SymbolicType)

data Node tag = Node
  { nodeRef         :: ViewRef tag
  , nodeLabel       :: ViewLabel
  , nodeContent     :: ContentMode
  , nodeKey         :: P.String
  , nodeStyle       :: Style
  , nodeOrigin      :: NodeOrigin
  , nodeStructure   :: NodeStructure
  , nodeConstraints :: [Constraint]
  }

data NodeOrigin
  = TraceOrigin ViewTags
  | SyntheticOrigin SyntheticMeta

data SyntheticMeta = SyntheticMeta
  { syntheticKey      :: P.String
  , syntheticQueryKey :: P.String
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

instance HasBounds (Node tag) where
  top node = top (nodeStyle node)
  left node = left (nodeStyle node)
  width node = width (nodeStyle node)
  height node = height (nodeStyle node)

instance HasStyle (Node tag) where
  style = nodeStyle

data ViewNode where
  ViewNode :: Node tag -> ViewNode

data ViewStep where
  ViewStep
    :: P.String -> [ViewNode] -> [Constraint] -> [[RenderIntent]] -> ViewStep

data ViewGraph = ViewGraph
  { viewNodes             :: [ViewNode]
  , viewSteps             :: [ViewStep]
  , viewConstraints       :: [Constraint]
  , viewChoiceConstraints :: [ChoiceConstraint]
  , viewRenderFrames      :: [[RenderIntent]]
  }

data RenderIntent where
  RenderFresh :: ViewRef tag -> RenderIntent
  RenderContinue :: ViewRef old -> ViewRef tag -> RenderIntent
  RenderFork :: ViewRef old -> ViewRef tag -> RenderIntent
  RenderRemove :: ViewRef tag -> RenderIntent

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
    SyntheticOrigin _ -> P.Nothing

syntheticNodeMeta :: Node tag -> P.Maybe SyntheticMeta
syntheticNodeMeta node =
  case nodeOrigin node of
    TraceOrigin _        -> P.Nothing
    SyntheticOrigin meta -> P.Just meta

nodeChildFromTraceNode :: AnyTraceNode -> NodeChild
nodeChildFromTraceNode anyNode =
  case anyNode of
    AnyTraceNode node ->
      NodeChild
        { nodeChildId = viewRefId (nodeRef node)
        , nodeChildBounds = styleBounds (nodeStyle node)
        }

mapNodeStyleExprLeaves ::
     (forall (ty :: Type). P.String -> Expr ty -> a) -> Node tag -> [a]
mapNodeStyleExprLeaves f node = mapStyleExprLeaves f (nodeStyle node)

solvedNodeExprs :: Solution -> Node tag -> [(P.String, P.Double)]
solvedNodeExprs solution node = solvedStyleExprs solution (nodeStyle node)

viewTraceNodes :: [ViewNode] -> [AnyTraceNode]
viewTraceNodes nodes =
  case nodes of
    [] -> []
    node:rest ->
      case node of
        ViewNode viewNode ->
          case nodeOrigin viewNode of
            TraceOrigin _     -> AnyTraceNode viewNode : viewTraceNodes rest
            SyntheticOrigin _ -> viewTraceNodes rest

defaultNodeKey :: P.String
defaultNodeKey = "block"

styleForRef :: ViewRef tag -> Style
styleForRef ref = styleForBlockPath ref []

styleForBlockPath :: ViewRef tag -> [P.String] -> Style
styleForBlockPath ref path =
  styleWithBounds
    (Bounds
       (blockVarPath ref path "top")
       (blockVarPath ref path "left")
       (blockVarPath ref path "width")
       (blockVarPath ref path "height"))

blockVarName :: ViewRef tag -> [P.String] -> P.String -> P.String
blockVarName ref path field =
  joinPath (("B" P.++ P.show (viewRefInt ref)) : (path P.++ [field]))

blockVarPath ::
     SymbolicType ty => ViewRef tag -> [P.String] -> P.String -> Expr ty
blockVarPath ref path field = S.var (blockVarName ref path field)

syntheticNodeId :: P.String -> P.String -> P.Int
syntheticNodeId key queryKey' =
  P.negate (1 P.+ positiveHash (key P.++ ":" P.++ queryKey'))

styleForSyntheticKey :: P.String -> P.String -> Style
styleForSyntheticKey key queryKey' =
  styleWithBounds
    (Bounds
       (syntheticVar key queryKey' "top")
       (syntheticVar key queryKey' "left")
       (syntheticVar key queryKey' "width")
       (syntheticVar key queryKey' "height"))

syntheticVarName :: P.String -> P.String -> P.String -> P.String
syntheticVarName key queryKey' field =
  joinPath ["V", key, safeKey queryKey', field]

syntheticVar :: SymbolicType ty => P.String -> P.String -> P.String -> Expr ty
syntheticVar key queryKey' field = S.var (syntheticVarName key queryKey' field)

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
