{-# LANGUAGE GADTs #-}

module LinearTrace.View.Materialize
  ( ConcreteBounds
  , ConcreteHsl
  , ConcreteStyle(..)
  , ConcreteField(..)
  , ConcreteScalar(..)
  , ConcreteColor(..)
  , ConcreteDiscrete
  , ConcreteBlockView(..)
  , ConcreteVirtualView(..)
  , ConcreteViewNode(..)
  , ConcreteViewGraph(..)
  , concreteTop
  , concreteLeft
  , concreteWidth
  , concreteHeight
  , concreteScalarValue
  , concreteScalars
  , concreteColors
  , concreteDiscrete
  , materializeViewGraph
  , materializeViewNode
  , materializeStyle
  , materializeBounds
  , materializeHsl
  ) where

import           LinearTrace.View.Graph
import           LinearTrace.View.Primitives
import           LinearTrace.View.Style
import           LinearTrace.View.Types      (ContentMode (..), ViewLabel,
                                              ViewRef)
import           Prelude
import           Solver                      (Expr, Solution, categoryName,
                                              evalChoice, evalExpr)

data ConcreteStyle = ConcreteStyle
  { concreteBounds :: ConcreteBounds
  , concreteFields :: [ConcreteField]
  } deriving (Eq, Show)

data ConcreteField
  = ConcreteScalarField String (Maybe String) Double StyleValueUnit
  | ConcreteColorField String (Maybe String) (Maybe ConcreteHsl)
  | ConcreteTextField String (Maybe String) (Maybe StyleText)
  | ConcreteChoiceField String (Maybe String) (Maybe String) DiscreteStyleValue
  deriving (Eq, Show)

data ConcreteScalar =
  ConcreteScalar String Double StyleValueUnit
  deriving (Eq, Show)

data ConcreteColor =
  ConcreteColor String (Maybe ConcreteHsl)
  deriving (Eq, Show)

type ConcreteDiscrete = DiscreteStyleValue

data ConcreteBlockView tag = ConcreteBlockView
  { concreteBlockRef      :: ViewRef tag
  , concreteBlockLabel    :: ViewLabel
  , concreteBlockContent  :: String
  , concreteBlockNodeKey  :: String
  , concreteBlockPieceKey :: String
  , concreteBlockStyle    :: ConcreteStyle
  }

data ConcreteVirtualView tag = ConcreteVirtualView
  { concreteVirtualRef      :: ViewRef tag
  , concreteVirtualLabel    :: ViewLabel
  , concreteVirtualContent  :: String
  , concreteVirtualNodeKey  :: String
  , concreteVirtualPieceKey :: String
  , concreteVirtualStyle    :: ConcreteStyle
  }

data ConcreteViewNode where
  ConcreteBlockViewNode :: ConcreteBlockView tag -> ConcreteViewNode
  ConcreteVirtualViewNode :: ConcreteVirtualView tag -> ConcreteViewNode

data ConcreteViewGraph = ConcreteViewGraph
  { concreteViewNodes        :: [ConcreteViewNode]
  , concreteViewRenderFrames :: [[RenderIntent]]
  }

concreteTop :: ConcreteStyle -> Double
concreteTop = boundsTop . concreteBounds

concreteLeft :: ConcreteStyle -> Double
concreteLeft = boundsLeft . concreteBounds

concreteWidth :: ConcreteStyle -> Double
concreteWidth = boundsWidth . concreteBounds

concreteHeight :: ConcreteStyle -> Double
concreteHeight = boundsHeight . concreteBounds

concreteScalarValue :: String -> Double -> ConcreteStyle -> Double
concreteScalarValue name fallback style' = go (concreteFields style')
  where
    go fields =
      case fields of
        [] -> fallback
        ConcreteScalarField name' _ value _:rest
          | name == name' -> value
          | otherwise -> go rest
        _:rest -> go rest

concreteScalars :: ConcreteStyle -> [ConcreteScalar]
concreteScalars style' = concatMap fieldScalar (concreteFields style')
  where
    fieldScalar field =
      case field of
        ConcreteScalarField name _ value unit ->
          [ConcreteScalar name value unit]
        _ -> []

concreteColors :: ConcreteStyle -> [ConcreteColor]
concreteColors style' = concatMap fieldColor (concreteFields style')
  where
    fieldColor field =
      case field of
        ConcreteColorField name _ value -> [ConcreteColor name value]
        _                               -> []

concreteDiscrete :: ConcreteStyle -> [ConcreteDiscrete]
concreteDiscrete style' = concatMap fieldDiscrete (concreteFields style')
  where
    fieldDiscrete field =
      case field of
        ConcreteChoiceField _ _ _ discrete -> [discrete]
        _                                  -> []

materializeViewGraph :: Solution -> ViewGraph -> Either String ConcreteViewGraph
materializeViewGraph solution graph = do
  nodes <- traverse (materializeViewNode solution) (viewNodes graph)
  pure
    ConcreteViewGraph
      { concreteViewNodes = nodes
      , concreteViewRenderFrames = viewRenderFrames graph
      }

materializeViewNode :: Solution -> ViewNode -> Either String ConcreteViewNode
materializeViewNode solution node =
  case node of
    BlockViewNode block ->
      ConcreteBlockViewNode <$> materializeBlockView solution block
    VirtualViewNode virtual ->
      ConcreteVirtualViewNode <$> materializeVirtualView solution virtual

materializeBlockView ::
     Solution -> BlockView tag -> Either String (ConcreteBlockView tag)
materializeBlockView solution block = do
  concreteStyle <- materializeStyle solution (blockStyle block)
  pure
    ConcreteBlockView
      { concreteBlockRef = blockRef block
      , concreteBlockLabel = blockLabel block
      , concreteBlockContent = materializeContent (blockContent block)
      , concreteBlockNodeKey = blockNodeKey block
      , concreteBlockPieceKey = blockPieceKey block
      , concreteBlockStyle = concreteStyle
      }

materializeVirtualView ::
     Solution -> VirtualView tag -> Either String (ConcreteVirtualView tag)
materializeVirtualView solution virtual = do
  concreteStyle <- materializeStyle solution (virtualStyle virtual)
  pure
    ConcreteVirtualView
      { concreteVirtualRef = virtualRef virtual
      , concreteVirtualLabel = virtualLabel virtual
      , concreteVirtualContent = materializeContent (virtualContent virtual)
      , concreteVirtualNodeKey = virtualNodeKey virtual
      , concreteVirtualPieceKey = virtualPieceKey virtual
      , concreteVirtualStyle = concreteStyle
      }

materializeContent :: ContentMode -> String
materializeContent contentMode =
  case contentMode of
    ContentEmpty      -> ""
    ContentText value -> value

materializeStyle :: Solution -> Style -> Either String ConcreteStyle
materializeStyle solution style' =
  ConcreteStyle
    <$> materializeBounds solution (styleBounds style')
    <*> traverse (materializeField solution) (styleFields style')

materializeBounds :: Solution -> BoundsExpr -> Either String ConcreteBounds
materializeBounds solution = traverse (requireExprValue "view bounds")
  where
    requireExprValue = requireSolvedExpr solution

materializeField :: Solution -> StyleField -> Either String ConcreteField
materializeField solution field =
  case field of
    StyleScalarField _ spec expr -> materializeScalar solution spec expr
    StyleColorField spec maybeHsl ->
      ConcreteColorField (styleTextName spec) (styleTextAttrName spec)
        <$> traverse (materializeHsl solution) maybeHsl
    StyleTextField spec value ->
      Right
        (ConcreteTextField (styleTextName spec) (styleTextAttrName spec) value)
    StyleChoiceField spec value -> materializeChoiceField solution spec value

materializeChoiceField ::
     Solution
  -> StyleChoiceSpec value
  -> Maybe (StyleChoiceValue value)
  -> Either String ConcreteField
materializeChoiceField solution spec maybeValue = do
  concreteValue <- traverse (materializeChoiceValue solution spec) maybeValue
  pure
    (ConcreteChoiceField
       (styleChoiceName spec)
       (styleChoiceAttrName spec)
       (styleChoiceAttrValue spec <$> concreteValue)
       (styleChoiceDiscreteValue spec concreteValue))

materializeChoiceValue ::
     Solution
  -> StyleChoiceSpec value
  -> StyleChoiceValue value
  -> Either String value
materializeChoiceValue solution spec value =
  case value of
    FixedStyleChoice fixed -> Right fixed
    SolvedStyleChoice selected -> do
      selectedCategory <-
        maybe
          (Left "could not materialize a style choice from the solver solution")
          Right
          (evalChoice solution selected)
      requireChoiceValue spec (categoryName selectedCategory)

requireChoiceValue :: StyleChoiceSpec value -> String -> Either String value
requireChoiceValue spec name =
  case lookupChoiceValue spec name of
    Just value -> Right value
    Nothing ->
      Left ("could not map solved style choice category to a value: " ++ name)

lookupChoiceValue :: StyleChoiceSpec value -> String -> Maybe value
lookupChoiceValue spec name = go (styleChoiceDomainValues spec)
  where
    go values =
      case values of
        [] -> Nothing
        value:rest
          | styleChoiceCategoryName spec value == name -> Just value
          | otherwise -> go rest

materializeScalar ::
     Solution -> StyleScalarSpec -> Expr ty -> Either String ConcreteField
materializeScalar solution spec expr =
  ConcreteScalarField (styleScalarName spec) (styleScalarAttrName spec)
    <$> requireSolvedExpr solution (styleScalarName spec) expr
    <*> pure (styleScalarValueUnit spec)

materializeHsl :: Solution -> ColorExpr -> Either String ConcreteHsl
materializeHsl solution hsl =
  Hsl
    <$> requireSolvedExpr solution "hue" (hue hsl)
    <*> requireSolvedExpr solution "saturation" (saturation hsl)
    <*> requireSolvedExpr solution "lightness" (lightness hsl)

requireSolvedExpr :: Solution -> String -> Expr ty -> Either String Double
requireSolvedExpr solution label expr =
  case evalExpr solution expr of
    Just value -> Right value
    Nothing ->
      Left
        ("could not materialize "
           ++ label
           ++ " from the solver solution; the expression probably references a \
             \variable that was not included in any constraint")
