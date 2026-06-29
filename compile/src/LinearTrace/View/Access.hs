module LinearTrace.View.Access
  ( ValueComponent
  , ValueAccess
  , LayoutAttr(..)
  , StyleLayoutAttr(..)
  , StyleUnitAttr(..)
  , StyleFreeAttr(..)
  , StyleColorAttr(..)
  , HslPart(..)
  , StyleRequirement(..)
  , layoutValueAccess
  , styleLayoutValueAccess
  , styleUnitValueAccess
  , styleFreeValueAccess
  , styleColorPartValueAccess
  , valueAccessComponent
  , valueAccessRequirements
  , applyStyleRequirements
  ) where

import qualified Data.Maybe             as Maybe
import           LinearTrace.View.Graph
import           LinearTrace.View.Style
import           Prelude                (Maybe (..))
import qualified Prelude                as P
import qualified Solver                 as S
import           Solver                 (Component, Expr, SymbolicType)

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

newtype StyleRequirement =
  RequireColor StyleColorAttr
  deriving (P.Eq, P.Show)

data ValueAccess =
  ValueAccess [StyleRequirement] (AnyLayoutView -> ValueComponent)

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

valueAccessComponent :: ValueAccess -> AnyLayoutView -> ValueComponent
valueAccessComponent access view =
  case access of
    ValueAccess _ project -> project view

valueAccessRequirements :: ValueAccess -> [StyleRequirement]
valueAccessRequirements access =
  case access of
    ValueAccess requirements _ -> requirements

layoutViewAttr :: LayoutAttr -> AnyLayoutView -> LayoutExpr
layoutViewAttr attr view =
  case view of
    AnyLayoutBlock block     -> boundsAttr attr block
    AnyLayoutVirtual virtual -> boundsAttr attr virtual

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

applyStyleRequirements :: [StyleRequirement] -> ViewNode -> ViewNode
applyStyleRequirements requirements node =
  case requirements of
    [] -> node
    requirement:rest ->
      applyStyleRequirements rest (applyStyleRequirement requirement node)

applyStyleRequirement :: StyleRequirement -> ViewNode -> ViewNode
applyStyleRequirement requirement node =
  case node of
    BlockViewNode block ->
      BlockViewNode
        block
          { blockStyle =
              requireStyleForView
                (AnyLayoutBlock block)
                requirement
                (blockStyle block)
          }
    VirtualViewNode virtual ->
      VirtualViewNode
        virtual
          { virtualStyle =
              requireStyleForView
                (AnyLayoutVirtual virtual)
                requirement
                (virtualStyle virtual)
          }

requireStyleForView :: AnyLayoutView -> StyleRequirement -> Style -> Style
requireStyleForView view requirement style' =
  case requirement of
    RequireColor color ->
      requireColorField color (requiredStyleColor color view) style'

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
