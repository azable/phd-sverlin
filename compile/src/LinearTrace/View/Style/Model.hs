{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}

-- | Core symbolic node-style model. This module defines the storage shape and
-- field class; field definitions live in 'LinearTrace.View.Style'.
module LinearTrace.View.Style.Model
  ( -- * Node style storage
    NodeStyle(..)
  , nodeStyleWithBounds
  , AnyStyleField(..)
  , getStyleField
  , setStyleField
  , requireStyleField
  , -- * Field API
    StyleField(..)
  , StyleValueVars(..)
  , StyleValueUnit(..)
  , StyleExprLeaf(..)
  , -- * Concrete style output
    ConcreteStyleField(..)
  , ConcreteStyleValue(..)
  ) where

import           Data.Kind                   (Type)
import           Data.Proxy                  (Proxy (..))
import           Data.Type.Equality          ((:~:) (..))
import           Data.Typeable               (Typeable, eqT)
import           LinearTrace.View.Primitives
import           Prelude
import           Solver                      (Choice, ChoiceConstraint,
                                              ChoiceDomain, Constraint, Expr,
                                              Solution, SymbolicType)

data StyleValueUnit
  = StyleNumber
  | StylePixels
  | StyleHidden
  deriving (Eq, Show)

data StyleValueVars = StyleValueVars
  { styleExprVar :: forall (ty :: Type). SymbolicType ty =>
                                           [String] -> String -> Expr ty
  , styleChoiceVar :: forall value. ChoiceDomain value => String -> Choice value
  }

data ConcreteStyleValue
  = ConcreteScalar Double StyleValueUnit
  | ConcreteColor ConcreteHsl
  | ConcreteToken String
  deriving (Eq, Show)

data ConcreteStyleField = ConcreteStyleField
  { concreteStyleFieldName    :: String
  , concreteStyleFieldCssName :: Maybe String
  , concreteStyleFieldValue   :: ConcreteStyleValue
  } deriving (Eq, Show)

data StyleExprLeaf where
  StyleExprLeaf :: String -> Expr (ty :: Type) -> StyleExprLeaf

class Typeable field =>
      StyleField (field :: Type)
  where
  type StyleValue field
  styleFieldName :: Proxy field -> String
  styleFieldCssName :: Proxy field -> Maybe String
  styleFieldCssName proxy = Just (styleFieldName proxy)
  generatedStyleValue :: Proxy field -> StyleValueVars -> StyleValue field
  mapStyleValueExprs ::
       (forall (ty :: Type). Expr ty -> Expr ty)
    -> StyleValue field
    -> StyleValue field
  styleValueExprLeaves :: Proxy field -> StyleValue field -> [StyleExprLeaf]
  styleValueChoiceNames :: Proxy field -> StyleValue field -> [String]
  styleValueChoiceNames _ _ = []
  styleValueConstraints :: Proxy field -> StyleValue field -> [Constraint]
  styleValueConstraints _ _ = []
  styleValueChoices :: Proxy field -> StyleValue field -> [ChoiceConstraint]
  styleValueChoices _ _ = []
  materializeStyleValue ::
       Proxy field
    -> Solution
    -> StyleValue field
    -> Either String ConcreteStyleValue

data AnyStyleField where
  AnyStyleField
    :: StyleField field => Proxy field -> StyleValue field -> AnyStyleField

anyStyleFieldName :: AnyStyleField -> String
anyStyleFieldName field =
  case field of
    AnyStyleField proxy _ -> styleFieldName proxy

data NodeStyle = NodeStyle
  { nodeStyleBounds :: BoundsExpr
  , nodeStyleFields :: [AnyStyleField]
  }

nodeStyleWithBounds :: BoundsExpr -> NodeStyle
nodeStyleWithBounds bounds =
  NodeStyle {nodeStyleBounds = bounds, nodeStyleFields = []}

instance HasBounds NodeStyle where
  top = top . nodeStyleBounds
  left = left . nodeStyleBounds
  width = width . nodeStyleBounds
  height = height . nodeStyleBounds

getStyleField ::
     forall field. StyleField field
  => NodeStyle
  -> Maybe (StyleValue field)
getStyleField style' = go (nodeStyleFields style')
  where
    go fields =
      case fields of
        [] -> Nothing
        AnyStyleField (_ :: Proxy other) value:rest ->
          case eqT @field @other of
            Just Refl -> Just value
            Nothing   -> go rest

setStyleField ::
     forall field. StyleField field
  => StyleValue field
  -> NodeStyle
  -> NodeStyle
setStyleField value style' =
  style'
    { nodeStyleFields =
        replaceByName
          anyStyleFieldName
          (AnyStyleField (Proxy :: Proxy field) value)
          (nodeStyleFields style')
    }

requireStyleField ::
     forall field. StyleField field
  => StyleValueVars
  -> NodeStyle
  -> NodeStyle
requireStyleField vars style' =
  case getStyleField @field style' of
    Just _ -> style'
    Nothing ->
      setStyleField @field (generatedStyleValue (Proxy @field) vars) style'

replaceByName :: (a -> String) -> a -> [a] -> [a]
replaceByName getName newValue = go
  where
    target = getName newValue
    go xs =
      case xs of
        [] -> [newValue]
        x:rest
          | getName x == target -> newValue : rest
          | otherwise -> x : go rest
