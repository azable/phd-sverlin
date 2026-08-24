{-# LANGUAGE NoImplicitPrelude #-}

-- | Box-model and parent-relative layout declarations.
module LinearTrace.Choreography.Box
  ( Insets
  , uniform
  , symmetric
  , edges
  , padding
  , margin
  , Axis(..)
  , ContentFit(..)
  , contentFit
  , aspectRatio
  , Percent
  , percent
  , xAt
  , yAt
  , widthOf
  , heightOf
  ) where

import           LinearTrace.Choreography.Node (Span, VisualizationBuilder,
                                                editCanvasNode, editCurrentNode,
                                                spanConstraints, spanExpr)
import qualified LinearTrace.View.Box          as Box
import           LinearTrace.View.Graph        (Axis (..), ContentFit (..),
                                                RelativeLayoutAttr (..))
import qualified LinearTrace.View.Template     as Template
import qualified Prelude                       as P
import           Prelude.Linear
import qualified Solver                        as S

data Insets =
  Insets Box.InsetsExpr [S.Constraint]

uniform :: Span -> Insets
uniform value =
  Insets (Box.uniformInsets (spanExpr value)) (spanConstraints value)

symmetric :: Span -> Span -> Insets
symmetric vertical horizontal =
  Insets
    (Box.symmetricInsets (spanExpr vertical) (spanExpr horizontal))
    (spanConstraints vertical P.++ spanConstraints horizontal)

edges :: Span -> Span -> Span -> Span -> Insets
edges top right bottom left =
  Insets
    Box.EdgeInsets
      { Box.insetTop = spanExpr top
      , Box.insetRight = spanExpr right
      , Box.insetBottom = spanExpr bottom
      , Box.insetLeft = spanExpr left
      }
    (spanConstraints top
       P.++ spanConstraints right
       P.++ spanConstraints bottom
       P.++ spanConstraints left)

padding :: Insets -> VisualizationBuilder ()
padding (Insets insets constraints) =
  editCurrentNode
    "padding"
    (\_bindings template ->
       template
         { Template.templatePadding = Just insets
         , Template.templateConstraints =
             Template.templateConstraints template P.++ constraints
         })

margin :: Insets -> VisualizationBuilder ()
margin (Insets insets constraints) =
  editCurrentNode
    "margin"
    (\_bindings template ->
       template
         { Template.templateMargin = Just insets
         , Template.templateConstraints =
             Template.templateConstraints template P.++ constraints
         })

contentFit :: Axis -> ContentFit -> VisualizationBuilder ()
contentFit axis fit =
  editCurrentNode
    "contentFit"
    (\_bindings template ->
       case axis of
         Horizontal -> template {Template.templateHorizontalFit = fit}
         Vertical -> template {Template.templateVerticalFit = fit}
         Both ->
           template
             { Template.templateHorizontalFit = fit
             , Template.templateVerticalFit = fit
             })

aspectRatio :: P.Double -> P.Double -> VisualizationBuilder ()
aspectRatio horizontal vertical
  | invalid horizontal P.|| invalid vertical =
    P.error "aspectRatio components must be finite positive numbers"
  | P.otherwise =
    editCanvasNode
      "aspectRatio"
      (\_bindings template ->
         template
           {Template.templateAspectRatio = Just (horizontal P./ vertical)})
  where
    invalid value = value P.<= 0 P.|| P.isNaN value P.|| P.isInfinite value

newtype Percent =
  Percent P.Double

percent :: P.Double -> Percent
percent value
  | value P.< 0 P.|| value P.> 100 =
    P.error "A parent-relative percentage must be between 0 and 100."
  | P.otherwise = Percent (value P./ 100)

xAt :: Percent -> VisualizationBuilder ()
xAt = setPercentPin "xAt" RelativeCenterX setX
  where
    setX template pin = template {Template.templateX = pin}

yAt :: Percent -> VisualizationBuilder ()
yAt = setPercentPin "yAt" RelativeCenterY setY
  where
    setY template pin = template {Template.templateY = pin}

widthOf :: Percent -> VisualizationBuilder ()
widthOf = setPercentPin "widthOf" RelativeWidth setWidth
  where
    setWidth template pin = template {Template.templateWidth = pin}

heightOf :: Percent -> VisualizationBuilder ()
heightOf = setPercentPin "heightOf" RelativeHeight setHeight
  where
    setHeight template pin = template {Template.templateHeight = pin}

setPercentPin ::
     P.String
  -> RelativeLayoutAttr
  -> (Template.NodeTemplate -> Maybe Template.LayoutPin -> Template.NodeTemplate)
  -> Percent
  -> VisualizationBuilder ()
setPercentPin property attr setPin (Percent ratio) =
  editCurrentNode
    property
    (\_bindings template ->
       setPin template (Just (Template.parentPercentPin attr ratio)))
