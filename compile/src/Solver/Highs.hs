{-# LANGUAGE OverloadedStrings #-}

-- | Bounded MIP feasibility adapter for large finite affine design spaces.
-- The Haskell @MIP@ package owns LP serialization and invokes the external
-- HiGHS executable; this module owns only Sverlin's lowering policy.
module Solver.Highs
  ( selectFeasibleAssignmentWithHighs
  ) where

import           Control.Exception                     (SomeException, try)
import           Data.Default.Class                    (def)
import           Data.Map.Strict                       (Map)
import qualified Data.Map.Strict                       as Map
import           Data.Scientific                       (Scientific,
                                                        fromFloatDigits)
import qualified Data.Set                              as Set
import qualified Data.Text                             as Text
import qualified Numeric.Optimization.MIP              as MIP
import qualified Numeric.Optimization.MIP.Solver.Base  as MIPSolver
import qualified Numeric.Optimization.MIP.Solver.HiGHS as HiGHS
import           Prelude
import           Solver.Affine
import           Solver.Choice
import           Solver.Constraint
import           Solver.Expr
import           Solver.Problem
import           Solver.Random
import           System.IO                            (hClose, hPutStrLn)
import           System.IO.Temp                       (withSystemTempFile)

type Assignment = Map String String

data MipVariables = MipVariables
  { numericMipVariables :: Map String MIP.Var
  , choiceMipVariables  :: Map (String, String) MIP.Var
  }

data GuardedConstraint = GuardedConstraint
  { guardedBy         :: [(String, String)]
  , guardedConstraint :: Constraint
  }

-- | Select one mixed discrete/continuous feasible assignment. Random objective
-- coefficients make repeated deterministic seeds explore different feasible
-- discrete regions; hit-and-run samples the chosen region afterwards.
selectFeasibleAssignmentWithHighs ::
     RandomSeed
  -> Map String [String]
  -> SolverProblem
  -> IO (Either String Assignment)
selectFeasibleAssignmentWithHighs seed domains problem =
  case buildMipProblem seed domains problem of
    Left err -> pure (Left err)
    Right (variables, mipProblem) ->
      withSystemTempFile "sverlin-highs.log" $ \logPath logHandle -> do
        hClose logHandle
        withSystemTempFile "sverlin-highs.options" $ \optionsPath handle -> do
          mapM_
            (hPutStrLn handle)
            [ "random_seed = " ++ showSeed seed
            , "threads = 1"
            , "parallel = off"
            , "log_file = " ++ logPath
            , "log_to_console = false"
            ]
          hClose handle
          solved <-
            try
              (MIPSolver.solve
                 (HiGHS.highs
                    {HiGHS.highsArgs = ["--options_file", optionsPath]})
                 def
                 mipProblem)
          pure
            (case solved of
               Left err ->
                 Left
                   ("could not run the HiGHS feasibility backend: "
                      ++ show (err :: SomeException))
               Right solution -> decodeAssignment domains variables solution)

buildMipProblem ::
     RandomSeed
  -> Map String [String]
  -> SolverProblem
  -> Either String (MipVariables, MIP.Problem Scientific)
buildMipProblem seed domains problem = do
  numericBounds <- finiteNumericBounds (solverConstraints problem)
  let variables = makeMipVariables numericBounds domains
      oneHot = map (oneHotConstraint variables) (Map.toAscList domains)
      categorical =
        concatMap
          (categoricalConstraints variables)
          (solverChoiceConstraints problem)
  numeric <-
    fmap
      concat
      (traverse
         (lowerGuardedConstraint variables numericBounds)
         (guardedConstraints [] (solverConstraints problem)))
  let binaries = Map.elems (choiceMipVariables variables)
      objectiveUnits = randomUnitsFromSeed (deriveSeed seed "highs.objective")
      -- MIP 0.2.0.1's HiGHS solution parser rejects signed numeric fields.
      -- Positive costs preserve randomized selection because every domain is
      -- one-hot, so a common cost translation per domain is constant.
      objective =
        sum
          [ scientificExpr unit * MIP.varExpr variable
          | (unit, variable) <- zip objectiveUnits binaries
          ]
      variableDomains =
        Map.fromList
          ([ ( variable
             , (MIP.ContinuousVariable, shiftedScientificBounds bounds))
           | (name, bounds) <- Map.toAscList numericBounds
           , let variable = numericVariable variables name
           ]
             ++ [ ( variable
                  , (MIP.IntegerVariable, (MIP.Finite 0, MIP.Finite 1)))
                | variable <- binaries
                ])
      mipProblem =
        (def :: MIP.Problem Scientific)
          { MIP.name = Just "sverlin-design-space"
          , MIP.objectiveFunction =
              MIP.ObjectiveFunction
                { MIP.objLabel = Just "seeded_branch_selection"
                , MIP.objDir = MIP.OptMin
                , MIP.objExpr = objective
                }
          , MIP.constraints = oneHot ++ categorical ++ numeric
          , MIP.varDomains = variableDomains
          }
  pure (variables, mipProblem)

makeMipVariables ::
     Map String DomainBounds -> Map String [String] -> MipVariables
makeMipVariables numericBounds domains =
  MipVariables
    { numericMipVariables =
        Map.fromList
          [ (name, MIP.Var (Text.pack ("x." ++ show index)))
          | (index, name) <- zip [0 :: Int ..] (Map.keys numericBounds)
          ]
    , choiceMipVariables =
        Map.fromList
          [ ((name, token), MIP.Var (Text.pack ("z." ++ show index)))
          | (index, (name, token)) <-
              zip
                [0 :: Int ..]
                [ (name, token)
                | (name, tokens) <- Map.toAscList domains
                , token <- tokens
                ]
          ]
    }

finiteNumericBounds :: [Constraint] -> Either String (Map String DomainBounds)
finiteNumericBounds constraints = traverseWithKey validate bounds
  where
    types = collectConstraintVarTypes constraints
    inferred = inferDomainBounds constraints
    bounds =
      Map.mapWithKey
        (\name ty ->
           domainDefaultBounds ty
             `mergeDomainBounds` Map.findWithDefault
                                   unboundedDomainBounds
                                   name
                                   inferred)
        types
    validate name domainBounds =
      case (domainLowerBound domainBounds, domainUpperBound domainBounds) of
        (Just lower, Just upper)
          | lower <= upper -> Right domainBounds
          | otherwise ->
            Left ("inconsistent numeric bounds for MIP variable " ++ show name)
        _ ->
          Left
            ("HiGHS disjunction lowering requires finite bounds for numeric variable "
               ++ show name)

traverseWithKey ::
     (Ord key)
  => (key -> value -> Either err result)
  -> Map key value
  -> Either err (Map key result)
traverseWithKey f =
  fmap Map.fromAscList
    . traverse (\(key, value) -> (key, ) <$> f key value)
    . Map.toAscList

guardedConstraints :: [(String, String)] -> [Constraint] -> [GuardedConstraint]
guardedConstraints guards = concatMap collect
  where
    collect constraint =
      case constraint of
        Soft _ -> []
        Minimize _ -> []
        All nested -> guardedConstraints guards nested
        Cases spec ->
          concat
            [ guardedConstraints
              ((decisionSpecName spec, token) : guards)
              nested
            | (token, nested) <- decisionSpecAlternatives spec
            ]
        _ -> [GuardedConstraint guards constraint]

lowerGuardedConstraint ::
     MipVariables
  -> Map String DomainBounds
  -> GuardedConstraint
  -> Either String [MIP.Constraint Scientific]
lowerGuardedConstraint variables bounds guarded =
  case guardedConstraint guarded of
    Equals ty lhs rhs ->
      case domainCircularPeriod ty of
        Just _ ->
          Left "cyclic equalities are not supported by affine MIP lowering"
        Nothing -> do
          row <- affineDifference lhs rhs
          traverse
            (guardedUpperBound variables bounds (guardedBy guarded))
            [row, negateRow row]
    LessOrEqual lhs rhs -> do
      row <- affineDifference lhs rhs
      (: []) <$> guardedUpperBound variables bounds (guardedBy guarded) row
    Soft _ -> pure []
    Minimize _ -> pure []
    All _ -> Left "unflattened conjunction reached affine MIP lowering"
    Cases _ -> Left "unflattened disjunction reached affine MIP lowering"

affineDifference :: RawExpr -> RawExpr -> Either String AffineRow
affineDifference lhs rhs =
  case linearRawExpr (ESub lhs rhs) of
    Nothing -> Left "non-affine constraint cannot be lowered to HiGHS"
    Just (coefficients, constant) -> Right (AffineRow coefficients (-constant))

negateRow :: AffineRow -> AffineRow
negateRow row =
  AffineRow
    { affineRowCoefficients = Map.map negate (affineRowCoefficients row)
    , affineRowRhs = negate (affineRowRhs row)
    }

guardedUpperBound ::
     MipVariables
  -> Map String DomainBounds
  -> [(String, String)]
  -> AffineRow
  -> Either String (MIP.Constraint Scientific)
guardedUpperBound variables bounds guards row = do
  maximumValue <- affineMaximum bounds row
  shift <- affineLowerShift bounds row
  let bigM = max 0 (maximumValue - affineRowRhs row)
      shiftedRhs = affineRowRhs row - shift
      numericExpr =
        sum
          [ scientificExpr coefficient
            * MIP.varExpr (numericVariable variables name)
          | (name, coefficient) <- Map.toAscList (affineRowCoefficients row)
          ]
      guardExpr =
        sum
          [ MIP.varExpr (choiceVariable variables name token)
          | (name, token) <- guards
          ]
      guardCount = fromIntegral (length guards)
  pure
    ((numericExpr + scientificExpr bigM * guardExpr)
       MIP..<=. scientificExpr (shiftedRhs + bigM * guardCount))

affineMaximum :: Map String DomainBounds -> AffineRow -> Either String Double
affineMaximum bounds row =
  foldl addTerm (Right 0) (Map.toAscList (affineRowCoefficients row))
  where
    addTerm result (name, coefficient) = do
      total <- result
      variableBounds <-
        maybe
          (Left ("missing bounds for MIP variable " ++ show name))
          Right
          (Map.lookup name bounds)
      bound <-
        if coefficient >= 0
          then maybeBound name "upper" (domainUpperBound variableBounds)
          else maybeBound name "lower" (domainLowerBound variableBounds)
      pure (total + coefficient * bound)

affineLowerShift ::
     Map String DomainBounds -> AffineRow -> Either String Double
affineLowerShift bounds row =
  foldl addTerm (Right 0) (Map.toAscList (affineRowCoefficients row))
  where
    addTerm result (name, coefficient) = do
      total <- result
      variableBounds <-
        maybe
          (Left ("missing bounds for MIP variable " ++ show name))
          Right
          (Map.lookup name bounds)
      lower <-
        maybeBound name "lower" (domainLowerBound variableBounds)
      pure (total + coefficient * lower)

maybeBound :: String -> String -> Maybe Double -> Either String Double
maybeBound name side =
  maybe
    (Left ("missing " ++ side ++ " bound for MIP variable " ++ show name))
    Right

oneHotConstraint ::
     MipVariables -> (String, [String]) -> MIP.Constraint Scientific
oneHotConstraint variables (name, tokens) =
  sum [binaryExpr variables name token | token <- tokens] MIP..==. 1

categoricalConstraints ::
     MipVariables -> ChoiceConstraint -> [MIP.Constraint Scientific]
categoricalConstraints variables constraint =
  case constraint of
    ChoiceFree _ -> []
    ChoiceIs spec token ->
      [binaryExpr variables (choiceSpecName spec) token MIP..==. 1]
    ChoiceSame lhs rhs ->
      [ binaryExpr variables (choiceSpecName lhs) token
        MIP..==. binaryExpr variables (choiceSpecName rhs) token
      | token <- relationTokens lhs rhs
      ]
    ChoiceDifferent lhs rhs ->
      [ binaryExpr variables (choiceSpecName lhs) token
        + binaryExpr variables (choiceSpecName rhs) token MIP..<=. 1
      | token <- relationTokens lhs rhs
      , token `elem` choiceSpecCategories lhs
      , token `elem` choiceSpecCategories rhs
      ]

relationTokens :: ChoiceSpec -> ChoiceSpec -> [String]
relationTokens lhs rhs =
  Set.toAscList
    (Set.fromList (choiceSpecCategories lhs ++ choiceSpecCategories rhs))

binaryExpr :: MipVariables -> String -> String -> MIP.Expr Scientific
binaryExpr variables name token =
  maybe 0 MIP.varExpr (Map.lookup (name, token) (choiceMipVariables variables))

numericVariable :: MipVariables -> String -> MIP.Var
numericVariable variables name =
  Map.findWithDefault
    (error ("missing numeric MIP variable: " ++ name))
    name
    (numericMipVariables variables)

choiceVariable :: MipVariables -> String -> String -> MIP.Var
choiceVariable variables name token =
  Map.findWithDefault
    (error ("missing categorical MIP variable: " ++ name ++ "." ++ token))
    (name, token)
    (choiceMipVariables variables)

shiftedScientificBounds :: DomainBounds -> MIP.Bounds Scientific
shiftedScientificBounds bounds =
  -- The shift is also reflected in every lowered affine row. Besides improving
  -- conditioning, nonnegative columns avoid signed primal values that the MIP
  -- 0.2.0.1 HiGHS solution parser cannot read.
  case (domainLowerBound bounds, domainUpperBound bounds) of
    (Just lower, Just upper) ->
      (MIP.Finite 0, MIP.Finite (scientific (upper - lower)))
    _ ->
      error "non-finite numeric bounds reached affine MIP variable lowering"

scientific :: Double -> Scientific
scientific = fromFloatDigits

scientificExpr :: Double -> MIP.Expr Scientific
scientificExpr = MIP.constExpr . scientific

decodeAssignment ::
     Map String [String]
  -> MipVariables
  -> MIP.Solution Scientific
  -> Either String Assignment
decodeAssignment domains variables solution =
  case MIP.solStatus solution of
    MIP.StatusOptimal -> traverseDomains
    MIP.StatusFeasible -> traverseDomains
    status -> Left ("HiGHS did not find a feasible design: " ++ show status)
  where
    traverseDomains =
      fmap Map.fromAscList (traverse selectToken (Map.toAscList domains))
    selectToken (name, tokens) =
      case filter ((> 0.5) . snd) (map tokenValue tokens) of
        [(token, _)] -> Right (name, token)
        selected ->
          Left
            ("HiGHS returned an invalid one-hot assignment for "
               ++ show name
               ++ ": "
               ++ show selected)
      where
        tokenValue token =
          ( token
          , realToFrac
              (Map.findWithDefault
                 0
                 (choiceVariable variables name token)
                 (MIP.solVariables solution)) :: Double)

showSeed :: RandomSeed -> String
showSeed (RandomSeed value) = show (abs (toInteger value))
