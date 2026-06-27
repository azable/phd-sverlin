{-# LANGUAGE ScopedTypeVariables #-}

module Solver.Choice
  ( Category
  , category
  , categoryName
  , Choice
  , choice
  , choiceName
  , CategoricalType(..)
  , ChoiceConstraint
  , choose
  , sameChoice
  , differentChoice
  , choiceConstraintSpecs
  , choiceConstraintSatisfied
  ) where

import           Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import           Data.Proxy      (Proxy (..))
import           Prelude

newtype Category ty =
  Category String
  deriving (Eq, Ord, Show)

category :: String -> Category ty
category = Category

categoryName :: Category ty -> String
categoryName value =
  case value of
    Category name -> name

data Choice ty = Choice
  { choiceName       :: String
  , choiceCategories :: [String]
  } deriving (Eq, Ord, Show)

class CategoricalType ty where
  categoricalDomain :: Proxy ty -> [Category ty]

choice ::
     forall ty. CategoricalType ty
  => String
  -> Choice ty
choice name =
  Choice
    { choiceName = name
    , choiceCategories =
        map categoryName (categoricalDomain (Proxy :: Proxy ty))
    }

data ChoiceSpec = ChoiceSpec
  { choiceSpecName       :: String
  , choiceSpecCategories :: [String]
  } deriving (Eq, Ord, Show)

data ChoiceConstraint
  = ChoiceIs ChoiceSpec String
  | ChoiceSame ChoiceSpec ChoiceSpec
  | ChoiceDifferent ChoiceSpec ChoiceSpec
  deriving (Eq, Ord, Show)

choose :: Choice ty -> Category ty -> ChoiceConstraint
choose selected value = ChoiceIs (choiceSpec selected) (categoryName value)

sameChoice :: Choice ty -> Choice ty -> ChoiceConstraint
sameChoice lhs rhs = ChoiceSame (choiceSpec lhs) (choiceSpec rhs)

differentChoice :: Choice ty -> Choice ty -> ChoiceConstraint
differentChoice lhs rhs = ChoiceDifferent (choiceSpec lhs) (choiceSpec rhs)

choiceSpec :: Choice ty -> ChoiceSpec
choiceSpec selected =
  ChoiceSpec
    { choiceSpecName = choiceName selected
    , choiceSpecCategories = choiceCategories selected
    }

choiceConstraintSpecs :: ChoiceConstraint -> [(String, [String])]
choiceConstraintSpecs constraint =
  case constraint of
    ChoiceIs spec _         -> [specEntry spec]
    ChoiceSame lhs rhs      -> [specEntry lhs, specEntry rhs]
    ChoiceDifferent lhs rhs -> [specEntry lhs, specEntry rhs]

specEntry :: ChoiceSpec -> (String, [String])
specEntry spec = (choiceSpecName spec, choiceSpecCategories spec)

choiceConstraintSatisfied :: Map String String -> ChoiceConstraint -> Bool
choiceConstraintSatisfied values constraint =
  case constraint of
    ChoiceIs spec expected ->
      Map.lookup (choiceSpecName spec) values == Just expected
    ChoiceSame lhs rhs -> relationSatisfied (==) values lhs rhs
    ChoiceDifferent lhs rhs -> relationSatisfied (/=) values lhs rhs

relationSatisfied ::
     (String -> String -> Bool)
  -> Map String String
  -> ChoiceSpec
  -> ChoiceSpec
  -> Bool
relationSatisfied relation values lhs rhs =
  case ( Map.lookup (choiceSpecName lhs) values
       , Map.lookup (choiceSpecName rhs) values) of
    (Just lhsValue, Just rhsValue) -> relation lhsValue rhsValue
    _                              -> False
