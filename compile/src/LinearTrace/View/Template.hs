{-# LANGUAGE RankNTypes #-}

-- | Declarative updates collected by one public @node@ declaration.
module LinearTrace.View.Template
  ( LayoutPin(..)
  , parentPercentPin
  , NodeTemplate(..)
  , emptyNodeTemplate
  , mapNodeTemplateExprs
  , substituteNodeTemplateVars
  , templateGeometryConstraints
  , applyNodeTemplate
  , updateTemplateContent
  ) where

import           Data.Kind                   (Type)
import           Data.Maybe                  (fromMaybe)
import           LinearTrace.View.Box        (InsetsExpr, mapInsets,
                                              setNodeMargin, setNodePadding)
import           LinearTrace.View.Graph      (ContentFit (..), ContentMode,
                                              Node (..), RelativeLayoutAttr,
                                              RelativeLayoutPin (..))
import           LinearTrace.View.Primitives (HasBounds (..), LayoutExpr)
import           LinearTrace.View.Style      (NodeStyle, emptyNodeStyle,
                                              mapNodeStyleExprs)
import           Prelude                     (Maybe (..))
import qualified Prelude                     as P
import qualified Solver                      as S
import           Solver                      (Constraint)

data LayoutPin
  = LayoutPin LayoutExpr [Constraint]
  | ParentPercentPin RelativeLayoutAttr P.Double

parentPercentPin :: RelativeLayoutAttr -> P.Double -> LayoutPin
parentPercentPin = ParentPercentPin

data NodeTemplate = NodeTemplate
  { templateStyle         :: NodeStyle
  , templateContent       :: Maybe ContentMode
  , templatePadding       :: Maybe InsetsExpr
  , templateMargin        :: Maybe InsetsExpr
  , templateHorizontalFit :: ContentFit
  , templateVerticalFit   :: ContentFit
  , templateConstraints   :: [Constraint]
  , templateLeft          :: Maybe LayoutPin
  , templateTop           :: Maybe LayoutPin
  , templateWidth         :: Maybe LayoutPin
  , templateHeight        :: Maybe LayoutPin
  , templateRight         :: Maybe LayoutPin
  , templateBottom        :: Maybe LayoutPin
  , templateX             :: Maybe LayoutPin
  , templateY             :: Maybe LayoutPin
  }

emptyNodeTemplate :: NodeTemplate
emptyNodeTemplate =
  NodeTemplate
    { templateStyle = emptyNodeStyle
    , templateContent = Nothing
    , templatePadding = Nothing
    , templateMargin = Nothing
    , templateHorizontalFit = Hug
    , templateVerticalFit = Hug
    , templateConstraints = []
    , templateLeft = Nothing
    , templateTop = Nothing
    , templateWidth = Nothing
    , templateHeight = Nothing
    , templateRight = Nothing
    , templateBottom = Nothing
    , templateX = Nothing
    , templateY = Nothing
    }

mapNodeTemplateExprs ::
     (forall (ty :: Type). S.Expr ty -> S.Expr ty)
  -> NodeTemplate
  -> NodeTemplate
mapNodeTemplateExprs f template =
  template
    { templateStyle = mapNodeStyleExprs f (templateStyle template)
    , templatePadding = P.fmap (mapInsets f) (templatePadding template)
    , templateMargin = P.fmap (mapInsets f) (templateMargin template)
    , templateLeft = P.fmap (mapLayoutPin f) (templateLeft template)
    , templateTop = P.fmap (mapLayoutPin f) (templateTop template)
    , templateWidth = P.fmap (mapLayoutPin f) (templateWidth template)
    , templateHeight = P.fmap (mapLayoutPin f) (templateHeight template)
    , templateRight = P.fmap (mapLayoutPin f) (templateRight template)
    , templateBottom = P.fmap (mapLayoutPin f) (templateBottom template)
    , templateX = P.fmap (mapLayoutPin f) (templateX template)
    , templateY = P.fmap (mapLayoutPin f) (templateY template)
    }

substituteNodeTemplateVars ::
     [(P.String, P.Double)] -> NodeTemplate -> NodeTemplate
substituteNodeTemplateVars substitutions template =
  (mapNodeTemplateExprs (S.substituteExprVars substitutions) template)
    { templateConstraints =
        P.map
          (S.substituteConstraintVars substitutions)
          (templateConstraints template)
    , templateLeft = substitutePin (templateLeft template)
    , templateTop = substitutePin (templateTop template)
    , templateWidth = substitutePin (templateWidth template)
    , templateHeight = substitutePin (templateHeight template)
    , templateRight = substitutePin (templateRight template)
    , templateBottom = substitutePin (templateBottom template)
    , templateX = substitutePin (templateX template)
    , templateY = substitutePin (templateY template)
    }
  where
    substitutePin = P.fmap substituteOnePin
    substituteOnePin pin =
      case pin of
        LayoutPin expression constraints ->
          LayoutPin
            (S.substituteExprVars substitutions expression)
            (P.map (S.substituteConstraintVars substitutions) constraints)
        ParentPercentPin attr ratio -> ParentPercentPin attr ratio

mapLayoutPin ::
     (forall (ty :: Type). S.Expr ty -> S.Expr ty) -> LayoutPin -> LayoutPin
mapLayoutPin f pin =
  case pin of
    LayoutPin expression constraints -> LayoutPin (f expression) constraints
    ParentPercentPin attr ratio      -> ParentPercentPin attr ratio

templateGeometryConstraints :: NodeTemplate -> Node tag -> [Constraint]
templateGeometryConstraints template node =
  pinConstraints (left node) (templateLeft template)
    P.++ pinConstraints (top node) (templateTop template)
    P.++ pinConstraints (width node) (templateWidth template)
    P.++ pinConstraints (height node) (templateHeight template)
    P.++ pinConstraints (right node) (templateRight template)
    P.++ pinConstraints (bottom node) (templateBottom template)
    P.++ pinConstraints (centerX node) (templateX template)
    P.++ pinConstraints (centerY node) (templateY template)

pinConstraints :: LayoutExpr -> Maybe LayoutPin -> [Constraint]
pinConstraints expression maybePin =
  case maybePin of
    Nothing -> []
    Just (LayoutPin target constraints) ->
      constraints P.++ [expression S.@==@ target]
    Just (ParentPercentPin _ _) -> []

applyNodeTemplate :: NodeTemplate -> Node tag -> Node tag
applyNodeTemplate template node0 =
  let boxWithPadding =
        case templatePadding template of
          Nothing    -> nodeBox node0
          Just value -> setNodePadding value (nodeBox node0)
      box =
        case templateMargin template of
          Nothing    -> boxWithPadding
          Just value -> setNodeMargin value boxWithPadding
      node =
        node0
          { nodeStyle = templateStyle template
          , nodeContent =
              fromMaybe (nodeContent node0) (templateContent template)
          , nodeBox = box
          , nodeHorizontalFit = templateHorizontalFit template
          , nodeVerticalFit = templateVerticalFit template
          , nodeRelativePins = templateRelativePins template
          }
   in node
        { nodeConstraints =
            nodeConstraints node
              P.++ templateConstraints template
              P.++ templateGeometryConstraints template node
        }

templateRelativePins :: NodeTemplate -> [RelativeLayoutPin]
templateRelativePins template =
  [ RelativeLayoutPin attr ratio
  | Just (ParentPercentPin attr ratio) <-
      [ templateX template
      , templateY template
      , templateWidth template
      , templateHeight template
      ]
  ]

updateTemplateContent ::
     P.String -> (ContentMode -> ContentMode) -> NodeTemplate -> NodeTemplate
updateTemplateContent helper transform template =
  case templateContent template of
    Nothing      -> P.error (helper P.++ " must wrap a content declaration")
    Just current -> template {templateContent = Just (transform current)}
