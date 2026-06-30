-- | Value-access bridge from view layout/style fields to solver components.
-- Choreography and match rules use this module to relate selected values while
-- keeping the top-level view facade free of query-specific APIs.
{-# LANGUAGE GADTs #-}

module LinearTrace.View.Access
  ( -- * Endpoint values
    -- | Component projections over concrete selections. These feed
    -- choreography match relations and ultimately lower to solver components.
    ValueComponent
  , ValueAccess
  , LayoutAttr(..)
  , StyleScalarAttr(..)
  , StyleColorAttr(..)
  , StyleCategoryAttr(..)
  , HslPart(..)
  , -- * Style requirements
    -- | Requirements that a value access can impose on a view node, currently
    -- used to ensure optional style fields exist before relating values.
    StyleRequirement(..)
  , -- * Access constructors
    -- | Constructors and readers used by the DSL/match layer to turn layout or
    -- style attributes into component endpoints.
    layoutValueAccess
  , styleScalarValueAccess
  , styleColorPartValueAccess
  , styleCategoryValueAccess
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

import qualified Data.Maybe                  as Maybe
import           LinearTrace.View.Graph
import           LinearTrace.View.Primitives
import           LinearTrace.View.Style
import           Prelude                     (Maybe (..))
import qualified Prelude                     as P
import qualified Solver                      as S
import           Solver                      (Choice, Component, Expr,
                                              SymbolicType)

type ValueComponent = Component

data StyleScalarAttr ty where
  StyleFontSize :: StyleScalarAttr LayoutDomain
  StyleRadius :: StyleScalarAttr LayoutDomain
  StylePadding :: StyleScalarAttr LayoutDomain
  StyleStrokeWidth :: StyleScalarAttr LayoutDomain
  StyleOpacity :: StyleScalarAttr UnitDomain
  StyleAlpha :: StyleScalarAttr UnitDomain
  StyleZIndex :: StyleScalarAttr FreeDomain

data StyleColorAttr
  = StyleFill
  | StyleStroke
  deriving (P.Eq, P.Show)

data StyleCategoryAttr value where
  StyleFontFamily :: StyleCategoryAttr FontFamily
  StyleFontWeight :: StyleCategoryAttr FontWeight
  StyleFontStyle :: StyleCategoryAttr FontStyle
  StyleTextAlign :: StyleCategoryAttr TextAlign
  StyleBorderStyle :: StyleCategoryAttr BorderStyle
  StyleWhiteSpace :: StyleCategoryAttr WhiteSpace

data HslPart
  = HslHue
  | HslSaturation
  | HslLightness
  deriving (P.Eq, P.Show)

data SomeStyleCategoryAttr where
  SomeStyleCategoryAttr :: StyleCategoryAttr value -> SomeStyleCategoryAttr

data SomeStyleScalarAttr where
  SomeStyleScalarAttr :: StyleScalarAttr ty -> SomeStyleScalarAttr

data StyleRequirement
  = RequireScalar SomeStyleScalarAttr
  | RequireColor StyleColorAttr
  | RequireCategory SomeStyleCategoryAttr

instance P.Show StyleRequirement where
  show requirement =
    case requirement of
      RequireScalar some ->
        case some of
          SomeStyleScalarAttr attr ->
            "RequireScalar " P.++ styleScalarAccessName attr
      RequireColor color -> "RequireColor " P.++ P.show color
      RequireCategory some ->
        case some of
          SomeStyleCategoryAttr attr ->
            "RequireCategory " P.++ styleCategoryAccessName attr

data ValueAccess =
  ValueAccess [StyleRequirement] (AnyLayoutView -> ValueComponent)

data CategoryAccess value =
  CategoryAccess [StyleRequirement] (AnyLayoutView -> StyleCategory value)

layoutValueAccess :: LayoutAttr -> ValueAccess
layoutValueAccess attr =
  ValueAccess [] (\view -> S.component (layoutViewAttr attr view) [])

styleScalarValueAccess :: StyleScalarAttr ty -> ValueAccess
styleScalarValueAccess attr =
  ValueAccess
    [RequireScalar (SomeStyleScalarAttr attr)]
    (styleScalarComponent attr)

styleScalarComponent :: StyleScalarAttr ty -> AnyLayoutView -> ValueComponent
styleScalarComponent attr view =
  case attr of
    StyleFontSize    -> componentFor attr view
    StyleRadius      -> componentFor attr view
    StylePadding     -> componentFor attr view
    StyleStrokeWidth -> componentFor attr view
    StyleOpacity     -> componentFor attr view
    StyleAlpha       -> componentFor attr view
    StyleZIndex      -> componentFor attr view

componentFor ::
     SymbolicType ty => StyleScalarAttr ty -> AnyLayoutView -> ValueComponent
componentFor attr view = S.component (styleScalarAttr attr view) []

styleColorPartValueAccess :: StyleColorAttr -> HslPart -> ValueAccess
styleColorPartValueAccess color part =
  ValueAccess [RequireColor color] (styleColorPartComponent color part)

styleCategoryValueAccess :: StyleCategoryAttr value -> CategoryAccess value
styleCategoryValueAccess attr =
  CategoryAccess
    [RequireCategory (SomeStyleCategoryAttr attr)]
    (styleCategoryValue attr)

valueAccessComponent :: ValueAccess -> AnyLayoutView -> ValueComponent
valueAccessComponent access view =
  case access of
    ValueAccess _ project -> project view

valueAccessRequirements :: ValueAccess -> [StyleRequirement]
valueAccessRequirements access =
  case access of
    ValueAccess requirements _ -> requirements

categoryAccessValue ::
     CategoryAccess value -> AnyLayoutView -> StyleCategory value
categoryAccessValue access view =
  case access of
    CategoryAccess _ project -> project view

categoryAccessRequirements :: CategoryAccess value -> [StyleRequirement]
categoryAccessRequirements access =
  case access of
    CategoryAccess requirements _ -> requirements

layoutViewAttr :: LayoutAttr -> AnyLayoutView -> LayoutExpr
layoutViewAttr attr view =
  case view of
    AnyLayoutView node -> boundsAttr attr node

layoutViewStyle :: AnyLayoutView -> Style
layoutViewStyle view =
  case view of
    AnyLayoutView node -> nodeStyle node

styleScalarAttr :: StyleScalarAttr ty -> AnyLayoutView -> Expr ty
styleScalarAttr attr view =
  Maybe.fromMaybe (requiredStyleScalar attr view) maybeValue
  where
    style' = layoutViewStyle view
    maybeValue = styleScalarValue attr style'

styleScalarValue :: StyleScalarAttr ty -> Style -> Maybe (Expr ty)
styleScalarValue attr style' =
  case attr of
    StyleFontSize    -> fontSize style'
    StyleRadius      -> radius style'
    StylePadding     -> padding style'
    StyleStrokeWidth -> strokeWidth style'
    StyleOpacity     -> opacity style'
    StyleAlpha       -> alpha style'
    StyleZIndex      -> zIndex style'

requiredStyleScalar :: StyleScalarAttr ty -> AnyLayoutView -> Expr ty
requiredStyleScalar = styleScalarVar

styleScalarVar :: StyleScalarAttr ty -> AnyLayoutView -> Expr ty
styleScalarVar attr view =
  case attr of
    StyleFontSize    -> varFor attr view
    StyleRadius      -> varFor attr view
    StylePadding     -> varFor attr view
    StyleStrokeWidth -> varFor attr view
    StyleOpacity     -> varFor attr view
    StyleAlpha       -> varFor attr view
    StyleZIndex      -> varFor attr view

varFor :: SymbolicType ty => StyleScalarAttr ty -> AnyLayoutView -> Expr ty
varFor attr view =
  case view of
    AnyLayoutView node ->
      nodeVar (nodeRoot node) ["style"] (styleScalarAccessName attr)

styleScalarAccessName :: StyleScalarAttr ty -> P.String
styleScalarAccessName attr =
  case attr of
    StyleFontSize    -> "fontSize"
    StyleRadius      -> "radius"
    StylePadding     -> "padding"
    StyleStrokeWidth -> "strokeWidth"
    StyleOpacity     -> "opacity"
    StyleAlpha       -> "alpha"
    StyleZIndex      -> "zIndex"

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
  Maybe.fromMaybe (requiredStyleColor color view) maybeColor
  where
    maybeColor =
      case color of
        StyleFill   -> fill (layoutViewStyle view)
        StyleStroke -> stroke (layoutViewStyle view)

requiredStyleColor :: StyleColorAttr -> AnyLayoutView -> ColorExpr
requiredStyleColor color view =
  Hsl
    (styleColorVar color view "hue")
    (styleColorVar color view "saturation")
    (styleColorVar color view "lightness")

styleColorVar ::
     SymbolicType ty => StyleColorAttr -> AnyLayoutView -> P.String -> Expr ty
styleColorVar color view part =
  case view of
    AnyLayoutView node ->
      nodeVar (nodeRoot node) ["style", styleColorName color] part

styleColorName :: StyleColorAttr -> P.String
styleColorName color =
  case color of
    StyleFill   -> "fill"
    StyleStroke -> "stroke"

styleCategoryValue ::
     StyleCategoryAttr value -> AnyLayoutView -> StyleCategory value
styleCategoryValue attr view =
  Maybe.fromMaybe (requiredStyleCategory attr view) maybeCategory
  where
    maybeCategory =
      case attr of
        StyleFontFamily  -> fontFamily (layoutViewStyle view)
        StyleFontWeight  -> fontWeight (layoutViewStyle view)
        StyleFontStyle   -> fontStyle (layoutViewStyle view)
        StyleTextAlign   -> textAlign (layoutViewStyle view)
        StyleBorderStyle -> borderStyle (layoutViewStyle view)
        StyleWhiteSpace  -> whiteSpace (layoutViewStyle view)

requiredStyleCategory ::
     StyleCategoryAttr value -> AnyLayoutView -> StyleCategory value
requiredStyleCategory attr view =
  VariableCategory (styleCategoryChoice attr view)

styleCategoryChoice :: StyleCategoryAttr value -> AnyLayoutView -> Choice value
styleCategoryChoice attr view =
  case attr of
    StyleFontFamily  -> S.choice name
    StyleFontWeight  -> S.choice name
    StyleFontStyle   -> S.choice name
    StyleTextAlign   -> S.choice name
    StyleBorderStyle -> S.choice name
    StyleWhiteSpace  -> S.choice name
  where
    name = styleCategoryChoiceName attr view

styleCategoryChoiceName :: StyleCategoryAttr value -> AnyLayoutView -> P.String
styleCategoryChoiceName attr view =
  case view of
    AnyLayoutView node ->
      nodeVarName (nodeRoot node) ["style"] (styleCategoryAccessName attr)

nodeRoot :: Node tag -> NodeVarRoot
nodeRoot node =
  case nodeOrigin node of
    TraceOrigin _ -> traceNodeRoot (nodeRef node)
    GeneratedOrigin meta ->
      generatedNodeRoot (generatedKey meta) (generatedQueryKey meta)

styleCategoryAccessName :: StyleCategoryAttr value -> P.String
styleCategoryAccessName attr =
  case attr of
    StyleFontFamily  -> "fontFamily"
    StyleFontWeight  -> "fontWeight"
    StyleFontStyle   -> "fontStyle"
    StyleTextAlign   -> "textAlign"
    StyleBorderStyle -> "borderStyle"
    StyleWhiteSpace  -> "whiteSpace"

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

requireStyleForView :: AnyLayoutView -> StyleRequirement -> Style -> Style
requireStyleForView view requirement style' =
  case requirement of
    RequireScalar some ->
      case some of
        SomeStyleScalarAttr attr ->
          requireScalarField attr (requiredStyleScalar attr view) style'
    RequireColor color ->
      requireColorField color (requiredStyleColor color view) style'
    RequireCategory some ->
      case some of
        SomeStyleCategoryAttr attr ->
          requireCategoryField attr (requiredStyleCategory attr view) style'

requireScalarField :: StyleScalarAttr ty -> Expr ty -> Style -> Style
requireScalarField attr value style' =
  case attr of
    StyleFontSize    -> requirePresent fontSize (setFontSize value) style'
    StyleRadius      -> requirePresent radius (setRadius value) style'
    StylePadding     -> requirePresent padding (setPadding value) style'
    StyleStrokeWidth -> requirePresent strokeWidth (setStrokeWidth value) style'
    StyleOpacity     -> requirePresent opacity (setOpacity value) style'
    StyleAlpha       -> requirePresent alpha (setAlpha value) style'
    StyleZIndex      -> requirePresent zIndex (setZIndex value) style'

requireColorField :: StyleColorAttr -> ColorExpr -> Style -> Style
requireColorField color value style' =
  case color of
    StyleFill ->
      case fill style' of
        Nothing -> setFill value style'
        Just _  -> style'
    StyleStroke ->
      case stroke style' of
        Nothing -> setStroke value style'
        Just _  -> style'

requirePresent :: (Style -> Maybe value) -> (Style -> Style) -> Style -> Style
requirePresent getValue setValue style' =
  case getValue style' of
    Nothing -> setValue style'
    Just _  -> style'

requireCategoryField ::
     StyleCategoryAttr value -> StyleCategory value -> Style -> Style
requireCategoryField attr value style' =
  case attr of
    StyleFontFamily ->
      case fontFamily style' of
        Nothing -> setFontFamily value style'
        Just _  -> style'
    StyleFontWeight ->
      case fontWeight style' of
        Nothing -> setFontWeight value style'
        Just _  -> style'
    StyleFontStyle ->
      case fontStyle style' of
        Nothing -> setFontStyle value style'
        Just _  -> style'
    StyleTextAlign ->
      case textAlign style' of
        Nothing -> setTextAlign value style'
        Just _  -> style'
    StyleBorderStyle ->
      case borderStyle style' of
        Nothing -> setBorderStyle value style'
        Just _  -> style'
    StyleWhiteSpace ->
      case whiteSpace style' of
        Nothing -> setWhiteSpace value style'
        Just _  -> style'
