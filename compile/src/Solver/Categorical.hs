-- | Exact seeded sampling of finite categorical constraints by independent
-- connected component.
module Solver.Categorical
  ( ChoiceStatistics(..)
  , solveChoiceConstraints
  , choiceDomains
  , enumerateChoiceAssignments
  ) where

import           Data.List       (intercalate)
import           Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import           Data.Set        (Set)
import qualified Data.Set        as Set
import           Prelude
import           Solver.Choice
import           Solver.Random

-- | Search size after splitting unrelated choices into components.
data ChoiceStatistics = ChoiceStatistics
  { choiceVariableCount              :: Int
  , choiceComponentCount             :: Int
  , choiceCandidateCount             :: Int
  , choiceLargestComponentCandidates :: Int
  } deriving (Eq, Show)

-- | Uniformly select one satisfying assignment from each independent choice
-- component. The configured limit applies per component, not to an unrelated
-- global Cartesian product.
solveChoiceConstraints ::
     RandomSeed
  -> Int
  -> [ChoiceConstraint]
  -> (Map String String, ChoiceStatistics)
solveChoiceConstraints _ _ [] =
  ( Map.empty
  , ChoiceStatistics
      { choiceVariableCount = 0
      , choiceComponentCount = 0
      , choiceCandidateCount = 0
      , choiceLargestComponentCandidates = 0
      })
solveChoiceConstraints seed branchLimit constraints =
  ( Map.unions (map solveComponent components)
  , ChoiceStatistics
      { choiceVariableCount = Map.size domains
      , choiceComponentCount = length components
      , choiceCandidateCount = sum componentCandidateCounts
      , choiceLargestComponentCandidates =
          maximum (0 : componentCandidateCounts)
      })
  where
    domains = choiceDomains constraints
    components = connectedComponents constraints (Map.keysSet domains)
    componentCandidateCounts = map candidateCount components
    candidateCount names =
      product
        [ length categories
        | (name, categories) <- Map.toAscList domains
        , name `Set.member` names
        ]
    solveComponent names
      | candidates > max 1 branchLimit =
        error
          ("categorical solver component branch count "
             ++ show candidates
             ++ " exceeds configured limit "
             ++ show (max 1 branchLimit)
             ++ " for: "
             ++ intercalate ", " componentNames)
      | otherwise =
        case validAssignments of
          [] ->
            error
              ("categorical solver constraints have no satisfying assignment for: "
                 ++ intercalate ", " componentNames)
          valid -> valid !! selectedIndex valid
      where
        componentNames = Set.toAscList names
        candidates = candidateCount names
        componentChoices =
          [ (name, categories)
          | (name, categories) <- Map.toAscList domains
          , name `Set.member` names
          ]
        componentConstraints = filter (constraintTouches names) constraints
        validAssignments =
          filter
            (\assignment ->
               all (choiceConstraintSatisfied assignment) componentConstraints)
            (enumerateChoiceAssignments componentChoices)
        selectedIndex valid =
          min
            (length valid - 1)
            (floor (seedUnit * fromIntegral (length valid)))
        seedUnit =
          case randomUnitsFromSeed componentSeed of
            value:_ -> value
            []      -> 0
        componentSeed =
          deriveSeed seed ("categorical." ++ intercalate "\NUL" componentNames)

choiceDomains :: [ChoiceConstraint] -> Map String [String]
choiceDomains = foldl' addConstraint Map.empty
  where
    addConstraint domains constraint =
      foldl' addSpec domains (choiceConstraintSpecs constraint)
    addSpec domains (name, categories)
      | null categories =
        error ("categorical choice " ++ show name ++ " has an empty domain")
      | otherwise =
        Map.alter (Just . mergeChoiceDomain name categories) name domains

mergeChoiceDomain :: String -> [String] -> Maybe [String] -> [String]
mergeChoiceDomain _ categories Nothing = categories
mergeChoiceDomain name categories (Just old)
  | old == categories = old
  | otherwise =
    error
      ("categorical choice "
         ++ show name
         ++ " was used with incompatible domains")

connectedComponents :: [ChoiceConstraint] -> Set String -> [Set String]
connectedComponents constraints = go []
  where
    adjacency = foldl' addEdges Map.empty constraints
    addEdges graph constraint =
      foldl'
        (\current name ->
           Map.insertWith Set.union name (Set.delete name names) current)
        graph
        (Set.toList names)
      where
        names = Set.fromList (map fst (choiceConstraintSpecs constraint))
    go components remaining
      | Set.null remaining = reverse components
      | otherwise =
        let start = Set.findMin remaining
            component = reachable adjacency Set.empty [start]
         in go (component : components) (remaining Set.\\ component)

reachable :: Map String (Set String) -> Set String -> [String] -> Set String
reachable _ visited [] = visited
reachable adjacency visited (name:pending)
  | name `Set.member` visited = reachable adjacency visited pending
  | otherwise =
    reachable
      adjacency
      (Set.insert name visited)
      (Set.toList (Map.findWithDefault Set.empty name adjacency) ++ pending)

constraintTouches :: Set String -> ChoiceConstraint -> Bool
constraintTouches names =
  any ((`Set.member` names) . fst) . choiceConstraintSpecs

enumerateChoiceAssignments :: [(String, [String])] -> [Map String String]
enumerateChoiceAssignments choices =
  case choices of
    [] -> [Map.empty]
    (name, categories):rest ->
      [ Map.insert name categoryValue assignment
      | categoryValue <- categories
      , assignment <- enumerateChoiceAssignments rest
      ]
