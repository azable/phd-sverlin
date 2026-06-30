{-# LANGUAGE GADTs               #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

-- | Generic lowering, traversal, and materialization for symbolic node styles.
module LinearTrace.View.Style.Lower
  ( mapNodeStyleExprs
  , mapNodeStyleExprLeaves
  , solvedNodeStyleExprs
  , nodeStyleConstraints
  , nodeStyleChoiceConstraints
  , materializeAnyStyleField
  ) where

import           Data.Kind                    (Type)
import           Data.Maybe                   (mapMaybe)
import           Data.Proxy                   (Proxy (..))
import           LinearTrace.View.Primitives
import           LinearTrace.View.Style.Model
import           Prelude
import           Solver                       (ChoiceConstraint, Constraint,
                                               Expr, Solution, evalExpr)

mapNodeStyleExprs ::
     (forall (ty :: Type). Expr ty -> Expr ty) -> NodeStyle -> NodeStyle
mapNodeStyleExprs f style' =
  NodeStyle
    { nodeStyleBounds = fmap f (nodeStyleBounds style')
    , nodeStyleFields = map (mapAnyStyleFieldExprs f) (nodeStyleFields style')
    }

mapAnyStyleFieldExprs ::
     (forall (ty :: Type). Expr ty -> Expr ty) -> AnyStyleField -> AnyStyleField
mapAnyStyleFieldExprs f field =
  case field of
    AnyStyleField (proxy :: Proxy field) value ->
      AnyStyleField proxy (mapStyleValueExprs @field f value)

nodeStyleExprLeaves :: NodeStyle -> [StyleExprLeaf]
nodeStyleExprLeaves style' =
  [ StyleExprLeaf "top" (top style')
  , StyleExprLeaf "left" (left style')
  , StyleExprLeaf "width" (width style')
  , StyleExprLeaf "height" (height style')
  ]
    ++ concatMap anyStyleFieldExprLeaves (nodeStyleFields style')

anyStyleFieldExprLeaves :: AnyStyleField -> [StyleExprLeaf]
anyStyleFieldExprLeaves field =
  case field of
    AnyStyleField proxy value -> styleValueExprLeaves proxy value

mapNodeStyleExprLeaves ::
     (forall (ty :: Type). String -> Expr ty -> a) -> NodeStyle -> [a]
mapNodeStyleExprLeaves f style' = map go (nodeStyleExprLeaves style')
  where
    go leaf =
      case leaf of
        StyleExprLeaf name expr -> f name expr

solvedNodeStyleExprs :: Solution -> NodeStyle -> [(String, Double)]
solvedNodeStyleExprs solution = mapMaybe solveLeaf . nodeStyleExprLeaves
  where
    solveLeaf leaf =
      case leaf of
        StyleExprLeaf name expr ->
          case evalExpr solution expr of
            Nothing    -> Nothing
            Just value -> Just (name, value)

nodeStyleConstraints :: NodeStyle -> [Constraint]
nodeStyleConstraints style' =
  concatMap anyStyleFieldConstraints (nodeStyleFields style')

anyStyleFieldConstraints :: AnyStyleField -> [Constraint]
anyStyleFieldConstraints field =
  case field of
    AnyStyleField proxy value -> styleValueConstraints proxy value

nodeStyleChoiceConstraints :: NodeStyle -> [ChoiceConstraint]
nodeStyleChoiceConstraints style' =
  concatMap anyStyleFieldChoices (nodeStyleFields style')

anyStyleFieldChoices :: AnyStyleField -> [ChoiceConstraint]
anyStyleFieldChoices field =
  case field of
    AnyStyleField proxy value -> styleValueChoices proxy value

materializeAnyStyleField ::
     Solution -> AnyStyleField -> Either String ConcreteStyleField
materializeAnyStyleField solution field =
  case field of
    AnyStyleField proxy value ->
      ConcreteStyleField (styleFieldName proxy) (styleFieldCssName proxy)
        <$> materializeStyleValue proxy solution value
