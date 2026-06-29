{-# LANGUAGE AllowAmbiguousTypes  #-}
{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE GADTs                #-}
{-# LANGUAGE LinearTypes          #-}
{-# LANGUAGE RankNTypes           #-}
{-# LANGUAGE RebindableSyntax     #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE UndecidableInstances #-}

module LinearTrace.View
  ( -- * View graph
    ViewId(..)
  , viewIdInt
  , ViewRef(..)
  , viewRefId
  , viewRefInt
  , syntheticViewRef
  , ViewLabel(..)
  , ViewTagValue(..)
  , ViewTags(..)
  , emptyViewTags
  , viewTagsToList
  , ViewGraph
  , ViewNode(..)
  , ViewStep(..)
  , BlockView(..)
  , VirtualView(..)
  , blockViewRef
  , blockViewLabel
  , blockViewTags
  , blockViewNodeKey
  , blockViewPieceKey
  , defaultNodeKey
  , defaultPieceKey
  , styleForRef
  , mapBlockViewStyleExprLeaves
  , solvedBlockViewExprs
  , RenderIntent(..)
  , ContentMode(..)
  , LayoutPin(..)
  , NodePatch(..)
  , emptyNodePatch
  , appendNodePatch
  , ValueComponent
  , ValueAccess
  , StyleLayoutAttr(..)
  , StyleUnitAttr(..)
  , StyleFreeAttr(..)
  , StyleColorAttr(..)
  , HslPart(..)
  , StyleMaterialization
  , layoutValueAccess
  , styleLayoutValueAccess
  , styleUnitValueAccess
  , styleFreeValueAccess
  , styleColorPartValueAccess
  , valueAccessComponent
  , valueAccessMaterializations
  , applyStyleMaterializations
  , LayoutAttr(..)
  , AnyBlockView(..)
  , AnyLayoutView(..)
  , viewNodeBlocks
  , patchedBlockOutput
  , finalizeViewGraph
  , styleForVirtualKey
  , virtualBlockId
  , viewNodes
  , viewSteps
  , viewConstraints
  , viewRenderFrames
  , -- * Styles
    Style
  , Bounds(..)
  , BoundsExpr
  , MaterializedBounds
  , Hsl(..)
  , CssText(..)
  , cssTextString
  , FontWeight(..)
  , FontStyle(..)
  , TextAlign(..)
  , BorderStyle(..)
  , WhiteSpace(..)
  , styleBounds
  , mapStyleExprLeaves
  , solvedStyleExprs
  , -- * Expressions
    Free
  , Layout
  , Unit
  , Angle
  , Expr
  , Constraint
  , FreeExpr
  , LayoutExpr
  , UnitExpr
  , AngleExpr
  , ColorExpr
  , MaterializedHsl
  , global
  , num
  , absExpr
  , -- * Builder
    ViewOutput(..)
  , emptyViewOutput
  , appendViewOutput
  , flushViewOutput
  , renderIntentOutput
  , mergeInitialRenderIntents
  , withImplicitInitialFrame
  , solveCSP
  , solveCSPWithSeed
  , RandomSeed(..)
  , -- * Style accessors
    opacity
  , zIndex
  , fontSize
  , radius
  , strokeWidth
  , alpha
  , fill
  , stroke
  , -- * Materialization
    MaterializedStyle
  , MaterializedBlockView(..)
  , MaterializedVirtualView(..)
  , MaterializedViewNode(..)
  , materializedTop
  , materializedLeft
  , materializedWidth
  , materializedHeight
  , materializedCssAttrsWith
  , materializeViewNode
  ) where

import           Data.Kind              (Type)
import qualified Data.Maybe             as Maybe
import           LinearTrace.View.Style
import           LinearTrace.View.Types
import qualified Prelude                as P
import           Prelude.Linear
import qualified Solver                 as S
import           Solver                 hiding (absExpr, component, num)

--------------------------------------------------------------------------------
-- View patches
--------------------------------------------------------------------------------
data LayoutPin =
  LayoutPin LayoutExpr [Constraint]

data NodePatch = NodePatch
  { nodePatchStyleUpdate :: Style -> Style
  , nodePatchContent     :: Maybe ContentMode
  , nodePatchLeft        :: Maybe LayoutPin
  , nodePatchTop         :: Maybe LayoutPin
  , nodePatchWidth       :: Maybe LayoutPin
  , nodePatchHeight      :: Maybe LayoutPin
  , nodePatchRight       :: Maybe LayoutPin
  , nodePatchBottom      :: Maybe LayoutPin
  , nodePatchX           :: Maybe LayoutPin
  , nodePatchY           :: Maybe LayoutPin
  }

emptyNodePatch :: NodePatch
emptyNodePatch =
  NodePatch
    { nodePatchStyleUpdate = P.id
    , nodePatchContent = Nothing
    , nodePatchLeft = Nothing
    , nodePatchTop = Nothing
    , nodePatchWidth = Nothing
    , nodePatchHeight = Nothing
    , nodePatchRight = Nothing
    , nodePatchBottom = Nothing
    , nodePatchX = Nothing
    , nodePatchY = Nothing
    }

appendNodePatch :: NodePatch -> NodePatch -> NodePatch
appendNodePatch first second =
  NodePatch
    { nodePatchStyleUpdate =
        composeStyleUpdates
          (nodePatchStyleUpdate first)
          (nodePatchStyleUpdate second)
    , nodePatchContent =
        preferLater (nodePatchContent first) (nodePatchContent second)
    , nodePatchLeft = preferLater (nodePatchLeft first) (nodePatchLeft second)
    , nodePatchTop = preferLater (nodePatchTop first) (nodePatchTop second)
    , nodePatchWidth =
        preferLater (nodePatchWidth first) (nodePatchWidth second)
    , nodePatchHeight =
        preferLater (nodePatchHeight first) (nodePatchHeight second)
    , nodePatchRight =
        preferLater (nodePatchRight first) (nodePatchRight second)
    , nodePatchBottom =
        preferLater (nodePatchBottom first) (nodePatchBottom second)
    , nodePatchX = preferLater (nodePatchX first) (nodePatchX second)
    , nodePatchY = preferLater (nodePatchY first) (nodePatchY second)
    }

composeStyleUpdates :: (Style -> Style) -> (Style -> Style) -> Style -> Style
composeStyleUpdates first second style0 = second (first style0)

preferLater :: Maybe a -> Maybe a -> Maybe a
preferLater earlier later =
  case later of
    Nothing -> earlier
    Just _  -> later

type ValueComponent = Component

data StyleLayoutAttr
  = StyleFontSize
  | StyleRadius
  | StylePadding
  | StyleStrokeWidth
  deriving (P.Eq, P.Show)

data StyleUnitAttr
  = StyleOpacity
  | StyleAlpha
  deriving (P.Eq, P.Show)

data StyleFreeAttr =
  StyleZIndex
  deriving (P.Eq, P.Show)

data StyleColorAttr
  = StyleFill
  | StyleStroke
  deriving (P.Eq, P.Show)

data HslPart
  = HslHue
  | HslSaturation
  | HslLightness
  deriving (P.Eq, P.Show)

newtype StyleMaterialization =
  MaterializeColor StyleColorAttr
  deriving (P.Eq, P.Show)

data ValueAccess =
  ValueAccess [StyleMaterialization] (AnyLayoutView -> ValueComponent)

layoutValueAccess :: LayoutAttr -> ValueAccess
layoutValueAccess attr =
  ValueAccess [] (\view -> S.component (layoutViewAttr attr view) [])

styleLayoutValueAccess :: StyleLayoutAttr -> ValueAccess
styleLayoutValueAccess attr =
  ValueAccess [] (\view -> S.component (styleLayoutAttr attr view) [])

styleUnitValueAccess :: StyleUnitAttr -> ValueAccess
styleUnitValueAccess attr =
  ValueAccess [] (\view -> S.component (styleUnitAttr attr view) [])

styleFreeValueAccess :: StyleFreeAttr -> ValueAccess
styleFreeValueAccess attr =
  ValueAccess [] (\view -> S.component (styleFreeAttr attr view) [])

styleColorPartValueAccess :: StyleColorAttr -> HslPart -> ValueAccess
styleColorPartValueAccess color part =
  ValueAccess [MaterializeColor color] (styleColorPartComponent color part)

--------------------------------------------------------------------------------
-- Block views
--------------------------------------------------------------------------------
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
  { virtualRef      :: ViewRef tag
  , virtualLabel    :: ViewLabel
  , virtualContent  :: ContentMode
  , virtualQueryKey :: P.String
  , virtualNodeKey  :: P.String
  , virtualPieceKey :: P.String
  , virtualStyle    :: Style
  , virtualPatch    :: NodePatch
  , virtualChildren :: [AnyBlockView]
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
  { viewNodes        :: [ViewNode]
  , viewSteps        :: [ViewStep]
  , viewConstraints  :: [Constraint]
  , viewRenderFrames :: [[RenderIntent]]
  }

--------------------------------------------------------------------------------
-- Materialized views
--------------------------------------------------------------------------------
data MaterializedBlockView tag = MaterializedBlockView
  { materializedBlockRef      :: ViewRef tag
  , materializedBlockLabel    :: ViewLabel
  , materializedBlockContent  :: P.String
  , materializedBlockNodeKey  :: P.String
  , materializedBlockPieceKey :: P.String
  , materializedBlockStyle    :: MaterializedStyle
  }

data MaterializedVirtualView tag = MaterializedVirtualView
  { materializedVirtualRef      :: ViewRef tag
  , materializedVirtualLabel    :: ViewLabel
  , materializedVirtualContent  :: P.String
  , materializedVirtualNodeKey  :: P.String
  , materializedVirtualPieceKey :: P.String
  , materializedVirtualStyle    :: MaterializedStyle
  }

data MaterializedViewNode where
  MaterializedBlockViewNode :: MaterializedBlockView tag -> MaterializedViewNode
  MaterializedVirtualViewNode
    :: MaterializedVirtualView tag -> MaterializedViewNode

materializeBlockView ::
     Solution -> BlockView tag -> Maybe (MaterializedBlockView tag)
materializeBlockView solution block =
  P.fmap
    (MaterializedBlockView
       (blockRef block)
       (blockLabel block)
       (materializeContent (blockContent block))
       (blockNodeKey block)
       (blockPieceKey block))
    (materializeStyle solution (blockStyle block))

materializeVirtualView ::
     Solution -> VirtualView tag -> Maybe (MaterializedVirtualView tag)
materializeVirtualView solution virtual =
  P.fmap
    (MaterializedVirtualView
       (virtualRef virtual)
       (virtualLabel virtual)
       (materializeContent (virtualContent virtual))
       (virtualNodeKey virtual)
       (virtualPieceKey virtual))
    (materializeStyle solution (virtualStyle virtual))

materializeContent :: ContentMode -> P.String
materializeContent contentMode =
  case contentMode of
    ContentEmpty      -> ""
    ContentText value -> value

materializeViewNode :: Solution -> ViewNode -> Maybe MaterializedViewNode
materializeViewNode solution node =
  case node of
    BlockViewNode block ->
      P.fmap MaterializedBlockViewNode (materializeBlockView solution block)
    VirtualViewNode virtual ->
      P.fmap
        MaterializedVirtualViewNode
        (materializeVirtualView solution virtual)

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
     (forall (ty :: Type). String -> Expr ty -> a) -> BlockView tag -> [a]
mapBlockViewStyleExprLeaves f block = mapStyleExprLeaves f (blockStyle block)

solvedBlockViewExprs :: Solution -> BlockView tag -> [(String, Double)]
solvedBlockViewExprs solution block =
  solvedStyleExprs solution (blockStyle block)

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

num :: SymbolicType ty => Double -> Expr ty
num = S.num

global :: SymbolicType ty => String -> Expr ty
global name = S.var ("global." ++ name)

absExpr :: Expr ty -> Expr ty
absExpr = S.absExpr

--------------------------------------------------------------------------------
-- Reader + writer builder
--------------------------------------------------------------------------------
data ViewEnv = ViewEnv
  { canvasWidthValue  :: Double
  , canvasHeightValue :: Double
  , canvasWidth       :: LayoutExpr
  , canvasHeight      :: LayoutExpr
  }

defaultViewEnv :: ViewEnv
defaultViewEnv =
  ViewEnv
    { canvasWidthValue = 800
    , canvasHeightValue = 600
    , canvasWidth = num 800
    , canvasHeight = num 600
    }

data ViewOutput = ViewOutput
  { emittedNodes         :: [ViewNode]
  , emittedConstraints   :: [Constraint]
  , emittedRenderFrames  :: [[RenderIntent]]
  , pendingRenderIntents :: [RenderIntent]
  }

instance Semigroup ViewOutput where
  ViewOutput nodesA constraintsA framesA pendingA <> ViewOutput nodesB constraintsB framesB pendingB =
    ViewOutput
      { emittedNodes = nodesA ++ nodesB
      , emittedConstraints = constraintsA ++ constraintsB
      , emittedRenderFrames = framesA ++ framesB
      , pendingRenderIntents = pendingA ++ pendingB
      }

instance Monoid ViewOutput where
  mempty =
    ViewOutput
      { emittedNodes = []
      , emittedConstraints = []
      , emittedRenderFrames = []
      , pendingRenderIntents = []
      }

emptyViewOutput :: ViewOutput
emptyViewOutput = mempty

appendViewOutput :: ViewOutput -> ViewOutput -> ViewOutput
appendViewOutput lhs rhs =
  ViewOutput
    { emittedNodes = emittedNodes lhs P.++ emittedNodes rhs
    , emittedConstraints = emittedConstraints lhs P.++ emittedConstraints rhs
    , emittedRenderFrames = emittedRenderFrames lhs P.++ emittedRenderFrames rhs
    , pendingRenderIntents =
        pendingRenderIntents lhs P.++ pendingRenderIntents rhs
    }

flushViewOutput :: ViewOutput -> ViewOutput
flushViewOutput = flushPendingOutput

renderIntentOutput :: RenderIntent -> ViewOutput
renderIntentOutput intent = mempty {pendingRenderIntents = [intent]}

flushPendingOutput :: ViewOutput -> ViewOutput
flushPendingOutput output =
  case pendingRenderIntents output of
    [] -> output
    intents ->
      output
        { emittedRenderFrames =
            emittedRenderFrames output ++ renderIntentFrames intents
        , pendingRenderIntents = []
        }

renderIntentFrames :: [RenderIntent] -> [[RenderIntent]]
renderIntentFrames intents =
  case splitRenderIntents intents of
    ([], [])                  -> []
    (introductions, [])       -> [introductions]
    ([], removals)            -> [removals]
    (introductions, removals) -> [introductions, removals]

splitRenderIntents :: [RenderIntent] -> ([RenderIntent], [RenderIntent])
splitRenderIntents intents =
  case intents of
    [] -> ([], [])
    intent:rest ->
      case splitRenderIntents rest of
        (introductions, removals) ->
          case isRemovalIntent intent of
            True  -> (introductions, intent : removals)
            False -> (intent : introductions, removals)

isRemovalIntent :: RenderIntent -> P.Bool
isRemovalIntent intent =
  case intent of
    RenderRemove _ -> True
    _              -> False

--------------------------------------------------------------------------------
-- Per-block visualisation
--------------------------------------------------------------------------------
patchedBlockOutput :: NodePatch -> BlockView tag -> ViewOutput
patchedBlockOutput patch block0 =
  let block =
        block0
          { blockStyle = nodePatchStyleUpdate patch (blockStyle block0)
          , blockContent =
              case nodePatchContent patch of
                Nothing      -> blockContent block0
                Just content -> content
          }
      constraints =
        styleConstraints (blockStyle block)
          P.++ [ right block S.@<=@ canvasWidth defaultViewEnv
               , bottom block S.@<=@ canvasHeight defaultViewEnv
               ]
          P.++ patchGeometryConstraints patch block
   in mempty
        {emittedNodes = [BlockViewNode block], emittedConstraints = constraints}

patchGeometryConstraints :: NodePatch -> BlockView tag -> [Constraint]
patchGeometryConstraints patch block =
  pinConstraints (left block) (nodePatchLeft patch)
    P.++ pinConstraints (top block) (nodePatchTop patch)
    P.++ pinConstraints (width block) (nodePatchWidth patch)
    P.++ pinConstraints (height block) (nodePatchHeight patch)
    P.++ pinConstraints (right block) (nodePatchRight patch)
    P.++ pinConstraints (bottom block) (nodePatchBottom patch)
    P.++ pinConstraints (centerX block) (nodePatchX patch)
    P.++ pinConstraints (centerY block) (nodePatchY patch)

--------------------------------------------------------------------------------
-- Build a view graph
--------------------------------------------------------------------------------
finalizeViewGraph ::
     [ViewNode] -> [ViewStep] -> [Constraint] -> [[RenderIntent]] -> ViewGraph
finalizeViewGraph nodes viewSteps' baseConstraints renderFrames =
  let virtualConstraints = P.concatMap virtualNodeConstraints nodes
      -- Block styles are first registered while building trace steps. Layout
      -- rules can later materialize optional style fields, so collect style
      -- constraints again after materialization.
      nodeStyleConstraints = P.concatMap viewNodeStyleConstraints nodes
      nodeRangeConstraints =
        P.concatMap (viewNodeRangeConstraints defaultViewEnv) nodes
      constraints =
        baseConstraints
          P.++ nodeStyleConstraints
          P.++ nodeRangeConstraints
          P.++ virtualConstraints
      frames = addVirtualRenderFrames nodes renderFrames
   in ViewGraph
        { viewNodes = nodes
        , viewSteps = viewSteps'
        , viewConstraints = constraints
        , viewRenderFrames = frames
        }

solveCSP :: SolveConfig -> ViewGraph -> IO Solution
solveCSP config graph = S.solveProblem config (viewSolveProblem graph)

solveCSPWithSeed :: RandomSeed -> ViewGraph -> IO Solution
solveCSPWithSeed seed graph =
  solveCSP (viewSolveConfig seed) graph P.>>= \solution ->
    case viewSolutionAcceptable solution of
      True  -> P.pure solution
      False -> solveCSP (viewRetrySolveConfig seed) graph

viewSolveConfig :: RandomSeed -> SolveConfig
viewSolveConfig seed =
  S.withOptimizerTolerances (Just 1e-5) (Just 1e-3)
    $ S.withConstraintWeights
        (P.fromInteger (10 :: P.Integer))
        (P.fromInteger (1 :: P.Integer))
    $ S.withInitialSeed seed S.defaultSolveConfig

viewRetrySolveConfig :: RandomSeed -> SolveConfig
viewRetrySolveConfig seed =
  S.withMaxOptimizerIterations 3000
    $ S.withOptimizerTolerances (Just 1e-7) (Just 1e-5)
    $ S.withConstraintWeights
        (P.fromInteger (10 :: P.Integer))
        (P.fromInteger (1 :: P.Integer))
    $ S.withInitialSeed seed S.defaultSolveConfig

viewSolutionAcceptable :: Solution -> P.Bool
viewSolutionAcceptable solution = solutionEnergy solution P.<= 1e-4

viewSolveProblem :: ViewGraph -> SolverProblem
viewSolveProblem graph =
  S.solverProblemWithChoices
    (viewConstraints graph)
    (viewStyleChoiceConstraints graph)

viewStyleChoiceConstraints :: ViewGraph -> [ChoiceConstraint]
viewStyleChoiceConstraints graph =
  P.concatMap viewNodeStyleChoiceConstraints (viewNodes graph)

viewNodeStyleChoiceConstraints :: ViewNode -> [ChoiceConstraint]
viewNodeStyleChoiceConstraints node =
  case node of
    BlockViewNode block     -> styleChoiceConstraints (blockStyle block)
    VirtualViewNode virtual -> styleChoiceConstraints (virtualStyle virtual)

data AnyBlockView where
  AnyBlockView :: BlockView tag -> AnyBlockView

data AnyVirtualView where
  AnyVirtualView :: VirtualView tag -> AnyVirtualView

data AnyLayoutView where
  AnyLayoutBlock :: BlockView tag -> AnyLayoutView
  AnyLayoutVirtual :: VirtualView tag -> AnyLayoutView

viewNodeBlocks :: [ViewNode] -> [AnyBlockView]
viewNodeBlocks nodes =
  case nodes of
    [] -> []
    node:rest ->
      case node of
        BlockViewNode block -> AnyBlockView block : viewNodeBlocks rest
        VirtualViewNode _   -> viewNodeBlocks rest

layoutViewAttr :: LayoutAttr -> AnyLayoutView -> LayoutExpr
layoutViewAttr attr view =
  case view of
    AnyLayoutBlock block     -> boundsAttr attr block
    AnyLayoutVirtual virtual -> boundsAttr attr virtual

valueAccessComponent :: ValueAccess -> AnyLayoutView -> ValueComponent
valueAccessComponent access view =
  case access of
    ValueAccess _ project -> project view

valueAccessMaterializations :: ValueAccess -> [StyleMaterialization]
valueAccessMaterializations access =
  case access of
    ValueAccess materializations _ -> materializations

layoutViewStyle :: AnyLayoutView -> Style
layoutViewStyle view =
  case view of
    AnyLayoutBlock block     -> blockStyle block
    AnyLayoutVirtual virtual -> virtualStyle virtual

styleLayoutAttr :: StyleLayoutAttr -> AnyLayoutView -> LayoutExpr
styleLayoutAttr attr view =
  let style' = layoutViewStyle view
   in case attr of
        StyleFontSize    -> fontSize style'
        StyleRadius      -> radius style'
        StylePadding     -> padding style'
        StyleStrokeWidth -> strokeWidth style'

styleUnitAttr :: StyleUnitAttr -> AnyLayoutView -> UnitExpr
styleUnitAttr attr view =
  let style' = layoutViewStyle view
   in case attr of
        StyleOpacity -> opacity style'
        StyleAlpha   -> alpha style'

styleFreeAttr :: StyleFreeAttr -> AnyLayoutView -> FreeExpr
styleFreeAttr attr view =
  let style' = layoutViewStyle view
   in case attr of
        StyleZIndex -> zIndex style'

styleColorPartComponent ::
     StyleColorAttr -> HslPart -> AnyLayoutView -> ValueComponent
styleColorPartComponent color part view =
  case part of
    HslHue        -> S.component (styleColorHue color view) []
    HslSaturation -> S.component (styleColorSaturation color view) []
    HslLightness  -> S.component (styleColorLightness color view) []

styleColorHue :: StyleColorAttr -> AnyLayoutView -> AngleExpr
styleColorHue color view = hue (styleColorValue color view)

styleColorSaturation :: StyleColorAttr -> AnyLayoutView -> UnitExpr
styleColorSaturation color view = saturation (styleColorValue color view)

styleColorLightness :: StyleColorAttr -> AnyLayoutView -> UnitExpr
styleColorLightness color view = lightness (styleColorValue color view)

styleColorValue :: StyleColorAttr -> AnyLayoutView -> ColorExpr
styleColorValue color view =
  Maybe.fromMaybe (materializedStyleColor color view)
    $ case color of
        StyleFill   -> fill (layoutViewStyle view)
        StyleStroke -> stroke (layoutViewStyle view)

materializedStyleColor :: StyleColorAttr -> AnyLayoutView -> ColorExpr
materializedStyleColor color view =
  Hsl
    (styleColorVar color view "hue")
    (styleColorVar color view "saturation")
    (styleColorVar color view "lightness")

styleColorVar ::
     SymbolicType ty => StyleColorAttr -> AnyLayoutView -> P.String -> Expr ty
styleColorVar color view part =
  case view of
    AnyLayoutBlock block ->
      blockVarPath (blockRef block) ["style", styleColorName color] part
    AnyLayoutVirtual virtual ->
      virtualVar
        (virtualNodeKey virtual)
        (virtualQueryKey virtual)
        ("style." P.++ styleColorName color P.++ "." P.++ part)

styleColorName :: StyleColorAttr -> P.String
styleColorName color =
  case color of
    StyleFill   -> "fill"
    StyleStroke -> "stroke"

boundsAttr :: HasBounds bounds => LayoutAttr -> bounds -> LayoutExpr
boundsAttr attr bounds' =
  case attr of
    AttrLeft    -> left bounds'
    AttrRight   -> right bounds'
    AttrWidth   -> width bounds'
    AttrCenterX -> centerX bounds'
    AttrTop     -> top bounds'
    AttrBottom  -> bottom bounds'
    AttrHeight  -> height bounds'
    AttrCenterY -> centerY bounds'

applyStyleMaterializations :: [StyleMaterialization] -> ViewNode -> ViewNode
applyStyleMaterializations materializations node =
  case materializations of
    [] -> node
    materialization:rest ->
      applyStyleMaterializations
        rest
        (applyStyleMaterialization materialization node)

applyStyleMaterialization :: StyleMaterialization -> ViewNode -> ViewNode
applyStyleMaterialization materialization node =
  case node of
    BlockViewNode block ->
      BlockViewNode
        block
          { blockStyle =
              materializeStyleForView
                (AnyLayoutBlock block)
                materialization
                (blockStyle block)
          }
    VirtualViewNode virtual ->
      VirtualViewNode
        virtual
          { virtualStyle =
              materializeStyleForView
                (AnyLayoutVirtual virtual)
                materialization
                (virtualStyle virtual)
          }

materializeStyleForView ::
     AnyLayoutView -> StyleMaterialization -> Style -> Style
materializeStyleForView view materialization style' =
  case materialization of
    MaterializeColor color ->
      materializeColorField color (materializedStyleColor color view) style'

materializeColorField :: StyleColorAttr -> ColorExpr -> Style -> Style
materializeColorField color value style' =
  case color of
    StyleFill ->
      case fill style' of
        Nothing -> setFill value style'
        Just _  -> style'
    StyleStroke ->
      case stroke style' of
        Nothing -> setStroke value style'
        Just _  -> style'

virtualBlockId :: P.String -> P.String -> P.Int
virtualBlockId key queryKey' =
  negate (1 P.+ positiveHash (key P.++ ":" P.++ queryKey'))

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

styleForVirtualKey :: P.String -> P.String -> Style
styleForVirtualKey key queryKey' =
  styleWithBounds
    (Bounds
       (virtualVar key queryKey' "top")
       (virtualVar key queryKey' "left")
       (virtualVar key queryKey' "width")
       (virtualVar key queryKey' "height"))

virtualVar :: SymbolicType ty => P.String -> P.String -> P.String -> Expr ty
virtualVar key queryKey' field =
  var (joinPath ["V", key, safeKey queryKey', field])

virtualNodeConstraints :: ViewNode -> [Constraint]
virtualNodeConstraints node =
  case node of
    BlockViewNode _ -> []
    VirtualViewNode virtual ->
      styleConstraints (virtualStyle virtual)
        P.++ virtualCanvasConstraints virtual
        P.++ virtualFitConstraints virtual
        P.++ virtualPatchGeometryConstraints virtual

virtualCanvasConstraints :: VirtualView tag -> [Constraint]
virtualCanvasConstraints virtual =
  [ right virtual S.@<=@ canvasWidth defaultViewEnv
  , bottom virtual S.@<=@ canvasHeight defaultViewEnv
  ]

virtualFitConstraints :: VirtualView tag -> [Constraint]
virtualFitConstraints virtual =
  case virtualChildren virtual of
    []       -> []
    [child]  -> virtualExactFitConstraints virtual child
    children -> virtualTightFitConstraints virtual children

virtualExactFitConstraints :: VirtualView tag -> AnyBlockView -> [Constraint]
virtualExactFitConstraints virtual child =
  [ left virtual S.@==@ (anyBlockLeft child @-@ virtualPadding virtual)
  , top virtual S.@==@ (anyBlockTop child @-@ virtualPadding virtual)
  , right virtual S.@==@ (anyBlockRight child @+@ virtualPadding virtual)
  , bottom virtual S.@==@ (anyBlockBottom child @+@ virtualPadding virtual)
  ]

virtualTightFitConstraints :: VirtualView tag -> [AnyBlockView] -> [Constraint]
virtualTightFitConstraints virtual children =
  case children of
    [] -> []
    child:rest ->
      let allChildren = child : rest
       in [ left virtual
              S.@==@ (minChildEdge anyBlockLeft allChildren
                        @-@ virtualPadding virtual)
          , top virtual
              S.@==@ (minChildEdge anyBlockTop allChildren
                        @-@ virtualPadding virtual)
          , right virtual
              S.@==@ (maxChildEdge anyBlockRight allChildren
                        @+@ virtualPadding virtual)
          , bottom virtual
              S.@==@ (maxChildEdge anyBlockBottom allChildren
                        @+@ virtualPadding virtual)
          ]

virtualPadding :: VirtualView tag -> LayoutExpr
virtualPadding virtual = padding (virtualStyle virtual)

minChildEdge :: (AnyBlockView -> LayoutExpr) -> [AnyBlockView] -> LayoutExpr
minChildEdge edge children =
  case children of
    []         -> P.error "Cannot shrinkwrap an empty virtual node."
    child:rest -> foldChildEdge S.minExpr edge (edge child) rest

maxChildEdge :: (AnyBlockView -> LayoutExpr) -> [AnyBlockView] -> LayoutExpr
maxChildEdge edge children =
  case children of
    []         -> P.error "Cannot shrinkwrap an empty virtual node."
    child:rest -> foldChildEdge S.maxExpr edge (edge child) rest

foldChildEdge ::
     (LayoutExpr -> LayoutExpr -> LayoutExpr)
  -> (AnyBlockView -> LayoutExpr)
  -> LayoutExpr
  -> [AnyBlockView]
  -> LayoutExpr
foldChildEdge combine edge current children =
  case children of
    []         -> current
    child:rest -> foldChildEdge combine edge (combine current (edge child)) rest

anyBlockLeft :: AnyBlockView -> LayoutExpr
anyBlockLeft anyBlock =
  case anyBlock of
    AnyBlockView child -> left child

anyBlockTop :: AnyBlockView -> LayoutExpr
anyBlockTop anyBlock =
  case anyBlock of
    AnyBlockView child -> top child

anyBlockRight :: AnyBlockView -> LayoutExpr
anyBlockRight anyBlock =
  case anyBlock of
    AnyBlockView child -> right child

anyBlockBottom :: AnyBlockView -> LayoutExpr
anyBlockBottom anyBlock =
  case anyBlock of
    AnyBlockView child -> bottom child

virtualPatchGeometryConstraints :: VirtualView tag -> [Constraint]
virtualPatchGeometryConstraints virtual =
  pinConstraints (left virtual) (nodePatchLeft patch)
    P.++ pinConstraints (top virtual) (nodePatchTop patch)
    P.++ pinConstraints (width virtual) (nodePatchWidth patch)
    P.++ pinConstraints (height virtual) (nodePatchHeight patch)
    P.++ pinConstraints (right virtual) (nodePatchRight patch)
    P.++ pinConstraints (bottom virtual) (nodePatchBottom patch)
    P.++ pinConstraints (centerX virtual) (nodePatchX patch)
    P.++ pinConstraints (centerY virtual) (nodePatchY patch)
  where
    patch = virtualPatch virtual

pinConstraints :: LayoutExpr -> Maybe LayoutPin -> [Constraint]
pinConstraints expr maybePin =
  case maybePin of
    Nothing -> []
    Just pin ->
      case pin of
        LayoutPin target constraints -> constraints P.++ [expr S.@==@ target]

viewNodeStyleConstraints :: ViewNode -> [Constraint]
viewNodeStyleConstraints node =
  case node of
    BlockViewNode block     -> styleConstraints (blockStyle block)
    VirtualViewNode virtual -> styleConstraints (virtualStyle virtual)

viewNodeRangeConstraints :: ViewEnv -> ViewNode -> [Constraint]
viewNodeRangeConstraints env node =
  case node of
    BlockViewNode block ->
      blockBoundsRangeConstraints env (styleBounds (blockStyle block))
    VirtualViewNode virtual ->
      virtualBoundsRangeConstraints env (styleBounds (virtualStyle virtual))

boundsRangeConstraints ::
     ViewEnv
  -> P.Double
  -> P.Double
  -> P.Double
  -> P.Double
  -> BoundsExpr
  -> [Constraint]
boundsRangeConstraints env minWidth minHeight maxWidth maxHeight bounds' =
  case bounds' of
    Bounds topExpr leftExpr widthExpr heightExpr ->
      [ S.within
          topExpr
          (Range 0 (P.max 0 (canvasHeightValue env P.- minHeight)))
      , S.within
          leftExpr
          (Range 0 (P.max 0 (canvasWidthValue env P.- minWidth)))
      , S.within widthExpr (Range minWidth maxWidth)
      , S.within heightExpr (Range minHeight maxHeight)
      ]

minimumLayoutExtent :: P.Double
minimumLayoutExtent = 20

blockBoundsRangeConstraints :: ViewEnv -> BoundsExpr -> [Constraint]
blockBoundsRangeConstraints env =
  boundsRangeConstraints
    env
    minimumLayoutExtent
    minimumLayoutExtent
    (P.max 20 (canvasWidthValue env P./ 2))
    (P.max 20 (canvasHeightValue env P./ 2))

virtualBoundsRangeConstraints :: ViewEnv -> BoundsExpr -> [Constraint]
virtualBoundsRangeConstraints env =
  boundsRangeConstraints
    env
    minimumLayoutExtent
    minimumLayoutExtent
    (canvasWidthValue env)
    (canvasHeightValue env)

addVirtualRenderFrames :: [ViewNode] -> [[RenderIntent]] -> [[RenderIntent]]
addVirtualRenderFrames nodes frames =
  let lifecycles = virtualLifecycles nodes
   in case lifecycles of
        [] -> frames
        _  -> addVirtualLifecycleFrames lifecycles frames

data VirtualLifecycle =
  VirtualLifecycle AnyVirtualView [ViewId] [ViewId]

virtualLifecycles :: [ViewNode] -> [VirtualLifecycle]
virtualLifecycles nodes =
  [ VirtualLifecycle (AnyVirtualView virtual) (virtualChildIds virtual) []
  | VirtualViewNode virtual <- nodes
  ]

virtualChildIds :: VirtualView tag -> [ViewId]
virtualChildIds virtual =
  [blockRefId (blockRef child) | AnyBlockView child <- virtualChildren virtual]

addVirtualLifecycleFrames ::
     [VirtualLifecycle] -> [[RenderIntent]] -> [[RenderIntent]]
addVirtualLifecycleFrames lifecycles frames =
  case frames of
    [] -> []
    frame:rest ->
      let (nextLifecycles, virtualIntents) =
            updateVirtualLifecycles frame lifecycles
       in (frame P.++ virtualIntents)
            : addVirtualLifecycleFrames nextLifecycles rest

updateVirtualLifecycles ::
     [RenderIntent]
  -> [VirtualLifecycle]
  -> ([VirtualLifecycle], [RenderIntent])
updateVirtualLifecycles frame lifecycles =
  case lifecycles of
    [] -> ([], [])
    lifecycle:rest ->
      let (nextLifecycle, intents) = updateVirtualLifecycle frame lifecycle
          (nextRest, restIntents) = updateVirtualLifecycles frame rest
       in (nextLifecycle : nextRest, intents P.++ restIntents)

updateVirtualLifecycle ::
     [RenderIntent] -> VirtualLifecycle -> (VirtualLifecycle, [RenderIntent])
updateVirtualLifecycle frame lifecycle =
  case lifecycle of
    VirtualLifecycle virtual childIds liveIds ->
      let wasLive = P.not (P.null liveIds)
          nextLiveIds =
            P.foldl (applyVirtualRenderIntent childIds) liveIds frame
          isLive = P.not (P.null nextLiveIds)
          nextLifecycle = VirtualLifecycle virtual childIds nextLiveIds
          lifecycleIntents =
            case (wasLive, isLive) of
              (False, True) -> [virtualFreshIntent virtual]
              (True, False) -> [virtualRemoveIntent virtual]
              _             -> []
       in (nextLifecycle, lifecycleIntents)

applyVirtualRenderIntent :: [ViewId] -> [ViewId] -> RenderIntent -> [ViewId]
applyVirtualRenderIntent childIds liveIds intent =
  case intent of
    RenderFresh ref -> addLiveChild childIds (blockRefId ref) liveIds
    RenderFork _ ref -> addLiveChild childIds (blockRefId ref) liveIds
    RenderContinue source target ->
      addLiveChild
        childIds
        (blockRefId target)
        (removeLiveChild (blockRefId source) liveIds)
    RenderRemove ref -> removeLiveChild (blockRefId ref) liveIds

addLiveChild :: [ViewId] -> ViewId -> [ViewId] -> [ViewId]
addLiveChild childIds blockId liveIds =
  case blockId `P.elem` childIds of
    False -> liveIds
    True ->
      case blockId `P.elem` liveIds of
        True  -> liveIds
        False -> blockId : liveIds

removeLiveChild :: ViewId -> [ViewId] -> [ViewId]
removeLiveChild blockId = P.filter (P./= blockId)

virtualFreshIntent :: AnyVirtualView -> RenderIntent
virtualFreshIntent anyVirtual =
  case anyVirtual of
    AnyVirtualView virtual -> RenderFresh (virtualRef virtual)

virtualRemoveIntent :: AnyVirtualView -> RenderIntent
virtualRemoveIntent anyVirtual =
  case anyVirtual of
    AnyVirtualView virtual -> RenderRemove (virtualRef virtual)

blockRefId :: ViewRef tag -> ViewId
blockRefId = viewRefId

withImplicitInitialFrame :: [[RenderIntent]] -> [[RenderIntent]]
withImplicitInitialFrame frames =
  case frames of
    [] -> []
    first:rest ->
      case splitLeadingFresh first of
        ([], _)          -> first : rest
        (freshes, [])    -> freshes : rest
        (freshes, tail') -> freshes : tail' : rest

splitLeadingFresh :: [RenderIntent] -> ([RenderIntent], [RenderIntent])
splitLeadingFresh intents =
  case intents of
    RenderFresh ref:rest ->
      case splitLeadingFresh rest of
        (freshes, tail') -> (RenderFresh ref : freshes, tail')
    _ -> ([], intents)

mergeInitialRenderIntents :: [RenderIntent] -> ViewOutput -> ViewOutput
mergeInitialRenderIntents pending output =
  case pending of
    [] -> output
    _ ->
      case emittedRenderFrames output of
        [] ->
          output {pendingRenderIntents = pending ++ pendingRenderIntents output}
        firstFrame:restFrames ->
          output {emittedRenderFrames = (pending ++ firstFrame) : restFrames}

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

blockVarPath ::
     SymbolicType ty => ViewRef tag -> [P.String] -> P.String -> Expr ty
blockVarPath ref path field =
  var (joinPath (("B" ++ P.show (viewRefInt ref)) : (path P.++ [field])))

joinPath :: [P.String] -> P.String
joinPath parts =
  case parts of
    []        -> ""
    [part]    -> part
    part:rest -> part ++ "." ++ joinPath rest

safeKey :: P.String -> P.String
safeKey value =
  case value of
    [] -> []
    ch:rest ->
      let safeChar
            {- HLINT ignore "Use if" -}
           =
            case isSafeKeyChar ch of
              True  -> ch
              False -> '_'
       in safeChar : safeKey rest

isSafeKeyChar :: P.Char -> P.Bool
isSafeKeyChar ch = ch `P.elem` safeKeyChars

safeKeyChars :: [P.Char]
safeKeyChars = ['a' .. 'z'] P.++ ['A' .. 'Z'] P.++ ['0' .. '9'] P.++ "_-"
