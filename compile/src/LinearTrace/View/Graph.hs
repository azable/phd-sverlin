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
  , ViewStep(..)
  , BlockView(..)
  , VirtualView(..)
  , RenderIntent(..)
  , LayoutAttr(..)
  , AnyBlockView(..)
  , AnyVirtualView(..)
  , AnyLayoutView(..)
  , -- * Lookups and helpers
    -- | Accessors and stable key helpers used by choreography matching,
    -- printing, and compile identity tracking.
    blockViewRef
  , blockViewLabel
  , blockViewTags
  , blockViewNodeKey
  , blockViewPieceKey
  , defaultNodeKey
  , defaultPieceKey
  , styleForRef
  , styleForVirtualKey
  , virtualBlockId
  , blockVarName
  , blockVarPath
  , virtualVarName
  , virtualVar
  , -- * Solver diagnostics
    -- | Style expression traversal helpers used by printing to show solved
    -- view values by step.
    mapBlockViewStyleExprLeaves
  , solvedBlockViewExprs
  , viewNodeBlocks
  ) where

import           Data.Kind                   (Type)
import           LinearTrace.View.Primitives (Bounds (..), HasBounds (..))
import           LinearTrace.View.Style      (HasStyle (..), Style,
                                              mapStyleExprLeaves,
                                              solvedStyleExprs, styleWithBounds)
import           LinearTrace.View.Types      (ContentMode, ViewLabel, ViewRef,
                                              ViewTags, viewRefInt)
import qualified Prelude                     as P
import qualified Solver                      as S
import           Solver                      (ChoiceConstraint, Constraint,
                                              Expr, Solution, SymbolicType)

data BlockView tag = BlockView
  { blockRef      :: ViewRef tag
  , blockLabel    :: ViewLabel
  , blockContent  :: ContentMode
  , blockTags     :: ViewTags
  , blockNodeKey  :: P.String
  , blockPieceKey :: P.String
  , blockStyle    :: Style
  }

instance HasBounds (BlockView tag) where
  top block = top (blockStyle block)
  left block = left (blockStyle block)
  width block = width (blockStyle block)
  height block = height (blockStyle block)

instance HasStyle (BlockView tag) where
  style = blockStyle

data VirtualView tag = VirtualView
  { virtualRef         :: ViewRef tag
  , virtualLabel       :: ViewLabel
  , virtualContent     :: ContentMode
  , virtualQueryKey    :: P.String
  , virtualNodeKey     :: P.String
  , virtualPieceKey    :: P.String
  , virtualStyle       :: Style
  , virtualConstraints :: [Constraint]
  , virtualChildren    :: [AnyBlockView]
  }

instance HasBounds (VirtualView tag) where
  top virtual = top (virtualStyle virtual)
  left virtual = left (virtualStyle virtual)
  width virtual = width (virtualStyle virtual)
  height virtual = height (virtualStyle virtual)

instance HasStyle (VirtualView tag) where
  style = virtualStyle

data ViewNode where
  BlockViewNode :: BlockView tag -> ViewNode
  VirtualViewNode :: VirtualView tag -> ViewNode

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

data AnyBlockView where
  AnyBlockView :: BlockView tag -> AnyBlockView

data AnyVirtualView where
  AnyVirtualView :: VirtualView tag -> AnyVirtualView

data AnyLayoutView where
  AnyLayoutBlock :: BlockView tag -> AnyLayoutView
  AnyLayoutVirtual :: VirtualView tag -> AnyLayoutView

blockViewRef :: BlockView tag -> ViewRef tag
blockViewRef = blockRef

blockViewLabel :: BlockView tag -> ViewLabel
blockViewLabel = blockLabel

blockViewTags :: BlockView tag -> ViewTags
blockViewTags = blockTags

blockViewNodeKey :: BlockView tag -> P.String
blockViewNodeKey = blockNodeKey

blockViewPieceKey :: BlockView tag -> P.String
blockViewPieceKey = blockPieceKey

mapBlockViewStyleExprLeaves ::
     (forall (ty :: Type). P.String -> Expr ty -> a) -> BlockView tag -> [a]
mapBlockViewStyleExprLeaves f block = mapStyleExprLeaves f (blockStyle block)

solvedBlockViewExprs :: Solution -> BlockView tag -> [(P.String, P.Double)]
solvedBlockViewExprs solution block =
  solvedStyleExprs solution (blockStyle block)

viewNodeBlocks :: [ViewNode] -> [AnyBlockView]
viewNodeBlocks nodes =
  case nodes of
    [] -> []
    node:rest ->
      case node of
        BlockViewNode block -> AnyBlockView block : viewNodeBlocks rest
        VirtualViewNode _   -> viewNodeBlocks rest

defaultNodeKey :: P.String
defaultNodeKey = "block"

defaultPieceKey :: P.String
defaultPieceKey = "body"

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

virtualBlockId :: P.String -> P.String -> P.Int
virtualBlockId key queryKey' =
  P.negate (1 P.+ positiveHash (key P.++ ":" P.++ queryKey'))

styleForVirtualKey :: P.String -> P.String -> Style
styleForVirtualKey key queryKey' =
  styleWithBounds
    (Bounds
       (virtualVar key queryKey' "top")
       (virtualVar key queryKey' "left")
       (virtualVar key queryKey' "width")
       (virtualVar key queryKey' "height"))

virtualVarName :: P.String -> P.String -> P.String -> P.String
virtualVarName key queryKey' field =
  joinPath ["V", key, safeKey queryKey', field]

virtualVar :: SymbolicType ty => P.String -> P.String -> P.String -> Expr ty
virtualVar key queryKey' field = S.var (virtualVarName key queryKey' field)

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
