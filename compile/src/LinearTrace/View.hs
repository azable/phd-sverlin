{-# LANGUAGE AllowAmbiguousTypes  #-}
{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE GADTs                #-}
{-# LANGUAGE LinearTypes          #-}
{-# LANGUAGE RankNTypes           #-}
{-# LANGUAGE RebindableSyntax     #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeApplications     #-}
{-# LANGUAGE TypeFamilies         #-}
{-# LANGUAGE TypeOperators        #-}
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
  , Query(..)
  , QueryTerm(..)
  , QueryValue(..)
  , emptyQuery
  , queryAtom
  , queryInt
  , queryAppend
  , queryKey
  , queryFacts
  , queryMatches
  , QueryInt(..)
  , QueryBindings
  , queryIntConst
  , queryIntVar
  , queryIntAdd
  , queryBindingValue
  , MatchBinding(..)
  , MatchBindings
  , MatchContext
  , matchContextIndex
  , matchContextBindings
  , matchBinding
  , matchBindingValue
  , PayloadPattern
  , anyPayloadPattern
  , payloadBindingPattern
  , payloadBoolPattern
  , payloadIntPattern
  , payloadDoublePattern
  , payloadStringPattern
  , payloadUnitPattern
  , ContentMode(..)
  , LayoutPin(..)
  , NodePatch(..)
  , emptyNodePatch
  , appendNodePatch
  , NodeSelection(..)
  , ConstraintStrength(..)
  , LayoutRelation(..)
  , ValueComponent
  , ValueEndpoint
  , ValueAccess
  , StyleLayoutAttr(..)
  , StyleUnitAttr(..)
  , StyleFreeAttr(..)
  , StyleColorAttr(..)
  , HslPart(..)
  , rawValueEndpoint
  , selectionValueEndpoint
  , layoutValueAccess
  , styleLayoutValueAccess
  , styleUnitValueAccess
  , styleFreeValueAccess
  , styleColorPartValueAccess
  , MatchSpec
  , emptyMatchSpec
  , matchSpecAppend
  , matchQueryNode
  , matchAnyQueryNode
  , matchQueryPayloadNode
  , matchVirtualNode
  , matchValueRelation
  , matchValueDirectedBridge
  , matchValueSymmetricBridge
  , LayoutAttr(..)
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
    ViewScript(..)
  , ViewOutput
  , emptyViewOutput
  , appendViewOutput
  , flushViewOutput
  , matchedBlockOutput
  , renderIntentOutput
  , buildCSP
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

import           Control.Functor.Linear  hiding ((<$>), (<*>))
import           Data.Kind               (Type)
import qualified Data.Maybe              as Maybe
import           Data.Proxy              (Proxy (..))
import           Data.Type.Equality      ((:~:) (..))
import           Data.Typeable           (eqT)
import           GHC.OverloadedLabels    (IsLabel (..))
import           GHC.TypeLits            (KnownSymbol, symbolVal)
import qualified LinearTrace.Core        as C
import qualified LinearTrace.Core.Events as E
import           LinearTrace.View.Style
import           LinearTrace.View.Types
import qualified Prelude                 as P
import           Prelude.Linear
import qualified Solver                  as S
import           Solver                  hiding (absExpr, component, num)

--------------------------------------------------------------------------------
-- Semantic queries and visualization matches
--------------------------------------------------------------------------------
data QueryInt
  = QueryIntConst P.Int
  | QueryIntVar P.String
  | QueryIntAdd QueryInt P.Int
  deriving (P.Eq, P.Ord, P.Show)

data QueryValue
  = QueryAtom
  | QueryIntValue QueryInt
  deriving (P.Eq, P.Ord, P.Show)

data QueryTerm =
  QueryTerm P.String QueryValue
  deriving (P.Eq, P.Ord, P.Show)

newtype Query =
  Query [QueryTerm]
  deriving (P.Eq, P.Ord, P.Show)

type QueryBindings = [(P.String, P.Int)]

emptyQuery :: Query
emptyQuery = Query []

queryAtom :: P.String -> Query
queryAtom name = Query [QueryTerm name QueryAtom]

queryInt :: P.String -> QueryInt -> Query
queryInt name value = Query [QueryTerm name (QueryIntValue value)]

queryIntConst :: P.Int -> QueryInt
queryIntConst = QueryIntConst

queryIntVar :: P.String -> QueryInt
queryIntVar = QueryIntVar

queryIntAdd :: QueryInt -> P.Int -> QueryInt
queryIntAdd = QueryIntAdd

queryAppend :: Query -> Query -> Query
queryAppend lhs rhs =
  case lhs of
    Query leftTerms ->
      case rhs of
        Query rightTerms -> Query (canonicalTerms (leftTerms P.++ rightTerms))

labelName :: KnownSymbol name => Proxy name -> P.String
labelName proxy = dotName (symbolVal proxy)

dotName :: P.String -> P.String
dotName name =
  case name of
    []        -> []
    char:rest -> dotChar char : dotName rest

dotChar :: P.Char -> P.Char
dotChar char =
  case char P.== '_' of
    P.True  -> '.'
    P.False -> char

instance KnownSymbol name => IsLabel name Query where
  fromLabel = queryAtom (labelName (Proxy @name))

instance KnownSymbol name => IsLabel name (P.Int -> Query) where
  fromLabel value = queryInt (labelName (Proxy @name)) (queryIntConst value)

instance KnownSymbol name => IsLabel name (QueryInt -> Query) where
  fromLabel = queryInt (labelName (Proxy @name))

queryKey :: Query -> P.String
queryKey query =
  case query of
    Query terms -> joinPath ("q" : P.map queryTermKey (canonicalTerms terms))

queryFacts :: Query -> C.Facts
queryFacts query =
  case query of
    Query terms -> C.Facts (P.map queryTermToFact (canonicalTerms terms))

queryTermKey :: QueryTerm -> P.String
queryTermKey term =
  case term of
    QueryTerm name value ->
      case value of
        QueryAtom             -> safeKey name
        QueryIntValue intTerm -> safeKey name ++ "-" ++ queryIntKey intTerm

queryIntKey :: QueryInt -> P.String
queryIntKey intPattern =
  case intPattern of
    QueryIntConst value     -> P.show value
    QueryIntVar name        -> "$" ++ safeKey name
    QueryIntAdd base offset -> queryIntKey base ++ "+" ++ P.show offset

queryMatches :: Query -> C.Facts -> Maybe QueryBindings
queryMatches query facts =
  case query of
    Query terms -> matchQueryTerms (canonicalTerms terms) facts []

queryBindingValue :: QueryBindings -> P.Int -> P.Int
queryBindingValue bindings fallback =
  case bindings of
    []               -> fallback
    (_name, value):_ -> value

data MatchBinding =
  MatchBinding P.String P.String
  deriving (P.Eq, P.Show)

type MatchBindings = [MatchBinding]

data MatchContext tag = MatchContext
  { matchContextIndex    :: P.Int
  , matchContextPayload  :: C.Payload tag
  , matchContextLabel    :: C.PayloadView
  , matchContextBindings :: MatchBindings
  }

matchBinding :: P.String -> P.String -> MatchBinding
matchBinding = MatchBinding

matchBindingValue :: P.String -> MatchBindings -> Maybe P.String
matchBindingValue name bindings =
  case bindings of
    [] -> Nothing
    MatchBinding bindingName bindingValue:rest ->
      case matchBindingValue name rest of
        Just later -> Just later
        Nothing
          | name P.== bindingName -> Just bindingValue
          | otherwise -> Nothing

queryMatchBindings :: QueryBindings -> MatchBindings
queryMatchBindings bindings =
  case bindings of
    [] -> []
    (name, value):rest ->
      MatchBinding name (P.show value) : queryMatchBindings rest

newtype PayloadPattern tag =
  PayloadPattern (C.Payload tag -> C.PayloadView -> Maybe MatchBindings)

payloadPatternMatches ::
     PayloadPattern tag -> C.Payload tag -> C.PayloadView -> Maybe MatchBindings
payloadPatternMatches payloadPattern payload payloadView =
  case payloadPattern of
    PayloadPattern matchPayload -> matchPayload payload payloadView

anyPayloadPattern :: PayloadPattern tag
anyPayloadPattern = PayloadPattern (\_payload _payloadView -> Just [])

payloadBindingPattern :: P.String -> PayloadPattern tag
payloadBindingPattern name =
  PayloadPattern
    (\_payload payloadView ->
       Just [MatchBinding name (C.payloadContent payloadView)])

payloadBoolPattern ::
     (C.Payload tag ~ C.LBool tag) => P.Bool -> PayloadPattern tag
payloadBoolPattern expected =
  PayloadPattern
    (\payload _payloadView ->
       case payload of
         C.LBool actual
           | actual P.== expected -> Just []
           | otherwise -> Nothing)

payloadIntPattern :: (C.Payload tag ~ C.LInt tag) => P.Int -> PayloadPattern tag
payloadIntPattern expected =
  PayloadPattern
    (\payload _payloadView ->
       case payload of
         C.LInt actual
           | actual P.== expected -> Just []
           | otherwise -> Nothing)

payloadDoublePattern ::
     (C.Payload tag ~ C.LDouble tag) => P.Double -> PayloadPattern tag
payloadDoublePattern expected =
  PayloadPattern
    (\payload _payloadView ->
       case payload of
         C.LDouble actual
           | actual P.== expected -> Just []
           | otherwise -> Nothing)

payloadStringPattern ::
     (C.Payload tag ~ C.LString tag) => P.String -> PayloadPattern tag
payloadStringPattern expected =
  PayloadPattern
    (\payload _payloadView ->
       case payload of
         C.LString actual
           | actual P.== expected -> Just []
           | otherwise -> Nothing)

payloadUnitPattern :: (C.Payload tag ~ C.LUnit tag) => () -> PayloadPattern tag
payloadUnitPattern () =
  PayloadPattern
    (\payload _payloadView ->
       case payload of
         C.LUnit -> Just [])

matchQueryTerms ::
     [QueryTerm] -> C.Facts -> QueryBindings -> Maybe QueryBindings
matchQueryTerms terms facts bindings =
  case terms of
    [] -> Just bindings
    term:rest ->
      case matchQueryTerm term (C.factsToList facts) bindings of
        Nothing           -> Nothing
        Just nextBindings -> matchQueryTerms rest facts nextBindings

matchQueryTerm :: QueryTerm -> [C.Fact] -> QueryBindings -> Maybe QueryBindings
matchQueryTerm term facts bindings =
  firstJust (P.map (\fact -> matchQueryFact term fact bindings) facts)

matchQueryFact :: QueryTerm -> C.Fact -> QueryBindings -> Maybe QueryBindings
matchQueryFact term fact bindings =
  case term of
    QueryTerm expectedName expectedValue ->
      case fact of
        C.Fact actualName actualValue
          | expectedName P.== actualName ->
            matchQueryValue expectedValue actualValue bindings
        _ -> Nothing

matchQueryValue ::
     QueryValue -> C.FactValue -> QueryBindings -> Maybe QueryBindings
matchQueryValue expected actual bindings =
  case expected of
    QueryAtom ->
      case actual of
        C.FactAtom -> Just bindings
        _          -> Nothing
    QueryIntValue expectedInt ->
      case actual of
        C.FactInt actualInt -> matchQueryInt expectedInt actualInt bindings
        _                   -> Nothing

matchQueryInt :: QueryInt -> P.Int -> QueryBindings -> Maybe QueryBindings
matchQueryInt intPattern actual bindings =
  case intPattern of
    QueryIntConst expected
      | expected P.== actual -> Just bindings
      | otherwise -> Nothing
    QueryIntVar name -> bindQueryInt name actual bindings
    QueryIntAdd base offset -> matchQueryInt base (actual P.- offset) bindings

bindQueryInt :: P.String -> P.Int -> QueryBindings -> Maybe QueryBindings
bindQueryInt name value bindings =
  case lookupQueryBinding name bindings of
    Nothing -> Just (bindings P.++ [(name, value)])
    Just existing
      | existing P.== value -> Just bindings
      | otherwise -> Nothing

lookupQueryBinding :: P.String -> QueryBindings -> Maybe P.Int
lookupQueryBinding name bindings =
  case bindings of
    [] -> Nothing
    (bindingName, bindingValue):rest
      | name P.== bindingName -> Just bindingValue
      | otherwise -> lookupQueryBinding name rest

firstJust :: [Maybe a] -> Maybe a
firstJust values =
  case values of
    []           -> Nothing
    Nothing:rest -> firstJust rest
    Just value:_ -> Just value

queryTermToFact :: QueryTerm -> C.Fact
queryTermToFact term =
  case term of
    QueryTerm name value ->
      case value of
        QueryAtom -> C.factAtom name
        QueryIntValue intValue ->
          case queryIntConcrete intValue of
            Nothing ->
              P.error ("Cannot materialize non-concrete query term #" P.++ name)
            Just actualValue -> C.factInt name actualValue

queryIntConcrete :: QueryInt -> Maybe P.Int
queryIntConcrete value =
  case value of
    QueryIntConst actualValue -> Just actualValue
    QueryIntVar _ -> Nothing
    QueryIntAdd base offset ->
      case queryIntConcrete base of
        Nothing          -> Nothing
        Just actualValue -> Just (actualValue P.+ offset)

canonicalTerms :: [QueryTerm] -> [QueryTerm]
canonicalTerms terms = dedupeTerms (sortTerms terms)

sortTerms :: [QueryTerm] -> [QueryTerm]
sortTerms terms =
  case terms of
    [] -> []
    term:rest ->
      sortTerms [x | x <- rest, x P.<= term]
        P.++ [term]
        P.++ sortTerms [x | x <- rest, x P.> term]

dedupeTerms :: [QueryTerm] -> [QueryTerm]
dedupeTerms terms =
  case terms of
    [] -> []
    term:rest
      {- HLINT ignore "Use if" -}
     ->
      case term `P.elem` rest of
        True  -> dedupeTerms rest
        False -> term : dedupeTerms rest

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

data NodeSelection
  = TraceSelection Query
  | VirtualSelection P.String Query
  deriving (P.Eq, P.Show)

data ConstraintStrength
  = EnsureConstraint
  | EncourageConstraint
  deriving (P.Eq, P.Show)

data LayoutRelation
  = LayoutEqual
  | LayoutLessOrEqual
  deriving (P.Eq, P.Show)

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

data ValueEndpoint
  = RawValueEndpoint ValueComponent
  | SelectionValueEndpoint NodeSelection ValueAccess

data MatchSpec =
  MatchSpec [NodeRule] [LayoutRule] [VirtualRule]

data NodeRule where
  QueryNodeRule
    :: C.Traceable tag=> Proxy tag
    -> Query
    -> PayloadPattern tag
    -> (MatchContext tag -> NodePatch)
    -> NodeRule
  AnyQueryNodeRule :: Query -> (MatchBindings -> NodePatch) -> NodeRule

data LayoutRule where
  ValueRelationLayout
    :: ConstraintStrength
    -> [ValueEndpoint]
    -> LayoutRelation
    -> [ValueEndpoint]
    -> LayoutRule
  ValueDirectedBridgeLayout
    :: ConstraintStrength
    -> [ValueEndpoint]
    -> [ValueEndpoint]
    -> [ValueEndpoint]
    -> LayoutRule
  ValueSymmetricBridgeLayout
    :: ConstraintStrength
    -> [ValueEndpoint]
    -> [ValueEndpoint]
    -> [ValueEndpoint]
    -> LayoutRule

data VirtualRule =
  VirtualRule P.String Query NodePatch

emptyMatchSpec :: MatchSpec
emptyMatchSpec = MatchSpec [] [] []

matchSpecAppend :: MatchSpec -> MatchSpec -> MatchSpec
matchSpecAppend lhs rhs =
  case lhs of
    MatchSpec leftNodes leftLayouts leftVirtuals ->
      case rhs of
        MatchSpec rightNodes rightLayouts rightVirtuals ->
          MatchSpec
            (leftNodes P.++ rightNodes)
            (leftLayouts P.++ rightLayouts)
            (leftVirtuals P.++ rightVirtuals)

matchQueryNode ::
     forall tag. C.Traceable tag
  => Query
  -> (MatchContext tag -> NodePatch)
  -> MatchSpec
matchQueryNode query makePatch =
  MatchSpec
    [QueryNodeRule (Proxy :: Proxy tag) query anyPayloadPattern makePatch]
    []
    []

matchAnyQueryNode :: Query -> (MatchBindings -> NodePatch) -> MatchSpec
matchAnyQueryNode query makePatch =
  MatchSpec [AnyQueryNodeRule query makePatch] [] []

matchQueryPayloadNode ::
     forall tag. C.Traceable tag
  => Query
  -> PayloadPattern tag
  -> (MatchContext tag -> NodePatch)
  -> MatchSpec
matchQueryPayloadNode query payloadPattern makePatch =
  MatchSpec
    [QueryNodeRule (Proxy :: Proxy tag) query payloadPattern makePatch]
    []
    []

matchVirtualNode :: P.String -> Query -> NodePatch -> MatchSpec
matchVirtualNode key query patch =
  MatchSpec [] [] [VirtualRule (safeKey key) query patch]

rawValueEndpoint :: ValueComponent -> ValueEndpoint
rawValueEndpoint = RawValueEndpoint

selectionValueEndpoint :: NodeSelection -> ValueAccess -> ValueEndpoint
selectionValueEndpoint = SelectionValueEndpoint

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

matchValueRelation ::
     ConstraintStrength
  -> [ValueEndpoint]
  -> LayoutRelation
  -> [ValueEndpoint]
  -> MatchSpec
matchValueRelation strength lhs relation rhs =
  MatchSpec [] [ValueRelationLayout strength lhs relation rhs] []

matchValueDirectedBridge ::
     ConstraintStrength
  -> [ValueEndpoint]
  -> [ValueEndpoint]
  -> [ValueEndpoint]
  -> MatchSpec
matchValueDirectedBridge strength lhs gap rhs =
  MatchSpec [] [ValueDirectedBridgeLayout strength lhs gap rhs] []

matchValueSymmetricBridge ::
     ConstraintStrength
  -> [ValueEndpoint]
  -> [ValueEndpoint]
  -> [ValueEndpoint]
  -> MatchSpec
matchValueSymmetricBridge strength lhs delta rhs =
  MatchSpec [] [ValueSymmetricBridgeLayout strength lhs delta rhs] []

--------------------------------------------------------------------------------
-- Block views
--------------------------------------------------------------------------------
data BlockView tag = BlockView
  { blockRef         :: ViewRef tag
  , blockPayload     :: C.Payload tag
  , blockPayloadView :: C.PayloadView
  , blockLabel       :: ViewLabel
  , blockContent     :: ContentMode
  , blockFacts       :: C.Facts
  , blockTags        :: ViewTags
  , blockNodeKey     :: P.String
  , blockPieceKey    :: P.String
  , blockStyle       :: Style
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
  , viewMatchSpec     :: MatchSpec
  }

defaultViewEnv :: ViewEnv
defaultViewEnv =
  ViewEnv
    { canvasWidthValue = 800
    , canvasHeightValue = 600
    , canvasWidth = num 800
    , canvasHeight = num 600
    , viewMatchSpec = emptyMatchSpec
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

data ViewState where
  ViewState :: Ur ViewEnv %1 -> Ur ViewOutput %1 -> ViewState

type ViewBuilder a = State ViewState a

data ViewScript acts where
  ViewScript :: ViewOutput -> ViewScript acts

instance Consumable ViewState where
  consume (ViewState env output) = consume env `lseq` consume output

instance Dupable ViewState where
  dup2 (ViewState env output) =
    case dup2 env of
      (env1, env2) ->
        case dup2 output of
          (output1, output2) -> (ViewState env1 output1, ViewState env2 output2)

runViewBuilderWithOutput ::
     ViewEnv -> ViewOutput -> ViewBuilder a -> (a, ViewOutput)
runViewBuilderWithOutput env initialOutput builder =
  let (result, ViewState _ (Ur output)) =
        runState builder (ViewState (Ur env) (Ur initialOutput))
   in (result, output)

matchedBlockOutput ::
     C.Traceable tag => MatchSpec -> BlockView tag -> ViewOutput
matchedBlockOutput spec block =
  let (_result, output) =
        runViewBuilderWithOutput
          defaultViewEnv {viewMatchSpec = spec}
          mempty
          (defineMatchedBlock block)
   in output

askViewEnv :: ViewBuilder (Ur ViewEnv)
askViewEnv = do
  ViewState (Ur env) output <- get
  put (ViewState (Ur env) output)
  return (Ur env)

tellOutput :: ViewOutput -> ViewBuilder ()
tellOutput newOutput = do
  ViewState env (Ur oldOutput) <- get
  put (ViewState env (Ur (oldOutput <> newOutput)))

traverseView_ :: (a -> ViewBuilder ()) -> [a] -> ViewBuilder ()
traverseView_ action values =
  case values of
    [] -> return ()
    value:rest -> do
      action value
      traverseView_ action rest

ensureRaw :: Constraint -> ViewBuilder ()
ensureRaw constraint = tellOutput mempty {emittedConstraints = [constraint]}

emitViewNode :: ViewNode -> ViewBuilder ()
emitViewNode node = tellOutput mempty {emittedNodes = [node]}

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
defineMatchedBlock ::
     forall tag. C.Traceable tag
  => BlockView tag
  -> ViewBuilder ()
defineMatchedBlock block = do
  Ur env <- askViewEnv
  case viewMatchSpec env of
    MatchSpec nodeRules _ _ ->
      case matchedNodePatch block nodeRules of
        Nothing    -> return ()
        Just patch -> definePatchedBlock patch block

matchedNodePatch ::
     forall tag. C.Traceable tag
  => BlockView tag
  -> [NodeRule]
  -> Maybe NodePatch
matchedNodePatch block rules =
  foldNodePatches (matchingNodePatches 0 block rules)

matchingNodePatches ::
     forall tag. C.Traceable tag
  => P.Int
  -> BlockView tag
  -> [NodeRule]
  -> [NodePatch]
matchingNodePatches _ _ [] = []
matchingNodePatches matchIndex block (rule:rest) =
  case nodeRulePatch matchIndex block rule of
    Nothing    -> matchingNodePatches matchIndex block rest
    Just patch -> patch : matchingNodePatches (matchIndex P.+ 1) block rest

nodeRulePatch ::
     forall sourceTag. C.Traceable sourceTag
  => P.Int
  -> BlockView sourceTag
  -> NodeRule
  -> Maybe NodePatch
nodeRulePatch matchIndex block rule =
  case rule of
    AnyQueryNodeRule query makePatch ->
      case queryMatches query (blockFacts block) of
        Nothing       -> Nothing
        Just bindings -> Just (makePatch (queryMatchBindings bindings))
    QueryNodeRule (_ :: Proxy matchedTag) query payloadPattern makePatch ->
      case eqT @sourceTag @matchedTag of
        Nothing -> Nothing
        Just Refl ->
          case queryMatches query (blockFacts block) of
            Nothing -> Nothing
            Just bindings ->
              matchedPayloadNodePatch
                matchIndex
                (queryMatchBindings bindings)
                block
                payloadPattern
                makePatch

matchedPayloadNodePatch ::
     P.Int
  -> MatchBindings
  -> BlockView tag
  -> PayloadPattern tag
  -> (MatchContext tag -> NodePatch)
  -> Maybe NodePatch
matchedPayloadNodePatch matchIndex factBindings block payloadPattern makePatch =
  case payloadPatternMatches
         payloadPattern
         (blockPayload block)
         (blockPayloadView block) of
    Nothing -> Nothing
    Just payloadBindings ->
      Just
        (makePatch
           (MatchContext
              { matchContextIndex = matchIndex
              , matchContextPayload = blockPayload block
              , matchContextLabel = blockPayloadView block
              , matchContextBindings = factBindings P.++ payloadBindings
              }))

foldNodePatches :: [NodePatch] -> Maybe NodePatch
foldNodePatches patches =
  case patches of
    []         -> Nothing
    patch:rest -> Just (foldNodePatchesFrom patch rest)

foldNodePatchesFrom :: NodePatch -> [NodePatch] -> NodePatch
foldNodePatchesFrom current patches =
  case patches of
    []         -> current
    patch:rest -> foldNodePatchesFrom (appendNodePatch current patch) rest

definePatchedBlock :: NodePatch -> BlockView tag -> ViewBuilder ()
definePatchedBlock patch block0 = do
  Ur env <- askViewEnv
  let block =
        block0
          { blockStyle = nodePatchStyleUpdate patch (blockStyle block0)
          , blockContent =
              case nodePatchContent patch of
                Nothing      -> blockContent block0
                Just content -> content
          }
  constrainStyle (blockStyle block)
  ensureRaw (right block S.@<=@ canvasWidth env)
  ensureRaw (bottom block S.@<=@ canvasHeight env)
  constrainPatchGeometry patch block
  emitViewNode (BlockViewNode block)
  return ()

constrainPatchGeometry :: NodePatch -> BlockView tag -> ViewBuilder ()
constrainPatchGeometry patch block = do
  constrainMaybePin (left block) (nodePatchLeft patch)
  constrainMaybePin (top block) (nodePatchTop patch)
  constrainMaybePin (width block) (nodePatchWidth patch)
  constrainMaybePin (height block) (nodePatchHeight patch)
  constrainMaybePin (right block) (nodePatchRight patch)
  constrainMaybePin (bottom block) (nodePatchBottom patch)
  constrainMaybePin (centerX block) (nodePatchX patch)
  constrainMaybePin (centerY block) (nodePatchY patch)

constrainMaybePin :: LayoutExpr -> Maybe LayoutPin -> ViewBuilder ()
constrainMaybePin expr maybePin =
  case maybePin of
    Nothing -> return ()
    Just pin ->
      case pin of
        LayoutPin target constraints ->
          ensureRaw (S.allOf (constraints P.++ [expr S.@==@ target]))

--------------------------------------------------------------------------------
-- Build a view graph
--------------------------------------------------------------------------------
buildCSP :: MatchSpec -> E.TraceGraphWith ViewScript -> ViewGraph
buildCSP spec coreGraph =
  let steps = E.traceGraphSteps coreGraph
      stepsOutput = viewTraceSteps steps
      traceNodes = materializeNodesForSpec spec (builtNodes stepsOutput)
      virtualNodes =
        materializeNodesForSpec spec (virtualNodesForSpec spec traceNodes)
      nodes = materializeNodesForSpec spec (traceNodes P.++ virtualNodes)
      viewSteps' = builtSteps stepsOutput
      virtualConstraints = P.concatMap virtualNodeConstraints nodes
      -- Block styles are first registered while building trace steps. Layout
      -- rules can later materialize optional style fields, so collect style
      -- constraints again after materialization.
      nodeStyleConstraints = P.concatMap viewNodeStyleConstraints nodes
      nodeRangeConstraints =
        P.concatMap (viewNodeRangeConstraints defaultViewEnv) nodes
      constraints =
        builtConstraints stepsOutput
          P.++ nodeStyleConstraints
          P.++ nodeRangeConstraints
          P.++ virtualConstraints
          P.++ matchSpecConstraints spec nodes
      renderFrames =
        addVirtualRenderFrames virtualNodes (builtRenderFrames stepsOutput)
   in ViewGraph
        { viewNodes = nodes
        , viewSteps = viewSteps'
        , viewConstraints = constraints
        , viewRenderFrames = renderFrames
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

matchSpecConstraints :: MatchSpec -> [ViewNode] -> [Constraint]
matchSpecConstraints spec nodes =
  case spec of
    MatchSpec _ layoutRules _ ->
      P.concatMap (layoutRuleConstraints nodes) layoutRules

viewNodeBlocks :: [ViewNode] -> [AnyBlockView]
viewNodeBlocks nodes =
  case nodes of
    [] -> []
    node:rest ->
      case node of
        BlockViewNode block -> AnyBlockView block : viewNodeBlocks rest
        VirtualViewNode _   -> viewNodeBlocks rest

layoutRuleConstraints :: [ViewNode] -> LayoutRule -> [Constraint]
layoutRuleConstraints nodes layoutRule =
  case layoutRule of
    ValueRelationLayout strength lhs relation rhs ->
      applyConstraintStrength
        strength
        (P.concatMap
           (valueRelationConstraints relation)
           (matchingValueTerms lhs rhs nodes))
    ValueDirectedBridgeLayout strength lhs gap rhs ->
      applyConstraintStrength
        strength
        (P.concatMap
           valueDirectedBridgeConstraints
           (matchingValueTermTriples lhs gap rhs nodes))
    ValueSymmetricBridgeLayout strength lhs delta rhs ->
      applyConstraintStrength
        strength
        (P.concatMap
           valueSymmetricBridgeConstraints
           (matchingValueTermTriples lhs delta rhs nodes))

applyConstraintStrength :: ConstraintStrength -> [Constraint] -> [Constraint]
applyConstraintStrength strength constraints =
  case strength of
    EnsureConstraint    -> constraints
    EncourageConstraint -> P.map S.soften constraints

data LayoutEndpointMatch =
  LayoutEndpointMatch ValueComponent QueryBindings

matchingValueTerms ::
     [ValueEndpoint]
  -> [ValueEndpoint]
  -> [ViewNode]
  -> [([ValueComponent], [ValueComponent])]
matchingValueTerms lhs rhs nodes =
  [ (lhsComponents, rhsComponents)
  | ([lhsComponents, rhsComponents], _) <-
      matchingValueTermGroups [lhs, rhs] nodes
  ]

matchingValueTermTriples ::
     [ValueEndpoint]
  -> [ValueEndpoint]
  -> [ValueEndpoint]
  -> [ViewNode]
  -> [([ValueComponent], [ValueComponent], [ValueComponent])]
matchingValueTermTriples first second third nodes =
  [ (firstComponents, secondComponents, thirdComponents)
  | ([firstComponents, secondComponents, thirdComponents], _) <-
      matchingValueTermGroups [first, second, third] nodes
  ]

matchingValueTermGroups ::
     [[ValueEndpoint]] -> [ViewNode] -> [([[ValueComponent]], QueryBindings)]
matchingValueTermGroups endpointGroups nodes =
  case endpointGroups of
    [] -> [([], [])]
    endpoints:rest ->
      [ (components : restComponents, mergedBindings)
      | (components, bindings) <- matchingValueTerm endpoints nodes
      , (restComponents, restBindings) <- matchingValueTermGroups rest nodes
      , Just mergedBindings <- [mergeQueryBindings bindings restBindings]
      ]

matchingValueTerm ::
     [ValueEndpoint] -> [ViewNode] -> [([ValueComponent], QueryBindings)]
matchingValueTerm endpoints nodes =
  case endpoints of
    [] -> [([], [])]
    endpoint:rest ->
      [ (component : restComponents, mergedBindings)
      | LayoutEndpointMatch component bindings <-
          matchingEndpointNodes endpoint nodes
      , (restComponents, restBindings) <- matchingValueTerm rest nodes
      , Just mergedBindings <- [mergeQueryBindings bindings restBindings]
      ]

matchingEndpointNodes :: ValueEndpoint -> [ViewNode] -> [LayoutEndpointMatch]
matchingEndpointNodes endpoint nodes =
  case endpoint of
    RawValueEndpoint component -> [LayoutEndpointMatch component []]
    SelectionValueEndpoint selection access ->
      [ LayoutEndpointMatch (valueAccessComponent access node) bindings
      | (node, bindings) <- matchingSelectionNodes selection nodes
      ]

matchingSelectionNodes ::
     NodeSelection -> [ViewNode] -> [(AnyLayoutView, QueryBindings)]
matchingSelectionNodes selection nodes =
  case nodes of
    [] -> []
    node:rest ->
      selectionNodeMatches selection node
        P.++ matchingSelectionNodes selection rest

selectionNodeMatches ::
     NodeSelection -> ViewNode -> [(AnyLayoutView, QueryBindings)]
selectionNodeMatches selection node =
  case selection of
    TraceSelection query ->
      case node of
        BlockViewNode block ->
          case queryMatches query (blockFacts block) of
            Nothing       -> []
            Just bindings -> [(AnyLayoutBlock block, bindings)]
        VirtualViewNode _ -> []
    VirtualSelection key query ->
      case node of
        BlockViewNode _ -> []
        VirtualViewNode virtual
          | key P.== virtualNodeKey virtual
              P.&& queryKey query P.== virtualQueryKey virtual ->
            [(AnyLayoutVirtual virtual, [])]
          | otherwise -> []

anyBlockQueryMatches :: Query -> AnyBlockView -> [(AnyBlockView, QueryBindings)]
anyBlockQueryMatches query anyBlock =
  case anyBlock of
    AnyBlockView block ->
      case queryMatches query (blockFacts block) of
        Nothing       -> []
        Just bindings -> [(anyBlock, bindings)]

mergeQueryBindings :: QueryBindings -> QueryBindings -> Maybe QueryBindings
mergeQueryBindings lhs rhs =
  case rhs of
    [] -> Just lhs
    (name, value):rest ->
      case bindQueryInt name value lhs of
        Nothing     -> Nothing
        Just merged -> mergeQueryBindings merged rest

valueRelationConstraints ::
     LayoutRelation -> ([ValueComponent], [ValueComponent]) -> [Constraint]
valueRelationConstraints relation pair' =
  case pair' of
    (lhsComponents, rhsComponents) ->
      S.relateComponents (termRelation relation) lhsComponents rhsComponents

termRelation :: LayoutRelation -> S.ComponentRelation
termRelation relation =
  case relation of
    LayoutEqual       -> S.ComponentEqual
    LayoutLessOrEqual -> S.ComponentLessOrEqual

valueDirectedBridgeConstraints ::
     ([ValueComponent], [ValueComponent], [ValueComponent]) -> [Constraint]
valueDirectedBridgeConstraints triple =
  case triple of
    (lhsComponents, gapComponents, rhsComponents) ->
      S.directedBridgeComponents lhsComponents gapComponents rhsComponents

valueSymmetricBridgeConstraints ::
     ([ValueComponent], [ValueComponent], [ValueComponent]) -> [Constraint]
valueSymmetricBridgeConstraints triple =
  case triple of
    (lhsComponents, deltaComponents, rhsComponents) ->
      S.symmetricBridgeComponents lhsComponents deltaComponents rhsComponents

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

materializeNodesForSpec :: MatchSpec -> [ViewNode] -> [ViewNode]
materializeNodesForSpec spec nodes =
  case spec of
    MatchSpec _ layoutRules _ ->
      P.map (materializeNodeForRules layoutRules) nodes

materializeNodeForRules :: [LayoutRule] -> ViewNode -> ViewNode
materializeNodeForRules rules node =
  case rules of
    []        -> node
    rule:rest -> materializeNodeForRules rest (materializeNodeForRule rule node)

materializeNodeForRule :: LayoutRule -> ViewNode -> ViewNode
materializeNodeForRule rule node =
  case rule of
    ValueRelationLayout _ lhs _ rhs ->
      materializeNodeForEndpoints (lhs P.++ rhs) node
    ValueDirectedBridgeLayout _ lhs gap rhs ->
      materializeNodeForEndpoints (lhs P.++ gap P.++ rhs) node
    ValueSymmetricBridgeLayout _ lhs delta rhs ->
      materializeNodeForEndpoints (lhs P.++ delta P.++ rhs) node

materializeNodeForEndpoints :: [ValueEndpoint] -> ViewNode -> ViewNode
materializeNodeForEndpoints endpoints node =
  case endpoints of
    [] -> node
    endpoint:rest ->
      materializeNodeForEndpoints
        rest
        (materializeNodeForEndpoint endpoint node)

materializeNodeForEndpoint :: ValueEndpoint -> ViewNode -> ViewNode
materializeNodeForEndpoint endpoint node =
  case endpoint of
    RawValueEndpoint _ -> node
    SelectionValueEndpoint selection access ->
      case nodeMatchesSelection selection node of
        False -> node
        True ->
          applyStyleMaterializations (valueAccessMaterializations access) node

nodeMatchesSelection :: NodeSelection -> ViewNode -> P.Bool
nodeMatchesSelection selection node =
  case selectionNodeMatches selection node of
    [] -> False
    _  -> True

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

virtualNodesForSpec :: MatchSpec -> [ViewNode] -> [ViewNode]
virtualNodesForSpec spec nodes =
  case spec of
    MatchSpec _ _ virtualRules ->
      maybeVirtualNodes (mergedVirtualRules virtualRules)
  where
    blocks = viewNodeBlocks nodes
    maybeVirtualNodes rules =
      case rules of
        [] -> []
        rule:rest ->
          case virtualNodeForRule blocks rule of
            Nothing   -> maybeVirtualNodes rest
            Just node -> node : maybeVirtualNodes rest

mergedVirtualRules :: [VirtualRule] -> [VirtualRule]
mergedVirtualRules rules =
  case rules of
    [] -> []
    VirtualRule key query patch:rest ->
      case mergeVirtualRule key query patch rest of
        (mergedPatch, remaining) ->
          VirtualRule key query mergedPatch : mergedVirtualRules remaining

mergeVirtualRule ::
     P.String
  -> Query
  -> NodePatch
  -> [VirtualRule]
  -> (NodePatch, [VirtualRule])
mergeVirtualRule key query patch rules =
  case rules of
    [] -> (patch, [])
    VirtualRule nextKey nextQuery nextPatch:rest ->
      case key P.== nextKey P.&& query P.== nextQuery of
        True ->
          mergeVirtualRule key query (appendNodePatch patch nextPatch) rest
        False ->
          case mergeVirtualRule key query patch rest of
            (mergedPatch, remaining) ->
              (mergedPatch, VirtualRule nextKey nextQuery nextPatch : remaining)

virtualNodeForRule :: [AnyBlockView] -> VirtualRule -> Maybe ViewNode
virtualNodeForRule blocks rule =
  case rule of
    VirtualRule key query patch ->
      case matchingQueryBlocks query blocks of
        [] -> Nothing
        children ->
          Just
            (VirtualViewNode
               (virtualViewForRule key query patch children :: VirtualView ()))

matchingQueryBlocks :: Query -> [AnyBlockView] -> [AnyBlockView]
matchingQueryBlocks query blocks =
  [ anyBlock
  | anyBlock <- blocks
  , (_matchedNode, _bindings) <- anyBlockQueryMatches query anyBlock
  ]

virtualViewForRule ::
     P.String -> Query -> NodePatch -> [AnyBlockView] -> VirtualView tag
virtualViewForRule key query patch children =
  let ref = syntheticViewRef (virtualBlockId key query)
      baseStyle = styleForVirtual key query
   in VirtualView
        { virtualRef = ref
        , virtualLabel = ViewLabel ("Virtual." P.++ key) ""
        , virtualContent = Maybe.fromMaybe ContentEmpty (nodePatchContent patch)
        , virtualQueryKey = queryKey query
        , virtualNodeKey = key
        , virtualPieceKey = defaultPieceKey
        , virtualStyle = nodePatchStyleUpdate patch baseStyle
        , virtualPatch = patch
        , virtualChildren = children
        }

virtualBlockId :: P.String -> Query -> P.Int
virtualBlockId key query =
  negate (1 P.+ positiveHash (key P.++ ":" P.++ queryKey query))

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

styleForVirtual :: P.String -> Query -> Style
styleForVirtual key query =
  styleWithBounds
    (Bounds
       (virtualVar key (queryKey query) "top")
       (virtualVar key (queryKey query) "left")
       (virtualVar key (queryKey query) "width")
       (virtualVar key (queryKey query) "height"))

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

data BuiltViewStep = BuiltViewStep
  { stepView                 :: ViewStep
  , stepNodes                :: [ViewNode]
  , stepConstraints          :: [Constraint]
  , stepRenderFrames         :: [[RenderIntent]]
  , stepPendingRenderIntents :: [RenderIntent]
  }

data BuiltViewSteps = BuiltViewSteps
  { builtSteps        :: [ViewStep]
  , builtNodes        :: [ViewNode]
  , builtConstraints  :: [Constraint]
  , builtRenderFrames :: [[RenderIntent]]
  }

viewTraceSteps :: [E.TraceStepWith ViewScript] -> BuiltViewSteps
viewTraceSteps = viewTraceStepsWith viewTraceStep [] [] [] [] []

viewTraceStepsWith ::
     ([RenderIntent] -> record -> BuiltViewStep)
  -> [ViewStep]
  -> [ViewNode]
  -> [Constraint]
  -> [[RenderIntent]]
  -> [RenderIntent]
  -> [record]
  -> BuiltViewSteps
viewTraceStepsWith buildStep steps nodes constraints renderFrames pending records =
  case records of
    [] ->
      let finalOutput =
            flushPendingOutput mempty {pendingRenderIntents = pending}
          finalFrames = renderFrames ++ emittedRenderFrames finalOutput
       in BuiltViewSteps
            { builtSteps = steps
            , builtNodes = nodes
            , builtConstraints = constraints
            , builtRenderFrames = withImplicitInitialFrame finalFrames
            }
    record:rest ->
      let builtStep = buildStep pending record
       in viewTraceStepsWith
            buildStep
            (steps ++ [stepView builtStep])
            (nodes ++ stepNodes builtStep)
            (constraints ++ stepConstraints builtStep)
            (renderFrames ++ stepRenderFrames builtStep)
            (stepPendingRenderIntents builtStep)
            rest

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

viewTraceStep :: [RenderIntent] -> E.TraceStepWith ViewScript -> BuiltViewStep
viewTraceStep pending step =
  case E.traceStepOutput step of
    E.ExplainedTraceStep label (ViewScript rawOutput) _plainStep ->
      let output = mergeInitialRenderIntents pending rawOutput
          nodes = emittedNodes output
          constraints = emittedConstraints output
          renderFrames = emittedRenderFrames output
       in BuiltViewStep
            { stepView = ViewStep label nodes constraints []
            , stepNodes = nodes
            , stepConstraints = constraints
            , stepRenderFrames = renderFrames
            , stepPendingRenderIntents = pendingRenderIntents output
            }
    E.DiscardedTraceStep reason _plainStep ->
      BuiltViewStep
        { stepView = ViewStep ("Discarded: " P.++ reason) [] [] []
        , stepNodes = []
        , stepConstraints = []
        , stepRenderFrames = []
        , stepPendingRenderIntents = pending
        }

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

constrainStyle :: Style -> ViewBuilder ()
constrainStyle style' = traverseView_ ensureRaw (styleConstraints style')
