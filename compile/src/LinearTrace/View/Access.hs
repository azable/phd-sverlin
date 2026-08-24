-- | Value-access bridge from view layout/style fields to solver components.
-- Choreography and match rules use this module to relate selected values while
-- keeping the top-level view facade free of query-specific APIs.
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}

module LinearTrace.View.Access
  ( -- * Endpoint values
    -- | Component projections over concrete selections. These feed
    -- choreography match relations and ultimately lower to solver components.
    ValueComponent
  , ValueAccess
  , LayoutAttr(..)
  , HslPart(..)
  , -- * Style requirements
    -- | Requirements that a value access can impose on a view node, currently
    -- used to ensure optional style fields exist before relating values.
    StyleRequirement
  , -- * Access constructors
    -- | Constructors and readers used by the DSL/match layer to turn layout or
    -- style fields into component endpoints.
    layoutValueAccess
  , styleValueAccess
  , styleColorPartValueAccess
  , styleChoiceValueAccess
  , valueAccessComponent
  , valueAccessRequirements
  , CategoryAccess
  , categoryAccessValue
  , categoryAccessRequirements
  , -- * Requirement application
    -- | Applies access-implied style fields to graph nodes before constraints
    -- are emitted.
    applyStyleRequirements
  ) where

import           Data.Kind                   (Type)
import           Data.Proxy                  (Proxy (..))
import           Data.Type.Equality          (type (~))
import           LinearTrace.View.Graph
import           LinearTrace.View.Primitives (ColorExpr, HasBounds (..),
                                              Hsl (..), LayoutExpr)
import           LinearTrace.View.Style
import           Prelude                     (Maybe (..))
import qualified Prelude                     as P
import qualified Solver                      as S
import           Solver                      (Component, Expr, SymbolicType)

type ValueComponent = Component

data HslPart
  = HslHue
  | HslSaturation
  | HslLightness
  deriving (P.Eq, P.Show)

data SomeStyleField where
  SomeStyleField :: StyleField field => Proxy field -> SomeStyleField

newtype StyleRequirement =
  RequireStyleField SomeStyleField

instance P.Show StyleRequirement where
  show requirement =
    case requirement of
      RequireStyleField some ->
        case some of
          SomeStyleField proxy -> "RequireStyleField " P.++ styleFieldName proxy

data ValueAccess =
  ValueAccess [StyleRequirement] (AnyLayoutView -> ValueComponent)

data CategoryAccess value =
  CategoryAccess [StyleRequirement] (AnyLayoutView -> ChoiceValue value)

layoutValueAccess :: LayoutAttr -> ValueAccess
layoutValueAccess field =
  ValueAccess [] (\view -> S.component (layoutViewField field view) [])

styleValueAccess ::
     forall field (ty :: Type).
     (StyleField field, StyleValue field ~ Expr ty, SymbolicType ty)
  => ValueAccess
styleValueAccess =
  ValueAccess
    [styleRequirement @field]
    (\view -> S.component (styleValue @field view) [])

styleColorPartValueAccess ::
     forall field. (StyleField field, StyleValue field ~ ColorExpr)
  => HslPart
  -> ValueAccess
styleColorPartValueAccess part =
  ValueAccess [styleRequirement @field] (styleColorPartComponent @field part)

styleChoiceValueAccess ::
     forall field value.
     (StyleField field, StyleValue field ~ ChoiceValue value)
  => CategoryAccess value
styleChoiceValueAccess =
  CategoryAccess [styleRequirement @field] (styleValue @field)

styleRequirement ::
     forall field. StyleField field
  => StyleRequirement
styleRequirement = RequireStyleField (SomeStyleField (Proxy @field))

valueAccessComponent :: ValueAccess -> AnyLayoutView -> ValueComponent
valueAccessComponent access view =
  case access of
    ValueAccess _ project -> project view

valueAccessRequirements :: ValueAccess -> [StyleRequirement]
valueAccessRequirements access =
  case access of
    ValueAccess requirements _ -> requirements

categoryAccessValue ::
     CategoryAccess value -> AnyLayoutView -> ChoiceValue value
categoryAccessValue access view =
  case access of
    CategoryAccess _ project -> project view

categoryAccessRequirements :: CategoryAccess value -> [StyleRequirement]
categoryAccessRequirements access =
  case access of
    CategoryAccess requirements _ -> requirements

layoutViewField :: LayoutAttr -> AnyLayoutView -> LayoutExpr
layoutViewField field view =
  case view of
    AnyLayoutView node -> boundsField field node

layoutViewStyle :: AnyLayoutView -> NodeStyle
layoutViewStyle view =
  case view of
    AnyLayoutView node -> nodeStyle node

styleValue ::
     forall field. StyleField field
  => AnyLayoutView
  -> StyleValue field
styleValue view =
  case getStyleField @field (layoutViewStyle view) of
    Just value -> value
    Nothing    -> generatedStyleValue (Proxy @field) (styleValueVarsFor view)

styleValueVarsFor :: AnyLayoutView -> StyleValueVars
styleValueVarsFor view =
  case view of
    AnyLayoutView node ->
      let root = nodeRoot node
       in StyleValueVars
            { styleExprVar = \path name -> nodeVar root ("style" : path) name
            , styleChoiceVar = S.choice P.. nodeVarName root ["style"]
            }

nodeRoot :: Node tag -> NodeVarRoot
nodeRoot node =
  case nodeOrigin node of
    CanvasOrigin _       -> canvasNodeRoot
    TraceOrigin _        -> traceNodeRoot (nodeRef node)
    GeneratedOrigin meta -> generatedNodeRoot (generatedKey meta)

boundsField :: LayoutAttr -> Node tag -> LayoutExpr
boundsField field node =
  case field of
    AttrLeft    -> left node
    AttrRight   -> right node
    AttrWidth   -> width node
    AttrCenterX -> centerX node
    AttrTop     -> top node
    AttrBottom  -> bottom node
    AttrHeight  -> height node
    AttrCenterY -> centerY node

styleColorPartComponent ::
     forall field. (StyleField field, StyleValue field ~ ColorExpr)
  => HslPart
  -> AnyLayoutView
  -> ValueComponent
styleColorPartComponent part view =
  let value = styleValue @field view
   in case part of
        HslHue        -> S.component (hue value) []
        HslSaturation -> S.component (saturation value) []
        HslLightness  -> S.component (lightness value) []

applyStyleRequirements :: [StyleRequirement] -> ViewNode -> ViewNode
applyStyleRequirements requirements node =
  case requirements of
    [] -> node
    requirement:rest ->
      applyStyleRequirements rest (applyStyleRequirement requirement node)

applyStyleRequirement :: StyleRequirement -> ViewNode -> ViewNode
applyStyleRequirement requirement node =
  case node of
    ViewNode viewNode ->
      ViewNode
        viewNode
          { nodeStyle =
              requireStyleForView
                (AnyLayoutView viewNode)
                requirement
                (nodeStyle viewNode)
          }

requireStyleForView ::
     AnyLayoutView -> StyleRequirement -> NodeStyle -> NodeStyle
requireStyleForView view requirement style' =
  case requirement of
    RequireStyleField some ->
      case some of
        SomeStyleField (_ :: Proxy field) ->
          requireStyleField @field (styleValueVarsFor view) style'
