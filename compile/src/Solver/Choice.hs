{-# LANGUAGE ScopedTypeVariables #-}

-- | Finite categorical choice implementation. Choice domains provide typed
-- values plus stable solver tokens; 'Solver.Problem' samples satisfying
-- assignments before numeric optimization.
module Solver.Choice
  ( -- * Choice domains
    -- | Typed finite choices. Public users normally access these through the
    -- 'Solver' facade.
    ChoiceDomain(..)
  , ChoiceValue(..)
  , Choice
  , choice
  , choiceName
  , choiceValueFromToken
  , -- * Choice constraints
    -- | Relations over finite choices. These are consumed by 'Solver.Problem'
    -- and by the view style solver bridge.
    ChoiceConstraint
  , freeChoice
  , choose
  , sameChoice
  , differentChoice
  , -- * Solver implementation helpers
    -- | Internal inspection/evaluation hooks used while compiling and checking
    -- categorical assignments.
    choiceConstraintSpecs
  , choiceConstraintSatisfied
  ) where

import           Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import           Prelude

class ChoiceDomain value where
  choiceDomain :: [value]
  choiceToken :: value -> String

data ChoiceValue value
  = Fixed value
  | Variable (Choice value)
  deriving (Eq, Show)

data Choice value = Choice
  { choiceName       :: String
  , choiceCategories :: [String]
  } deriving (Eq, Ord, Show)

choice ::
     forall value. ChoiceDomain value
  => String
  -> Choice value
choice name =
  Choice
    { choiceName = name
    , choiceCategories = map choiceToken (choiceDomain :: [value])
    }

choiceValueFromToken :: ChoiceDomain value => String -> Maybe value
choiceValueFromToken token = go choiceDomain
  where
    go values =
      case values of
        [] -> Nothing
        value:rest
          | choiceToken value == token -> Just value
          | otherwise -> go rest

data ChoiceSpec = ChoiceSpec
  { choiceSpecName       :: String
  , choiceSpecCategories :: [String]
  } deriving (Eq, Ord, Show)

data ChoiceConstraint
  = ChoiceFree ChoiceSpec
  | ChoiceIs ChoiceSpec String
  | ChoiceSame ChoiceSpec ChoiceSpec
  | ChoiceDifferent ChoiceSpec ChoiceSpec
  deriving (Eq, Ord, Show)

freeChoice :: Choice value -> ChoiceConstraint
freeChoice selected = ChoiceFree (choiceSpec selected)

choose :: ChoiceDomain value => Choice value -> value -> ChoiceConstraint
choose selected value = ChoiceIs (choiceSpec selected) (choiceToken value)

sameChoice :: Choice value -> Choice value -> ChoiceConstraint
sameChoice lhs rhs = ChoiceSame (choiceSpec lhs) (choiceSpec rhs)

differentChoice :: Choice value -> Choice value -> ChoiceConstraint
differentChoice lhs rhs = ChoiceDifferent (choiceSpec lhs) (choiceSpec rhs)

choiceSpec :: Choice value -> ChoiceSpec
choiceSpec selected =
  ChoiceSpec
    { choiceSpecName = choiceName selected
    , choiceSpecCategories = choiceCategories selected
    }

choiceConstraintSpecs :: ChoiceConstraint -> [(String, [String])]
choiceConstraintSpecs constraint =
  case constraint of
    ChoiceFree spec         -> [specEntry spec]
    ChoiceIs spec _         -> [specEntry spec]
    ChoiceSame lhs rhs      -> [specEntry lhs, specEntry rhs]
    ChoiceDifferent lhs rhs -> [specEntry lhs, specEntry rhs]

specEntry :: ChoiceSpec -> (String, [String])
specEntry spec = (choiceSpecName spec, choiceSpecCategories spec)

choiceConstraintSatisfied :: Map String String -> ChoiceConstraint -> Bool
choiceConstraintSatisfied values constraint =
  case constraint of
    ChoiceFree spec -> Map.member (choiceSpecName spec) values
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
