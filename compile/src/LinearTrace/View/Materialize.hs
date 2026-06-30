{-# LANGUAGE GADTs #-}

-- | Materialization boundary from solved symbolic view graphs to concrete
-- render data. 'LinearTrace.Compile' is the intended caller; symbolic style and
-- graph helpers stay internal to this module.
module LinearTrace.View.Materialize
  ( -- * Concrete style data
    -- | Solved style fields and geometry values. Compile code reads these to
    -- map style fields to CSS/JSON.
    ConcreteHsl
  , ConcreteStyle
  , concreteFields
  , ConcreteField(..)
  , -- * Concrete view nodes
    -- | Solved view nodes. Compile code reads these to build JSON render
    -- elements after symbolic tags have been erased.
    ConcreteNode
  , concreteNodeId
  , concreteNodeLabel
  , concreteNodeContent
  , concreteNodeKey
  , concreteNodeStyle
  , -- * Concrete graph
    -- | Whole solved graph and render frames produced from a solver solution.
    ConcreteViewGraph
  , concreteViewNodes
  , concreteViewRenderFrames
  , -- * Geometry helpers
    -- | Convenience readers over concrete bounds and scalar style fields used
    -- by compile-time CSS mapping.
    concreteTop
  , concreteLeft
  , concreteWidth
  , concreteHeight
  , concreteScalarValue
  , -- * Materialization
    -- | The only public conversion entrypoint: solved 'ViewGraph' to concrete
    -- graph, failing if a referenced symbolic value was not solved.
    materializeViewGraph
  ) where

import           LinearTrace.View.Graph
import           LinearTrace.View.Primitives
import           LinearTrace.View.Style
import           LinearTrace.View.Types      (ContentMode (..), ViewId,
                                              ViewLabel, viewRefId)
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
  | ConcreteTokenField String (Maybe String) (Maybe String)
  deriving (Eq, Show)

data ConcreteNode = ConcreteNode
  { concreteNodeId      :: ViewId
  , concreteNodeLabel   :: ViewLabel
  , concreteNodeContent :: String
  , concreteNodeKey     :: String
  , concreteNodeStyle   :: ConcreteStyle
  }

data ConcreteViewGraph = ConcreteViewGraph
  { concreteViewNodes        :: [ConcreteNode]
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

materializeViewGraph :: Solution -> ViewGraph -> Either String ConcreteViewGraph
materializeViewGraph solution graph = do
  nodes <- traverse (materializeViewNode solution) (viewNodes graph)
  pure
    ConcreteViewGraph
      { concreteViewNodes = nodes
      , concreteViewRenderFrames = viewRenderFrames graph
      }

materializeViewNode :: Solution -> ViewNode -> Either String ConcreteNode
materializeViewNode solution node =
  case node of
    ViewNode viewNode -> materializeNode solution viewNode

materializeNode :: Solution -> Node tag -> Either String ConcreteNode
materializeNode solution node = do
  concreteStyle <- materializeStyle solution (nodeStyle node)
  pure
    ConcreteNode
      { concreteNodeId = viewRefId (nodeRef node)
      , concreteNodeLabel = nodeLabel node
      , concreteNodeContent = materializeContent (nodeContent node)
      , concreteNodeKey = nodeKey node
      , concreteNodeStyle = concreteStyle
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
      ConcreteColorField (styleAttrName spec) (styleAttrCssName spec)
        <$> traverse (materializeHsl solution) maybeHsl
    StyleCategoryField spec value ->
      materializeCategoryField solution spec value

materializeCategoryField ::
     Solution
  -> StyleCategorySpec value
  -> Maybe (StyleCategory value)
  -> Either String ConcreteField
materializeCategoryField solution spec maybeValue = do
  concreteValue <- traverse (materializeCategoryValue solution spec) maybeValue
  pure
    (ConcreteTokenField
       (styleCategoryName spec)
       (styleCategoryAttrName spec)
       (styleCategoryValueToken spec <$> concreteValue))

materializeCategoryValue ::
     Solution
  -> StyleCategorySpec value
  -> StyleCategory value
  -> Either String value
materializeCategoryValue solution spec value =
  case value of
    FixedCategory fixed -> Right fixed
    VariableCategory selected -> do
      selectedCategory <-
        maybe
          (Left
             "could not materialize a style category from the solver solution")
          Right
          (evalChoice solution selected)
      requireCategoryValue spec (categoryName selectedCategory)

requireCategoryValue :: StyleCategorySpec value -> String -> Either String value
requireCategoryValue spec name =
  case lookupCategoryValue spec name of
    Just value -> Right value
    Nothing -> Left ("could not map solved style category to a value: " ++ name)

lookupCategoryValue :: StyleCategorySpec value -> String -> Maybe value
lookupCategoryValue spec name = go (styleCategoryDomainValues spec)
  where
    go values =
      case values of
        [] -> Nothing
        value:rest
          | styleCategoryValueToken spec value == name -> Just value
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
