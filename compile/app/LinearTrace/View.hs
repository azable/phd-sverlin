{-# LANGUAGE AllowAmbiguousTypes    #-}
{-# LANGUAGE DataKinds              #-}
{-# LANGUAGE FlexibleContexts       #-}
{-# LANGUAGE FlexibleInstances      #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE GADTs                  #-}
{-# LANGUAGE LinearTypes            #-}
{-# LANGUAGE RankNTypes             #-}
{-# LANGUAGE RebindableSyntax       #-}
{-# LANGUAGE ScopedTypeVariables    #-}
{-# LANGUAGE TypeApplications       #-}
{-# LANGUAGE TypeFamilies           #-}
{-# LANGUAGE TypeOperators          #-}
{-# LANGUAGE UndecidableInstances   #-}

module LinearTrace.View
  ( -- * View graph
    ViewGraph
  , ViewNode(..)
  , ViewStep(..)
  , BlockView
  , VirtualView
  , blockViewRef
  , blockViewLabel
  , blockViewFacts
  , blockViewNodeKey
  , blockViewPieceKey
  , mapBlockViewStyleExprLeaves
  , solvedBlockViewExprs
  , VisualExplainToken
  , ExplainedVisual
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
  , Pattern(..)
  , PatternTerm(..)
  , PatternValue(..)
  , PatternInt(..)
  , PatternBindings
  , patternAtom
  , patternInt
  , patternIntConst
  , patternIntVar
  , patternIntAdd
  , patternAppend
  , patternKey
  , patternMatches
  , patternBindingValue
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
  , LayoutRelation(..)
  , MatchSpec
  , emptyMatchSpec
  , matchSpecAppend
  , matchPatternNode
  , matchPatternPayloadNode
  , matchVirtualNode
  , matchGlobalLayout
  , matchSelectionRelation
  , matchSelectionBridge
  , Visual
  , Unrendered
  , Rendered
  , Stable
  , Consumed
  , LayoutAttr(..)
  , Available
  , Taken
  , NewVisual
  , LiveVisual
  , ConsumedVisual
  , CopiedVisual
  , BoxAttrs
  , SizeAttrs
  , BoxVisual
  , SizeVisual
  , BoxDefinition
  , SizeDefinition
  , boxDefinition
  , sizeDefinition
  , ViewDefinition(..)
  , LayoutUse(..)
  , OneExpr(..)
  , OneConstraint(..)
  , (|>)
  , StyleDraft
  , EmptyStyleDraft
  , finalizeStyle
  , finalizeStyleWith
  , setOpacityOnce
  , setZIndexOnce
  , setFontSizeOnce
  , setRadiusOnce
  , setFillOnce
  , setStrokeOnce
  , setStrokeWidthOnce
  , setAlphaOnce
  , setFontFamilyOnce
  , setFontWeightOnce
  , setFontStyleOnce
  , setTextAlignOnce
  , setBorderStyleOnce
  , setWhiteSpaceOnce
  , fresh
  , freshMatched
  , freshCopy
  , forkCopy
  , forkCopyMatched
  , continueFrom
  , continueFromMatched
  , completeCopy
  , replaceMatched
  , replaceMatchedOutput
  , remove
  , complete
  , checkpoint
  , takeLeft
  , takeRight
  , takeWidth
  , takeCenterX
  , takeTop
  , takeBottom
  , takeHeight
  , takeCenterY
  , viewNodes
  , viewSteps
  , viewConstraints
  , viewInitialVars
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
    Expr
  , Constraint
  , FreeExpr
  , LayoutExpr
  , UnitExpr
  , AngleExpr
  , Hue
  , HueExpr
  , HslExpr
  , MaterializedHsl
  , global
  , num
  , (@+@)
  , (@-@)
  , (@*@)
  , (@/@)
  , (@^@)
  , absExpr
  , (@==@)
  , (@<=@)
  , (@>=@)
  , -- * Builder
    ViewBuilder
  , ViewScript
  , VisualTraceBuilder
  , VisualTraceGraph
  , visualTraceCore
  , Created(..)
  , Observed(..)
  , Used(..)
  , Copied(..)
  , Replaced(..)
  , Computed(..)
  , Destroyed(..)
  , Sealed(..)
  , Unsealed(..)
  , Decided(..)
  , create
  , createTagged
  , observe
  , use
  , copy
  , copyTagged
  , replace
  , compute
  , computeTagged
  , computeTaggedWith
  , destroy
  , seal
  , unseal
  , decide
  , explainVisual
  , appendTraceView
  , checkpointTrace
  , (==>)
  , explain
  , discard
  , buildGraph
  , buildGraphWithSpec
  , buildCSP
  , solveCSP
  , solveCSPWithSeed
  , RandomSeed(..)
  , ensure
  , encourage
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

import           Control.Functor.Linear                hiding ((<$>), (<*>))
import qualified Control.Functor.Linear.Internal.State as LinearState
import           Data.Kind                             (Type)
import qualified Data.Kind                             as K
import qualified Data.Maybe                            as Maybe
import           Data.Proxy                            (Proxy (..))
import           Data.Type.Equality                    ((:~:) (..))
import           Data.Typeable                         (eqT)
import           GHC.OverloadedLabels                  (IsLabel (..))
import           GHC.TypeLits                          (ErrorMessage (..),
                                                        KnownSymbol, Nat,
                                                        TypeError, type (+),
                                                        type CmpNat)
import qualified LinearTrace.Core.Internal             as C
import           LinearTrace.Solver                    hiding (absExpr, num,
                                                        (@*@), (@+@), (@-@),
                                                        (@/@), (@<=@), (@==@),
                                                        (@>=@), (@^@))
import qualified LinearTrace.Solver                    as S
import           LinearTrace.View.Style
import qualified Prelude                               as P
import           Prelude.Linear
import qualified Unsafe.Coerce                         as Unsafe

--------------------------------------------------------------------------------
-- Semantic queries and visualization matches
--------------------------------------------------------------------------------
data QueryValue
  = QueryAtom
  | QueryInt P.Int
  deriving (P.Eq, P.Ord, P.Show)

data QueryTerm =
  QueryTerm P.String QueryValue
  deriving (P.Eq, P.Ord, P.Show)

newtype Query =
  Query [QueryTerm]
  deriving (P.Eq, P.Ord, P.Show)

emptyQuery :: Query
emptyQuery = Query []

queryAtom :: P.String -> Query
queryAtom name = Query [QueryTerm name QueryAtom]

queryInt :: P.String -> P.Int -> Query
queryInt name value = Query [QueryTerm name (QueryInt value)]

queryAppend :: Query -> Query -> Query
queryAppend lhs rhs =
  case lhs of
    Query leftTerms ->
      case rhs of
        Query rightTerms -> Query (canonicalTerms (leftTerms P.++ rightTerms))

instance KnownSymbol name => IsLabel name Query where
  fromLabel = queryAtom (S.labelName (Proxy @name))

instance KnownSymbol name => IsLabel name (P.Int -> Query) where
  fromLabel = queryInt (S.labelName (Proxy @name))

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
        QueryAtom         -> safeKey name
        QueryInt intValue -> safeKey name ++ "-" ++ P.show intValue

queryMatches :: Query -> C.Facts -> P.Bool
queryMatches query facts =
  case query of
    Query terms -> P.all (`factSetContains` facts) terms

data PatternInt
  = PatternIntConst P.Int
  | PatternIntVar P.String
  | PatternIntAdd PatternInt P.Int
  deriving (P.Eq, P.Ord, P.Show)

data PatternValue
  = PatternAtom
  | PatternIntValue PatternInt
  deriving (P.Eq, P.Ord, P.Show)

data PatternTerm =
  PatternTerm P.String PatternValue
  deriving (P.Eq, P.Ord, P.Show)

newtype Pattern =
  Pattern [PatternTerm]
  deriving (P.Eq, P.Ord, P.Show)

type PatternBindings = [(P.String, P.Int)]

patternAtom :: P.String -> Pattern
patternAtom name = Pattern [PatternTerm name PatternAtom]

patternInt :: P.String -> PatternInt -> Pattern
patternInt name value = Pattern [PatternTerm name (PatternIntValue value)]

patternIntConst :: P.Int -> PatternInt
patternIntConst = PatternIntConst

patternIntVar :: P.String -> PatternInt
patternIntVar = PatternIntVar

patternIntAdd :: PatternInt -> P.Int -> PatternInt
patternIntAdd = PatternIntAdd

patternAppend :: Pattern -> Pattern -> Pattern
patternAppend lhs rhs =
  case lhs of
    Pattern leftTerms ->
      case rhs of
        Pattern rightTerms ->
          Pattern (canonicalPatternTerms (leftTerms P.++ rightTerms))

instance KnownSymbol name => IsLabel name Pattern where
  fromLabel = patternAtom (S.labelName (Proxy @name))

instance KnownSymbol name => IsLabel name (PatternInt -> Pattern) where
  fromLabel = patternInt (S.labelName (Proxy @name))

patternKey :: Pattern -> P.String
patternKey pattern' =
  case pattern' of
    Pattern terms ->
      joinPath ("p" : P.map patternTermKey (canonicalPatternTerms terms))

patternTermKey :: PatternTerm -> P.String
patternTermKey term =
  case term of
    PatternTerm name value ->
      case value of
        PatternAtom            -> safeKey name
        PatternIntValue intPat -> safeKey name ++ "-" ++ patternIntKey intPat

patternIntKey :: PatternInt -> P.String
patternIntKey intPattern =
  case intPattern of
    PatternIntConst value     -> P.show value
    PatternIntVar name        -> "$" ++ safeKey name
    PatternIntAdd base offset -> patternIntKey base ++ "+" ++ P.show offset

patternMatches :: Pattern -> C.Facts -> Maybe PatternBindings
patternMatches pattern' facts =
  case pattern' of
    Pattern terms -> matchPatternTerms (canonicalPatternTerms terms) facts []

patternBindingValue :: PatternBindings -> P.Int -> P.Int
patternBindingValue bindings fallback =
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

patternMatchBindings :: PatternBindings -> MatchBindings
patternMatchBindings bindings =
  case bindings of
    [] -> []
    (name, value):rest ->
      MatchBinding name (P.show value) : patternMatchBindings rest

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

matchPatternTerms ::
     [PatternTerm] -> C.Facts -> PatternBindings -> Maybe PatternBindings
matchPatternTerms terms facts bindings =
  case terms of
    [] -> Just bindings
    term:rest ->
      case matchPatternTerm term (C.factsToList facts) bindings of
        Nothing           -> Nothing
        Just nextBindings -> matchPatternTerms rest facts nextBindings

matchPatternTerm ::
     PatternTerm -> [C.Fact] -> PatternBindings -> Maybe PatternBindings
matchPatternTerm term facts bindings =
  firstJust (P.map (\fact -> matchPatternFact term fact bindings) facts)

matchPatternFact ::
     PatternTerm -> C.Fact -> PatternBindings -> Maybe PatternBindings
matchPatternFact term fact bindings =
  case term of
    PatternTerm expectedName expectedValue ->
      case fact of
        C.Fact actualName actualValue
          | expectedName P.== actualName ->
            matchPatternValue expectedValue actualValue bindings
        _ -> Nothing

matchPatternValue ::
     PatternValue -> C.FactValue -> PatternBindings -> Maybe PatternBindings
matchPatternValue expected actual bindings =
  case expected of
    PatternAtom ->
      case actual of
        C.FactAtom -> Just bindings
        _          -> Nothing
    PatternIntValue expectedInt ->
      case actual of
        C.FactInt actualInt -> matchPatternInt expectedInt actualInt bindings
        _                   -> Nothing

matchPatternInt ::
     PatternInt -> P.Int -> PatternBindings -> Maybe PatternBindings
matchPatternInt intPattern actual bindings =
  case intPattern of
    PatternIntConst expected
      | expected P.== actual -> Just bindings
      | otherwise -> Nothing
    PatternIntVar name -> bindPatternInt name actual bindings
    PatternIntAdd base offset ->
      matchPatternInt base (actual P.- offset) bindings

bindPatternInt :: P.String -> P.Int -> PatternBindings -> Maybe PatternBindings
bindPatternInt name value bindings =
  case lookupPatternBinding name bindings of
    Nothing -> Just (bindings P.++ [(name, value)])
    Just existing
      | existing P.== value -> Just bindings
      | otherwise -> Nothing

lookupPatternBinding :: P.String -> PatternBindings -> Maybe P.Int
lookupPatternBinding name bindings =
  case bindings of
    [] -> Nothing
    (bindingName, bindingValue):rest
      | name P.== bindingName -> Just bindingValue
      | otherwise -> lookupPatternBinding name rest

firstJust :: [Maybe a] -> Maybe a
firstJust values =
  case values of
    []           -> Nothing
    Nothing:rest -> firstJust rest
    Just value:_ -> Just value

canonicalPatternTerms :: [PatternTerm] -> [PatternTerm]
canonicalPatternTerms terms = dedupePatternTerms (sortPatternTerms terms)

sortPatternTerms :: [PatternTerm] -> [PatternTerm]
sortPatternTerms terms =
  case terms of
    [] -> []
    term:rest ->
      sortPatternTerms [x | x <- rest, x P.<= term]
        P.++ [term]
        P.++ sortPatternTerms [x | x <- rest, x P.> term]

dedupePatternTerms :: [PatternTerm] -> [PatternTerm]
dedupePatternTerms terms =
  case terms of
    [] -> []
    term:rest
      {- HLINT ignore "Use if" -}
     ->
      case term `P.elem` rest of
        True  -> dedupePatternTerms rest
        False -> term : dedupePatternTerms rest

factSetContains :: QueryTerm -> C.Facts -> P.Bool
factSetContains term facts = queryTermToFact term `P.elem` C.factsToList facts

queryTermToFact :: QueryTerm -> C.Fact
queryTermToFact term =
  case term of
    QueryTerm name value ->
      case value of
        QueryAtom         -> C.factAtom name
        QueryInt intValue -> C.factInt name intValue

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

data ContentMode
  = ContentEmpty
  | ContentText P.String
  deriving (P.Eq, P.Show)

data LayoutPin =
  LayoutPin LayoutExpr [Constraint]

data NodePatch = NodePatch
  { nodePatchStyleUpdate  :: Style -> Style
  , nodePatchContent      :: Maybe ContentMode
  , nodePatchLeft         :: Maybe LayoutPin
  , nodePatchTop          :: Maybe LayoutPin
  , nodePatchWidth        :: Maybe LayoutPin
  , nodePatchHeight       :: Maybe LayoutPin
  , nodePatchRight        :: Maybe LayoutPin
  , nodePatchBottom       :: Maybe LayoutPin
  , nodePatchX            :: Maybe LayoutPin
  , nodePatchY            :: Maybe LayoutPin
  , nodePatchRequirements :: [ViewBuilder ()]
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
    , nodePatchRequirements = []
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
    , nodePatchRequirements =
        nodePatchRequirements first P.++ nodePatchRequirements second
    }

composeStyleUpdates :: (Style -> Style) -> (Style -> Style) -> Style -> Style
composeStyleUpdates first second style0 = second (first style0)

preferLater :: Maybe a -> Maybe a -> Maybe a
preferLater earlier later =
  case later of
    Nothing -> earlier
    Just _  -> later

data NodeSelection
  = TraceSelection Pattern
  | VirtualSelection P.String Pattern
  deriving (P.Eq, P.Show)

data LayoutRelation
  = LayoutEqual
  | LayoutLessOrEqual
  deriving (P.Eq, P.Show)

data MatchSpec =
  MatchSpec [NodeRule] [LayoutRule] [VirtualRule]

data NodeRule where
  PatternNodeRule
    :: C.Traceable tag=> Proxy tag
    -> Pattern
    -> PayloadPattern tag
    -> (MatchContext tag -> NodePatch)
    -> NodeRule

data LayoutRule where
  GlobalLayout :: ViewBuilder () -> LayoutRule
  SelectionRelationLayout
    :: NodeSelection
    -> LayoutAttr
    -> LayoutRelation
    -> NodeSelection
    -> LayoutAttr
    -> LayoutRule
  SelectionBridgeLayout
    :: NodeSelection
    -> LayoutAttr
    -> LayoutRelation
    -> LayoutExpr
    -> [Constraint]
    -> LayoutRelation
    -> NodeSelection
    -> LayoutAttr
    -> LayoutRule

data VirtualRule =
  VirtualRule P.String Pattern NodePatch

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

matchPatternNode ::
     forall tag. C.Traceable tag
  => Pattern
  -> (MatchContext tag -> NodePatch)
  -> MatchSpec
matchPatternNode pattern' makePatch =
  MatchSpec
    [PatternNodeRule (Proxy :: Proxy tag) pattern' anyPayloadPattern makePatch]
    []
    []

matchPatternPayloadNode ::
     forall tag. C.Traceable tag
  => Pattern
  -> PayloadPattern tag
  -> (MatchContext tag -> NodePatch)
  -> MatchSpec
matchPatternPayloadNode pattern' payloadPattern makePatch =
  MatchSpec
    [PatternNodeRule (Proxy :: Proxy tag) pattern' payloadPattern makePatch]
    []
    []

matchVirtualNode :: P.String -> Pattern -> NodePatch -> MatchSpec
matchVirtualNode key pattern' patch =
  MatchSpec [] [] [VirtualRule (safeKey key) pattern' patch]

matchGlobalLayout :: ViewBuilder () -> MatchSpec
matchGlobalLayout body = MatchSpec [] [GlobalLayout body] []

matchSelectionRelation ::
     NodeSelection
  -> LayoutAttr
  -> LayoutRelation
  -> NodeSelection
  -> LayoutAttr
  -> MatchSpec
matchSelectionRelation lhs lhsAttr relation rhs rhsAttr =
  MatchSpec [] [SelectionRelationLayout lhs lhsAttr relation rhs rhsAttr] []

matchSelectionBridge ::
     NodeSelection
  -> LayoutAttr
  -> LayoutRelation
  -> LayoutExpr
  -> [Constraint]
  -> LayoutRelation
  -> NodeSelection
  -> LayoutAttr
  -> MatchSpec
matchSelectionBridge lhs lhsAttr lhsRelation gap gapConstraints rhsRelation rhs rhsAttr =
  MatchSpec
    []
    [ SelectionBridgeLayout
        lhs
        lhsAttr
        lhsRelation
        gap
        gapConstraints
        rhsRelation
        rhs
        rhsAttr
    ]
    []

--------------------------------------------------------------------------------
-- Block views
--------------------------------------------------------------------------------
data BlockView tag = BlockView
  { blockRef      :: C.BlockRef tag
  , blockPayload  :: C.Payload tag
  , blockLabel    :: C.PayloadView
  , blockContent  :: ContentMode
  , blockFacts    :: C.Facts
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
  { virtualRef      :: C.BlockRef tag
  , virtualLabel    :: C.PayloadView
  , virtualContent  :: ContentMode
  , virtualPattern  :: Pattern
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
    :: C.TraceStep -> [ViewNode] -> [Constraint] -> [[RenderIntent]] -> ViewStep

data ViewGraph = ViewGraph
  { viewNodes        :: [ViewNode]
  , viewSteps        :: [ViewStep]
  , viewConstraints  :: [Constraint]
  , viewInitialVars  :: [InitialVar]
  , viewRenderFrames :: [[RenderIntent]]
  }

--------------------------------------------------------------------------------
-- Materialized views
--------------------------------------------------------------------------------
data MaterializedBlockView tag = MaterializedBlockView
  { materializedBlockRef      :: C.BlockRef tag
  , materializedBlockLabel    :: C.PayloadView
  , materializedBlockContent  :: P.String
  , materializedBlockNodeKey  :: P.String
  , materializedBlockPieceKey :: P.String
  , materializedBlockStyle    :: MaterializedStyle
  }

data MaterializedVirtualView tag = MaterializedVirtualView
  { materializedVirtualRef      :: C.BlockRef tag
  , materializedVirtualLabel    :: C.PayloadView
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

blockViewRef :: BlockView tag -> C.BlockRef tag
blockViewRef = blockRef

blockViewLabel :: BlockView tag -> C.PayloadView
blockViewLabel = blockLabel

blockViewFacts :: BlockView tag -> C.Facts
blockViewFacts = blockFacts

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

--------------------------------------------------------------------------------
-- Linear view tokens
--------------------------------------------------------------------------------
data ViewToken act where
  CreatedToken :: BlockView tag -> ViewToken (C.Create tag)
  ObservedToken :: BlockView tag -> ViewToken (C.Observe tag)
  UsedToken :: BlockView tag -> ViewToken (C.Use tag)
  CopiedToken :: BlockView tag -> BlockView tag -> ViewToken (C.Copy tag)
  ReplacedToken
    :: BlockView tag
    -> BlockView tag
    -> BlockView tag
    -> ViewToken (C.Replace tag)
  ComputedToken :: BlockView tag -> ViewToken (C.Compute tag)
  DestroyedToken :: BlockView tag -> ViewToken (C.Destroy tag)
  SealedToken
    :: BlockView owner -> BlockView tag -> ViewToken (C.Seal owner tag)
  UnsealedToken
    :: BlockView owner -> BlockView tag -> ViewToken (C.Unseal owner tag)
  DecidedToken :: BlockView tag -> ViewToken (C.Decide tag)

type family ExplainedVisual act :: Type where
  ExplainedVisual (C.Create tag) = NewVisual tag
  ExplainedVisual (C.Observe tag) = LiveVisual tag
  ExplainedVisual (C.Use tag) = ConsumedVisual tag
  ExplainedVisual (C.Copy tag) = CopiedVisual tag
  ExplainedVisual (C.Replace tag) = ( ConsumedVisual tag
                                    , ConsumedVisual tag
                                    , NewVisual tag)
  ExplainedVisual (C.Compute tag) = NewVisual tag
  ExplainedVisual (C.Destroy tag) = ConsumedVisual tag
  ExplainedVisual (C.Seal owner tag) = (LiveVisual owner, LiveVisual tag)
  ExplainedVisual (C.Unseal owner tag) = (LiveVisual owner, LiveVisual tag)
  ExplainedVisual (C.Decide tag) = ConsumedVisual tag

data VisualExplainToken act where
  VisualExplainToken :: ExplainedVisual act %1 -> VisualExplainToken act

data Created tag where
  Created
    :: C.Block tag %1 -> VisualExplainToken (C.Create tag) %1 -> Created tag

data Observed tag where
  Observed
    :: C.Block tag %1 -> VisualExplainToken (C.Observe tag) %1 -> Observed tag

data Used tag where
  Used
    :: C.OneUse (C.Payload tag)
       %1 -> VisualExplainToken (C.Use tag)
       %1 -> Used tag

data Copied tag where
  Copied
    :: C.Block tag
       %1 -> C.Block tag
       %1 -> VisualExplainToken (C.Copy tag)
       %1 -> Copied tag

data Replaced tag where
  Replaced
    :: C.Block tag %1 -> VisualExplainToken (C.Replace tag) %1 -> Replaced tag

data Computed tag where
  Computed
    :: C.Block tag %1 -> VisualExplainToken (C.Compute tag) %1 -> Computed tag

data Destroyed tag where
  Destroyed :: VisualExplainToken (C.Destroy tag) %1 -> Destroyed tag

data Sealed owner tag where
  Sealed
    :: C.Block owner
       %1 -> C.Slot owner tag
       %1 -> VisualExplainToken (C.Seal owner tag)
       %1 -> Sealed owner tag

data Unsealed owner tag where
  Unsealed
    :: C.Block owner
       %1 -> C.Block tag
       %1 -> VisualExplainToken (C.Unseal owner tag)
       %1 -> Unsealed owner tag

data Decided tag where
  DecidedTrue :: VisualExplainToken (C.Decide tag) %1 -> Decided tag
  DecidedFalse :: VisualExplainToken (C.Decide tag) %1 -> Decided tag

data RenderIntent where
  RenderFresh :: C.BlockRef tag -> RenderIntent
  RenderContinue :: C.BlockRef old -> C.BlockRef tag -> RenderIntent
  RenderFork :: C.BlockRef old -> C.BlockRef tag -> RenderIntent
  RenderRemove :: C.BlockRef tag -> RenderIntent

data Unrendered

data Rendered

data Stable

data Consumed

data Available

data Taken

data LayoutAttr
  = AttrLeft
  | AttrRight
  | AttrWidth
  | AttrCenterX
  | AttrTop
  | AttrBottom
  | AttrHeight
  | AttrCenterY

data Axis
  = XAxis
  | YAxis

type family AttrRank (attr :: LayoutAttr) :: Nat where
  AttrRank AttrLeft = 0
  AttrRank AttrRight = 1
  AttrRank AttrWidth = 2
  AttrRank AttrCenterX = 3
  AttrRank AttrTop = 4
  AttrRank AttrBottom = 5
  AttrRank AttrHeight = 6
  AttrRank AttrCenterY = 7

type family Insert (attr :: LayoutAttr) (used :: [LayoutAttr]) :: [LayoutAttr] where
  Insert attr '[] = '[ attr]
  Insert attr (current : rest) = InsertByRank
    (CmpNat (AttrRank attr) (AttrRank current))
    attr
    current
    rest

type family InsertByRank (ordering :: Ordering) (attr :: LayoutAttr) (current :: LayoutAttr) (rest :: [LayoutAttr]) :: [LayoutAttr] where
  InsertByRank 'LT attr current rest = attr : current : rest
  InsertByRank 'EQ attr current rest = current : rest
  InsertByRank 'GT attr current rest = current : Insert attr rest

type family AttrEq (lhs :: LayoutAttr) (rhs :: LayoutAttr) :: Bool where
  AttrEq AttrLeft AttrLeft = 'True
  AttrEq AttrRight AttrRight = 'True
  AttrEq AttrWidth AttrWidth = 'True
  AttrEq AttrCenterX AttrCenterX = 'True
  AttrEq AttrTop AttrTop = 'True
  AttrEq AttrBottom AttrBottom = 'True
  AttrEq AttrHeight AttrHeight = 'True
  AttrEq AttrCenterY AttrCenterY = 'True
  AttrEq _ _ = 'False

type family MemberAttr (attr :: LayoutAttr) (used :: [LayoutAttr]) :: Bool where
  MemberAttr attr '[] = 'False
  MemberAttr attr (current : rest) = MemberAttrStep
    (AttrEq attr current)
    attr
    rest

type family MemberAttrStep (found :: Bool) (attr :: LayoutAttr) (rest :: [LayoutAttr]) :: Bool where
  MemberAttrStep 'True attr rest = 'True
  MemberAttrStep 'False attr rest = MemberAttr attr rest

type family AxisOf (attr :: LayoutAttr) :: Axis where
  AxisOf AttrLeft = XAxis
  AxisOf AttrRight = XAxis
  AxisOf AttrWidth = XAxis
  AxisOf AttrCenterX = XAxis
  AxisOf AttrTop = YAxis
  AxisOf AttrBottom = YAxis
  AxisOf AttrHeight = YAxis
  AxisOf AttrCenterY = YAxis

type family AxisEq (lhs :: Axis) (rhs :: Axis) :: Bool where
  AxisEq XAxis XAxis = 'True
  AxisEq YAxis YAxis = 'True
  AxisEq _ _ = 'False

type family AxisCount (axis :: Axis) (used :: [LayoutAttr]) :: Nat where
  AxisCount axis '[] = 0
  AxisCount axis (attr : rest) = AxisCountStep
    (AxisEq axis (AxisOf attr))
    axis
    rest

type family AxisCountStep (matches :: Bool) (axis :: Axis) (rest :: [LayoutAttr]) :: Nat where
  AxisCountStep 'True axis rest = 1 + AxisCount axis rest
  AxisCountStep 'False axis rest = AxisCount axis rest

type family CanTakeAttr (attr :: LayoutAttr) (used :: [LayoutAttr]) :: K.Constraint where
  CanTakeAttr attr used = CheckUnusedAttr (MemberAttr attr used) attr used

type family CheckUnusedAttr (alreadyUsed :: Bool) (attr :: LayoutAttr) (used :: [LayoutAttr]) :: K.Constraint where
  CheckUnusedAttr 'True attr used = TypeError
    ('Text "Layout attribute " :<>: 'ShowType attr :<>: 'Text
       " has already been used for this visual.")
  CheckUnusedAttr 'False attr used = CheckAxisRoom
    (CmpNat (AxisCount (AxisOf attr) used) 2)
    attr

type family CheckAxisRoom (ordering :: Ordering) (attr :: LayoutAttr) :: K.Constraint where
  CheckAxisRoom 'LT attr = ()
  CheckAxisRoom 'EQ attr = TypeError
    ('Text "Cannot use layout attribute " :<>: 'ShowType attr :<>: 'Text
       ": this visual already has two attributes on that axis.")
  CheckAxisRoom 'GT attr = TypeError
    ('Text "Cannot use layout attribute " :<>: 'ShowType attr :<>: 'Text
       ": this visual already has more than two attributes on that axis.")

data Visual state lifecycle (used :: [LayoutAttr]) tag where
  Visual :: BlockView tag -> Visual state lifecycle used tag

type NewVisual tag = Visual Unrendered Stable '[] tag

type LiveVisual tag = Visual Rendered Stable '[] tag

type ConsumedVisual tag = Visual Rendered Consumed '[] tag

data CopiedVisual tag where
  CopiedVisual :: LiveVisual tag %1 -> NewVisual tag %1 -> CopiedVisual tag

type BoxAttrs = '[ AttrLeft, AttrWidth, AttrTop, AttrHeight]

type SizeAttrs = '[ AttrWidth, AttrHeight]

type BoxVisual tag = Visual Rendered Stable BoxAttrs tag

type SizeVisual tag = Visual Rendered Stable SizeAttrs tag

data StyleDraft opacity zIndex fontSize radius strokeWidth alpha fill stroke fontFamily fontWeight fontStyle textAlign borderStyle whiteSpace where
  StyleDraft
    :: Ur Style
       %1 -> StyleDraft
         opacity
         zIndex
         fontSize
         radius
         strokeWidth
         alpha
         fill
         stroke
         fontFamily
         fontWeight
         fontStyle
         textAlign
         borderStyle
         whiteSpace

type EmptyStyleDraft
  = StyleDraft
      Available
      Available
      Available
      Available
      Available
      Available
      Available
      Available
      Available
      Available
      Available
      Available
      Available
      Available

finalizeStyle ::
     StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
     %1 -> Style
finalizeStyle draft =
  case draft of
    StyleDraft (Ur style') -> style'

finalizeStyleWith :: (Style -> Style) -> EmptyStyleDraft %1 -> Style
finalizeStyleWith update draft =
  case draft of
    StyleDraft (Ur style') -> update style'

setOpacityOnce ::
     UnitExpr
  -> StyleDraft
       Available
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
     %1 -> StyleDraft
       Taken
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
setOpacityOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setOpacity value style'))

setZIndexOnce ::
     FreeExpr
  -> StyleDraft
       opacity
       Available
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
     %1 -> StyleDraft
       opacity
       Taken
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
setZIndexOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setZIndex value style'))

setFontSizeOnce ::
     LayoutExpr
  -> StyleDraft
       opacity
       zIndex
       Available
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
     %1 -> StyleDraft
       opacity
       zIndex
       Taken
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
setFontSizeOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setFontSize value style'))

setRadiusOnce ::
     LayoutExpr
  -> StyleDraft
       opacity
       zIndex
       fontSize
       Available
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
     %1 -> StyleDraft
       opacity
       zIndex
       fontSize
       Taken
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
setRadiusOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setRadius value style'))

setStrokeWidthOnce ::
     LayoutExpr
  -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       Available
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
     %1 -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       Taken
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
setStrokeWidthOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setStrokeWidth value style'))

setAlphaOnce ::
     UnitExpr
  -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       Available
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
     %1 -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       Taken
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
setAlphaOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setAlpha value style'))

setFillOnce ::
     HslExpr
  -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       Available
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
     %1 -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       Taken
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
setFillOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setFill value style'))

setStrokeOnce ::
     HslExpr
  -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       Available
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
     %1 -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       Taken
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
setStrokeOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setStroke value style'))

setFontFamilyOnce ::
     String
  -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       Available
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
     %1 -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       Taken
       fontWeight
       fontStyle
       textAlign
       borderStyle
       whiteSpace
setFontFamilyOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setFontFamily value style'))

setFontWeightOnce ::
     FontWeight
  -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       Available
       fontStyle
       textAlign
       borderStyle
       whiteSpace
     %1 -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       Taken
       fontStyle
       textAlign
       borderStyle
       whiteSpace
setFontWeightOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setFontWeight value style'))

setFontStyleOnce ::
     FontStyle
  -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       Available
       textAlign
       borderStyle
       whiteSpace
     %1 -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       Taken
       textAlign
       borderStyle
       whiteSpace
setFontStyleOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setFontStyle value style'))

setTextAlignOnce ::
     TextAlign
  -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       Available
       borderStyle
       whiteSpace
     %1 -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       Taken
       borderStyle
       whiteSpace
setTextAlignOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setTextAlign value style'))

setBorderStyleOnce ::
     BorderStyle
  -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       Available
       whiteSpace
     %1 -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       Taken
       whiteSpace
setBorderStyleOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setBorderStyle value style'))

setWhiteSpaceOnce ::
     WhiteSpace
  -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       Available
     %1 -> StyleDraft
       opacity
       zIndex
       fontSize
       radius
       strokeWidth
       alpha
       fill
       stroke
       fontFamily
       fontWeight
       fontStyle
       textAlign
       borderStyle
       Taken
setWhiteSpaceOnce value draft =
  case draft of
    StyleDraft (Ur style') -> StyleDraft (Ur (setWhiteSpace value style'))

data ViewDefinition tag (used :: [LayoutAttr]) where
  ViewDefinition
    :: (EmptyStyleDraft %1 -> Style)
    -> (LiveVisual tag %1 -> ViewBuilder (Visual Rendered Stable used tag))
    -> ViewDefinition tag used

type BoxDefinition tag = ViewDefinition tag BoxAttrs

type SizeDefinition tag = ViewDefinition tag SizeAttrs

boxDefinition ::
     (EmptyStyleDraft %1 -> Style)
  -> (LiveVisual tag %1 -> ViewBuilder (BoxVisual tag))
  -> BoxDefinition tag
boxDefinition = ViewDefinition

sizeDefinition ::
     (EmptyStyleDraft %1 -> Style)
  -> (LiveVisual tag %1 -> ViewBuilder (SizeVisual tag))
  -> SizeDefinition tag
sizeDefinition = ViewDefinition

data LayoutUse visual where
  LayoutUse :: visual %1 -> OneExpr Layout %1 -> LayoutUse visual

data OneExpr (ty :: Type) where
  OneExpr :: Ur (Expr ty) %1 -> OneExpr ty

data OneConstraint where
  OneConstraint :: Ur Constraint %1 -> OneConstraint

infixl 1 |>
(|>) :: a %1 -> (a %1 -> b) -> b
value |> next = next value

-- Solver expressions are immutable metadata; the linear obligation is the
-- OneExpr/OneConstraint wrapper that controls use at the View boundary.
unsafeUr :: forall a. a %1 -> Ur a
unsafeUr = Unsafe.unsafeCoerce (Ur :: a -> Ur a)

class BinaryExpr lhs rhs result | lhs rhs -> result where
  binaryExpr ::
       (forall (ty :: Type). Expr ty -> Expr ty -> Expr ty)
    -> lhs
       %1 -> rhs
       %1 -> result

instance BinaryExpr (Expr (ty :: Type)) (Expr ty) (Expr ty) where
  binaryExpr op lhs rhs =
    case unsafeUr lhs of
      Ur lhsRaw ->
        case unsafeUr rhs of
          Ur rhsRaw -> op lhsRaw rhsRaw

instance BinaryExpr (OneExpr (ty :: Type)) (Expr ty) (OneExpr ty) where
  binaryExpr op lhs rhs =
    case lhs of
      OneExpr (Ur lhsRaw) ->
        case unsafeUr rhs of
          Ur rhsRaw -> OneExpr (Ur (op lhsRaw rhsRaw))

instance BinaryExpr (Expr (ty :: Type)) (OneExpr ty) (OneExpr ty) where
  binaryExpr op lhs rhs =
    case unsafeUr lhs of
      Ur lhsRaw ->
        case rhs of
          OneExpr (Ur rhsRaw) -> OneExpr (Ur (op lhsRaw rhsRaw))

instance BinaryExpr (OneExpr (ty :: Type)) (OneExpr ty) (OneExpr ty) where
  binaryExpr op lhs rhs =
    case lhs of
      OneExpr (Ur lhsRaw) ->
        case rhs of
          OneExpr (Ur rhsRaw) -> OneExpr (Ur (op lhsRaw rhsRaw))

class RelateExpr lhs rhs where
  relateExpr ::
       (forall (ty :: Type). Expr ty -> Expr ty -> Constraint)
    -> lhs
       %1 -> rhs
       %1 -> OneConstraint

instance RelateExpr (Expr (ty :: Type)) (Expr ty) where
  relateExpr op lhs rhs =
    case unsafeUr lhs of
      Ur lhsRaw ->
        case unsafeUr rhs of
          Ur rhsRaw -> OneConstraint (Ur (op lhsRaw rhsRaw))

instance RelateExpr (OneExpr (ty :: Type)) (Expr ty) where
  relateExpr op lhs rhs =
    case lhs of
      OneExpr (Ur lhsRaw) ->
        case unsafeUr rhs of
          Ur rhsRaw -> OneConstraint (Ur (op lhsRaw rhsRaw))

instance RelateExpr (Expr (ty :: Type)) (OneExpr ty) where
  relateExpr op lhs rhs =
    case unsafeUr lhs of
      Ur lhsRaw ->
        case rhs of
          OneExpr (Ur rhsRaw) -> OneConstraint (Ur (op lhsRaw rhsRaw))

instance RelateExpr (OneExpr (ty :: Type)) (OneExpr ty) where
  relateExpr op lhs rhs =
    case lhs of
      OneExpr (Ur lhsRaw) ->
        case rhs of
          OneExpr (Ur rhsRaw) -> OneConstraint (Ur (op lhsRaw rhsRaw))

num :: SymbolicType ty => Double -> Expr ty
num = S.num

global :: SymbolicType ty => String -> Expr ty
global name = S.var ("global." ++ name)

infixl 6 @+@
infixl 6 @-@
infixl 7 @*@
infixl 7 @/@
infixr 8 @^@
infix 4 @==@
infix 4 @<=@
infix 4 @>=@
(@+@) :: BinaryExpr lhs rhs result => lhs %1 -> rhs %1 -> result
(@+@) = binaryExpr (S.@+@)

(@-@) :: BinaryExpr lhs rhs result => lhs %1 -> rhs %1 -> result
(@-@) = binaryExpr (S.@-@)

(@*@) :: BinaryExpr lhs rhs result => lhs %1 -> rhs %1 -> result
(@*@) = binaryExpr (S.@*@)

(@/@) :: BinaryExpr lhs rhs result => lhs %1 -> rhs %1 -> result
(@/@) = binaryExpr (S.@/@)

(@^@) :: BinaryExpr lhs rhs result => lhs %1 -> rhs %1 -> result
(@^@) = binaryExpr (S.@^@)

absExpr :: Expr ty -> Expr ty
absExpr = S.absExpr

(@==@) :: RelateExpr lhs rhs => lhs %1 -> rhs %1 -> OneConstraint
(@==@) = relateExpr (S.@==@)

(@<=@) :: RelateExpr lhs rhs => lhs %1 -> rhs %1 -> OneConstraint
(@<=@) = relateExpr (S.@<=@)

(@>=@) :: RelateExpr lhs rhs => lhs %1 -> rhs %1 -> OneConstraint
(@>=@) = relateExpr (flip (S.@<=@))

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
  , emittedInitialVars   :: [InitialVar]
  , emittedRenderFrames  :: [[RenderIntent]]
  , pendingRenderIntents :: [RenderIntent]
  }

type family Append (lhs :: [Type]) (rhs :: [Type]) :: [Type] where
  Append '[] rhs = rhs
  Append (act : acts) rhs = act : Append acts rhs

data SomeAudit where
  SomeAudit :: C.Audit acts -> SomeAudit

emptySomeAudit :: SomeAudit
emptySomeAudit = SomeAudit C.EmptyAudit

singletonSomeAudit :: C.AuditStep act -> SomeAudit
singletonSomeAudit step = SomeAudit (step C.:> C.EmptyAudit)

appendAudit :: C.Audit lhs -> C.Audit rhs -> C.Audit (Append lhs rhs)
appendAudit lhs rhs =
  case lhs of
    C.EmptyAudit   -> rhs
    step C.:> rest -> step C.:> appendAudit rest rhs

appendSomeAudit :: SomeAudit -> SomeAudit -> SomeAudit
appendSomeAudit lhs rhs =
  case lhs of
    SomeAudit lhsAudit ->
      case rhs of
        SomeAudit rhsAudit -> SomeAudit (appendAudit lhsAudit rhsAudit)

instance Semigroup ViewOutput where
  ViewOutput nodesA constraintsA initialsA framesA pendingA <> ViewOutput nodesB constraintsB initialsB framesB pendingB =
    ViewOutput
      { emittedNodes = nodesA ++ nodesB
      , emittedConstraints = constraintsA ++ constraintsB
      , emittedInitialVars = initialsA ++ initialsB
      , emittedRenderFrames = framesA ++ framesB
      , pendingRenderIntents = pendingA ++ pendingB
      }

instance Monoid ViewOutput where
  mempty =
    ViewOutput
      { emittedNodes = []
      , emittedConstraints = []
      , emittedInitialVars = []
      , emittedRenderFrames = []
      , pendingRenderIntents = []
      }

data ViewState where
  ViewState :: Ur ViewEnv %1 -> Ur ViewOutput %1 -> ViewState

type ViewBuilder a = State ViewState a

data ViewScript acts where
  ViewScript :: ViewOutput -> ViewScript acts

data VisualTraceState where
  VisualTraceState
    :: Ur ViewEnv
       %1 -> Ur (C.TraceBuilderState ViewScript)
       %1 -> Ur SomeAudit
       %1 -> Ur ViewOutput
       %1 -> VisualTraceState

type VisualTraceBuilder a = State VisualTraceState a

data VisualTraceGraph =
  VisualTraceGraph MatchSpec (C.TraceGraphWith ViewScript)

visualTraceCore :: VisualTraceGraph -> C.TraceGraphWith ViewScript
visualTraceCore graph =
  case graph of
    VisualTraceGraph _ coreGraph -> coreGraph

infixr 0 ==>
(==>) :: P.String -> ViewBuilder () %1 -> VisualTraceBuilder ()
(==>) = explain

explain :: P.String -> ViewBuilder () %1 -> VisualTraceBuilder ()
explain label script = do
  appendTraceView script
  checkpointTrace label

discard :: P.String -> VisualTraceBuilder ()
discard reason = do
  audit <- takePendingAudit
  Ur _output <- takePendingOutput
  case audit of
    SomeAudit auditSteps -> runCoreBuilder (C.discardAudit reason auditSteps)

initialVisualTraceStateWith :: ViewEnv -> VisualTraceState
initialVisualTraceStateWith env =
  VisualTraceState
    (Ur env)
    (Ur (C.TraceBuilderState (Ur 0) (Ur []) (Ur [])))
    (Ur emptySomeAudit)
    (Ur mempty)

buildGraph :: VisualTraceBuilder () -> VisualTraceGraph
buildGraph = buildGraphWithEnv defaultViewEnv

buildGraphWithSpec :: MatchSpec -> VisualTraceBuilder () -> VisualTraceGraph
buildGraphWithSpec spec =
  buildGraphWithEnv defaultViewEnv {viewMatchSpec = spec}

buildGraphWithEnv :: ViewEnv -> VisualTraceBuilder () -> VisualTraceGraph
buildGraphWithEnv env builder =
  let (_result, finalState) = runState builder (initialVisualTraceStateWith env)
      VisualTraceState _env (Ur coreState) _pendingAudit _pendingOutput =
        finalState
      C.TraceBuilderState (Ur _nextBlockId) (Ur blocks) (Ur steps) = coreState
   in VisualTraceGraph (viewMatchSpec env) (C.TraceGraph blocks steps)

instance Consumable ViewState where
  consume (ViewState env output) = consume env `lseq` consume output

instance Dupable ViewState where
  dup2 (ViewState env output) =
    case dup2 env of
      (env1, env2) ->
        case dup2 output of
          (output1, output2) -> (ViewState env1 output1, ViewState env2 output2)

instance Consumable VisualTraceState where
  consume (VisualTraceState env coreState pendingAudit pendingOutput) =
    consume env
      `lseq` consume coreState
      `lseq` consume pendingAudit
      `lseq` consume pendingOutput

instance Dupable VisualTraceState where
  dup2 (VisualTraceState env coreState pendingAudit pendingOutput) =
    case dup2 env of
      (env1, env2) ->
        case dup2 coreState of
          (coreState1, coreState2) ->
            case dup2 pendingAudit of
              (pendingAudit1, pendingAudit2) ->
                case dup2 pendingOutput of
                  (pendingOutput1, pendingOutput2) ->
                    ( VisualTraceState
                        env1
                        coreState1
                        pendingAudit1
                        pendingOutput1
                    , VisualTraceState
                        env2
                        coreState2
                        pendingAudit2
                        pendingOutput2)

runCoreBuilder :: C.TraceBuilderWith ViewScript a -> VisualTraceBuilder a
runCoreBuilder builder =
  LinearState.state
    (\(VisualTraceState env (Ur coreState) pendingAudit pendingOutput) ->
       let (result, nextCoreState) = runState builder coreState
        in ( result
           , VisualTraceState env (Ur nextCoreState) pendingAudit pendingOutput))

appendPendingAudit :: C.AuditStep act -> VisualTraceBuilder ()
appendPendingAudit step = do
  VisualTraceState env coreState (Ur pendingAudit) pendingOutput <- get
  put
    (VisualTraceState
       env
       coreState
       (Ur (appendSomeAudit pendingAudit (singletonSomeAudit step)))
       pendingOutput)

takePendingAudit :: VisualTraceBuilder SomeAudit
takePendingAudit = do
  VisualTraceState env coreState (Ur pendingAudit) pendingOutput <- get
  put (VisualTraceState env coreState (Ur emptySomeAudit) pendingOutput)
  return pendingAudit

appendTraceView :: ViewBuilder () %1 -> VisualTraceBuilder ()
appendTraceView script0 =
  case unsafeUr script0 of
    Ur script -> do
      VisualTraceState (Ur env) coreState pendingAudit (Ur pendingOutput) <- get
      let (_result, output) = runViewBuilderWithOutput env pendingOutput script
      put (VisualTraceState (Ur env) coreState pendingAudit (Ur output))

takePendingOutput :: VisualTraceBuilder (Ur ViewOutput)
takePendingOutput = do
  VisualTraceState env coreState pendingAudit (Ur pendingOutput) <- get
  put (VisualTraceState env coreState pendingAudit (Ur mempty))
  return (Ur pendingOutput)

checkpointTrace :: P.String -> VisualTraceBuilder ()
checkpointTrace label = do
  audit <- takePendingAudit
  Ur output <- takePendingOutput
  let output' = flushPendingOutput output
  case audit of
    SomeAudit auditSteps ->
      runCoreBuilder (C.explainAuditWith label (ViewScript output') auditSteps)

runViewBuilderWithOutput ::
     ViewEnv -> ViewOutput -> ViewBuilder a -> (a, ViewOutput)
runViewBuilderWithOutput env initialOutput builder =
  let (result, ViewState _ (Ur output)) =
        runState builder (ViewState (Ur env) (Ur initialOutput))
   in (result, output)

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

traverseMaybeView_ :: (a -> ViewBuilder ()) -> Maybe a -> ViewBuilder ()
traverseMaybeView_ action value
  {- HLINT ignore "Use forM_" -}
 =
  case value of
    Nothing -> return ()
    Just x  -> action x

ensure :: OneConstraint %1 -> ViewBuilder ()
ensure oneConstraint =
  case oneConstraint of
    OneConstraint (Ur constraint) -> ensureRaw constraint

ensureRaw :: Constraint -> ViewBuilder ()
ensureRaw constraint = tellOutput mempty {emittedConstraints = [constraint]}

encourage :: Expr ty -> ViewBuilder ()
encourage objective =
  tellOutput mempty {emittedConstraints = [S.minimize objective]}

registerInitialVar :: InitialVar -> ViewBuilder ()
registerInitialVar initial = tellOutput mempty {emittedInitialVars = [initial]}

registerInitialRange :: Expr ty -> Range -> ViewBuilder ()
registerInitialRange expr range =
  traverseMaybeView_ registerInitialVar (initialRangeFor expr range)

emitViewNode :: ViewNode -> ViewBuilder ()
emitViewNode node = tellOutput mempty {emittedNodes = [node]}

emitRenderIntent :: RenderIntent -> ViewBuilder ()
emitRenderIntent intent = tellOutput mempty {pendingRenderIntents = [intent]}

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

checkpoint :: ViewBuilder ()
checkpoint = do
  ViewState env (Ur output) <- get
  put (ViewState env (Ur (flushPendingOutput output)))

--------------------------------------------------------------------------------
-- Per-block visualisation
--------------------------------------------------------------------------------
defineNewBlock ::
     forall tag used.
     ViewDefinition tag used
     %1 -> BlockView tag
  -> ViewBuilder (Visual Rendered Stable used tag)
defineNewBlock definition block0 =
  case definition of
    ViewDefinition styleDefinition viewDefinition -> do
      Ur env <- askViewEnv
      let block =
            block0
              { blockStyle =
                  styleDefinition (StyleDraft (Ur (blockStyle block0)))
              }
      registerInitialStyleBounds (blockStyle block)
      constrainStyle (blockStyle block)
      ensureRaw (S.num 0 S.@<=@ left block)
      ensureRaw (S.num 0 S.@<=@ top block)
      ensureRaw (right block S.@<=@ canvasWidth env)
      ensureRaw (bottom block S.@<=@ canvasHeight env)
      emitViewNode (BlockViewNode block)
      viewDefinition (Visual block)

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
    PatternNodeRule (_ :: Proxy matchedTag) pattern' payloadPattern makePatch ->
      case eqT @sourceTag @matchedTag of
        Nothing -> Nothing
        Just Refl ->
          case patternMatches pattern' (blockFacts block) of
            Nothing -> Nothing
            Just bindings ->
              matchedPayloadNodePatch
                matchIndex
                (patternMatchBindings bindings)
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
         (blockLabel block) of
    Nothing -> Nothing
    Just payloadBindings ->
      Just
        (makePatch
           (MatchContext
              { matchContextIndex = matchIndex
              , matchContextPayload = blockPayload block
              , matchContextLabel = blockLabel block
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
  registerInitialStyleBounds (blockStyle block)
  constrainStyle (blockStyle block)
  ensureRaw (S.num 0 S.@<=@ left block)
  ensureRaw (S.num 0 S.@<=@ top block)
  ensureRaw (right block S.@<=@ canvasWidth env)
  ensureRaw (bottom block S.@<=@ canvasHeight env)
  constrainPatchGeometry patch block
  runPatchRequirements (nodePatchRequirements patch)
  emitViewNode (BlockViewNode block)
  return ()

runPatchRequirements :: [ViewBuilder ()] -> ViewBuilder ()
runPatchRequirements actions =
  case actions of
    [] -> return ()
    action:rest -> do
      action
      runPatchRequirements rest

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
          ensureRaw (S.All (constraints P.++ [expr S.@==@ target]))

--------------------------------------------------------------------------------
-- Explicit token handling
--------------------------------------------------------------------------------
explainedVisual :: ViewToken act %1 -> ExplainedVisual act
explainedVisual token =
  case token of
    CreatedToken block -> Visual block
    ObservedToken block -> Visual block
    UsedToken block -> Visual block
    CopiedToken original copy' -> CopiedVisual (Visual original) (Visual copy')
    ReplacedToken old incoming output ->
      (Visual old, Visual incoming, Visual output)
    ComputedToken block -> Visual block
    DestroyedToken block -> Visual block
    SealedToken owner child -> (Visual owner, Visual child)
    UnsealedToken owner child -> (Visual owner, Visual child)
    DecidedToken block -> Visual block

visualExplainToken ::
     C.ExplainToken act %1 -> VisualTraceBuilder (VisualExplainToken act)
visualExplainToken explainToken =
  case C.explainTokenToAuditStep explainToken of
    Ur step -> do
      appendPendingAudit step
      return (VisualExplainToken (explainedVisual (viewToken step)))

create ::
     forall tag. C.Traceable tag
  => C.Payload tag
     %1 -> VisualTraceBuilder (Created tag)
create payload =
  case unsafeUr payload of
    Ur payload' -> do
      C.Created block explainToken <- runCoreBuilder (C.create payload')
      token <- visualExplainToken explainToken
      return (Created block token)

createTagged ::
     forall tag. C.Traceable tag
  => C.Facts
  -> C.Payload tag
     %1 -> VisualTraceBuilder (Created tag)
createTagged facts payload =
  case unsafeUr payload of
    Ur payload' -> do
      C.Created block explainToken <-
        runCoreBuilder (C.createTagged facts payload')
      token <- visualExplainToken explainToken
      return (Created block token)

observe ::
     forall tag. C.Traceable tag
  => C.Block tag
     %1 -> VisualTraceBuilder (Observed tag)
observe block0 =
  case unsafeUr block0 of
    Ur block0' -> do
      C.Observed block explainToken <- runCoreBuilder (C.observe block0')
      token <- visualExplainToken explainToken
      return (Observed block token)

use ::
     forall tag. C.Traceable tag
  => C.Block tag
     %1 -> VisualTraceBuilder (Used tag)
use block =
  case unsafeUr block of
    Ur block' -> do
      C.Used payload explainToken <- runCoreBuilder (C.use block')
      token <- visualExplainToken explainToken
      return (Used payload token)

copy ::
     forall tag. C.Traceable tag
  => C.Block tag
     %1 -> VisualTraceBuilder (Copied tag)
copy block =
  case unsafeUr block of
    Ur block' -> do
      C.Copied original copy' explainToken <- runCoreBuilder (C.copy block')
      token <- visualExplainToken explainToken
      return (Copied original copy' token)

copyTagged ::
     forall tag. C.Traceable tag
  => C.Facts
  -> C.Block tag
     %1 -> VisualTraceBuilder (Copied tag)
copyTagged facts block =
  case unsafeUr block of
    Ur block' -> do
      C.Copied original copy' explainToken <-
        runCoreBuilder (C.copyTagged facts block')
      token <- visualExplainToken explainToken
      return (Copied original copy' token)

replace ::
     forall tag. C.Traceable tag
  => C.Block tag
     %1 -> C.Block tag
     %1 -> VisualTraceBuilder (Replaced tag)
replace oldBlock incomingBlock =
  case unsafeUr oldBlock of
    Ur oldBlock' ->
      case unsafeUr incomingBlock of
        Ur incomingBlock' -> do
          C.Replaced output explainToken <-
            runCoreBuilder (C.replace oldBlock' incomingBlock')
          token <- visualExplainToken explainToken
          return (Replaced output token)

compute ::
     forall tag. C.Traceable tag
  => C.OneUse (C.Payload tag)
     %1 -> VisualTraceBuilder (Computed tag)
compute payload =
  case unsafeUr payload of
    Ur payload' -> do
      C.Computed block explainToken <- runCoreBuilder (C.compute payload')
      token <- visualExplainToken explainToken
      return (Computed block token)

computeTagged ::
     forall tag. C.Traceable tag
  => C.Facts
  -> C.OneUse (C.Payload tag)
     %1 -> VisualTraceBuilder (Computed tag)
computeTagged facts = computeTaggedWith facts (P.const C.emptyFacts)

computeTaggedWith ::
     forall tag. C.Traceable tag
  => C.Facts
  -> (C.Payload tag -> C.Facts)
  -> C.OneUse (C.Payload tag)
     %1 -> VisualTraceBuilder (Computed tag)
computeTaggedWith facts selectFacts payload =
  case unsafeUr payload of
    Ur payload' -> do
      C.Computed block explainToken <-
        runCoreBuilder (C.computeTaggedWith facts selectFacts payload')
      token <- visualExplainToken explainToken
      return (Computed block token)

destroy ::
     forall tag. C.Traceable tag
  => C.Block tag
     %1 -> VisualTraceBuilder (Destroyed tag)
destroy block =
  case unsafeUr block of
    Ur block' -> do
      C.Destroyed explainToken <- runCoreBuilder (C.destroy block')
      token <- visualExplainToken explainToken
      return (Destroyed token)

seal ::
     forall owner tag. (C.Traceable owner, C.Traceable tag)
  => C.Block owner
     %1 -> C.Block tag
     %1 -> VisualTraceBuilder (Sealed owner tag)
seal owner child =
  case unsafeUr owner of
    Ur owner' ->
      case unsafeUr child of
        Ur child' -> do
          C.Sealed ownerBlock childSlot explainToken <-
            runCoreBuilder (C.seal owner' child')
          token <- visualExplainToken explainToken
          return (Sealed ownerBlock childSlot token)

unseal ::
     forall owner tag. (C.Traceable owner, C.Traceable tag)
  => C.Block owner
     %1 -> C.Slot owner tag
     %1 -> VisualTraceBuilder (Unsealed owner tag)
unseal owner slot =
  case unsafeUr owner of
    Ur owner' ->
      case unsafeUr slot of
        Ur slot' -> do
          C.Unsealed ownerBlock childBlock explainToken <-
            runCoreBuilder (C.unseal owner' slot')
          token <- visualExplainToken explainToken
          return (Unsealed ownerBlock childBlock token)

decide ::
     forall tag. C.Traceable tag
  => (C.Payload tag %1 -> Bool)
  -> C.Block tag
     %1 -> VisualTraceBuilder (Decided tag)
decide predicate block =
  case unsafeUr block of
    Ur block' -> do
      decision <- runCoreBuilder (C.decide predicate block')
      case decision of
        C.DecidedTrue explainToken -> do
          token <- visualExplainToken explainToken
          return (DecidedTrue token)
        C.DecidedFalse explainToken -> do
          token <- visualExplainToken explainToken
          return (DecidedFalse token)

explainVisual :: VisualExplainToken act %1 -> ViewBuilder (ExplainedVisual act)
explainVisual token =
  case token of
    VisualExplainToken visual' -> return visual'

class ToNewVisual visual tag | visual -> tag where
  toNewVisual :: visual %1 -> ViewBuilder (NewVisual tag)

instance ToNewVisual (NewVisual tag) tag where
  toNewVisual = return

instance ToNewVisual (VisualExplainToken (C.Create tag)) tag where
  toNewVisual = explainVisual

instance ToNewVisual (VisualExplainToken (C.Compute tag)) tag where
  toNewVisual = explainVisual

class ToCopiedVisual visual tag | visual -> tag where
  toCopiedVisual :: visual %1 -> ViewBuilder (CopiedVisual tag)

instance ToCopiedVisual (CopiedVisual tag) tag where
  toCopiedVisual = return

instance ToCopiedVisual (VisualExplainToken (C.Copy tag)) tag where
  toCopiedVisual = explainVisual

class ToLiveVisual visual tag | visual -> tag where
  toLiveVisual :: visual %1 -> ViewBuilder (LiveVisual tag)

instance ToLiveVisual (LiveVisual tag) tag where
  toLiveVisual = return

instance ToLiveVisual (VisualExplainToken (C.Observe tag)) tag where
  toLiveVisual = explainVisual

class Removable visual where
  remove :: visual %1 -> ViewBuilder ()

instance Removable (Visual Rendered Consumed used tag) where
  remove visual' =
    case visual' of
      Visual block -> emitRenderIntent (RenderRemove (blockRef block))

instance forall (tag :: Type). Removable (VisualExplainToken (C.Use tag)) where
  remove token =
    case token of
      VisualExplainToken (visual' :: ConsumedVisual tag) -> remove visual'

instance forall (tag :: Type). Removable (VisualExplainToken (C.Destroy tag)) where
  remove token =
    case token of
      VisualExplainToken (visual' :: ConsumedVisual tag) -> remove visual'

instance forall (tag :: Type). Removable (VisualExplainToken (C.Decide tag)) where
  remove token =
    case token of
      VisualExplainToken (visual' :: ConsumedVisual tag) -> remove visual'

fresh ::
     forall tag used visual. ToNewVisual visual tag
  => ViewDefinition tag used
     %1 -> visual
     %1 -> ViewBuilder (Visual Rendered Stable used tag)
fresh definition visual0 = do
  visual1 <- toNewVisual visual0
  freshRaw definition visual1

freshRaw ::
     forall tag used.
     ViewDefinition tag used
     %1 -> NewVisual tag
     %1 -> ViewBuilder (Visual Rendered Stable used tag)
freshRaw definition visual =
  case visual of
    Visual block -> do
      rendered <- defineNewBlock definition block
      emitRenderIntent (RenderFresh (blockRef block))
      pure rendered

freshMatched ::
     forall tag visual. (C.Traceable tag, ToNewVisual visual tag)
  => visual
     %1 -> ViewBuilder ()
freshMatched visual0 = do
  visual1 <- toNewVisual visual0
  freshMatchedRaw visual1

freshMatchedRaw ::
     forall tag. C.Traceable tag
  => NewVisual tag
     %1 -> ViewBuilder ()
freshMatchedRaw visual =
  case visual of
    Visual block -> do
      defineMatchedBlock block
      emitRenderIntent (RenderFresh (blockRef block))

freshCopy ::
     forall tag used visual. ToCopiedVisual visual tag
  => ViewDefinition tag used
     %1 -> visual
     %1 -> ViewBuilder (LiveVisual tag, Visual Rendered Stable used tag)
freshCopy definition copied0 = do
  copied <- toCopiedVisual copied0
  freshCopyRaw definition copied

freshCopyRaw ::
     forall tag used.
     ViewDefinition tag used
     %1 -> CopiedVisual tag
     %1 -> ViewBuilder (LiveVisual tag, Visual Rendered Stable used tag)
freshCopyRaw definition copied =
  case copied of
    CopiedVisual source visual ->
      case source of
        Visual sourceBlock ->
          case visual of
            Visual block -> do
              rendered <- defineNewBlock definition block
              emitRenderIntent (RenderFresh (blockRef block))
              pure (Visual sourceBlock, rendered)

forkCopy ::
     forall tag used visual. ToCopiedVisual visual tag
  => ViewDefinition tag used
     %1 -> visual
     %1 -> ViewBuilder (LiveVisual tag, Visual Rendered Stable used tag)
forkCopy definition copied0 = do
  copied <- toCopiedVisual copied0
  forkCopyRaw definition copied

forkCopyRaw ::
     forall tag used.
     ViewDefinition tag used
     %1 -> CopiedVisual tag
     %1 -> ViewBuilder (LiveVisual tag, Visual Rendered Stable used tag)
forkCopyRaw definition copied =
  case copied of
    CopiedVisual source visual ->
      case source of
        Visual sourceBlock ->
          case visual of
            Visual block -> do
              rendered <- defineNewBlock definition block
              emitRenderIntent
                (RenderFork (blockRef sourceBlock) (blockRef block))
              pure (Visual sourceBlock, rendered)

forkCopyMatched ::
     forall tag visual. (C.Traceable tag, ToCopiedVisual visual tag)
  => visual
     %1 -> ViewBuilder ()
forkCopyMatched copied0 = do
  copied <- toCopiedVisual copied0
  forkCopyMatchedRaw copied

forkCopyMatchedRaw ::
     forall tag. C.Traceable tag
  => CopiedVisual tag
     %1 -> ViewBuilder ()
forkCopyMatchedRaw copied =
  case copied of
    CopiedVisual source visual ->
      case source of
        Visual sourceBlock ->
          case visual of
            Visual block -> do
              defineMatchedBlock block
              emitRenderIntent
                (RenderFork (blockRef sourceBlock) (blockRef block))

continueFrom ::
     forall tag oldTag used source visual.
     (ToLiveVisual source oldTag, ToNewVisual visual tag)
  => ViewDefinition tag used
     %1 -> source
     %1 -> visual
     %1 -> ViewBuilder (Visual Rendered Stable used tag)
continueFrom definition source0 visual0 = do
  source <- toLiveVisual source0
  visual1 <- toNewVisual visual0
  continueFromRaw definition source visual1

continueFromRaw ::
     forall tag oldTag used.
     ViewDefinition tag used
     %1 -> LiveVisual oldTag
     %1 -> NewVisual tag
     %1 -> ViewBuilder (Visual Rendered Stable used tag)
continueFromRaw definition source visual =
  case source of
    Visual sourceBlock ->
      case visual of
        Visual block -> do
          rendered <- defineNewBlock definition block
          emitRenderIntent
            (RenderContinue (blockRef sourceBlock) (blockRef block))
          pure rendered

continueFromMatched ::
     forall tag oldTag source visual.
     (C.Traceable tag, ToLiveVisual source oldTag, ToNewVisual visual tag)
  => source
     %1 -> visual
     %1 -> ViewBuilder ()
continueFromMatched source0 visual0 = do
  source <- toLiveVisual source0
  visual1 <- toNewVisual visual0
  continueFromMatchedRaw source visual1

continueFromMatchedRaw ::
     forall tag oldTag. C.Traceable tag
  => LiveVisual oldTag
     %1 -> NewVisual tag
     %1 -> ViewBuilder ()
continueFromMatchedRaw source visual =
  case source of
    Visual sourceBlock ->
      case visual of
        Visual block -> do
          defineMatchedBlock block
          emitRenderIntent
            (RenderContinue (blockRef sourceBlock) (blockRef block))

completeCopy ::
     forall (tag :: Type). VisualExplainToken (C.Copy tag) %1 -> ViewBuilder ()
completeCopy token =
  case token of
    VisualExplainToken (copied :: CopiedVisual tag) ->
      case copied of
        CopiedVisual source copy' -> do
          completeAnyVisual source
          completeAnyVisual copy'

replaceMatched ::
     forall tag. C.Traceable tag
  => VisualExplainToken (C.Replace tag)
     %1 -> ViewBuilder ()
replaceMatched token = do
  (oldVisual, incomingVisual, outputVisual) <- explainVisual token
  continueConsumedFromMatched oldVisual outputVisual
  remove incomingVisual

replaceMatchedOutput ::
     forall tag. C.Traceable tag
  => VisualExplainToken (C.Replace tag)
     %1 -> ViewBuilder ()
replaceMatchedOutput token = do
  (oldVisual, incomingVisual, outputVisual) <- explainVisual token
  continueConsumedFromMatched oldVisual outputVisual
  completeConsumed incomingVisual

completeConsumed :: ConsumedVisual tag %1 -> ViewBuilder ()
completeConsumed = completeAnyVisual

completeAnyVisual :: Visual state lifecycle used tag %1 -> ViewBuilder ()
completeAnyVisual visual =
  case visual of
    Visual _ -> return ()

continueConsumedFromMatched ::
     forall tag. C.Traceable tag
  => ConsumedVisual tag
     %1 -> NewVisual tag
     %1 -> ViewBuilder ()
continueConsumedFromMatched source visual =
  case source of
    Visual sourceBlock ->
      case visual of
        Visual block -> do
          defineMatchedBlock block
          emitRenderIntent
            (RenderContinue (blockRef sourceBlock) (blockRef block))

complete :: Visual Rendered Stable used tag %1 -> ViewBuilder ()
complete visual =
  case visual of
    Visual _ -> pure ()

takeLeft ::
     CanTakeAttr AttrLeft used
  => Visual state lifecycle used tag
     %1 -> ViewBuilder
       (LayoutUse (Visual state lifecycle (Insert AttrLeft used) tag))
takeLeft visual =
  case visual of
    Visual block -> pure (LayoutUse (Visual block) (OneExpr (Ur (left block))))

takeRight ::
     CanTakeAttr AttrRight used
  => Visual state lifecycle used tag
     %1 -> ViewBuilder
       (LayoutUse (Visual state lifecycle (Insert AttrRight used) tag))
takeRight visual =
  case visual of
    Visual block -> pure (LayoutUse (Visual block) (OneExpr (Ur (right block))))

takeWidth ::
     CanTakeAttr AttrWidth used
  => Visual state lifecycle used tag
     %1 -> ViewBuilder
       (LayoutUse (Visual state lifecycle (Insert AttrWidth used) tag))
takeWidth visual =
  case visual of
    Visual block -> pure (LayoutUse (Visual block) (OneExpr (Ur (width block))))

takeCenterX ::
     CanTakeAttr AttrCenterX used
  => Visual state lifecycle used tag
     %1 -> ViewBuilder
       (LayoutUse (Visual state lifecycle (Insert AttrCenterX used) tag))
takeCenterX visual =
  case visual of
    Visual block ->
      pure (LayoutUse (Visual block) (OneExpr (Ur (centerX block))))

takeTop ::
     CanTakeAttr AttrTop used
  => Visual state lifecycle used tag
     %1 -> ViewBuilder
       (LayoutUse (Visual state lifecycle (Insert AttrTop used) tag))
takeTop visual =
  case visual of
    Visual block -> pure (LayoutUse (Visual block) (OneExpr (Ur (top block))))

takeBottom ::
     CanTakeAttr AttrBottom used
  => Visual state lifecycle used tag
     %1 -> ViewBuilder
       (LayoutUse (Visual state lifecycle (Insert AttrBottom used) tag))
takeBottom visual =
  case visual of
    Visual block ->
      pure (LayoutUse (Visual block) (OneExpr (Ur (bottom block))))

takeHeight ::
     CanTakeAttr AttrHeight used
  => Visual state lifecycle used tag
     %1 -> ViewBuilder
       (LayoutUse (Visual state lifecycle (Insert AttrHeight used) tag))
takeHeight visual =
  case visual of
    Visual block ->
      pure (LayoutUse (Visual block) (OneExpr (Ur (height block))))

takeCenterY ::
     CanTakeAttr AttrCenterY used
  => Visual state lifecycle used tag
     %1 -> ViewBuilder
       (LayoutUse (Visual state lifecycle (Insert AttrCenterY used) tag))
takeCenterY visual =
  case visual of
    Visual block ->
      pure (LayoutUse (Visual block) (OneExpr (Ur (centerY block))))

--------------------------------------------------------------------------------
-- Build a view graph
--------------------------------------------------------------------------------
buildCSP :: VisualTraceGraph -> ViewGraph
buildCSP (VisualTraceGraph spec (C.TraceGraph _blocks steps)) =
  let stepsOutput = viewTraceSteps steps
      traceNodes = builtNodes stepsOutput
      virtualNodes = virtualNodesForSpec spec traceNodes
      nodes = traceNodes P.++ virtualNodes
      viewSteps' = builtSteps stepsOutput
      virtualConstraints = P.concatMap virtualNodeConstraints virtualNodes
      virtualInitialVars = P.concatMap virtualNodeInitialVars virtualNodes
      constraints =
        builtConstraints stepsOutput
          P.++ virtualConstraints
          P.++ matchSpecConstraints spec nodes
      initialVars = builtInitialVars stepsOutput P.++ virtualInitialVars
      renderFrames =
        addVirtualRenderFrames virtualNodes (builtRenderFrames stepsOutput)
   in ViewGraph
        { viewNodes = nodes
        , viewSteps = viewSteps'
        , viewConstraints = constraints
        , viewInitialVars = initialVars
        , viewRenderFrames = renderFrames
        }

solveCSP :: SolveConfig -> ViewGraph -> IO Solution
solveCSP config graph =
  solveWithInitialVars config (viewInitialVars graph) (viewConstraints graph)

solveCSPWithSeed :: RandomSeed -> ViewGraph -> IO Solution
solveCSPWithSeed seed = solveCSP defaultSolveConfig {initialSeed = seed}

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
    GlobalLayout body -> layoutConstraints body
    SelectionRelationLayout lhs lhsAttr relation rhs rhsAttr ->
      P.concatMap
        (selectionRelationConstraints lhsAttr relation rhsAttr)
        (matchingSelectionPairs lhs rhs nodes)
    SelectionBridgeLayout lhs lhsAttr lhsRelation gap gapConstraints rhsRelation rhs rhsAttr ->
      P.concatMap
        (selectionBridgeConstraints
           lhsAttr
           lhsRelation
           gap
           gapConstraints
           rhsRelation
           rhsAttr)
        (matchingSelectionPairs lhs rhs nodes)

matchingSelectionPairs ::
     NodeSelection
  -> NodeSelection
  -> [ViewNode]
  -> [(AnyLayoutView, AnyLayoutView)]
matchingSelectionPairs lhs rhs nodes =
  [ (firstNode, secondNode)
  | (firstNode, firstBindings) <- matchingSelectionNodes lhs nodes
  , (secondNode, secondBindings) <- matchingSelectionNodes rhs nodes
  , bindingsCompatible firstBindings secondBindings
  ]

matchingSelectionNodes ::
     NodeSelection -> [ViewNode] -> [(AnyLayoutView, PatternBindings)]
matchingSelectionNodes selection nodes =
  case nodes of
    [] -> []
    node:rest ->
      selectionNodeMatches selection node
        P.++ matchingSelectionNodes selection rest

selectionNodeMatches ::
     NodeSelection -> ViewNode -> [(AnyLayoutView, PatternBindings)]
selectionNodeMatches selection node =
  case selection of
    TraceSelection pattern' ->
      case node of
        BlockViewNode block ->
          case patternMatches pattern' (blockFacts block) of
            Nothing       -> []
            Just bindings -> [(AnyLayoutBlock block, bindings)]
        VirtualViewNode _ -> []
    VirtualSelection key pattern' ->
      case node of
        BlockViewNode _ -> []
        VirtualViewNode virtual
          | key P.== virtualNodeKey virtual
              P.&& pattern' P.== virtualPattern virtual ->
            [(AnyLayoutVirtual virtual, [])]
          | otherwise -> []

anyBlockPatternMatches ::
     Pattern -> AnyBlockView -> [(AnyBlockView, PatternBindings)]
anyBlockPatternMatches pattern' anyBlock =
  case anyBlock of
    AnyBlockView block ->
      case patternMatches pattern' (blockFacts block) of
        Nothing       -> []
        Just bindings -> [(anyBlock, bindings)]

bindingsCompatible :: PatternBindings -> PatternBindings -> P.Bool
bindingsCompatible lhs rhs =
  case mergePatternBindings lhs rhs of
    Nothing -> False
    Just _  -> True

mergePatternBindings ::
     PatternBindings -> PatternBindings -> Maybe PatternBindings
mergePatternBindings lhs rhs =
  case rhs of
    [] -> Just lhs
    (name, value):rest ->
      case bindPatternInt name value lhs of
        Nothing     -> Nothing
        Just merged -> mergePatternBindings merged rest

selectionRelationConstraints ::
     LayoutAttr
  -> LayoutRelation
  -> LayoutAttr
  -> (AnyLayoutView, AnyLayoutView)
  -> [Constraint]
selectionRelationConstraints lhsAttr relation rhsAttr pair' =
  case pair' of
    (lhs, rhs) ->
      [ relationConstraint
          relation
          (layoutViewAttr lhsAttr lhs)
          (layoutViewAttr rhsAttr rhs)
      ]

selectionBridgeConstraints ::
     LayoutAttr
  -> LayoutRelation
  -> LayoutExpr
  -> [Constraint]
  -> LayoutRelation
  -> LayoutAttr
  -> (AnyLayoutView, AnyLayoutView)
  -> [Constraint]
selectionBridgeConstraints lhsAttr lhsRelation gap gapConstraints rhsRelation rhsAttr pair' =
  case pair' of
    (lhs, rhs) ->
      gapConstraints
        P.++ [ bridgeRelationConstraint
                 lhsRelation
                 rhsRelation
                 (layoutViewAttr lhsAttr lhs)
                 gap
                 (layoutViewAttr rhsAttr rhs)
             ]

relationConstraint :: LayoutRelation -> LayoutExpr -> LayoutExpr -> Constraint
relationConstraint relation lhs rhs =
  case relation of
    LayoutEqual       -> lhs S.@==@ rhs
    LayoutLessOrEqual -> lhs S.@<=@ rhs

bridgeRelationConstraint ::
     LayoutRelation
  -> LayoutRelation
  -> LayoutExpr
  -> LayoutExpr
  -> LayoutExpr
  -> Constraint
bridgeRelationConstraint lhsRelation rhsRelation lhs gap rhs =
  case (lhsRelation, rhsRelation) of
    (LayoutEqual, LayoutEqual) -> lhs S.@+@ gap S.@==@ rhs
    _                          -> lhs S.@+@ gap S.@<=@ rhs

layoutViewAttr :: LayoutAttr -> AnyLayoutView -> LayoutExpr
layoutViewAttr attr view =
  case view of
    AnyLayoutBlock block     -> boundsAttr attr block
    AnyLayoutVirtual virtual -> boundsAttr attr virtual

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

layoutConstraints :: ViewBuilder () -> [Constraint]
layoutConstraints body =
  let (_result, output) = runViewBuilderWithOutput defaultViewEnv mempty body
   in emittedConstraints output

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
    VirtualRule key pattern' patch:rest ->
      case mergeVirtualRule key pattern' patch rest of
        (mergedPatch, remaining) ->
          VirtualRule key pattern' mergedPatch : mergedVirtualRules remaining

mergeVirtualRule ::
     P.String
  -> Pattern
  -> NodePatch
  -> [VirtualRule]
  -> (NodePatch, [VirtualRule])
mergeVirtualRule key pattern' patch rules =
  case rules of
    [] -> (patch, [])
    VirtualRule nextKey nextPattern nextPatch:rest ->
      case key P.== nextKey P.&& pattern' P.== nextPattern of
        True ->
          mergeVirtualRule key pattern' (appendNodePatch patch nextPatch) rest
        False ->
          case mergeVirtualRule key pattern' patch rest of
            (mergedPatch, remaining) ->
              ( mergedPatch
              , VirtualRule nextKey nextPattern nextPatch : remaining)

virtualNodeForRule :: [AnyBlockView] -> VirtualRule -> Maybe ViewNode
virtualNodeForRule blocks rule =
  case rule of
    VirtualRule key pattern' patch ->
      case matchingPatternBlocks pattern' blocks of
        [] -> Nothing
        children ->
          Just
            (VirtualViewNode
               (virtualViewForRule key pattern' patch children :: VirtualView ()))

matchingPatternBlocks :: Pattern -> [AnyBlockView] -> [AnyBlockView]
matchingPatternBlocks pattern' blocks =
  [ anyBlock
  | anyBlock <- blocks
  , (_matchedNode, _bindings) <- anyBlockPatternMatches pattern' anyBlock
  ]

virtualViewForRule ::
     P.String -> Pattern -> NodePatch -> [AnyBlockView] -> VirtualView tag
virtualViewForRule key pattern' patch children =
  let ref = C.BlockRef (virtualBlockId key pattern')
      baseStyle = styleForVirtual key pattern'
   in VirtualView
        { virtualRef = ref
        , virtualLabel = C.PayloadView ("Virtual." P.++ key) ""
        , virtualContent = Maybe.fromMaybe ContentEmpty (nodePatchContent patch)
        , virtualPattern = pattern'
        , virtualNodeKey = key
        , virtualPieceKey = defaultPieceKey
        , virtualStyle = nodePatchStyleUpdate patch baseStyle
        , virtualPatch = patch
        , virtualChildren = children
        }

virtualBlockId :: P.String -> Pattern -> C.BlockId
virtualBlockId key pattern' =
  negate (1 P.+ positiveHash (key P.++ ":" P.++ patternKey pattern'))

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

styleForVirtual :: P.String -> Pattern -> Style
styleForVirtual key pattern' =
  styleWithBounds
    (Bounds
       (virtualVar key pattern' "top")
       (virtualVar key pattern' "left")
       (virtualVar key pattern' "width")
       (virtualVar key pattern' "height"))

virtualVar :: SymbolicType ty => P.String -> Pattern -> P.String -> Expr ty
virtualVar key pattern' field =
  var (joinPath ["V", key, safeKey (patternKey pattern'), field])

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
  [ S.num 0 S.@<=@ left virtual
  , S.num 0 S.@<=@ top virtual
  , S.num 0 S.@<=@ width virtual
  , S.num 0 S.@<=@ height virtual
  ]

virtualFitConstraints :: VirtualView tag -> [Constraint]
virtualFitConstraints virtual =
  case virtualChildren virtual of
    [] -> []
    child:children ->
      [ left virtual
          S.@==@ foldLayoutExpr
                   minLayoutExpr
                   (anyBlockLeft child)
                   (P.map anyBlockLeft children)
      , top virtual
          S.@==@ foldLayoutExpr
                   minLayoutExpr
                   (anyBlockTop child)
                   (P.map anyBlockTop children)
      , right virtual
          S.@==@ foldLayoutExpr
                   maxLayoutExpr
                   (anyBlockRight child)
                   (P.map anyBlockRight children)
      , bottom virtual
          S.@==@ foldLayoutExpr
                   maxLayoutExpr
                   (anyBlockBottom child)
                   (P.map anyBlockBottom children)
      ]

foldLayoutExpr ::
     (LayoutExpr -> LayoutExpr -> LayoutExpr)
  -> LayoutExpr
  -> [LayoutExpr]
  -> LayoutExpr
foldLayoutExpr op initial exprs =
  case exprs of
    []        -> initial
    expr:rest -> foldLayoutExpr op (op initial expr) rest

minLayoutExpr :: LayoutExpr -> LayoutExpr -> LayoutExpr
minLayoutExpr lhs rhs =
  (lhs S.@+@ rhs S.@-@ S.absExpr (lhs S.@-@ rhs)) S.@/@ S.num 2

maxLayoutExpr :: LayoutExpr -> LayoutExpr -> LayoutExpr
maxLayoutExpr lhs rhs =
  (lhs S.@+@ rhs S.@+@ S.absExpr (lhs S.@-@ rhs)) S.@/@ S.num 2

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

virtualNodeInitialVars :: ViewNode -> [InitialVar]
virtualNodeInitialVars node =
  case node of
    BlockViewNode _ -> []
    VirtualViewNode virtual ->
      boundsInitialVars (styleBounds (virtualStyle virtual))
        P.++ styleInitialVars (virtualStyle virtual)

boundsInitialVars :: BoundsExpr -> [InitialVar]
boundsInitialVars bounds' =
  case bounds' of
    Bounds topExpr leftExpr widthExpr heightExpr ->
      exprInitialVars topExpr
        P.++ exprInitialVars leftExpr
        P.++ exprInitialVars widthExpr
        P.++ exprInitialVars heightExpr

addVirtualRenderFrames :: [ViewNode] -> [[RenderIntent]] -> [[RenderIntent]]
addVirtualRenderFrames nodes frames =
  let lifecycles = virtualLifecycles nodes
   in case lifecycles of
        [] -> frames
        _  -> addVirtualLifecycleFrames lifecycles frames

data VirtualLifecycle =
  VirtualLifecycle AnyVirtualView [C.BlockId] [C.BlockId]

virtualLifecycles :: [ViewNode] -> [VirtualLifecycle]
virtualLifecycles nodes =
  [ VirtualLifecycle (AnyVirtualView virtual) (virtualChildIds virtual) []
  | VirtualViewNode virtual <- nodes
  ]

virtualChildIds :: VirtualView tag -> [C.BlockId]
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

applyVirtualRenderIntent ::
     [C.BlockId] -> [C.BlockId] -> RenderIntent -> [C.BlockId]
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

addLiveChild :: [C.BlockId] -> C.BlockId -> [C.BlockId] -> [C.BlockId]
addLiveChild childIds blockId liveIds =
  case blockId `P.elem` childIds of
    False -> liveIds
    True ->
      case blockId `P.elem` liveIds of
        True  -> liveIds
        False -> blockId : liveIds

removeLiveChild :: C.BlockId -> [C.BlockId] -> [C.BlockId]
removeLiveChild blockId = P.filter (P./= blockId)

virtualFreshIntent :: AnyVirtualView -> RenderIntent
virtualFreshIntent anyVirtual =
  case anyVirtual of
    AnyVirtualView virtual -> RenderFresh (virtualRef virtual)

virtualRemoveIntent :: AnyVirtualView -> RenderIntent
virtualRemoveIntent anyVirtual =
  case anyVirtual of
    AnyVirtualView virtual -> RenderRemove (virtualRef virtual)

blockRefId :: C.BlockRef tag -> C.BlockId
blockRefId ref =
  case ref of
    C.BlockRef blockId -> blockId

data BuiltViewStep = BuiltViewStep
  { stepView                 :: ViewStep
  , stepNodes                :: [ViewNode]
  , stepConstraints          :: [Constraint]
  , stepInitialVars          :: [InitialVar]
  , stepRenderFrames         :: [[RenderIntent]]
  , stepPendingRenderIntents :: [RenderIntent]
  }

data BuiltViewSteps = BuiltViewSteps
  { builtSteps        :: [ViewStep]
  , builtNodes        :: [ViewNode]
  , builtConstraints  :: [Constraint]
  , builtInitialVars  :: [InitialVar]
  , builtRenderFrames :: [[RenderIntent]]
  }

viewTraceSteps :: [C.TraceStepWith ViewScript] -> BuiltViewSteps
viewTraceSteps = viewTraceStepsWith viewTraceStep [] [] [] [] [] []

viewTraceStepsWith ::
     ([RenderIntent] -> record -> BuiltViewStep)
  -> [ViewStep]
  -> [ViewNode]
  -> [Constraint]
  -> [InitialVar]
  -> [[RenderIntent]]
  -> [RenderIntent]
  -> [record]
  -> BuiltViewSteps
viewTraceStepsWith buildStep steps nodes constraints initialVars renderFrames pending records =
  case records of
    [] ->
      let finalOutput =
            flushPendingOutput mempty {pendingRenderIntents = pending}
          finalFrames = renderFrames ++ emittedRenderFrames finalOutput
       in BuiltViewSteps
            { builtSteps = steps
            , builtNodes = nodes
            , builtConstraints = constraints
            , builtInitialVars = initialVars
            , builtRenderFrames = withImplicitInitialFrame finalFrames
            }
    record:rest ->
      let builtStep = buildStep pending record
       in viewTraceStepsWith
            buildStep
            (steps ++ [stepView builtStep])
            (nodes ++ stepNodes builtStep)
            (constraints ++ stepConstraints builtStep)
            (initialVars ++ stepInitialVars builtStep)
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

viewTraceStep :: [RenderIntent] -> C.TraceStepWith ViewScript -> BuiltViewStep
viewTraceStep pending step =
  case step of
    C.ExplainedStep label (ViewScript rawOutput) audit ->
      let plainStep = C.ExplainedStep label C.NoStepPayload audit
          output = mergeInitialRenderIntents pending rawOutput
          nodes = emittedNodes output
          constraints = emittedConstraints output
          initialVars = emittedInitialVars output
          renderFrames = emittedRenderFrames output
       in BuiltViewStep
            { stepView = ViewStep plainStep nodes constraints []
            , stepNodes = nodes
            , stepConstraints = constraints
            , stepInitialVars = initialVars
            , stepRenderFrames = renderFrames
            , stepPendingRenderIntents = pendingRenderIntents output
            }
    C.DiscardedStep reason audit ->
      BuiltViewStep
        { stepView = ViewStep (C.DiscardedStep reason audit) [] [] []
        , stepNodes = []
        , stepConstraints = []
        , stepInitialVars = []
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

--------------------------------------------------------------------------------
-- Core block snapshots -> base block views
--------------------------------------------------------------------------------
blockViewOfSnapshot :: C.BlockSnapshot tag -> BlockView tag
blockViewOfSnapshot (C.BlockSnapshot ref payload payloadView facts) =
  BlockView
    { blockRef = ref
    , blockPayload = payload
    , blockLabel = payloadView
    , blockContent = ContentEmpty
    , blockFacts = facts
    , blockNodeKey = defaultNodeKey
    , blockPieceKey = defaultPieceKey
    , blockStyle = styleForRef ref
    }

defaultNodeKey :: P.String
defaultNodeKey = "block"

defaultPieceKey :: P.String
defaultPieceKey = "body"

styleForRef :: C.BlockRef tag -> Style
styleForRef ref = styleForBlockPath ref []

styleForBlockPath :: C.BlockRef tag -> [P.String] -> Style
styleForBlockPath ref path =
  styleWithBounds
    (Bounds
       (blockVarPath ref path "top")
       (blockVarPath ref path "left")
       (blockVarPath ref path "width")
       (blockVarPath ref path "height"))

blockVarPath ::
     SymbolicType ty => C.BlockRef tag -> [P.String] -> P.String -> Expr ty
blockVarPath (C.BlockRef blockId) path field =
  var (joinPath (("B" ++ P.show blockId) : (path P.++ [field])))

joinPath :: [P.String] -> P.String
joinPath parts =
  case parts of
    []        -> ""
    [part]    -> part
    part:rest -> part ++ "." ++ joinPath rest

viewToken :: C.AuditStep act -> ViewToken act
viewToken step =
  case step of
    C.CreateStep snapshot -> CreatedToken (blockViewOfSnapshot snapshot)
    C.ObserveStep snapshot -> ObservedToken (blockViewOfSnapshot snapshot)
    C.UseStep snapshot -> UsedToken (blockViewOfSnapshot snapshot)
    C.CopyStep original copy' ->
      CopiedToken (blockViewOfSnapshot original) (blockViewOfSnapshot copy')
    C.ReplaceStep old incoming output ->
      ReplacedToken
        (blockViewOfSnapshot old)
        (blockViewOfSnapshot incoming)
        (blockViewOfSnapshot output)
    C.ComputeStep snapshot -> ComputedToken (blockViewOfSnapshot snapshot)
    C.DestroyStep snapshot -> DestroyedToken (blockViewOfSnapshot snapshot)
    C.SealStep owner child ->
      SealedToken (blockViewOfSnapshot owner) (blockViewOfSnapshot child)
    C.UnsealStep owner child ->
      UnsealedToken (blockViewOfSnapshot owner) (blockViewOfSnapshot child)
    C.DecideStep snapshot -> DecidedToken (blockViewOfSnapshot snapshot)

--------------------------------------------------------------------------------
-- Style bounds / registration
--------------------------------------------------------------------------------
registerInitialStyleBounds :: Style -> ViewBuilder ()
registerInitialStyleBounds style' = do
  Ur env <- askViewEnv
  let canvasW = canvasWidthValue env
      canvasH = canvasHeightValue env
  registerInitialRange (left style') (Range 0 canvasW)
  registerInitialRange (top style') (Range 0 canvasH)
  registerInitialRange (width style') (Range 20 (max 20 (canvasW / 4)))
  registerInitialRange (height style') (Range 20 (max 20 (canvasH / 4)))
  traverseView_ registerInitialVar (styleInitialVars style')

constrainStyle :: Style -> ViewBuilder ()
constrainStyle style' = traverseView_ ensureRaw (styleConstraints style')
