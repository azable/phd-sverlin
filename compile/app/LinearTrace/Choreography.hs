{-# LANGUAGE DataKinds              #-}
{-# LANGUAGE FlexibleInstances      #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE GADTs                  #-}
{-# LANGUAGE LinearTypes            #-}
{-# LANGUAGE NoImplicitPrelude      #-}
{-# LANGUAGE RebindableSyntax       #-}
{-# LANGUAGE ScopedTypeVariables    #-}
{-# LANGUAGE TypeFamilies           #-}
{-# LANGUAGE UndecidableInstances   #-}

module LinearTrace.Choreography
  ( -- * Program layer
    Program
  , Fragment
  , RenderRecipe
  , ViewLayout
  , VisualTraceGraph
  , runProgram
  , manifest
  , StepResult(..)
  , BranchCase(..)
  , BranchDecision(..)
  , LoopResult(..)
  , phase
  , step
  , satisfy
  , branchOn
  , loop
  , -- * Handles and obligations
    BlockHandle
  , SlotHandle
  , PayloadHandle
  , Obligation
  , -- * Payloads and trace tags
    Payload
  , PayloadView(..)
  , Traceable(..)
  , LUnit(..)
  , LBool(..)
  , LInt(..)
  , LDouble(..)
  , LString(..)
  , type Create
  , type Observe
  , type Use
  , type Copy
  , type Replace
  , type Compute
  , type Destroy
  , type Seal
  , type Unseal
  , type Decide
  , (<$>)
  , (<*>)
  , -- * Declarative trace atoms
    Created(..)
  , Observed(..)
  , Used(..)
  , Copied(..)
  , Replaced(..)
  , Computed(..)
  , Destroyed(..)
  , Sealed(..)
  , Unsealed(..)
  , Decided(..)
  , createAs
  , observeAs
  , useAs
  , copyAs
  , replaceAs
  , computeAs
  , destroyAs
  , sealAs
  , unsealAs
  , decideAs
  , -- * Render recipes
    FreshObligation
  , RemoveObligation
  , renderFresh
  , renderForkCopy
  , renderContinueFrom
  , renderRemove
  , renderComplete
  , renderCheckpoint
  , -- * Component and layout layer
    BoxDefinition
  , BoxVisual
  , NodeDefinition
  , NodeRecipe
  , NodeVisual
  , LiveVisual
  , LayoutUse(..)
  , OneExpr
  , OneConstraint
  , Style
  , EmptyStyleDraft
  , BorderStyle(..)
  , Bounds(..)
  , BoundsExpr
  , FontWeight(..)
  , FontStyle(..)
  , Hsl(..)
  , FreeExpr
  , HslExpr
  , HueExpr
  , LayoutExpr
  , UnitExpr
  , Vec2(..)
  , TextAlign(..)
  , WhiteSpace(..)
  , alpha
  , bold
  , bottom
  , bounds
  , borderStyle
  , boxDefinition
  , center
  , centerX
  , centerY
  , centerText
  , constrain
  , cssClass
  , encourage
  , fill
  , finalizeStyle
  , fontFamily
  , fontSize
  , fontStyle
  , fontWeight
  , global
  , height
  , left
  , noWrap
  , node
  , num
  , opacity
  , placeBox
  , placed
  , position
  , radius
  , require
  , right
  , setCssClassOnce
  , setFillOnce
  , setFontFamilyOnce
  , setFontSizeOnce
  , setFontWeightOnce
  , setRadiusOnce
  , setStrokeOnce
  , setStrokeWidthOnce
  , setTextAlignOnce
  , setWhiteSpaceOnce
  , setZIndexOnce
  , stroke
  , strokeWidth
  , style
  , size
  , sized
  , takeHeight
  , takeLeft
  , takeRight
  , takeTop
  , takeWidth
  , textAlign
  , top
  , vec2
  , whiteSpace
  , width
  , zIndex
  , (@*@)
  , (@+@)
  , (@-@)
  , (@/@)
  , (@<=@)
  , (@==@)
  , (|>)
  ) where

import           Control.Functor.Linear hiding ((<$>), (<*>))
import qualified Data.Functor.Linear    as DFL
import           LinearTrace.Core       (LBool (..), LDouble (..), LInt (..),
                                         LString (..), LUnit (..), Payload,
                                         PayloadView (..), Traceable (..),
                                         (<$>), (<*>))
import qualified LinearTrace.Core       as C
import           LinearTrace.Solver     (Vec2 (..), vec2)
import qualified LinearTrace.Solver     as S
import           LinearTrace.View       (BorderStyle (..), Bounds (..),
                                         BoundsExpr, BoxDefinition, BoxVisual,
                                         EmptyStyleDraft, FontStyle (..),
                                         FontWeight (..), FreeExpr, Hsl (..),
                                         HslExpr, HueExpr, LayoutExpr,
                                         LayoutUse (..), LiveVisual,
                                         OneConstraint (..), OneExpr (..),
                                         Style, TextAlign (..), UnitExpr,
                                         WhiteSpace (..), boxDefinition,
                                         encourage, finalizeStyle, global, num,
                                         setCssClassOnce, setFillOnce,
                                         setFontFamilyOnce, setFontSizeOnce,
                                         setFontWeightOnce, setRadiusOnce,
                                         setStrokeOnce, setStrokeWidthOnce,
                                         setTextAlignOnce, setWhiteSpaceOnce,
                                         setZIndexOnce, takeHeight, takeLeft,
                                         takeRight, takeTop, takeWidth, (@*@),
                                         (@+@), (@-@), (@/@), (@<=@), (@==@),
                                         (|>))
import qualified LinearTrace.View       as V
import qualified LinearTrace.View.Style as VS
import qualified Prelude                as P
import           Prelude.Linear

data Program a where
  PureProgram :: a %1 -> Program a
  BindProgram :: Program a %1 -> (a %1 -> Program b) %1 -> Program b
  PhaseProgram
    :: P.String
    -> Fragment (StepResult output obligations)
       %1 -> (obligations %1 -> RenderRecipe ())
    -> Program output
  SatisfyProgram
    :: P.String
    -> obligations
       %1 -> (obligations %1 -> RenderRecipe ())
    -> Program ()
  BranchOnProgram
    :: Fragment (Decided tag)
       %1 -> BranchCase tag
    -> BranchCase tag
    -> (BranchDecision %1 -> Program output)
       %1 -> Program output
  LoopProgram
    :: state
       %1 -> (state %1 -> Program (LoopResult state output))
    -> Program output

data Fragment a where
  PureFragment :: a %1 -> Fragment a
  BindFragment :: Fragment a %1 -> (a %1 -> Fragment b) %1 -> Fragment b
  CreateAsFragment
    :: C.Traceable tag => C.Payload tag %1 -> Fragment (Created tag)
  ObserveAsFragment
    :: C.Traceable tag => BlockHandle tag %1 -> Fragment (Observed tag)
  UseAsFragment :: C.Traceable tag => BlockHandle tag %1 -> Fragment (Used tag)
  CopyAsFragment
    :: C.Traceable tag => BlockHandle tag %1 -> Fragment (Copied tag)
  ReplaceAsFragment
    :: C.Traceable tag=> BlockHandle tag
       %1 -> BlockHandle tag
       %1 -> Fragment (Replaced tag)
  ComputeAsFragment
    :: C.Traceable tag => PayloadHandle tag %1 -> Fragment (Computed tag)
  DestroyAsFragment
    :: C.Traceable tag => BlockHandle tag %1 -> Fragment (Destroyed tag)
  SealAsFragment
    :: (C.Traceable owner, C.Traceable tag)=> BlockHandle owner
       %1 -> BlockHandle tag
       %1 -> Fragment (Sealed owner tag)
  UnsealAsFragment
    :: (C.Traceable owner, C.Traceable tag)=> BlockHandle owner
       %1 -> SlotHandle owner tag
       %1 -> Fragment (Unsealed owner tag)
  DecideAsFragment
    :: C.Traceable tag=> (C.Payload tag %1 -> Bool)
    -> BlockHandle tag
       %1 -> Fragment (Decided tag)

data RenderRecipe a where
  PureRender :: a %1 -> RenderRecipe a
  BindRender
    :: RenderRecipe a %1 -> (a %1 -> RenderRecipe b) %1 -> RenderRecipe b
  FreshCreateRender
    :: V.ViewDefinition tag used
       %1 -> Obligation (Create tag)
       %1 -> RenderRecipe (V.Visual V.Rendered V.Stable used tag)
  FreshComputeRender
    :: V.ViewDefinition tag used
       %1 -> Obligation (Compute tag)
       %1 -> RenderRecipe (V.Visual V.Rendered V.Stable used tag)
  ForkCopyRender
    :: V.ViewDefinition tag used
       %1 -> Obligation (Copy tag)
       %1 -> RenderRecipe
         (LiveVisual tag, V.Visual V.Rendered V.Stable used tag)
  ContinueFromRender
    :: V.ViewDefinition tag used
       %1 -> Obligation (Observe source)
       %1 -> Obligation (Create tag)
       %1 -> RenderRecipe (V.Visual V.Rendered V.Stable used tag)
  RemoveUseRender :: Obligation (Use tag) %1 -> RenderRecipe ()
  RemoveDestroyRender :: Obligation (Destroy tag) %1 -> RenderRecipe ()
  RemoveDecideRender :: Obligation (Decide tag) %1 -> RenderRecipe ()
  CompleteRender :: V.Visual V.Rendered V.Stable used tag %1 -> RenderRecipe ()
  CheckpointRender :: RenderRecipe ()

data NodeSpec = NodeSpec
  { nodeSpecStyleUpdate  :: Style -> Style
  , nodeSpecLeft         :: Maybe LayoutExpr
  , nodeSpecTop          :: Maybe LayoutExpr
  , nodeSpecWidth        :: Maybe LayoutExpr
  , nodeSpecHeight       :: Maybe LayoutExpr
  , nodeSpecRight        :: Maybe LayoutExpr
  , nodeSpecBottom       :: Maybe LayoutExpr
  , nodeSpecCenterX      :: Maybe LayoutExpr
  , nodeSpecCenterY      :: Maybe LayoutExpr
  , nodeSpecRequirements :: [ViewLayout ()]
  }

data NodeRecipe a where
  NodeRecipe :: a %1 -> NodeSpec -> NodeRecipe a

type ViewLayout a = V.ViewBuilder a

type VisualTraceGraph = V.VisualTraceGraph

type NodeDefinition tag = BoxDefinition tag

type NodeVisual tag = BoxVisual tag

type StyleRecipe = NodeRecipe

type BlockHandle = C.Block

type SlotHandle = C.Slot

type PayloadHandle tag = C.OneUse (C.Payload tag)

type Create tag = C.Create tag

type Observe tag = C.Observe tag

type Use tag = C.Use tag

type Copy tag = C.Copy tag

type Replace tag = C.Replace tag

type Compute tag = C.Compute tag

type Destroy tag = C.Destroy tag

type Seal owner tag = C.Seal owner tag

type Unseal owner tag = C.Unseal owner tag

type Decide tag = C.Decide tag

data Obligation act where
  Obligation :: V.VisualExplainToken act %1 -> Obligation act

data StepResult output obligations where
  StepResult :: output %1 -> obligations %1 -> StepResult output obligations

data BranchDecision
  = BranchTrue
  | BranchFalse

data BranchCase tag where
  BranchCase
    :: P.String
    -> (Obligation (Decide tag) %1 -> RenderRecipe ())
    -> BranchCase tag

data LoopResult state output where
  Continue :: state %1 -> LoopResult state output
  Finish :: output %1 -> LoopResult state output

mapProgramWith :: (a %1 -> b) %1 -> a %1 -> Program b
mapProgramWith f value = PureProgram (f value)

liftProgramWith :: (a %1 -> b %1 -> c) %1 -> Program b %1 -> a %1 -> Program c
liftProgramWith f rhs leftValue =
  BindProgram rhs (finishProgramLift f leftValue)

finishProgramLift :: (a %1 -> b %1 -> c) %1 -> a %1 -> b %1 -> Program c
finishProgramLift f leftValue rightValue = PureProgram (f leftValue rightValue)

instance DFL.Functor Program where
  fmap f program = BindProgram program (mapProgramWith f)

instance Functor Program where
  fmap f program = BindProgram program (mapProgramWith f)

instance DFL.Applicative Program where
  pure = PureProgram
  liftA2 f lhs rhs = BindProgram lhs (liftProgramWith f rhs)

instance Applicative Program where
  pure = PureProgram
  liftA2 f lhs rhs = BindProgram lhs (liftProgramWith f rhs)

instance Monad Program where
  (>>=) = BindProgram

mapFragmentWith :: (a %1 -> b) %1 -> a %1 -> Fragment b
mapFragmentWith f value = PureFragment (f value)

liftFragmentWith ::
     (a %1 -> b %1 -> c) %1 -> Fragment b %1 -> a %1 -> Fragment c
liftFragmentWith f rhs leftValue =
  BindFragment rhs (finishFragmentLift f leftValue)

finishFragmentLift :: (a %1 -> b %1 -> c) %1 -> a %1 -> b %1 -> Fragment c
finishFragmentLift f leftValue rightValue =
  PureFragment (f leftValue rightValue)

instance DFL.Functor Fragment where
  fmap f fragment = BindFragment fragment (mapFragmentWith f)

instance Functor Fragment where
  fmap f fragment = BindFragment fragment (mapFragmentWith f)

instance DFL.Applicative Fragment where
  pure = PureFragment
  liftA2 f lhs rhs = BindFragment lhs (liftFragmentWith f rhs)

instance Applicative Fragment where
  pure = PureFragment
  liftA2 f lhs rhs = BindFragment lhs (liftFragmentWith f rhs)

instance Monad Fragment where
  (>>=) = BindFragment

mapRenderWith :: (a %1 -> b) %1 -> a %1 -> RenderRecipe b
mapRenderWith f value = PureRender (f value)

liftRenderWith ::
     (a %1 -> b %1 -> c) %1 -> RenderRecipe b %1 -> a %1 -> RenderRecipe c
liftRenderWith f rhs leftValue = BindRender rhs (finishRenderLift f leftValue)

finishRenderLift :: (a %1 -> b %1 -> c) %1 -> a %1 -> b %1 -> RenderRecipe c
finishRenderLift f leftValue rightValue = PureRender (f leftValue rightValue)

instance DFL.Functor RenderRecipe where
  fmap f recipe = BindRender recipe (mapRenderWith f)

instance Functor RenderRecipe where
  fmap f recipe = BindRender recipe (mapRenderWith f)

instance DFL.Applicative RenderRecipe where
  pure = PureRender
  liftA2 f lhs rhs = BindRender lhs (liftRenderWith f rhs)

instance Applicative RenderRecipe where
  pure = PureRender
  liftA2 f lhs rhs = BindRender lhs (liftRenderWith f rhs)

instance Monad RenderRecipe where
  (>>=) = BindRender

emptyNodeSpec :: NodeSpec
emptyNodeSpec =
  NodeSpec
    { nodeSpecStyleUpdate = P.id
    , nodeSpecLeft = Nothing
    , nodeSpecTop = Nothing
    , nodeSpecWidth = Nothing
    , nodeSpecHeight = Nothing
    , nodeSpecRight = Nothing
    , nodeSpecBottom = Nothing
    , nodeSpecCenterX = Nothing
    , nodeSpecCenterY = Nothing
    , nodeSpecRequirements = []
    }

composeStyleUpdates :: (Style -> Style) -> (Style -> Style) -> Style -> Style
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
    , nodeSpecLeft = preferLater (nodeSpecLeft first) (nodeSpecLeft second)
    , nodeSpecTop = preferLater (nodeSpecTop first) (nodeSpecTop second)
    , nodeSpecWidth = preferLater (nodeSpecWidth first) (nodeSpecWidth second)
    , nodeSpecHeight =
        preferLater (nodeSpecHeight first) (nodeSpecHeight second)
    , nodeSpecRight = preferLater (nodeSpecRight first) (nodeSpecRight second)
    , nodeSpecBottom =
        preferLater (nodeSpecBottom first) (nodeSpecBottom second)
    , nodeSpecCenterX =
        preferLater (nodeSpecCenterX first) (nodeSpecCenterX second)
    , nodeSpecCenterY =
        preferLater (nodeSpecCenterY first) (nodeSpecCenterY second)
    , nodeSpecRequirements =
        nodeSpecRequirements first P.++ nodeSpecRequirements second
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

runProgram :: Program () -> VisualTraceGraph
runProgram program = V.buildGraph (interpretProgram program)

manifest :: Program () %1 -> Program ()
manifest program = program

phase ::
     P.String
  -> Fragment (StepResult output obligations)
     %1 -> (obligations %1 -> RenderRecipe ())
  -> Program output
phase = PhaseProgram

step ::
     P.String
  -> Fragment (StepResult output obligations)
     %1 -> (obligations %1 -> RenderRecipe ())
  -> Program output
step = phase

satisfy ::
     P.String
  -> obligations
     %1 -> (obligations %1 -> RenderRecipe ())
  -> Program ()
satisfy = SatisfyProgram

branchOn ::
     Fragment (Decided tag)
     %1 -> BranchCase tag
  -> BranchCase tag
  -> (BranchDecision %1 -> Program output)
     %1 -> Program output
branchOn = BranchOnProgram

loop ::
     state
     %1 -> (state %1 -> Program (LoopResult state output))
  -> Program output
loop = LoopProgram

interpretProgram :: Program a %1 -> V.VisualTraceBuilder a
interpretProgram program =
  case program of
    PureProgram value -> return value
    BindProgram first next -> do
      value <- interpretProgram first
      interpretProgram (next value)
    PhaseProgram label fragment render -> do
      StepResult output obligations <- interpretFragment fragment
      V.explain label (interpretRender (render obligations))
      return output
    SatisfyProgram label obligations render ->
      V.explain label (interpretRender (render obligations))
    BranchOnProgram decision trueCase falseCase next -> do
      decided <- interpretFragment decision
      branch <-
        case decided of
          DecidedTrue obligation -> do
            interpretBranchCase obligation trueCase
            return BranchTrue
          DecidedFalse obligation -> do
            interpretBranchCase obligation falseCase
            return BranchFalse
      interpretProgram (next branch)
    LoopProgram loopState body -> interpretLoop loopState body

interpretLoop ::
     state
     %1 -> (state %1 -> Program (LoopResult state output))
  -> V.VisualTraceBuilder output
interpretLoop loopState body = do
  result <- interpretProgram (body loopState)
  case result of
    Continue nextState -> interpretLoop nextState body
    Finish output      -> return output

interpretBranchCase ::
     Obligation (Decide tag) %1 -> BranchCase tag -> V.VisualTraceBuilder ()
interpretBranchCase obligation branchCase =
  case branchCase of
    BranchCase label render ->
      V.explain label (interpretRender (render obligation))

interpretFragment :: Fragment a %1 -> V.VisualTraceBuilder a
interpretFragment fragment =
  case fragment of
    PureFragment value -> return value
    BindFragment first next -> do
      value <- interpretFragment first
      interpretFragment (next value)
    CreateAsFragment payload -> do
      V.Created block token <- V.create payload
      return (Created block (Obligation token))
    ObserveAsFragment block -> do
      V.Observed next token <- V.observe block
      return (Observed next (Obligation token))
    UseAsFragment block -> do
      V.Used payload token <- V.use block
      return (Used payload (Obligation token))
    CopyAsFragment block -> do
      V.Copied original copy' token <- V.copy block
      return (Copied original copy' (Obligation token))
    ReplaceAsFragment oldBlock incomingBlock -> do
      V.Replaced output token <- V.replace oldBlock incomingBlock
      return (Replaced output (Obligation token))
    ComputeAsFragment payload -> do
      V.Computed block token <- V.compute payload
      return (Computed block (Obligation token))
    DestroyAsFragment block -> do
      V.Destroyed token <- V.destroy block
      return (Destroyed (Obligation token))
    SealAsFragment owner child -> do
      V.Sealed ownerBlock childSlot token <- V.seal owner child
      return (Sealed ownerBlock childSlot (Obligation token))
    UnsealAsFragment owner slot -> do
      V.Unsealed ownerBlock childBlock token <- V.unseal owner slot
      return (Unsealed ownerBlock childBlock (Obligation token))
    DecideAsFragment predicate block -> do
      decision <- V.decide predicate block
      case decision of
        V.DecidedTrue token  -> return (DecidedTrue (Obligation token))
        V.DecidedFalse token -> return (DecidedFalse (Obligation token))

interpretRender :: RenderRecipe a %1 -> V.ViewBuilder a
interpretRender recipe =
  case recipe of
    PureRender value -> return value
    BindRender first next -> do
      value <- interpretRender first
      interpretRender (next value)
    FreshCreateRender definition obligation ->
      case obligation of
        Obligation token -> V.fresh definition token
    FreshComputeRender definition obligation ->
      case obligation of
        Obligation token -> V.fresh definition token
    ForkCopyRender definition obligation ->
      case obligation of
        Obligation token -> V.forkCopy definition token
    ContinueFromRender definition sourceObligation newObligation ->
      case sourceObligation of
        Obligation source ->
          case newObligation of
            Obligation new -> V.continueFrom definition source new
    RemoveUseRender obligation ->
      case obligation of
        Obligation token -> V.remove token
    RemoveDestroyRender obligation ->
      case obligation of
        Obligation token -> V.remove token
    RemoveDecideRender obligation ->
      case obligation of
        Obligation token -> V.remove token
    CompleteRender visual -> V.complete visual
    CheckpointRender -> V.checkpoint

data Created tag where
  Created :: BlockHandle tag %1 -> Obligation (Create tag) %1 -> Created tag

data Observed tag where
  Observed :: BlockHandle tag %1 -> Obligation (Observe tag) %1 -> Observed tag

data Used tag where
  Used :: PayloadHandle tag %1 -> Obligation (Use tag) %1 -> Used tag

data Copied tag where
  Copied
    :: BlockHandle tag
       %1 -> BlockHandle tag
       %1 -> Obligation (Copy tag)
       %1 -> Copied tag

data Replaced tag where
  Replaced :: BlockHandle tag %1 -> Obligation (Replace tag) %1 -> Replaced tag

data Computed tag where
  Computed :: BlockHandle tag %1 -> Obligation (Compute tag) %1 -> Computed tag

data Destroyed tag where
  Destroyed :: Obligation (Destroy tag) %1 -> Destroyed tag

data Sealed owner tag where
  Sealed
    :: BlockHandle owner
       %1 -> SlotHandle owner tag
       %1 -> Obligation (Seal owner tag)
       %1 -> Sealed owner tag

data Unsealed owner tag where
  Unsealed
    :: BlockHandle owner
       %1 -> BlockHandle tag
       %1 -> Obligation (Unseal owner tag)
       %1 -> Unsealed owner tag

data Decided tag where
  DecidedTrue :: Obligation (Decide tag) %1 -> Decided tag
  DecidedFalse :: Obligation (Decide tag) %1 -> Decided tag

createAs ::
     forall tag. C.Traceable tag
  => C.Payload tag
     %1 -> Fragment (Created tag)
createAs = CreateAsFragment

observeAs ::
     forall tag. C.Traceable tag
  => BlockHandle tag
     %1 -> Fragment (Observed tag)
observeAs = ObserveAsFragment

useAs ::
     forall tag. C.Traceable tag
  => BlockHandle tag
     %1 -> Fragment (Used tag)
useAs = UseAsFragment

copyAs ::
     forall tag. C.Traceable tag
  => BlockHandle tag
     %1 -> Fragment (Copied tag)
copyAs = CopyAsFragment

replaceAs ::
     forall tag. C.Traceable tag
  => BlockHandle tag
     %1 -> BlockHandle tag
     %1 -> Fragment (Replaced tag)
replaceAs = ReplaceAsFragment

computeAs ::
     forall tag. C.Traceable tag
  => PayloadHandle tag
     %1 -> Fragment (Computed tag)
computeAs = ComputeAsFragment

destroyAs ::
     forall tag. C.Traceable tag
  => BlockHandle tag
     %1 -> Fragment (Destroyed tag)
destroyAs = DestroyAsFragment

sealAs ::
     forall owner tag. (C.Traceable owner, C.Traceable tag)
  => BlockHandle owner
     %1 -> BlockHandle tag
     %1 -> Fragment (Sealed owner tag)
sealAs = SealAsFragment

unsealAs ::
     forall owner tag. (C.Traceable owner, C.Traceable tag)
  => BlockHandle owner
     %1 -> SlotHandle owner tag
     %1 -> Fragment (Unsealed owner tag)
unsealAs = UnsealAsFragment

decideAs ::
     forall tag. C.Traceable tag
  => (C.Payload tag %1 -> Bool)
  -> BlockHandle tag
     %1 -> Fragment (Decided tag)
decideAs = DecideAsFragment

class FreshObligation act tag | act -> tag where
  renderFresh ::
       V.ViewDefinition tag used
       %1 -> Obligation act
       %1 -> RenderRecipe (V.Visual V.Rendered V.Stable used tag)

instance FreshObligation (Create tag) tag where
  renderFresh = FreshCreateRender

instance FreshObligation (Compute tag) tag where
  renderFresh = FreshComputeRender

renderForkCopy ::
     V.ViewDefinition tag used
     %1 -> Obligation (Copy tag)
     %1 -> RenderRecipe (LiveVisual tag, V.Visual V.Rendered V.Stable used tag)
renderForkCopy = ForkCopyRender

renderContinueFrom ::
     V.ViewDefinition tag used
     %1 -> Obligation (Observe source)
     %1 -> Obligation (Create tag)
     %1 -> RenderRecipe (V.Visual V.Rendered V.Stable used tag)
renderContinueFrom = ContinueFromRender

class RemoveObligation act where
  renderRemove :: Obligation act %1 -> RenderRecipe ()

instance RemoveObligation (Use tag) where
  renderRemove = RemoveUseRender

instance RemoveObligation (Destroy tag) where
  renderRemove = RemoveDestroyRender

instance RemoveObligation (Decide tag) where
  renderRemove = RemoveDecideRender

renderComplete :: V.Visual V.Rendered V.Stable used tag %1 -> RenderRecipe ()
renderComplete = CompleteRender

renderCheckpoint :: RenderRecipe ()
renderCheckpoint = CheckpointRender

constrain :: OneConstraint %1 -> ViewLayout ()
constrain = V.ensure

style :: StyleRecipe () -> (EmptyStyleDraft %1 -> Style)
style recipe =
  case recipe of
    NodeRecipe () spec -> V.finalizeStyleWith (nodeSpecStyleUpdate spec)

setStyleWith :: (Style -> Style) -> NodeRecipe ()
setStyleWith update = NodeRecipe () emptyNodeSpec {nodeSpecStyleUpdate = update}

opacity :: UnitExpr -> NodeRecipe ()
opacity value = setStyleWith (VS.setOpacity value)

zIndex :: FreeExpr -> NodeRecipe ()
zIndex value = setStyleWith (VS.setZIndex value)

fontSize :: LayoutExpr -> NodeRecipe ()
fontSize value = setStyleWith (VS.setFontSize value)

radius :: LayoutExpr -> NodeRecipe ()
radius value = setStyleWith (VS.setRadius value)

strokeWidth :: LayoutExpr -> NodeRecipe ()
strokeWidth value = setStyleWith (VS.setStrokeWidth value)

alpha :: UnitExpr -> NodeRecipe ()
alpha value = setStyleWith (VS.setAlpha value)

fill :: HslExpr -> NodeRecipe ()
fill value = setStyleWith (VS.setFill value)

stroke :: HslExpr -> NodeRecipe ()
stroke value = setStyleWith (VS.setStroke value)

fontFamily :: P.String -> NodeRecipe ()
fontFamily value = setStyleWith (VS.setFontFamily value)

fontWeight :: FontWeight -> NodeRecipe ()
fontWeight value = setStyleWith (VS.setFontWeight value)

fontStyle :: FontStyle -> NodeRecipe ()
fontStyle value = setStyleWith (VS.setFontStyle value)

textAlign :: TextAlign -> NodeRecipe ()
textAlign value = setStyleWith (VS.setTextAlign value)

borderStyle :: BorderStyle -> NodeRecipe ()
borderStyle value = setStyleWith (VS.setBorderStyle value)

whiteSpace :: WhiteSpace -> NodeRecipe ()
whiteSpace value = setStyleWith (VS.setWhiteSpace value)

cssClass :: P.String -> NodeRecipe ()
cssClass value = setStyleWith (VS.setCssClass value)

bold :: NodeRecipe ()
bold = fontWeight FontWeightBold

centerText :: NodeRecipe ()
centerText = textAlign TextAlignCenter

noWrap :: NodeRecipe ()
noWrap = whiteSpace WhiteSpaceNoWrap

setNodeSpecWith :: (NodeSpec -> NodeSpec) -> NodeRecipe ()
setNodeSpecWith update = NodeRecipe () (update emptyNodeSpec)

left :: LayoutExpr -> NodeRecipe ()
left value = setNodeSpecWith (\spec -> spec {nodeSpecLeft = Just value})

top :: LayoutExpr -> NodeRecipe ()
top value = setNodeSpecWith (\spec -> spec {nodeSpecTop = Just value})

width :: LayoutExpr -> NodeRecipe ()
width value = setNodeSpecWith (\spec -> spec {nodeSpecWidth = Just value})

height :: LayoutExpr -> NodeRecipe ()
height value = setNodeSpecWith (\spec -> spec {nodeSpecHeight = Just value})

right :: LayoutExpr -> NodeRecipe ()
right value = setNodeSpecWith (\spec -> spec {nodeSpecRight = Just value})

bottom :: LayoutExpr -> NodeRecipe ()
bottom value = setNodeSpecWith (\spec -> spec {nodeSpecBottom = Just value})

centerX :: LayoutExpr -> NodeRecipe ()
centerX value = setNodeSpecWith (\spec -> spec {nodeSpecCenterX = Just value})

centerY :: LayoutExpr -> NodeRecipe ()
centerY value = setNodeSpecWith (\spec -> spec {nodeSpecCenterY = Just value})

position :: Vec2 LayoutExpr -> NodeRecipe ()
position value =
  case value of
    Vec2 leftExpr topExpr -> do
      left leftExpr
      top topExpr

size :: Vec2 LayoutExpr -> NodeRecipe ()
size value =
  case value of
    Vec2 widthExpr heightExpr -> do
      width widthExpr
      height heightExpr

center :: Vec2 LayoutExpr -> NodeRecipe ()
center value =
  case value of
    Vec2 centerXExpr centerYExpr -> do
      centerX centerXExpr
      centerY centerYExpr

bounds :: BoundsExpr -> NodeRecipe ()
bounds value =
  case value of
    Bounds topExpr leftExpr widthExpr heightExpr -> do
      top topExpr
      left leftExpr
      width widthExpr
      height heightExpr

placed :: LayoutExpr -> LayoutExpr -> LayoutExpr -> LayoutExpr -> NodeRecipe ()
placed leftExpr topExpr widthExpr heightExpr = do
  left leftExpr
  top topExpr
  width widthExpr
  height heightExpr

sized :: LayoutExpr -> LayoutExpr -> NodeRecipe ()
sized widthExpr heightExpr = do
  width widthExpr
  height heightExpr

require :: ViewLayout () -> NodeRecipe ()
require action =
  setNodeSpecWith
    (\spec ->
       spec {nodeSpecRequirements = nodeSpecRequirements spec P.++ [action]})

node :: NodeRecipe () -> NodeDefinition tag
node recipe =
  case recipe of
    NodeRecipe () spec ->
      boxDefinition
        (V.finalizeStyleWith (nodeSpecStyleUpdate spec))
        (layoutNode spec)

layoutNode :: NodeSpec -> LiveVisual tag %1 -> ViewLayout (NodeVisual tag)
layoutNode spec visual0 = do
  LayoutUse visual1 leftVar <- takeLeft visual0
  LayoutUse visual2 topVar <- takeTop visual1
  LayoutUse visual3 widthVar <- takeWidth visual2
  LayoutUse visual4 heightVar <- takeHeight visual3
  case leftVar of
    OneExpr (Ur leftExpr) ->
      case topVar of
        OneExpr (Ur topExpr) ->
          case widthVar of
            OneExpr (Ur widthExpr) ->
              case heightVar of
                OneExpr (Ur heightExpr) -> do
                  runRequirements (nodeSpecRequirements spec)
                  constrainGeometry spec leftExpr topExpr widthExpr heightExpr
                  return visual4

runRequirements :: [ViewLayout ()] -> ViewLayout ()
runRequirements actions =
  case actions of
    [] -> return ()
    action:rest -> do
      action
      runRequirements rest

constrainGeometry ::
     NodeSpec
  -> LayoutExpr
  -> LayoutExpr
  -> LayoutExpr
  -> LayoutExpr
  -> ViewLayout ()
constrainGeometry spec leftExpr topExpr widthExpr heightExpr = do
  constrainMaybe leftExpr (nodeSpecLeft spec)
  constrainMaybe topExpr (nodeSpecTop spec)
  constrainMaybe widthExpr (nodeSpecWidth spec)
  constrainMaybe heightExpr (nodeSpecHeight spec)
  constrainMaybe (leftExpr S.@+@ widthExpr) (nodeSpecRight spec)
  constrainMaybe (topExpr S.@+@ heightExpr) (nodeSpecBottom spec)
  constrainMaybe
    (leftExpr S.@+@ (widthExpr S.@/@ (S.num 2 :: LayoutExpr)))
    (nodeSpecCenterX spec)
  constrainMaybe
    (topExpr S.@+@ (heightExpr S.@/@ (S.num 2 :: LayoutExpr)))
    (nodeSpecCenterY spec)

constrainMaybe :: LayoutExpr -> Maybe LayoutExpr -> ViewLayout ()
constrainMaybe expr maybeTarget =
  case maybeTarget of
    Nothing     -> return ()
    Just target -> constrainRaw (expr S.@==@ target)

constrainRaw :: S.Constraint -> ViewLayout ()
constrainRaw constraint = V.ensure (OneConstraint (Ur constraint))

placeBox ::
     LayoutExpr
  -> LayoutExpr
  -> LayoutExpr
  -> LayoutExpr
  -> LiveVisual tag
     %1 -> ViewLayout (BoxVisual tag)
placeBox leftExpr topExpr widthExpr heightExpr visual0 = do
  LayoutUse visual1 leftVar <- takeLeft visual0
  LayoutUse visual2 topVar <- takeTop visual1
  LayoutUse visual3 widthVar <- takeWidth visual2
  LayoutUse visual4 heightVar <- takeHeight visual3
  constrain (leftVar @==@ leftExpr)
  constrain (topVar @==@ topExpr)
  constrain (widthVar @==@ widthExpr)
  constrain (heightVar @==@ heightExpr)
  return visual4
