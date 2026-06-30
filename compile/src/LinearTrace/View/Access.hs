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
  , StyleLayoutAttr(..)
  , StyleUnitAttr(..)
  , StyleFreeAttr(..)
  , StyleColorAttr(..)
  , StyleCategoryAttr(..)
  , HslPart(..)
  , -- * Style requirements
    -- | Requirements that a value access can impose on a view node, currently
    -- used to ensure optional colour fields exist before relating HSL parts.
    StyleRequirement(..)
  , -- * Access constructors
    -- | Constructors and readers used by the DSL/match layer to turn layout or
    -- style attributes into component endpoints.
    layoutValueAccess
  , styleLayoutValueAccess
  , styleUnitValueAccess
  , styleFreeValueAccess
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

data StyleRequirement
  = RequireColor StyleColorAttr
  | RequireCategory SomeStyleCategoryAttr

instance P.Show StyleRequirement where
  show requirement =
    case requirement of
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
    RequireColor color ->
      requireColorField color (requiredStyleColor color view) style'
    RequireCategory some ->
      case some of
        SomeStyleCategoryAttr attr ->
          requireCategoryField attr (requiredStyleCategory attr view) style'

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
