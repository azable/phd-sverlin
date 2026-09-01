{-# LANGUAGE OverloadedStrings #-}

-- | Bounded MIP feasibility adapter for large finite affine design spaces.
-- The Haskell @MIP@ package owns LP serialization and invokes the external
-- HiGHS executable; this module owns only Sverlin's lowering policy.
module Solver.Highs
  ( HighsCompletion(..)
  , feasibleCompletionWithHighs
  ) where

import           Control.Exception                     (SomeException, try)
import           Data.Default.Class                    (def)
import           Data.Map.Strict                       (Map)
import qualified Data.Map.Strict                       as Map
import           Data.Maybe                            (fromMaybe)
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
import           System.IO                             (hClose, hPutStrLn)
import           System.IO.Temp                        (withSystemTempFile)

type Assignment = Map String String

data MipVariables = MipVariables
  { numericMipVariables :: Map String MIP.Var
  , numericMipLowers    :: Map String Double
  , choiceMipVariables  :: Map (String, String) MIP.Var
  }

data HighsCompletion = HighsCompletion
  { highsChoiceAssignment :: Map String String
  , highsNumericValues    :: Map String Double
  }

data GuardedConstraint = GuardedConstraint
  { guardedBy         :: [(String, String)]
  , guardedConstraint :: Constraint
  }

-- | Ask whether one partial finite assignment has a feasible completion.
-- An empty cost map is a pure feasibility query. Callers may assign costs to
-- any deferred finite token when they need one seeded completion.
feasibleCompletionWithHighs ::
     Double
  -> Map String [String]
  -> Map (String, String) Double
  -> SolverProblem
  -> Assignment
  -> IO (Either String (Maybe HighsCompletion))
feasibleCompletionWithHighs boundTolerance domains objectiveCosts problem partial =
  case buildMipProblem boundTolerance domains objectiveCosts problem partial of
    Left err -> pure (Left err)
    Right (variables, mipProblem) ->
      withSystemTempFile "sverlin-highs.log" $ \logPath logHandle -> do
        hClose logHandle
        withSystemTempFile "sverlin-highs.options" $ \optionsPath handle -> do
          mapM_
            (hPutStrLn handle)
            [ "random_seed = 0"
            , "threads = 1"
            , "parallel = off"
            , "primal_feasibility_tolerance = 1e-9"
            , "mip_feasibility_tolerance = 1e-9"
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
          pure $ do
            solution <-
              case solved of
                Left err ->
                  Left
                    ("could not run the HiGHS feasibility backend: "
                       ++ show (err :: SomeException))
                Right value -> Right value
            case MIP.solStatus solution of
              MIP.StatusInfeasible -> Right Nothing
              MIP.StatusInfeasibleOrUnbounded -> Right Nothing
              MIP.StatusOptimal ->
                Just <$> decodeCompletion domains variables solution
              MIP.StatusFeasible ->
                Just <$> decodeCompletion domains variables solution
              status ->
                Left
                  ("HiGHS feasibility ended with an indeterminate status: "
                     ++ show status)

buildMipProblem ::
     Double
  -> Map String [String]
  -> Map (String, String) Double
  -> SolverProblem
  -> Assignment
  -> Either String (MipVariables, MIP.Problem Scientific)
buildMipProblem boundTolerance domains objectiveCosts problem partial = do
  validatePartial domains partial
  numericBounds <-
    finiteNumericBounds boundTolerance (solverConstraints problem)
  let variables = makeMipVariables numericBounds domains
      oneHot = map (oneHotConstraint variables) (Map.toAscList domains)
      pinned =
        [ binaryExpr variables name token MIP..==. 1
        | (name, token) <- Map.toAscList partial
        ]
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
  objective <- choiceObjective variables objectiveCosts
  let binaries = Map.elems (choiceMipVariables variables)
      variableDomains =
        Map.fromList
          ([ ( variable
             , (MIP.ContinuousVariable, shiftedScientificBounds bounds))
           | (name, bounds) <- Map.toAscList numericBounds
           , let variable = numericVariable variables name
           ]
             ++ [ ( variable
                  , ( MIP.IntegerVariable
                    , ( MIP.Finite (scientific mipChoiceOrigin)
                      , MIP.Finite (scientific (mipChoiceOrigin + 1)))))
                | variable <- binaries
                ])
      mipProblem =
        (def :: MIP.Problem Scientific)
          { MIP.name = Just "sverlin-design-space"
          , MIP.objectiveFunction =
              MIP.ObjectiveFunction
                { MIP.objLabel =
                    Just
                      (if Map.null objectiveCosts
                         then "feasibility"
                         else "algebraic_completion")
                , MIP.objDir = MIP.OptMin
                , MIP.objExpr = objective
                }
          , MIP.constraints = oneHot ++ pinned ++ categorical ++ numeric
          , MIP.varDomains = variableDomains
          }
  pure (variables, mipProblem)

choiceObjective ::
     MipVariables
  -> Map (String, String) Double
  -> Either String (MIP.Expr Scientific)
choiceObjective variables costs =
  fmap
    sum
    (traverse
       (\(key, coefficient) ->
          case Map.lookup key (choiceMipVariables variables) of
            Nothing ->
              Left ("cannot weight unknown finite choice token " ++ show key)
            Just variable ->
              Right (scientificExpr coefficient * logicalChoiceExpr variable))
       (Map.toAscList costs))

validatePartial :: Map String [String] -> Assignment -> Either String ()
validatePartial domains partial = mapM_ validate (Map.toAscList partial)
  where
    validate (name, token) =
      case Map.lookup name domains of
        Nothing -> Left ("cannot condition unknown finite choice " ++ show name)
        Just tokens
          | token `elem` tokens -> Right ()
          | otherwise ->
            Left
              ("cannot condition token "
                 ++ show token
                 ++ " for finite choice "
                 ++ show name)

makeMipVariables ::
     Map String DomainBounds -> Map String [String] -> MipVariables
makeMipVariables numericBounds domains =
  MipVariables
    { numericMipVariables =
        Map.fromList
          [ (name, MIP.Var (Text.pack ("x." ++ show index)))
          | (index, name) <- zip [0 :: Int ..] (Map.keys numericBounds)
          ]
    , numericMipLowers =
        Map.map
          (fromMaybe
             (error "finite MIP numeric bounds lost their lower endpoint")
             . domainLowerBound)
          numericBounds
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

finiteNumericBounds ::
     Double -> [Constraint] -> Either String (Map String DomainBounds)
finiteNumericBounds boundTolerance constraints = traverseWithKey validate bounds
  where
    types = collectConstraintVarTypes constraints
    inferred = inferDomainBounds constraints
    bounds =
      Map.map
        (canonicalizeBounds boundTolerance)
        (Map.mapWithKey
           (\name ty ->
              domainDefaultBounds ty
                `mergeDomainBounds` Map.findWithDefault
                                      unboundedDomainBounds
                                      name
                                      inferred)
           types)
    validate name domainBounds =
      case (domainLowerBound domainBounds, domainUpperBound domainBounds) of
        (Just lower, Just upper)
          | lower <= upper -> Right domainBounds
          | otherwise ->
            Left
              ("inconsistent numeric bounds for MIP variable "
                 ++ show name
                 ++ ": inferred lower "
                 ++ show lower
                 ++ " exceeds upper "
                 ++ show upper)
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
        Soft _ -> [GuardedConstraint guards constraint]
        Minimize _ -> [GuardedConstraint guards constraint]
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
    Soft _ -> Left "soft constraints are unsupported in affine design spaces"
    Minimize _ ->
      Left "numeric objectives are unsupported in affine design spaces"
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
        sum [binaryExpr variables name token | (name, token) <- guards]
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

affineLowerShift :: Map String DomainBounds -> AffineRow -> Either String Double
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
      lower <- maybeBound name "lower" (domainLowerBound variableBounds)
      pure (total + coefficient * (lower - mipCoordinateOrigin))

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
  maybe
    0
    logicalChoiceExpr
    (Map.lookup (name, token) (choiceMipVariables variables))

logicalChoiceExpr :: MIP.Var -> MIP.Expr Scientific
logicalChoiceExpr variable =
  MIP.varExpr variable - scientificExpr mipChoiceOrigin

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
shiftedScientificBounds bounds
  -- The shift is also reflected in every lowered affine row. Keeping each
  -- temporary coordinate at or above one avoids tiny negative zero-endpoint
  -- values that the MIP 0.2.0.1 HiGHS solution parser cannot read.
 =
  case (domainLowerBound bounds, domainUpperBound bounds) of
    (Just lower, Just upper) ->
      ( MIP.Finite (scientific mipCoordinateOrigin)
      , MIP.Finite (scientific (upper - lower + mipCoordinateOrigin)))
    _ -> error "non-finite numeric bounds reached affine MIP variable lowering"

-- This is an exact coordinate translation, not a constraint margin. One is
-- deliberately well above HiGHS's configured 1e-9 feasibility tolerance.
mipCoordinateOrigin :: Double
mipCoordinateOrigin = 1

-- Logical zero and one are likewise stored as integer one and two. Every
-- expression subtracts this origin, so this is only a parser-safe coordinate
-- translation and does not change the MIP or its seeded objective.
mipChoiceOrigin :: Double
mipChoiceOrigin = 1

scientific :: Double -> Scientific
scientific = fromFloatDigits

scientificExpr :: Double -> MIP.Expr Scientific
scientificExpr = MIP.constExpr . scientific

decodeCompletion ::
     Map String [String]
  -> MipVariables
  -> MIP.Solution Scientific
  -> Either String HighsCompletion
decodeCompletion domains variables solution = do
  assignment <- decodeAssignment domains variables solution
  pure
    HighsCompletion
      { highsChoiceAssignment = assignment
      , highsNumericValues =
          Map.mapWithKey
            (\name variable ->
               Map.findWithDefault
                 (error ("missing MIP lower bound for " ++ show name))
                 name
                 (numericMipLowers variables)
                 - mipCoordinateOrigin
                 + (realToFrac
                      (Map.findWithDefault
                         0
                         variable
                         (MIP.solVariables solution)) :: Double))
            (numericMipVariables variables)
      }

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
          , (realToFrac
               (Map.findWithDefault
                  0
                  (choiceVariable variables name token)
                  (MIP.solVariables solution)) :: Double)
              - mipChoiceOrigin)
