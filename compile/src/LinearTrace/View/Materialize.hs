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
    -- | Solved block and virtual nodes. Constructors remain hidden except for
    -- the existential node wrapper needed by compile traversal.
    ConcreteBlockView
  , concreteBlockRef
  , concreteBlockLabel
  , concreteBlockContent
  , concreteBlockNodeKey
  , concreteBlockPieceKey
  , concreteBlockStyle
  , ConcreteVirtualView
  , concreteVirtualRef
  , concreteVirtualLabel
  , concreteVirtualContent
  , concreteVirtualNodeKey
  , concreteVirtualPieceKey
  , concreteVirtualStyle
  , ConcreteViewNode(..)
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
