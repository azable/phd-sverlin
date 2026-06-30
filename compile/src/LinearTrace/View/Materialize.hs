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
  , ConcreteStyleField(..)
  , ConcreteStyleValue(..)
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
import           Solver                      (Expr, Solution, evalExpr)

data ConcreteStyle = ConcreteStyle
  { concreteBounds :: ConcreteBounds
  , concreteFields :: [ConcreteStyleField]
  } deriving (Eq, Show)

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
        ConcreteStyleField name' _ (ConcreteScalar value _):rest
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

materializeStyle :: Solution -> NodeStyle -> Either String ConcreteStyle
materializeStyle solution style' =
  ConcreteStyle
    <$> materializeBounds solution (nodeStyleBounds style')
    <*> traverse (materializeAnyStyleField solution) (nodeStyleFields style')

materializeBounds :: Solution -> BoundsExpr -> Either String ConcreteBounds
materializeBounds solution = traverse (requireExprValue "view bounds")
  where
    requireExprValue = requireSolvedExpr solution

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
