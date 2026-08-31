{-# LANGUAGE ScopedTypeVariables #-}

-- | Expand a declarative 'RenderPlan' against one immutable semantic trace,
-- compile its finite affine design space once, and sample several views.
--
-- The module is intentionally private.  It is the narrow bridge between the
-- authored Render vocabulary and the versioned visualization package.
module Sverlin.Internal.Render.Compile
  ( RenderCompileError(..)
  , compileRenderBatch
  ) where

import           Control.Monad                      (foldM, unless, when)
import qualified Data.ByteString                    as BS
import           Data.Either                        (fromRight, lefts)
import           Data.IORef                         (modifyIORef', newIORef,
                                                     readIORef)
import           Data.List                          (find, intercalate,
                                                     isPrefixOf, nub, sortOn)
import           Data.Map.Strict                    (Map)
import qualified Data.Map.Strict                    as Map
import           Data.Maybe                         (catMaybes, fromMaybe,
                                                     isJust, isNothing,
                                                     mapMaybe)
import           Data.Set                           (Set)
import qualified Data.Set                           as Set
import qualified Data.Text                          as Text
import qualified Data.Text.Encoding                 as Text
import qualified LinearTrace.Visualization.IR       as IR
import qualified LinearTrace.Visualization.Resource as Resource
import           Prelude
import qualified Solver                             as S
import qualified Sverlin.Internal.Render            as R
import qualified Sverlin.Internal.Render.Theme      as Theme
import qualified Sverlin.Internal.Render.Typography as Typography
import qualified Sverlin.Internal.Semantic          as Sem
import           Text.Read                          (readMaybe)

--------------------------------------------------------------------------------
-- Public compiler boundary
--------------------------------------------------------------------------------
data RenderCompileError
  = InvalidRenderPlan String
  | UnsupportedRenderPlan String
  | RenderDesignSpaceError S.DesignSpaceError
  deriving (Eq, Show)

-- | Compile one scenario and sample all requested view seeds from the same
-- prepared affine design space.  The source content participates in the
-- scenario key; the display path does not.
compileRenderBatch ::
     FilePath
  -> String
  -> [Int]
  -> Sem.SemanticTrace
  -> R.RenderPlan
  -> IO (Either RenderCompileError Resource.CompilationPackage)
compileRenderBatch sourcePath sourceContent viewSeeds trace plan = do
  preparedResult <- prepareCompilation trace plan
  case preparedResult of
    Left err -> pure (Left err)
    Right prepared ->
      case S.compileDesignSpace
             (renderSolveConfig prepared)
             (preparedProblem prepared) of
        Left err -> pure (Left (RenderDesignSpaceError err))
        Right design -> do
          sampled <-
            S.sampleDesignSpaceBatch
              S.BalancedDesignChoices
              (map S.RandomSeed viewSeeds)
              design
          pure $ do
            solutions <- either (Left . RenderDesignSpaceError) Right sampled
            let key = scenarioKey sourceContent trace
            materialized <-
              sequence
                [ materializeVisualization
                  sourcePath
                  key
                  trace
                  prepared
                  solution
                | solution <- solutions
                ]
            let visualizations = map fst materialized
                resources = deduplicateResources (concatMap snd materialized)
            pure
              Resource.CompilationPackage
                { Resource.compilationPackageVisualizations = visualizations
                , Resource.compilationPackageResources = resources
                , Resource.compilationPackageProvenance =
                    Typography.typographyCompilationProvenance
                }
  where
    -- Fitted text and theme variables start at the midpoints of their
    -- documented ranges. Otherwise HiGHS supplies a lower-corner feasibility
    -- point and high-dimensional hit-and-run can spend its bounded burn-in at
    -- that corner. Phase I projects an infeasible text midpoint back into the
    -- valid region; these values are hints only and never pin the sample.
    renderSolveConfig prepared =
      S.withInitialOverrides
        (Map.fromList
           ([ (syntheticTextFontSizeName index declaration, 22)
            | (index, declaration) <-
                zip [0 :: Int ..] (R.planContents (preparedPlan prepared))
            , R.contentDeclarationFit declaration
            ]
              ++ [ (automaticStyleVariableName family field, midpoint)
                 | family <- automaticStyleFamilies (preparedExpanded prepared)
                 , (field, midpoint) <-
                     [ ("fill.hue", 180)
                     , ("fill.saturation", 0.45)
                     , ("fill.lightness", 0.9)
                     , ("stroke.saturation", 0.55)
                     , ("stroke.lightness", 0.375)
                     , ("soft-card.radius", 11)
                     ]
                 ]))
        -- Eight branches keep small authored alternatives exactly enumerable.
        -- The automatic 8-by-3 font catalog is instead conditioned once per
        -- requested seed, avoiding 24 repeated affine preparation passes.
        (S.withMaxCategoricalBranches 8 S.defaultSolveConfig)

scenarioKey :: String -> Sem.SemanticTrace -> IR.ScenarioKey
scenarioKey source trace =
  let bytes =
        Text.encodeUtf8
          (Text.pack
             ("sverlin-ir-v2-theme-1\NUL" ++ source ++ "\NUL" ++ show trace))
      IR.Sha256 digest = Resource.sha256Bytes bytes
   in IR.ScenarioKey digest

--------------------------------------------------------------------------------
-- Expanded semantic matches
--------------------------------------------------------------------------------
data LifetimeCheck
  = BlockLifetime Sem.BlockId
  | OccupancyLifetime Sem.TraceOccupancy
  | RelationLifetime Int
  deriving (Eq, Show)

data ExpansionContext = ExpansionContext
  { contextCurrentNode :: Maybe Int
  , contextBindings    :: Map R.SelectionId Sem.BlockId
  , contextRelations   :: Map R.RelationSelectionId Sem.TraceRelation
  , contextChecks      :: [LifetimeCheck]
  , contextKey         :: String
  } deriving (Eq, Show)

rootContext :: ExpansionContext
rootContext =
  ExpansionContext
    { contextCurrentNode = Nothing
    , contextBindings = Map.empty
    , contextRelations = Map.empty
    , contextChecks = []
    , contextKey = "root"
    }

data ExpandedNode = ExpandedNode
  { expandedNodeId            :: Int
  , expandedNodeDeclaration   :: R.NodeDeclarationId
  , expandedNodeTarget        :: R.NodeTarget
  , expandedNodeParent        :: Int
  , expandedNodeSemanticBlock :: Maybe Sem.BlockId
  , expandedNodeRole          :: String
  , expandedNodeContext       :: ExpansionContext
  , expandedNodeGuards        :: [R.PresenceGuard]
  } deriving (Eq, Show)

data ConcreteNode
  = ConcreteCanvas
  | ConcreteVisual ExpandedNode
  deriving (Eq, Show)

data ExpandedConnector = ExpandedConnector
  { expandedConnectorId          :: Int
  , expandedConnectorDeclaration :: R.ConnectorDeclaration
  , expandedConnectorContext     :: ExpansionContext
  , expandedConnectorStart       :: ConcreteNode
  , expandedConnectorEnd         :: ConcreteNode
  , expandedConnectorRelation    :: Maybe Sem.TraceRelation
  , expandedConnectorGuards      :: [R.PresenceGuard]
  } deriving (Show)

data ExpandedPlan = ExpandedPlan
  { expandedNodes      :: [ExpandedNode]
  , expandedConnectors :: [ExpandedConnector]
  , expandedRanks      :: Map R.RankingId (Map Sem.BlockId Int)
  }

data PreparedCompilation = PreparedCompilation
  { preparedExpanded :: ExpandedPlan
  , preparedProblem  :: S.SolverProblem
  , preparedPlan     :: R.RenderPlan
  , preparedText     :: [PreparedText]
  }

data PreparedText = PreparedText
  { preparedTextDeclaration :: Int
  , preparedTextNode        :: Int
  , preparedTextBranches    :: [PreparedTextBranch]
  , preparedTextRejected    :: [[ChoiceRequirement]]
  }

data PreparedTextBranch = PreparedTextBranch
  { preparedTextRequirements :: [ChoiceRequirement]
  , preparedTextLine         :: Typography.PreparedLine
  }

data MaterializedText = MaterializedText
  { materializedPreparedLine :: Typography.PreparedLine
  , materializedTextLayout   :: IR.TextLayout
  , materializedFontSize     :: Double
  }

data ChoiceRequirement = ChoiceRequirement
  { requirementName     :: String
  , requirementTokens   :: [String]
  , requirementSelected :: String
  } deriving (Eq, Show)

data RenderedText = RenderedText
  { renderedTextSource    :: String
  , renderedTextFragments :: [Typography.FragmentRange]
  }

data FontConfiguration = FontConfiguration
  { configurationFamily       :: String
  , configurationWeight       :: Int
  , configurationStyle        :: String
  , configurationRequirements :: [ChoiceRequirement]
  }

prepareCompilation ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> IO (Either RenderCompileError PreparedCompilation)
prepareCompilation trace plan =
  case expand of
    Left err -> pure (Left err)
    Right expanded -> do
      typographyResult <- prepareTypographyLines trace plan expanded
      pure $ do
        typography <- typographyResult
        constraints <- lowerPlan trace plan expanded typography
        pure
          PreparedCompilation
            { preparedExpanded = expanded
            , preparedProblem = S.solverProblem constraints
            , preparedPlan = plan
            , preparedText = typography
            }
  where
    expand = do
      validateFrames trace plan
      nodes <- expandNodes trace plan
      ranks <- compileRankings trace plan nodes
      connectors <- expandConnectors trace plan nodes
      pure (ExpandedPlan nodes connectors ranks)

prepareTypographyLines ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> ExpandedPlan
  -> IO (Either RenderCompileError [PreparedText])
prepareTypographyLines trace plan expanded =
  case typographyTasks of
    Left err -> pure (Left err)
    Right tasks -> do
      cache <- newIORef Map.empty
      fmap sequence (traverse (prepareTask cache) tasks)
  where
    nodes = expandedNodes expanded
    typographyTasks =
      concat
        <$> traverse
              (uncurry declarationTasks)
              (zip [0 :: Int ..] (R.planContents plan))
    declarationTasks index declaration = do
      contexts <-
        contextsForScope
          trace
          plan
          nodes
          (R.contentDeclarationScope declaration)
      fmap concat (traverse (contextTasks index declaration) contexts)
    contextTasks index declaration context = do
      candidates <-
        resolveReferenceCandidates
          trace
          plan
          expanded
          context
          (R.contentDeclarationNode declaration)
      traverse (candidateTask index declaration context) candidates
    candidateTask index declaration context concrete = do
      rendered <-
        renderContentLine
          trace
          expanded
          concrete
          (R.contentDeclarationPieces declaration)
      configurations <- fontConfigurations context concrete
      pure (index, concreteNodeId concrete, rendered, configurations)
    fontConfigurations context concrete = do
      families <- styleOptions context concrete R.FontFamilyField "Inter"
      weights <- styleOptions context concrete R.FontWeightField "400"
      styles <- styleOptions context concrete R.FontStyleField "normal"
      catMaybes
        <$> traverse
              makeConfiguration
              [ ( family
                , weight
                , style
                , familyRequirements ++ weightRequirements ++ styleRequirements)
              | (family, familyRequirements) <- families
              , (weight, weightRequirements) <- weights
              , (style, styleRequirements) <- styles
              ]
    makeConfiguration (family, weightToken, style, requirements) = do
      weight <- parseFontWeight weightToken
      pure
        (FontConfiguration family weight style
           <$> mergeRequirements requirements)
    styleOptions = categoricalStyleOptions trace plan expanded
    prepareTask cache (index, node, rendered, configurations) = do
      results <- traverse (prepareConfiguration cache rendered) configurations
      let accepted =
            [ PreparedTextBranch (configurationRequirements configuration) line
            | (configuration, Right line) <- zip configurations results
            ]
          rejected =
            [ configurationRequirements configuration
            | (configuration, Left _) <- zip configurations results
            ]
          errors = nub (lefts results)
      pure
        (if null accepted
           then Left
                  (InvalidRenderPlan
                     ("no managed font branch can shape text "
                        ++ show (renderedTextSource rendered)
                        ++ case errors of
                             [] -> ""
                             _  -> ": " ++ intercalate "; " errors))
           else Right
                  PreparedText
                    { preparedTextDeclaration = index
                    , preparedTextNode = node
                    , preparedTextBranches = accepted
                    , preparedTextRejected = rejected
                    })
    prepareConfiguration cache rendered configuration = do
      let key =
            intercalate
              "\NUL"
              [ configurationFamily configuration
              , show (configurationWeight configuration)
              , configurationStyle configuration
              , renderedTextSource rendered
              , show (renderedTextFragments rendered)
              ]
      cached <- Map.lookup key <$> readIORef cache
      case cached of
        Just result -> pure result
        Nothing -> do
          result <-
            Typography.prepareLine
              (configurationFamily configuration)
              (configurationWeight configuration)
              (configurationStyle configuration)
              (renderedTextSource rendered)
              (renderedTextFragments rendered)
          modifyIORef' cache (Map.insert key result)
          pure result

mergeRequirements :: [ChoiceRequirement] -> Maybe [ChoiceRequirement]
mergeRequirements requirements =
  Map.elems <$> foldM insertRequirement Map.empty requirements
  where
    insertRequirement current requirement =
      case Map.lookup (requirementName requirement) current of
        Nothing ->
          Just (Map.insert (requirementName requirement) requirement current)
        Just previous
          | requirementSelected previous == requirementSelected requirement ->
            Just current
          | otherwise -> Nothing

-- Font metrics are prepared before sampling.  Resolve a categorical style as
-- one option per finite assignment that can change its cascade, so a guarded
-- declaration and the emitted style always select the same concrete face.
categoricalStyleOptions ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> ExpandedPlan
  -> ExpansionContext
  -> ConcreteNode
  -> R.StyleFieldName
  -> String
  -> Either RenderCompileError [(String, [ChoiceRequirement])]
categoricalStyleOptions trace plan expanded context concrete field fallback = do
  domains <-
    collectStyleDomains Set.empty context concrete field automaticDomains
  traverse
    (evaluateOption domains)
    (decisionAssignments (Map.toAscList domains))
  where
    automaticDomains
      | not (automaticStyleEligible expanded concrete) = Map.empty
      | styleCascadeDeclared concrete field = Map.empty
      | field == R.FontFamilyField =
        Map.singleton
          Theme.automaticFontFamilyChoice
          Theme.automaticFontFamilies
      | field == R.FontWeightField =
        Map.singleton Theme.automaticFontWeightChoice Theme.automaticFontWeights
      | otherwise = Map.empty
    styleCascadeDeclared current fieldName =
      not (null (matchingStyleDeclarations plan current fieldName))
        || case parentConcrete expanded current of
             Left _       -> False
             Right parent -> styleCascadeDeclared parent fieldName
    evaluateOption domains assignment = do
      token <-
        evaluateStyleToken Set.empty assignment context concrete field fallback
      pure
        ( token
        , [ ChoiceRequirement name tokens selected
          | (name, tokens) <- Map.toAscList domains
          , Just selected <- [Map.lookup name assignment]
          ])
    collectStyleDomains visited currentContext current fieldName domains
      | Set.member (concreteNodeId current, fieldName) visited =
        leftInvalid "categorical style projection contains a cycle"
      | otherwise = do
        let nextVisited = Set.insert (concreteNodeId current, fieldName) visited
        local <-
          foldM
            (collectDeclarationDomains nextVisited currentContext)
            domains
            (matchingStyleDeclarations plan current fieldName)
        case parentConcrete expanded current of
          Left _ -> pure local
          Right parent ->
            collectStyleDomains
              nextVisited
              (contextForConcrete parent)
              parent
              fieldName
              local
    collectDeclarationDomains visited declarationContext domains declaration = do
      guarded <-
        foldM
          (collectGuardDomain visited declarationContext)
          domains
          (R.scopeGuards (R.styleDeclarationScope declaration))
      collectAssignmentDomain
        visited
        declarationContext
        guarded
        (R.styleDeclarationValue declaration)
    collectGuardDomain visited guardContext domains guard =
      case guard of
        R.StyleChoiceDecision reference sourceField _ -> do
          source <- resolveStyleSource guardContext reference
          collectStyleDomains visited guardContext source sourceField domains
        _ -> do
          resolved <- resolveGuard trace plan expanded guardContext guard
          case resolved of
            GuardDecision name tokens _ ->
              insertDecisionDomain name tokens domains
            GuardAlways -> pure domains
            GuardNever -> pure domains
    collectAssignmentDomain visited assignmentContext domains assignment =
      case assignment of
        R.ChoiceStyle reference ->
          case reference of
            R.DeclaredChoice identifier -> do
              declaration <- requireChoice plan identifier
              let decisionContext =
                    contextForScopeDeclaration
                      expanded
                      assignmentContext
                      (R.choiceDeclarationScope declaration)
              insertDecisionDomain
                (choiceName declaration decisionContext)
                (R.choiceDeclarationTokens declaration)
                domains
            R.StyleChoice source sourceField -> do
              sourceNode <- resolveStyleSource assignmentContext source
              collectStyleDomains
                visited
                assignmentContext
                sourceNode
                sourceField
                domains
        _ -> pure domains
    evaluateStyleToken visited assignment currentContext current fieldName defaultToken
      | Set.member (concreteNodeId current, fieldName) visited =
        leftInvalid "categorical style projection contains a cycle"
      | otherwise = do
        let nextVisited = Set.insert (concreteNodeId current, fieldName) visited
            declarations = matchingStyleDeclarations plan current fieldName
        active <-
          firstActiveDeclaration
            nextVisited
            assignment
            currentContext
            declarations
        case active of
          Just declaration -> do
            token <-
              evaluateStyleAssignment
                nextVisited
                assignment
                currentContext
                defaultToken
                (R.styleDeclarationValue declaration)
            resolveRelativeWeight
              nextVisited
              assignment
              current
              fieldName
              defaultToken
              token
          Nothing ->
            case parentConcrete expanded current of
              Left _ -> automaticToken assignment fieldName defaultToken
              Right parent ->
                evaluateStyleToken
                  nextVisited
                  assignment
                  (contextForConcrete parent)
                  parent
                  fieldName
                  defaultToken
    automaticToken assignment fieldName defaultToken
      | not (automaticStyleEligible expanded concrete) = pure defaultToken
      | fieldName == R.FontFamilyField =
        requireAutomatic
          Theme.automaticFontFamilyChoice
          Theme.automaticFontFamilies
      | fieldName == R.FontWeightField =
        requireAutomatic
          Theme.automaticFontWeightChoice
          Theme.automaticFontWeights
      | otherwise = pure defaultToken
      where
        requireAutomatic name tokens =
          case Map.lookup name assignment of
            Just token
              | token `elem` tokens -> pure token
            _ -> leftInvalid ("missing automatic style decision " ++ show name)
    -- CSS resolves relative weights against the inherited concrete weight:
    -- bolder maps <=300/400-500/>=600 to 400/700/900; lighter maps
    -- <=500/600-700/>=800 to 100/400/700.
    resolveRelativeWeight visited assignment current fieldName defaultToken token
      | fieldName /= R.FontWeightField = pure token
      | token /= "bolder" && token /= "lighter" = pure token
      | otherwise = do
        inheritedToken <-
          case parentConcrete expanded current of
            Left _ -> pure defaultToken
            Right parent ->
              evaluateStyleToken
                visited
                assignment
                (contextForConcrete parent)
                parent
                fieldName
                defaultToken
        inherited <- parseFontWeight inheritedToken
        let resolved :: Int
            resolved =
              case token of
                "bolder"
                  | inherited <= 300 -> 400
                  | inherited <= 500 -> 700
                  | otherwise -> 900
                _
                  | inherited <= 500 -> 100
                  | inherited <= 700 -> 400
                  | otherwise -> 700
        pure (show resolved)
    firstActiveDeclaration _ _ _ [] = pure Nothing
    firstActiveDeclaration visited assignment currentContext (declaration:rest) = do
      active <-
        allM
          (styleGuardActive visited assignment currentContext)
          (R.scopeGuards (R.styleDeclarationScope declaration))
      if active
        then pure (Just declaration)
        else firstActiveDeclaration visited assignment currentContext rest
    styleGuardActive visited assignment guardContext guard =
      case guard of
        R.StyleChoiceDecision reference sourceField required -> do
          source <- resolveStyleSource guardContext reference
          token <-
            evaluateStyleToken
              visited
              assignment
              guardContext
              source
              sourceField
              (categoricalStyleFallback sourceField)
          pure (token == required)
        _ -> do
          resolved <- resolveGuard trace plan expanded guardContext guard
          pure
            (case resolved of
               GuardAlways -> True
               GuardNever -> False
               GuardDecision name _ required ->
                 Map.lookup name assignment == Just required)
    evaluateStyleAssignment visited assignment assignmentContext defaultToken styleAssignment =
      case styleAssignment of
        R.FixedStyle token -> pure token
        R.RemovedStyle -> pure defaultToken
        R.ChoiceStyle reference ->
          case reference of
            R.DeclaredChoice identifier -> do
              declaration <- requireChoice plan identifier
              let decisionContext =
                    contextForScopeDeclaration
                      expanded
                      assignmentContext
                      (R.choiceDeclarationScope declaration)
                  name = choiceName declaration decisionContext
              maybe
                (leftInvalid
                   ("missing categorical style decision " ++ show name))
                pure
                (Map.lookup name assignment)
            R.StyleChoice source sourceField -> do
              sourceNode <- resolveStyleSource assignmentContext source
              evaluateStyleToken
                visited
                assignment
                assignmentContext
                sourceNode
                sourceField
                (categoricalStyleFallback sourceField)
        _ -> leftInvalid "text font style must be categorical"
    resolveStyleSource sourceContext reference = do
      candidates <-
        resolveReferenceCandidates trace plan expanded sourceContext reference
      requireSingle "categorical style source" candidates

insertDecisionDomain ::
     String
  -> [String]
  -> Map String [String]
  -> Either RenderCompileError (Map String [String])
insertDecisionDomain name tokens domains =
  case Map.lookup name domains of
    Nothing -> pure (Map.insert name tokens domains)
    Just previous
      | previous == tokens -> pure domains
      | otherwise ->
        leftInvalid ("choice has inconsistent domains: " ++ show name)

decisionAssignments :: [(String, [String])] -> [Map String String]
decisionAssignments entries =
  case entries of
    [] -> [Map.empty]
    (name, tokens):rest ->
      [ Map.insert name token assignment
      | token <- tokens
      , assignment <- decisionAssignments rest
      ]

categoricalStyleFallback :: R.StyleFieldName -> String
categoricalStyleFallback field =
  case field of
    R.FontFamilyField  -> "Inter"
    R.FontWeightField  -> "400"
    R.FontStyleField   -> "normal"
    R.TextAlignField   -> "center"
    R.BorderStyleField -> "none"
    _                  -> ""

allM :: Monad monad => (value -> monad Bool) -> [value] -> monad Bool
allM predicate values =
  case values of
    [] -> pure True
    value:rest -> do
      matches <- predicate value
      if matches
        then allM predicate rest
        else pure False

parseFontWeight :: String -> Either RenderCompileError Int
parseFontWeight token =
  case token of
    "normal" -> pure 400
    "bold" -> pure 700
    "bolder" ->
      leftInvalid
        "relative font weight bolder was not resolved against inheritance"
    "lighter" ->
      leftInvalid
        "relative font weight lighter was not resolved against inheritance"
    _ ->
      case readMaybe token of
        Just value
          | value >= 100 && value <= 900 -> pure value
        _ -> leftInvalid ("unsupported font weight " ++ show token)

validateFrames ::
     Sem.SemanticTrace -> R.RenderPlan -> Either RenderCompileError ()
validateFrames trace plan = do
  let declarations = R.planFrames plan
      identities = map R.frameStepIdentity declarations
      duplicateIdentities = duplicates identities
      alwaysIdentities =
        [ R.frameStepIdentity declaration
        | declaration <- declarations
        , R.frameAlways declaration
        ]
      occurred =
        Set.fromList
          [ Sem.traceMarkerType (Sem.stepOccurrenceDefinition occurrence)
          | occurrence <- Sem.semanticTraceSteps trace
          ]
  unless (null duplicateIdentities)
    $ leftInvalid
        ("duplicate frame declarations for "
           ++ intercalate ", " duplicateIdentities)
  when (null alwaysIdentities)
    $ leftInvalid "Render must declare at least one always frame"
  when (all (`Set.notMember` occurred) alwaysIdentities)
    $ leftInvalid "no always frame step occurs in this scenario"

leftInvalid :: String -> Either RenderCompileError value
leftInvalid = Left . InvalidRenderPlan

duplicates :: Ord value => [value] -> [value]
duplicates values =
  Map.keys
    (Map.filter
       (> (1 :: Int))
       (Map.fromListWith (+) [(value, 1) | value <- values]))

expandNodes ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> Either RenderCompileError [ExpandedNode]
expandNodes trace plan = foldM expand [] (R.planNodes plan)
  where
    expand nodes declaration = do
      contexts <-
        contextsForScope trace plan nodes (R.nodeDeclarationScope declaration)
      scopedCandidates <-
        fmap concat (traverse (candidatesFor declaration nodes) contexts)
      let additions =
            zipWith (instantiate declaration) [length nodes ..] scopedCandidates
      pure (nodes ++ additions)
    candidatesFor declaration nodes context = do
      candidates <- targetCandidates trace plan nodes context declaration
      pure [(context, candidate) | candidate <- candidates]
    instantiate declaration identifier (context, candidate) =
      let semanticBlock = candidateBlock candidate
          relationSuffix =
            case candidateRelation candidate of
              Nothing        -> ""
              Just relation' -> ":r" ++ show (Sem.traceRelationId relation')
          blockSuffix =
            maybe "" ((":b" ++) . show . Sem.blockIdInt) semanticBlock
          nodeKey =
            contextKey context
              ++ "/n"
              ++ showNodeDeclarationId (R.nodeDeclarationId declaration)
              ++ blockSuffix
              ++ relationSuffix
          bindings =
            case (R.nodeDeclarationTarget declaration, semanticBlock) of
              (R.SelectedNodeTarget selection, Just block) ->
                Map.insert selection block (contextBindings context)
              _ -> contextBindings context
          relationMap =
            case candidateRelation candidate of
              Nothing -> contextRelations context
              Just relation' ->
                case R.nodeDeclarationTarget declaration of
                  R.RelationEndpointTarget selection _ ->
                    Map.insert selection relation' (contextRelations context)
                  _ -> contextRelations context
          checks =
            contextChecks context
              ++ maybe [] (pure . BlockLifetime) semanticBlock
              ++ maybe
                   []
                   (pure . OccupancyLifetime)
                   (candidateOccupancy candidate)
              ++ maybe
                   []
                   (pure . RelationLifetime . Sem.traceRelationId)
                   (candidateRelation candidate)
          inner =
            context
              { contextCurrentNode = Just identifier
              , contextBindings = bindings
              , contextRelations = relationMap
              , contextChecks = nub checks
              , contextKey = nodeKey
              }
       in ExpandedNode
            { expandedNodeId = identifier
            , expandedNodeDeclaration = R.nodeDeclarationId declaration
            , expandedNodeTarget = R.nodeDeclarationTarget declaration
            , expandedNodeParent = fromMaybe (-1) (contextCurrentNode context)
            , expandedNodeSemanticBlock = semanticBlock
            , expandedNodeRole = targetRole plan declaration candidate
            , expandedNodeContext = inner
            , expandedNodeGuards =
                R.scopeGuards (R.nodeDeclarationScope declaration)
            }

data NodeCandidate = NodeCandidate
  { candidateBlock     :: Maybe Sem.BlockId
  , candidateOccupancy :: Maybe Sem.TraceOccupancy
  , candidateRelation  :: Maybe Sem.TraceRelation
  }

targetCandidates ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> [ExpandedNode]
  -> ExpansionContext
  -> R.NodeDeclaration
  -> Either RenderCompileError [NodeCandidate]
targetCandidates trace plan nodes context declaration =
  case R.nodeDeclarationTarget declaration of
    R.GeneratedNodeTarget -> pure [NodeCandidate Nothing Nothing Nothing]
    R.SelectedNodeTarget selection -> do
      blocks <-
        selectedBlocks
          trace
          plan
          nodes
          context
          (R.nodeDeclarationScope declaration)
          selection
      pure
        [ NodeCandidate (Just block) occupancy Nothing
        | (block, occupancy) <- blocks
        ]
    R.RelationEndpointTarget relationSelection isFirst -> do
      relation' <- requireContextRelation relationSelection context
      let block =
            if isFirst
              then Sem.traceRelationSource relation'
              else Sem.traceRelationTarget relation'
      pure [NodeCandidate (Just block) Nothing (Just relation')]

targetRole :: R.RenderPlan -> R.NodeDeclaration -> NodeCandidate -> String
targetRole plan declaration _candidate =
  case R.nodeDeclarationTarget declaration of
    R.GeneratedNodeTarget -> "Generated"
    R.SelectedNodeTarget selection ->
      maybe
        "Selected"
        R.selectionDeclarationKindKey
        (find
           ((== selection) . R.selectionDeclarationId)
           (R.planSelections plan))
    R.RelationEndpointTarget _ isFirst ->
      if isFirst
        then "RelationSource"
        else "RelationTarget"

selectedBlocks ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> [ExpandedNode]
  -> ExpansionContext
  -> R.Scope
  -> R.SelectionId
  -> Either RenderCompileError [(Sem.BlockId, Maybe Sem.TraceOccupancy)]
selectedBlocks trace plan nodes context scope selection = do
  declaration <- requireSelection plan selection
  let allMatches =
        [ Sem.traceBlockId block
        | block <- Sem.semanticTraceBlocks trace
        , Sem.traceMarkerType (Sem.traceBlockKind block)
            == R.selectionDeclarationKindKey declaration
        , blockVisibleAtAnyFrame trace plan block
        ]
      membershipMatches = applyMemberships trace plan context scope allMatches
  case contextCurrentNode context >>= (`lookupExpandedNode` nodes) of
    Nothing -> pure [(block, Nothing) | block <- membershipMatches]
    Just parent ->
      case expandedNodeSemanticBlock parent >>= (`lookupTraceBlock` trace) of
        Nothing -> pure [(block, Nothing) | block <- membershipMatches]
        Just owner ->
          let occupancies = Sem.traceBlockOccupancies owner
              matching =
                [ (Sem.traceOccupant occupancy, Just occupancy)
                | occupancy <- occupancies
                , Sem.traceOccupant occupancy `elem` membershipMatches
                ]
              occupantKinds =
                Set.fromList
                  [ Sem.traceMarkerType (Sem.traceBlockKind occupant)
                  | occupancy <- occupancies
                  , Just occupant <-
                      [lookupTraceBlock (Sem.traceOccupant occupancy) trace]
                  ]
              candidateKinds =
                Set.fromList
                  [ Sem.traceMarkerType (Sem.traceBlockKind block)
                  | identifier <- membershipMatches
                  , Just block <- [lookupTraceBlock identifier trace]
                  ]
           in if null occupancies
                   || Set.null (Set.intersection occupantKinds candidateKinds)
                then pure [(block, Nothing) | block <- membershipMatches]
                else pure matching

applyMemberships ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> ExpansionContext
  -> R.Scope
  -> [Sem.BlockId]
  -> [Sem.BlockId]
applyMemberships trace plan context scope =
  \candidates -> foldl' restrict candidates (R.scopeMemberships scope)
  where
    restrict candidates membership =
      case Map.lookup
             (R.membershipSelection membership)
             (contextBindings context) of
        Nothing -> candidates
        Just owner ->
          case find
                 ((== R.membershipRelation membership)
                    . R.relationSelectionDeclarationId)
                 (R.planRelationSelections plan) of
            Nothing -> candidates
            Just relationDeclaration ->
              let matchingRelations =
                    [ relation'
                    | relation' <- Sem.semanticTraceRelations trace
                    , Sem.traceMarkerType (Sem.traceRelationKind relation')
                        == R.relationSelectionDeclarationKindKey
                             relationDeclaration
                    ]
                  possibleTargetKinds =
                    Set.fromList
                      [ Sem.traceMarkerType (Sem.traceBlockKind target)
                      | relation' <- matchingRelations
                      , Just target <-
                          [ lookupTraceBlock
                              (Sem.traceRelationTarget relation')
                              trace
                          ]
                      ]
                  candidateKinds =
                    Set.fromList
                      [ Sem.traceMarkerType (Sem.traceBlockKind block)
                      | identifier <- candidates
                      , Just block <- [lookupTraceBlock identifier trace]
                      ]
                  targets =
                    Set.fromList
                      [ Sem.traceRelationTarget relation'
                      | relation' <- matchingRelations
                      , Sem.traceRelationSource relation' == owner
                      ]
               in if Set.null
                       (Set.intersection possibleTargetKinds candidateKinds)
                    then candidates
                    else filter (`Set.member` targets) candidates

contextsForScope ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> [ExpandedNode]
  -> R.Scope
  -> Either RenderCompileError [ExpansionContext]
contextsForScope trace plan nodes scope = do
  let base =
        case R.scopeCurrentNode scope of
          Nothing -> [rootContext]
          Just declaration ->
            [ expandedNodeContext node
            | node <- nodes
            , expandedNodeDeclaration node == declaration
            ]
  related <- fmap concat (traverse addRelation base)
  traverse bindLocalSelections related
  where
    addRelation context =
      case R.scopeRelation scope of
        Nothing -> pure [context]
        Just selection ->
          case Map.lookup selection (contextRelations context) of
            Just _ -> pure [context]
            Nothing -> do
              relations <- relationsForScope trace plan context scope selection
              pure
                [ context
                  { contextRelations =
                      Map.insert selection relation' (contextRelations context)
                  , contextChecks =
                      nub
                        (RelationLifetime (Sem.traceRelationId relation')
                           : contextChecks context)
                  , contextKey =
                      contextKey context
                        ++ "/r"
                        ++ showRelationSelectionId selection
                        ++ ":"
                        ++ show (Sem.traceRelationId relation')
                  }
                | relation' <- relations
                ]
    bindLocalSelections context = foldM bindOne context localSelections
      where
        ancestorDeclarations =
          [ expandedNodeDeclaration node
          | identifier <- contextAncestors nodes context
          , Just node <- [lookupExpandedNode identifier nodes]
          ]
        localSelections =
          [ declaration
          | declaration <- R.planSelections plan
          , let declarationScope = R.selectionDeclarationScope declaration
          , not (null (R.scopeMemberships declarationScope))
          , R.scopeCurrentNode declarationScope
              `elem` map Just ancestorDeclarations
          ]
        bindOne current declaration
          | Map.member identifier (contextBindings current) = pure current
          | otherwise = do
            matches <-
              selectedBlocks
                trace
                plan
                nodes
                current
                (R.selectionDeclarationScope declaration)
                identifier
            pure
              (case matches of
                 [(block, _)] ->
                   current
                     { contextBindings =
                         Map.insert identifier block (contextBindings current)
                     }
                 _ -> current)
          where
            identifier = R.selectionDeclarationId declaration

relationsForScope ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> ExpansionContext
  -> R.Scope
  -> R.RelationSelectionId
  -> Either RenderCompileError [Sem.TraceRelation]
relationsForScope trace plan context scope selection = do
  declaration <- requireRelationSelection plan selection
  let matching =
        [ relation'
        | relation' <- Sem.semanticTraceRelations trace
        , Sem.traceMarkerType (Sem.traceRelationKind relation')
            == R.relationSelectionDeclarationKindKey declaration
        ]
      correctDirection relation' =
        R.relationSelectionDeclarationOrdered declaration
          == (Sem.traceRelationDirection relation' == Sem.OrderedRelation)
  unless (all correctDirection matching)
    $ leftInvalid
        ("relation direction disagrees with Render selection "
           ++ R.relationSelectionDeclarationKindKey declaration)
  pure
    (induceMembershipRelations
       trace
       plan
       context
       scope
       (filter (relationVisibleAtAnyFrame trace plan) matching))

blockVisibleAtAnyFrame ::
     Sem.SemanticTrace -> R.RenderPlan -> Sem.TraceBlock -> Bool
blockVisibleAtAnyFrame trace plan block =
  any
    (\candidate ->
       intervalActive
         (Sem.stepOccurrenceEnd (frameOccurrence candidate))
         (blockInterval block))
    (frameCandidates trace plan)

relationVisibleAtAnyFrame ::
     Sem.SemanticTrace -> R.RenderPlan -> Sem.TraceRelation -> Bool
relationVisibleAtAnyFrame trace plan relation' =
  any
    (\candidate ->
       intervalActive
         (Sem.stepOccurrenceEnd (frameOccurrence candidate))
         (Sem.traceRelationStart relation', Sem.traceRelationEnd relation'))
    (frameCandidates trace plan)

induceMembershipRelations ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> ExpansionContext
  -> R.Scope
  -> [Sem.TraceRelation]
  -> [Sem.TraceRelation]
induceMembershipRelations trace plan context scope relations' =
  foldl' restrict relations' (R.scopeMemberships scope)
  where
    restrict current membership =
      case Map.lookup
             (R.membershipSelection membership)
             (contextBindings context) of
        Nothing -> current
        Just owner ->
          case find
                 ((== R.membershipRelation membership)
                    . R.relationSelectionDeclarationId)
                 (R.planRelationSelections plan) of
            Nothing -> current
            Just membershipDeclaration ->
              let members =
                    Set.fromList
                      [ Sem.traceRelationTarget relation'
                      | relation' <- Sem.semanticTraceRelations trace
                      , Sem.traceMarkerType (Sem.traceRelationKind relation')
                          == R.relationSelectionDeclarationKindKey
                               membershipDeclaration
                      , Sem.traceRelationSource relation' == owner
                      ]
               in filter
                    (\relation' ->
                       Sem.traceRelationSource relation' `Set.member` members
                         && Sem.traceRelationTarget relation'
                              `Set.member` members)
                    current

requireSelection ::
     R.RenderPlan
  -> R.SelectionId
  -> Either RenderCompileError R.SelectionDeclaration
requireSelection plan identifier =
  maybe
    (leftInvalid ("unknown selection " ++ showSelectionId identifier))
    Right
    (find ((== identifier) . R.selectionDeclarationId) (R.planSelections plan))

requireRelationSelection ::
     R.RenderPlan
  -> R.RelationSelectionId
  -> Either RenderCompileError R.RelationSelectionDeclaration
requireRelationSelection plan identifier =
  maybe
    (leftInvalid
       ("unknown relation selection " ++ showRelationSelectionId identifier))
    Right
    (find
       ((== identifier) . R.relationSelectionDeclarationId)
       (R.planRelationSelections plan))

requireContextRelation ::
     R.RelationSelectionId
  -> ExpansionContext
  -> Either RenderCompileError Sem.TraceRelation
requireContextRelation identifier context =
  maybe
    (leftInvalid
       ("relation endpoint has no active relation context for "
          ++ showRelationSelectionId identifier))
    Right
    (Map.lookup identifier (contextRelations context))

lookupExpandedNode :: Int -> [ExpandedNode] -> Maybe ExpandedNode
lookupExpandedNode identifier = find ((== identifier) . expandedNodeId)

lookupTraceBlock :: Sem.BlockId -> Sem.SemanticTrace -> Maybe Sem.TraceBlock
lookupTraceBlock identifier =
  find ((== identifier) . Sem.traceBlockId) . Sem.semanticTraceBlocks

showSelectionId :: R.SelectionId -> String
showSelectionId (R.SelectionId value) = show value

showRelationSelectionId :: R.RelationSelectionId -> String
showRelationSelectionId (R.RelationSelectionId value) = show value

showNodeDeclarationId :: R.NodeDeclarationId -> String
showNodeDeclarationId (R.NodeDeclarationId value) = show value

showRankingId :: R.RankingId -> String
showRankingId (R.RankingId value) = show value

showChoiceId :: R.ChoiceId -> String
showChoiceId (R.ChoiceId value) = show value

showPresenceId :: R.PresenceId -> String
showPresenceId (R.PresenceId value) = show value

--------------------------------------------------------------------------------
-- Structural validation and prepared ranks
--------------------------------------------------------------------------------
compileRankings ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> [ExpandedNode]
  -> Either RenderCompileError (Map R.RankingId (Map Sem.BlockId Int))
compileRankings trace plan expandedNodes' =
  Map.fromList <$> traverse compileOne (R.planRankings plan)
  where
    compileOne declaration = do
      selection <- requireSelection plan (R.rankingDeclarationNodes declaration)
      relationSelection <-
        requireRelationSelection
          plan
          (R.rankingDeclarationRelations declaration)
      unless (R.relationSelectionDeclarationOrdered relationSelection)
        $ leftInvalid
            ("structural view requires an ordered relation: "
               ++ R.relationSelectionDeclarationKindKey relationSelection)
      let offsets =
            nub
              [ Sem.stepOccurrenceEnd (frameOccurrence candidate)
              | candidate <- frameCandidates trace plan
              ]
      contexts <-
        contextsForScope
          trace
          plan
          expandedNodes'
          (R.rankingDeclarationScope declaration)
      frameRanks <-
        traverse
          (uncurry (rankAt selection relationSelection declaration))
          [(context, offset) | context <- contexts, offset <- offsets]
      ranks <- foldM mergeRanks Map.empty frameRanks
      pure (R.rankingDeclarationId declaration, ranks)
    rankAt selection relationSelection declaration context offset = do
      let allNodes =
            sortOn
              Sem.blockIdInt
              [ Sem.traceBlockId block
              | block <- Sem.semanticTraceBlocks trace
              , Sem.traceMarkerType (Sem.traceBlockKind block)
                  == R.selectionDeclarationKindKey selection
              , intervalActive offset (blockInterval block)
              ]
          nodes =
            applyMemberships
              trace
              plan
              context
              (R.rankingDeclarationScope declaration)
              allNodes
          nodeSet = Set.fromList nodes
          edges =
            nub
              [ ( Sem.traceRelationSource relation'
                , Sem.traceRelationTarget relation')
              | relation' <- Sem.semanticTraceRelations trace
              , Sem.traceMarkerType (Sem.traceRelationKind relation')
                  == R.relationSelectionDeclarationKindKey relationSelection
              , intervalActive
                  offset
                  ( Sem.traceRelationStart relation'
                  , Sem.traceRelationEnd relation')
              , Sem.traceRelationSource relation' `Set.member` nodeSet
              , Sem.traceRelationTarget relation' `Set.member` nodeSet
              ]
      case R.rankingDeclarationKind declaration of
        R.SequenceRanking -> sequenceRanks nodes edges
        R.TreeRanking     -> treeRanks nodes edges
        R.DagRanking      -> dagRanks nodes edges
    mergeRanks accumulated current =
      foldM mergeOne accumulated (Map.toList current)
    mergeOne accumulated (block, rank) =
      case Map.lookup block accumulated of
        Nothing -> pure (Map.insert block rank accumulated)
        Just previous
          | previous == rank -> pure accumulated
          | otherwise ->
            leftInvalid
              ("a structural rank changes during one visual block lifetime: block "
                 ++ show (Sem.blockIdInt block))

sequenceRanks ::
     [Sem.BlockId]
  -> [(Sem.BlockId, Sem.BlockId)]
  -> Either RenderCompileError (Map Sem.BlockId Int)
sequenceRanks [] edges
  | null edges = pure Map.empty
  | otherwise = leftInvalid "an empty sequence contains relations"
sequenceRanks nodes edges = do
  let indegree = degreeMap snd nodes edges
      outdegree = degreeMap fst nodes edges
      roots = [node | node <- nodes, Map.findWithDefault 0 node indegree == 0]
  unless (all (<= 1) (Map.elems indegree) && all (<= 1) (Map.elems outdegree))
    $ leftInvalid "asSequence requires a non-forking chain"
  unless (length roots == 1 && length edges == length nodes - 1)
    $ leftInvalid "asSequence requires one complete acyclic chain"
  root <- requireSingle "asSequence root" roots
  let adjacency = adjacencyMap edges
      ordered = walkChain adjacency root
  unless (length ordered == length nodes)
    $ leftInvalid "asSequence contains a cycle or disconnected node"
  pure (Map.fromList (zip ordered [0 :: Int ..]))

treeRanks ::
     [Sem.BlockId]
  -> [(Sem.BlockId, Sem.BlockId)]
  -> Either RenderCompileError (Map Sem.BlockId Int)
treeRanks [] _ = leftInvalid "asTree requires at least one node"
treeRanks nodes edges = do
  let indegree = degreeMap snd nodes edges
      roots = [node | node <- nodes, Map.findWithDefault 0 node indegree == 0]
  unless (length roots == 1) $ leftInvalid "asTree requires exactly one root"
  root <- requireSingle "asTree root" roots
  unless
    (all
       (\node ->
          let degree = Map.findWithDefault 0 node indegree
           in if node == root
                then degree == 0
                else degree == 1)
       nodes)
    $ leftInvalid "asTree requires exactly one parent for every non-root node"
  unless (length edges == length nodes - 1)
    $ leftInvalid "asTree contains the wrong number of edges"
  let ranked = breadthRanks (adjacencyMap edges) [(root, 0)] Map.empty
  unless (Map.size ranked == length nodes)
    $ leftInvalid "asTree does not reach every selected node"
  pure ranked

dagRanks ::
     [Sem.BlockId]
  -> [(Sem.BlockId, Sem.BlockId)]
  -> Either RenderCompileError (Map Sem.BlockId Int)
dagRanks nodes edges = do
  order <- topologicalOrder nodes edges
  let incoming =
        Map.fromListWith (++) [(target, [source]) | (source, target) <- edges]
      rankNode ranks node =
        let parents = Map.findWithDefault [] node incoming
            rank =
              case mapMaybe (`Map.lookup` ranks) parents of
                []     -> 0
                values -> 1 + maximum values
         in Map.insert node rank ranks
  pure (foldl' rankNode Map.empty order)

degreeMap ::
     Ord node
  => ((node, node) -> node)
  -> [node]
  -> [(node, node)]
  -> Map node Int
degreeMap project nodes edges =
  Map.unionWith
    (+)
    (Map.fromList [(node, 0) | node <- nodes])
    (Map.fromListWith (+) [(project edge, 1) | edge <- edges])

adjacencyMap :: Ord node => [(node, node)] -> Map node [node]
adjacencyMap =
  Map.fromListWith (flip (++)) . map (\(source, target) -> (source, [target]))

walkChain :: Ord node => Map node [node] -> node -> [node]
walkChain adjacency = go Set.empty
  where
    go seen node
      | node `Set.member` seen = []
      | otherwise =
        node
          : case Map.findWithDefault [] node adjacency of
              [next] -> go (Set.insert node seen) next
              _      -> []

breadthRanks ::
     Ord node
  => Map node [node]
  -> [(node, Int)]
  -> Map node Int
  -> Map node Int
breadthRanks _ [] ranks = ranks
breadthRanks adjacency ((node, level):rest) ranks
  | Map.member node ranks = breadthRanks adjacency rest ranks
  | otherwise =
    breadthRanks
      adjacency
      (rest
         ++ [ (child, level + 1)
            | child <- Map.findWithDefault [] node adjacency
            ])
      (Map.insert node level ranks)

topologicalOrder ::
     Ord node => [node] -> [(node, node)] -> Either RenderCompileError [node]
topologicalOrder nodes edges = go initialDegrees initialQueue []
  where
    initialDegrees = degreeMap snd nodes edges
    adjacency = adjacencyMap edges
    initialQueue =
      sortOn
        id
        [node | node <- nodes, Map.findWithDefault 0 node initialDegrees == 0]
    go _degrees [] ordered
      | length ordered == length nodes = pure ordered
      | otherwise = leftInvalid "asDag contains a directed cycle"
    go degrees (node:queue) ordered =
      let (degrees', ready) =
            foldl'
              (\(current, newlyReady) child ->
                 let nextDegree = Map.findWithDefault 0 child current - 1
                     updated = Map.insert child nextDegree current
                  in ( updated
                     , if nextDegree == 0
                         then child : newlyReady
                         else newlyReady))
              (degrees, [])
              (Map.findWithDefault [] node adjacency)
       in go degrees' (sortOn id (queue ++ ready)) (ordered ++ [node])

--------------------------------------------------------------------------------
-- Context-local visual references and connectors
--------------------------------------------------------------------------------
resolveReferenceCandidates ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> ExpandedPlan
  -> ExpansionContext
  -> R.NodeReference
  -> Either RenderCompileError [ConcreteNode]
resolveReferenceCandidates trace plan expanded context reference =
  case reference of
    R.CanvasReference -> pure [ConcreteCanvas]
    R.GeneratedReference declaration ->
      requireCandidates
        [ ConcreteVisual node
        | node <- nodes
        , expandedNodeDeclaration node == declaration
        , compatibleNode nodes context node
        ]
    R.SelectionReference selection ->
      let desired = Map.lookup selection (contextBindings context)
          exact =
            [ ConcreteVisual node
            | node <- nodes
            , expandedNodeTarget node == R.SelectedNodeTarget selection
            , maybe
                True
                (\block -> expandedNodeSemanticBlock node == Just block)
                desired
            , compatibleNode nodes context node
            ]
          matchingBlock =
            case desired of
              Nothing -> []
              Just block ->
                [ ConcreteVisual node
                | node <- nodes
                , expandedNodeSemanticBlock node == Just block
                , compatibleNode nodes context node
                ]
       in requireCandidates
            (if null exact
               then matchingBlock
               else exact)
    R.EndpointReference relationSelection isFirst -> do
      relation' <- requireContextRelation relationSelection context
      let desired =
            if isFirst
              then Sem.traceRelationSource relation'
              else Sem.traceRelationTarget relation'
          matching =
            [ node
            | node <- nodes
            , expandedNodeSemanticBlock node == Just desired
            ]
          local = filter (compatibleNode nodes context) matching
      candidates <-
        requireCandidates
          [ ConcreteVisual node
          | node <-
              if null local
                then matching
                else local
          ]
      validateEndpointCandidates trace plan expanded candidates
  where
    nodes = expandedNodes expanded
    requireCandidates [] =
      leftInvalid
        ("no context-local visual mapping for "
           ++ show reference
           ++ " in "
           ++ contextKey context)
    requireCandidates candidates =
      pure (bestCandidates nodes context candidates)

validateEndpointCandidates ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> ExpandedPlan
  -> [ConcreteNode]
  -> Either RenderCompileError [ConcreteNode]
validateEndpointCandidates trace plan expanded candidates = do
  guarded <- traverse resolveCandidate candidates
  case find (uncurry simultaneouslyActive) (candidatePairs guarded) of
    Nothing -> pure candidates
    Just ((firstNode, _), (secondNode, _)) ->
      leftInvalid
        ("relation endpoint has simultaneously active visual mappings "
           ++ show (concreteNodeId firstNode)
           ++ " and "
           ++ show (concreteNodeId secondNode))
  where
    resolveCandidate concrete = do
      let context = contextForConcrete concrete
      resolved <-
        traverse
          (resolveGuard trace plan expanded context)
          (concreteNodeGuards concrete)
      decisions <-
        consolidateGuards [guard | guard@GuardDecision {} <- resolved]
      pure
        ( concrete
        , if GuardNever `elem` resolved
            then [GuardNever]
            else decisions)
    simultaneouslyActive (_, firstGuards) (_, secondGuards)
      | GuardNever `elem` firstGuards || GuardNever `elem` secondGuards = False
      | otherwise =
        all
          (\(name, required) ->
             maybe True (== required) (Map.lookup name secondRequirements))
          firstRequirements
      where
        firstRequirements = guardRequirements firstGuards
        secondRequirements = Map.fromList (guardRequirements secondGuards)
    guardRequirements guards =
      [(name, required) | GuardDecision name _ required <- guards]
    candidatePairs values =
      [ (firstCandidate, secondCandidate)
      | (index, firstCandidate) <- zip [0 :: Int ..] values
      , secondCandidate <- drop (index + 1) values
      ]

compatibleNode :: [ExpandedNode] -> ExpansionContext -> ExpandedNode -> Bool
compatibleNode nodes context candidate =
  let ancestors = contextAncestors nodes context
   in expandedNodeId candidate `elem` ancestors
        || expandedNodeParent candidate `elem` ancestors
        || (null ancestors && expandedNodeParent candidate == -1)
        || (isNothing (contextCurrentNode context)
              && expandedNodeParent candidate == -1)

bestCandidates ::
     [ExpandedNode] -> ExpansionContext -> [ConcreteNode] -> [ConcreteNode]
bestCandidates _ _ candidates
  | any isCanvasNode candidates = [ConcreteCanvas]
bestCandidates nodes context candidates =
  let scored =
        [ (candidateScore nodes context node, ConcreteVisual node)
        | ConcreteVisual node <- candidates
        ]
      best = maximum (map fst scored)
   in [candidate | (score, candidate) <- scored, score == best]

isCanvasNode :: ConcreteNode -> Bool
isCanvasNode ConcreteCanvas = True
isCanvasNode _              = False

candidateScore :: [ExpandedNode] -> ExpansionContext -> ExpandedNode -> Int
candidateScore nodes context candidate =
  case contextCurrentNode context of
    Nothing ->
      if expandedNodeParent candidate == -1
        then 10
        else 0
    Just current
      | expandedNodeId candidate == current -> 10000
      | expandedNodeParent candidate == current -> 9000
      | otherwise ->
        let ancestors = contextAncestors nodes context
         in case findIndexValue (expandedNodeId candidate) ancestors of
              Just index -> 8000 - index
              Nothing ->
                case findIndexValue (expandedNodeParent candidate) ancestors of
                  Just index -> 7000 - index
                  Nothing    -> 0

findIndexValue :: Eq value => value -> [value] -> Maybe Int
findIndexValue needle = go 0
  where
    go _ [] = Nothing
    go index (value:rest)
      | value == needle = Just index
      | otherwise = go (index + 1) rest

contextAncestors :: [ExpandedNode] -> ExpansionContext -> [Int]
contextAncestors nodes context =
  case contextCurrentNode context of
    Nothing         -> [-1]
    Just identifier -> identifier : parentChain identifier
  where
    parentChain identifier =
      case lookupExpandedNode identifier nodes of
        Nothing -> [-1]
        Just node
          | expandedNodeParent node == -1 -> [-1]
          | otherwise ->
            expandedNodeParent node : parentChain (expandedNodeParent node)

expandConnectors ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> [ExpandedNode]
  -> Either RenderCompileError [ExpandedConnector]
expandConnectors trace plan nodes =
  snd <$> foldM expand (0, []) (R.planConnectors plan)
  where
    partialExpanded = ExpandedPlan nodes [] Map.empty
    expand (nextIdentifier, accumulated) declaration = do
      contexts <-
        contextsForScope
          trace
          plan
          nodes
          (R.connectorDeclarationScope declaration)
      concrete <- fmap concat (traverse (instantiate declaration) contexts)
      let identified =
            [ connector' {expandedConnectorId = nextIdentifier + offset}
            | (offset, connector') <- zip [0 :: Int ..] concrete
            ]
      pure (nextIdentifier + length identified, accumulated ++ identified)
    instantiate declaration context = do
      let R.ConnectorAnchor _ startReference =
            R.connectorDeclarationStart declaration
          R.ConnectorAnchor _ endReference =
            R.connectorDeclarationEnd declaration
      starts <-
        resolveReferenceCandidates
          trace
          plan
          partialExpanded
          context
          startReference
      ends <-
        resolveReferenceCandidates
          trace
          plan
          partialExpanded
          context
          endReference
      let relation' =
            R.scopeRelation (R.connectorDeclarationScope declaration)
              >>= (`Map.lookup` contextRelations context)
      pure
        [ ExpandedConnector
          { expandedConnectorId = -1
          , expandedConnectorDeclaration = declaration
          , expandedConnectorContext = context
          , expandedConnectorStart = start
          , expandedConnectorEnd = end
          , expandedConnectorRelation = relation'
          , expandedConnectorGuards =
              nub
                (R.scopeGuards (R.connectorDeclarationScope declaration)
                   ++ concreteNodeGuards start
                   ++ concreteNodeGuards end)
          }
        | start <- starts
        , end <- ends
        ]

concreteNodeGuards :: ConcreteNode -> [R.PresenceGuard]
concreteNodeGuards ConcreteCanvas        = []
concreteNodeGuards (ConcreteVisual node) = expandedNodeGuards node

concreteNodeId :: ConcreteNode -> Int
concreteNodeId ConcreteCanvas        = -1
concreteNodeId (ConcreteVisual node) = expandedNodeId node

contextForConcrete :: ConcreteNode -> ExpansionContext
contextForConcrete ConcreteCanvas        = rootContext
contextForConcrete (ConcreteVisual node) = expandedNodeContext node

--------------------------------------------------------------------------------
-- Affine lowering
--------------------------------------------------------------------------------
data RenderNumber

instance S.SymbolicType RenderNumber where
  symbolicDomain _ = S.realDomain "sverlin-render"

type SolverExpr = S.Expr RenderNumber

type NodeEnvironment = Map R.NodeReference ConcreteNode

automaticStyleFamily :: ConcreteNode -> Maybe String
automaticStyleFamily concrete =
  case concrete of
    ConcreteCanvas -> Nothing
    ConcreteVisual node ->
      Just ("node-" ++ showNodeDeclarationId (expandedNodeDeclaration node))

automaticStyleEligible :: ExpandedPlan -> ConcreteNode -> Bool
automaticStyleEligible expanded concrete =
  case concrete of
    ConcreteCanvas -> False
    ConcreteVisual node ->
      not
        (any
           ((== expandedNodeId node) . expandedNodeParent)
           (expandedNodes expanded))

automaticStyleFamilies :: ExpandedPlan -> [String]
automaticStyleFamilies expanded =
  nub
    [ family
    | node <- expandedNodes expanded
    , let concrete = ConcreteVisual node
    , automaticStyleEligible expanded concrete
    , Just family <- [automaticStyleFamily concrete]
    ]

automaticStyleVariable :: String -> String -> SolverExpr
automaticStyleVariable family field =
  S.var (automaticStyleVariableName family field)

automaticStyleVariableName :: String -> String -> String
automaticStyleVariableName family field =
  "render.theme." ++ family ++ "." ++ field

automaticStyleConstraints :: ExpandedPlan -> [S.Constraint]
automaticStyleConstraints expanded =
  concatMap familyConstraints (automaticStyleFamilies expanded)
  where
    familyConstraints family =
      [ S.within (automaticStyleVariable family "fill.hue") (S.Range 0 360)
      , S.within
          (automaticStyleVariable family "fill.saturation")
          (S.Range 0.25 0.65)
      , S.within
          (automaticStyleVariable family "fill.lightness")
          (S.Range 0.84 0.96)
      , S.within
          (automaticStyleVariable family "stroke.saturation")
          (S.Range 0.35 0.75)
      , S.within
          (automaticStyleVariable family "stroke.lightness")
          (S.Range 0.25 0.5)
      , S.within
          (automaticStyleVariable family "soft-card.radius")
          (S.Range 6 16)
      ]

data ResolvedGuard
  = GuardDecision String [String] String
  | GuardAlways
  | GuardNever
  deriving (Eq, Show)

lowerPlan ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> ExpandedPlan
  -> [PreparedText]
  -> Either RenderCompileError [S.Constraint]
lowerPlan trace plan expanded typography = do
  decisionConstraints <- lowerDecisionDeclarations trace plan expanded
  variableConstraints <- lowerVariableBounds plan
  inactiveNodeConstraints <- fmap concat (traverse lowerInactiveNode nodes)
  geometryConstraints <-
    fmap concat (traverse lowerGeometry (R.planGeometry plan))
  authoredConstraints <-
    fmap
      concat
      (traverse
         (uncurry lowerConstraint)
         (zip [0 :: Int ..] (R.planConstraints plan)))
  arrangementConstraints <-
    fmap concat (traverse lowerArrangement (R.planArrangements plan))
  containmentConstraints <- lowerContainment trace plan expanded
  textConstraints <- lowerTextFits trace plan expanded typography
  styleConstraints <- fmap concat (traverse lowerStyle (R.planStyles plan))
  pure
    (canvasConstraints
       ++ nodeBounds
       ++ automaticStyleConstraints expanded
       ++ variableConstraints
       ++ decisionConstraints
       ++ inactiveNodeConstraints
       ++ geometryConstraints
       ++ authoredConstraints
       ++ arrangementConstraints
       ++ containmentConstraints
       ++ textConstraints
       ++ styleConstraints)
  where
    nodes = expandedNodes expanded
    canvasConstraints =
      [ nodeAttribute ConcreteCanvas R.GeometryLeft S.@==@ S.num 0
      , nodeAttribute ConcreteCanvas R.GeometryTop S.@==@ S.num 0
      , nodeAttribute ConcreteCanvas R.GeometryWidth S.@>=@ S.num 0
      , nodeAttribute ConcreteCanvas R.GeometryHeight S.@>=@ S.num 0
      ]
    nodeBounds =
      concat
        [ let concrete = ConcreteVisual node
              guards = expandedNodeGuards node
              context = expandedNodeContext node
         in guardOne
              context
              guards
              [ nodeAttribute concrete R.GeometryX S.@>=@ S.num 0
              , nodeAttribute concrete R.GeometryY S.@>=@ S.num 0
              , nodeAttribute concrete R.GeometryWidth S.@>=@ S.num 0
              , nodeAttribute concrete R.GeometryHeight S.@>=@ S.num 0
              ]
        | node <- nodes
        ]
    guardOne context guards =
      concatMap
        (fromRight [] . guardConstraint trace plan expanded context guards)
    -- Optional nodes still have solver variables in the shared affine model.
    -- Pin those variables in every branch where the node is absent so omission
    -- cannot turn an otherwise finite design into an unbounded region.
    lowerInactiveNode node = do
      let concrete = ConcreteVisual node
          pins =
            [ nodeAttribute concrete R.GeometryX S.@==@ S.num 0
            , nodeAttribute concrete R.GeometryY S.@==@ S.num 0
            , nodeAttribute concrete R.GeometryWidth S.@==@ S.num 0
            , nodeAttribute concrete R.GeometryHeight S.@==@ S.num 0
            ]
      resolved <-
        traverse
          (resolveGuard trace plan expanded (expandedNodeContext node))
          (nub (expandedNodeGuards node))
      if GuardNever `elem` resolved
        then pure pins
        else do
          decisions <-
            consolidateGuards [guard | guard@GuardDecision {} <- resolved]
          if GuardNever `elem` decisions
            then pure pins
            else pure (map (pinWhenInactive pins) decisions)
    pinWhenInactive pins (GuardDecision name tokens required) =
      case tokens of
        [] -> impossibleConstraint
        firstToken:remaining ->
          S.oneOf
            name
            (inactiveAlternative firstToken)
            [inactiveAlternative token | token <- remaining]
      where
        inactiveAlternative token =
          S.alternative
            token
            (if token == required
               then []
               else pins)
    pinWhenInactive _ GuardAlways = tautologyConstraint
    pinWhenInactive _ GuardNever = tautologyConstraint
    lowerGeometry declaration = do
      contexts <-
        contextsForScope
          trace
          plan
          nodes
          (R.geometryAssignmentScope declaration)
      concat <$> traverse (lowerInContext declaration) contexts
    lowerInContext declaration context = do
      let targetReference = R.geometryAssignmentTarget declaration
          expression = R.geometryAssignmentValue declaration
          references = nub (targetReference : numericReferences expression)
      environments <-
        referenceEnvironments trace plan expanded context references
      concat <$> traverse (emitGeometry declaration context) environments
    emitGeometry declaration context environment = do
      target <-
        requireEnvironmentNode
          environment
          (R.geometryAssignmentTarget declaration)
      value <-
        lowerNumeric
          trace
          plan
          expanded
          context
          environment
          (R.geometryAssignmentValue declaration)
      let constraint =
            nodeAttribute target (R.geometryAssignmentAttribute declaration)
              S.@==@ value
          guards =
            nub
              (R.scopeGuards (R.geometryAssignmentScope declaration)
                 ++ environmentGuards environment)
      guardConstraint trace plan expanded context guards constraint
    lowerConstraint index declaration = do
      contexts <-
        contextsForScope
          trace
          plan
          nodes
          (R.constraintDeclarationScope declaration)
      concat <$> traverse (lowerConstraintContext index declaration) contexts
    lowerConstraintContext index declaration context =
      case R.constraintDeclarationValue declaration of
        R.NumericConstraint comparison left right -> do
          let references =
                nub (numericReferences left ++ numericReferences right)
          environments <-
            referenceEnvironments trace plan expanded context references
          concat
            <$> traverse
                  (emitNumeric comparison left right context declaration)
                  environments
        R.VectorConstraint comparison left right -> do
          let references = nub (concatMap numericReferences (left ++ right))
          environments <-
            referenceEnvironments trace plan expanded context references
          concat
            <$> traverse
                  (emitVector comparison left right context declaration)
                  environments
        R.SeparationConstraint gap firstReference secondReference -> do
          let references =
                nub (firstReference : secondReference : numericReferences gap)
          environments <-
            referenceEnvironments trace plan expanded context references
          concat
            <$> traverse
                  (emitSeparation
                     index
                     gap
                     firstReference
                     secondReference
                     context
                     declaration)
                  environments
    emitNumeric comparison left right context declaration environment = do
      lhs <- lowerNumeric trace plan expanded context environment left
      rhs <- lowerNumeric trace plan expanded context environment right
      let constraint = compareConstraint comparison lhs rhs
          guards =
            nub
              (R.scopeGuards (R.constraintDeclarationScope declaration)
                 ++ environmentGuards environment)
      guardConstraint trace plan expanded context guards constraint
    emitVector comparison left right context declaration environment = do
      unless (length left == length right)
        $ leftInvalid "vector constraint arity mismatch"
      lhs <-
        traverse (lowerNumeric trace plan expanded context environment) left
      rhs <-
        traverse (lowerNumeric trace plan expanded context environment) right
      let constraints = zipWith (compareConstraint comparison) lhs rhs
          guards =
            nub
              (R.scopeGuards (R.constraintDeclarationScope declaration)
                 ++ environmentGuards environment)
      concat
        <$> traverse
              (guardConstraint trace plan expanded context guards)
              constraints
    emitSeparation index gap firstReference secondReference context declaration environment = do
      firstNode <- requireEnvironmentNode environment firstReference
      secondNode <- requireEnvironmentNode environment secondReference
      gapExpr <- lowerNumeric trace plan expanded context environment gap
      let firstRight = nodeAttribute firstNode R.GeometryRight
          firstBottom = nodeAttribute firstNode R.GeometryBottom
          secondRight = nodeAttribute secondNode R.GeometryRight
          secondBottom = nodeAttribute secondNode R.GeometryBottom
          firstLeft = nodeAttribute firstNode R.GeometryLeft
          firstTop = nodeAttribute firstNode R.GeometryTop
          secondLeft = nodeAttribute secondNode R.GeometryLeft
          secondTop = nodeAttribute secondNode R.GeometryTop
          before = firstRight S.@+@ gapExpr S.@<=@ secondLeft
          after = secondRight S.@+@ gapExpr S.@<=@ firstLeft
          above = firstBottom S.@+@ gapExpr S.@<=@ secondTop
          below = secondBottom S.@+@ gapExpr S.@<=@ firstTop
          notBefore = secondLeft S.@<=@ firstRight S.@+@ gapExpr
          notAfter = firstLeft S.@<=@ secondRight S.@+@ gapExpr
          notAbove = secondTop S.@<=@ firstBottom S.@+@ gapExpr
          partition =
            S.algebraicOneOf
              ("render.separation."
                 ++ show index
                 ++ "."
                 ++ contextKey context
                 ++ "."
                 ++ show (concreteNodeId firstNode)
                 ++ "."
                 ++ show (concreteNodeId secondNode))
              (S.alternative "before" [before])
              [ S.alternative "after" [notBefore, after]
              , S.alternative "above" [notBefore, notAfter, above]
              , S.alternative "below" [notBefore, notAfter, notAbove, below]
              ]
          guards =
            nub
              (R.scopeGuards (R.constraintDeclarationScope declaration)
                 ++ environmentGuards environment)
      guardConstraint trace plan expanded context guards partition
    lowerArrangement declaration = do
      contexts <-
        contextsForScope
          trace
          plan
          nodes
          (R.arrangementDeclarationScope declaration)
      concat <$> traverse (arrangeContext declaration) contexts
    arrangeContext declaration context = do
      mapped <-
        resolveReferenceCandidates
          trace
          plan
          expanded
          context
          (R.SelectionReference (R.arrangementDeclarationNodes declaration))
      let concrete = sortOn concreteSortKey mapped
          environment = Map.empty
      gapX <-
        lowerNumeric
          trace
          plan
          expanded
          context
          environment
          (R.arrangementDeclarationGapX declaration)
      gapY <-
        lowerNumeric
          trace
          plan
          expanded
          context
          environment
          (R.arrangementDeclarationGapY declaration)
      raw <-
        case R.arrangementDeclarationKind declaration of
          R.GridArrangement columns ->
            pure (gridConstraints columns gapX gapY concrete)
          R.LayeredArrangement ->
            layeredConstraints
              R.DagRanking
              declaration
              context
              gapX
              gapY
              concrete
          R.TreeArrangement ->
            layeredConstraints
              R.TreeRanking
              declaration
              context
              gapX
              gapY
              concrete
          R.RadialArrangement ->
            pure (radialConstraints context gapX gapY concrete)
      let guards =
            nub
              (R.scopeGuards (R.arrangementDeclarationScope declaration)
                 ++ concatMap concreteNodeGuards concrete)
      concat
        <$> traverse (guardConstraint trace plan expanded context guards) raw
    layeredConstraints rankingKind declaration _context gapX gapY concrete = do
      relationSelection <-
        maybe
          (leftInvalid "layered arrangement requires relations")
          Right
          (R.arrangementDeclarationRelations declaration)
      relationDeclaration <- requireRelationSelection plan relationSelection
      unless (R.relationSelectionDeclarationOrdered relationDeclaration)
        $ leftInvalid
            "layered and tree arrangements require an ordered relation"
      let blockMap =
            Map.fromList
              [ (block, node)
              | node@(ConcreteVisual expandedNode) <- concrete
              , Just block <- [expandedNodeSemanticBlock expandedNode]
              ]
          blockEdges =
            [ (sourceBlock, targetBlock)
            | relation' <- Sem.semanticTraceRelations trace
            , Sem.traceMarkerType (Sem.traceRelationKind relation')
                == R.relationSelectionDeclarationKindKey relationDeclaration
            , let sourceBlock = Sem.traceRelationSource relation'
            , let targetBlock = Sem.traceRelationTarget relation'
            , Map.member sourceBlock blockMap
            , Map.member targetBlock blockMap
            ]
          edges =
            [ (blockMap Map.! source, blockMap Map.! target)
            | (source, target) <- blockEdges
            ]
          vertical =
            [ nodeAttribute target R.GeometryTop
              S.@>=@ nodeAttribute source R.GeometryBottom
              S.@+@ gapY
            | (source, target) <- edges
            ]
          blocks = sortOn Sem.blockIdInt (Map.keys blockMap)
      ranks <-
        case rankingKind of
          R.TreeRanking -> treeRanks blocks blockEdges
          R.DagRanking -> dagRanks blocks blockEdges
          R.SequenceRanking ->
            leftInvalid "a sequence ranking cannot lower a layered arrangement"
      let groups =
            Map.elems
              (Map.fromListWith
                 (++)
                 [ (Map.findWithDefault 0 block ranks, [node])
                 | (block, node) <- Map.toAscList blockMap
                 ])
          horizontal = concatMap (rowConstraints gapX) groups
      pure (vertical ++ horizontal)
    concreteSortKey ConcreteCanvas = (-1, -1)
    concreteSortKey (ConcreteVisual node) =
      ( maybe (-1) Sem.blockIdInt (expandedNodeSemanticBlock node)
      , expandedNodeId node)
    radialConstraints context gapX gapY concrete =
      let parent =
            maybe
              ConcreteCanvas
              (maybe ConcreteCanvas ConcreteVisual
                 . (`lookupExpandedNode` nodes))
              (contextCurrentNode context)
          count = max 1 (length concrete)
       in concat
            [ let angle = 2 * pi * fromIntegral index / fromIntegral count
                  radialX = gapX S.@*@ S.num (fromIntegral count / (2 * pi) + 1)
                  radialY = gapY S.@*@ S.num (fromIntegral count / (2 * pi) + 1)
             in [ nodeAttribute node R.GeometryX
                    S.@==@ nodeAttribute parent R.GeometryX
                    S.@+@ radialX
                    S.@*@ S.num (cos angle)
                , nodeAttribute node R.GeometryY
                    S.@==@ nodeAttribute parent R.GeometryY
                    S.@+@ radialY
                    S.@*@ S.num (sin angle)
                ]
            | (index, node) <- zip [0 :: Int ..] concrete
            ]
    lowerStyle declaration =
      case R.styleDeclarationValue declaration of
        R.NumericStyle expression -> lowerNumericStyle declaration [expression]
        R.ColorStyle hue saturation lightness ->
          lowerNumericStyle declaration [hue, saturation, lightness]
        _ -> pure []
    lowerNumericStyle declaration expressions = do
      contexts <-
        contextsForScope trace plan nodes (R.styleDeclarationScope declaration)
      concat <$> traverse (styleContext declaration expressions) contexts
    styleContext declaration expressions context = do
      let references =
            nub
              (builderTargetReferences (R.styleDeclarationTarget declaration)
                 ++ concatMap numericReferences expressions)
      environments <-
        referenceEnvironments trace plan expanded context references
      concat
        <$> traverse
              (styleEnvironment declaration expressions context)
              environments
    styleEnvironment declaration expressions context environment = do
      lowered <-
        traverse
          (lowerNumeric trace plan expanded context environment)
          expressions
      let constraints =
            styleRangeConstraints (R.styleDeclarationField declaration) lowered
          guards =
            nub
              (R.scopeGuards (R.styleDeclarationScope declaration)
                 ++ environmentGuards environment)
      concat
        <$> traverse
              (guardConstraint trace plan expanded context guards)
              constraints

compareConstraint :: R.Comparison -> SolverExpr -> SolverExpr -> S.Constraint
compareConstraint comparison =
  case comparison of
    R.LessOrEqual    -> (S.@<=@)
    R.GreaterOrEqual -> (S.@>=@)
    R.EqualTo        -> (S.@==@)

impossibleConstraint :: S.Constraint
impossibleConstraint = (S.num 0 :: SolverExpr) S.@==@ S.num 1

tautologyConstraint :: S.Constraint
tautologyConstraint = (S.num 0 :: SolverExpr) S.@==@ S.num 0

nodeAttribute :: ConcreteNode -> R.GeometryAttribute -> SolverExpr
nodeAttribute concrete attribute =
  let xValue = S.var (nodeVariableName concrete "x")
      yValue = S.var (nodeVariableName concrete "y")
      widthValue = S.var (nodeVariableName concrete "width")
      heightValue = S.var (nodeVariableName concrete "height")
      half value = value S.@/@ S.num 2
   in case attribute of
        R.GeometryLeft   -> xValue S.@-@ half widthValue
        R.GeometryTop    -> yValue S.@-@ half heightValue
        R.GeometryRight  -> xValue S.@+@ half widthValue
        R.GeometryBottom -> yValue S.@+@ half heightValue
        R.GeometryWidth  -> widthValue
        R.GeometryHeight -> heightValue
        R.GeometryX      -> xValue
        R.GeometryY      -> yValue

nodeVariableName :: ConcreteNode -> String -> String
nodeVariableName ConcreteCanvas field = "render.canvas." ++ field
nodeVariableName (ConcreteVisual node) field =
  "render.node." ++ show (expandedNodeId node) ++ "." ++ field

numericVariableName :: Int -> String
numericVariableName identifier = "render.variable." ++ show identifier

lowerNumeric ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> ExpandedPlan
  -> ExpansionContext
  -> NodeEnvironment
  -> R.NumericExpr
  -> Either RenderCompileError SolverExpr
lowerNumeric trace plan expanded context environment expression =
  case expression of
    R.NumericConstant value -> pure (S.num value)
    R.NumericVariable identifier _ ->
      pure (S.var (numericVariableName identifier))
    R.NumericNode reference attribute ->
      nodeAttribute
        <$> requireEnvironmentNode environment reference
        <*> pure attribute
    R.NumericRank ranking _declaration -> do
      node <- requireCurrentVisual expanded context "rankOf"
      block <-
        maybe
          (leftInvalid "rankOf requires a selected semantic node")
          Right
          (expandedNodeSemanticBlock node)
      ranks <-
        maybe
          (leftInvalid ("unknown ranking " ++ showRankingId ranking))
          Right
          (Map.lookup ranking (expandedRanks expanded))
      value <-
        maybe
          (leftInvalid "the current node is outside the structural ranking")
          Right
          (Map.lookup block ranks)
      pure (S.num (fromIntegral value))
    R.NumericPayload reference -> do
      concrete <- requireEnvironmentNode environment reference
      case concrete of
        ConcreteCanvas -> leftInvalid "the canvas has no semantic payload"
        ConcreteVisual node -> do
          blockId <-
            maybe
              (leftInvalid "payloadScalar requires a semantic node")
              Right
              (expandedNodeSemanticBlock node)
          block <-
            maybe
              (leftInvalid "payloadScalar refers to an unknown block")
              Right
              (lookupTraceBlock blockId trace)
          value <-
            maybe
              (leftInvalid "payloadScalar requires an LInt or LDouble payload")
              Right
              (Sem.traceBlockPayloadScalar block)
          pure (S.num value)
    R.NumericStyleValue reference field -> do
      concrete <- requireEnvironmentNode environment reference
      styleNumericExpression trace plan expanded context concrete field
    R.NumericParent reference attribute ratio -> do
      concrete <- requireEnvironmentNode environment reference
      parent <- parentConcrete expanded concrete
      pure
        $ case attribute of
            R.GeometryX ->
              nodeAttribute parent R.GeometryLeft
                S.@+@ nodeAttribute parent R.GeometryWidth
                S.@*@ S.num ratio
            R.GeometryY ->
              nodeAttribute parent R.GeometryTop
                S.@+@ nodeAttribute parent R.GeometryHeight
                S.@*@ S.num ratio
            R.GeometryWidth ->
              nodeAttribute parent R.GeometryWidth S.@*@ S.num ratio
            R.GeometryHeight ->
              nodeAttribute parent R.GeometryHeight S.@*@ S.num ratio
            _ -> nodeAttribute parent attribute S.@*@ S.num ratio
    R.NumericAdd left right -> binary (S.@+@) left right
    R.NumericSubtract left right -> binary (S.@-@) left right
    R.NumericMultiply left right -> binary (S.@*@) left right
    R.NumericDivide left right -> binary (S.@/@) left right
  where
    binary operator left right =
      operator
        <$> lowerNumeric trace plan expanded context environment left
        <*> lowerNumeric trace plan expanded context environment right

requireCurrentVisual ::
     ExpandedPlan
  -> ExpansionContext
  -> String
  -> Either RenderCompileError ExpandedNode
requireCurrentVisual expanded context operation =
  case contextCurrentNode context
         >>= (`lookupExpandedNode` expandedNodes expanded) of
    Nothing   -> leftInvalid (operation ++ " requires a current visual node")
    Just node -> pure node

parentConcrete ::
     ExpandedPlan -> ConcreteNode -> Either RenderCompileError ConcreteNode
parentConcrete _ ConcreteCanvas = leftInvalid "the canvas has no parent"
parentConcrete expanded (ConcreteVisual node)
  | expandedNodeParent node == -1 = pure ConcreteCanvas
  | otherwise =
    maybe
      (leftInvalid "visual parent mapping is missing")
      (pure . ConcreteVisual)
      (lookupExpandedNode (expandedNodeParent node) (expandedNodes expanded))

numericReferences :: R.NumericExpr -> [R.NodeReference]
numericReferences expression =
  case expression of
    R.NumericConstant _             -> []
    R.NumericVariable _ _           -> []
    R.NumericNode reference _       -> [reference]
    R.NumericRank _ _               -> []
    R.NumericPayload reference      -> [reference]
    R.NumericStyleValue reference _ -> [reference]
    R.NumericParent reference _ _   -> [reference]
    R.NumericAdd left right         -> nested left right
    R.NumericSubtract left right    -> nested left right
    R.NumericMultiply left right    -> nested left right
    R.NumericDivide left right      -> nested left right
  where
    nested left right = numericReferences left ++ numericReferences right

referenceEnvironments ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> ExpandedPlan
  -> ExpansionContext
  -> [R.NodeReference]
  -> Either RenderCompileError [NodeEnvironment]
referenceEnvironments trace plan expanded context = foldM add [Map.empty]
  where
    add environments reference = do
      candidates <-
        resolveReferenceCandidates trace plan expanded context reference
      pure
        [ Map.insert reference candidate environment
        | environment <- environments
        , candidate <- candidates
        ]

requireEnvironmentNode ::
     NodeEnvironment
  -> R.NodeReference
  -> Either RenderCompileError ConcreteNode
requireEnvironmentNode environment reference =
  maybe
    (leftInvalid ("numeric expression did not resolve " ++ show reference))
    Right
    (Map.lookup reference environment)

environmentGuards :: NodeEnvironment -> [R.PresenceGuard]
environmentGuards = nub . concatMap concreteNodeGuards . Map.elems

builderTargetReferences :: R.BuilderTarget -> [R.NodeReference]
builderTargetReferences target =
  case target of
    R.NodeBuilderTarget reference -> [reference]
    R.ConnectorBuilderTarget _    -> []

gridConstraints ::
     Int -> SolverExpr -> SolverExpr -> [ConcreteNode] -> [S.Constraint]
gridConstraints columns gapX gapY nodes =
  concat
    [ horizontal index node ++ vertical index node
    | (index, node) <- zip [0 :: Int ..] nodes
    ]
  where
    horizontal index node
      | index `mod` columns == 0 = []
      | otherwise =
        let previous = nodes !! (index - 1)
         in [ nodeAttribute node R.GeometryLeft
                S.@==@ nodeAttribute previous R.GeometryRight
                S.@+@ gapX
            , nodeAttribute node R.GeometryY
                S.@==@ nodeAttribute previous R.GeometryY
            ]
    vertical index node
      | index < columns = []
      | otherwise =
        let above = nodes !! (index - columns)
         in [ nodeAttribute node R.GeometryTop
                S.@==@ nodeAttribute above R.GeometryBottom
                S.@+@ gapY
            , nodeAttribute node R.GeometryX
                S.@==@ nodeAttribute above R.GeometryX
            ]

rowConstraints :: SolverExpr -> [ConcreteNode] -> [S.Constraint]
rowConstraints gap nodes =
  concat
    [ [ nodeAttribute current R.GeometryLeft
          S.@>=@ nodeAttribute previous R.GeometryRight
          S.@+@ gap
      , nodeAttribute current R.GeometryY
          S.@==@ nodeAttribute previous R.GeometryY
      ]
    | (previous, current) <- zip nodes (drop 1 nodes)
    ]

styleRangeConstraints :: R.StyleFieldName -> [SolverExpr] -> [S.Constraint]
styleRangeConstraints field values =
  case (field, values) of
    (R.OpacityField, [value]) -> unit value
    (R.AlphaField, [value]) -> unit value
    (R.FillHueField, [hue, saturation, lightness]) ->
      angle hue ++ unit saturation ++ unit lightness
    (R.StrokeHueField, [hue, saturation, lightness]) ->
      angle hue ++ unit saturation ++ unit lightness
    (R.FontSizeField, [value]) -> nonnegative value
    (R.RadiusField, [value]) -> nonnegative value
    (R.StrokeWidthField, [value]) -> nonnegative value
    _ -> []
  where
    nonnegative value = [value S.@>=@ S.num 0]
    unit value = [S.within value (S.Range 0 1)]
    angle value = [S.within value (S.Range 0 360)]

lowerVariableBounds :: R.RenderPlan -> Either RenderCompileError [S.Constraint]
lowerVariableBounds plan = do
  variables <-
    foldM
      addVariable
      Map.empty
      (concatMap numericVariables (planNumericExpressions plan))
  pure (concatMap roleConstraints (Map.toAscList variables))
  where
    addVariable roles (identifier, role) =
      case Map.lookup identifier roles of
        Nothing -> pure (Map.insert identifier role roles)
        Just existing
          | existing == role -> pure roles
          | otherwise ->
            leftInvalid
              ("render variable "
                 ++ show identifier
                 ++ " has conflicting numeric roles: "
                 ++ show existing
                 ++ " and "
                 ++ show role)
    roleConstraints (identifier, role) =
      let value = S.var (numericVariableName identifier) :: SolverExpr
       in case role of
            R.CoordNumeric  -> [value S.@>=@ S.num 0]
            R.SpanNumeric   -> [value S.@>=@ S.num 0]
            R.OffsetNumeric -> []
            R.ScalarNumeric -> []
            R.UnitNumeric   -> [S.within value (S.Range 0 1)]
            R.AngleNumeric  -> [S.within value (S.Range 0 360)]

numericVariables :: R.NumericExpr -> [(Int, R.NumericRole)]
numericVariables expression =
  case expression of
    R.NumericVariable identifier role -> [(identifier, role)]
    R.NumericAdd left right           -> nested left right
    R.NumericSubtract left right      -> nested left right
    R.NumericMultiply left right      -> nested left right
    R.NumericDivide left right        -> nested left right
    _                                 -> []
  where
    nested left right = numericVariables left ++ numericVariables right

planNumericExpressions :: R.RenderPlan -> [R.NumericExpr]
planNumericExpressions plan =
  map R.geometryAssignmentValue (R.planGeometry plan)
    ++ concatMap constraintExpressions (R.planConstraints plan)
    ++ concatMap insetsExpressions (R.planInsets plan)
    ++ concatMap
         (\arrangement ->
            [ R.arrangementDeclarationGapX arrangement
            , R.arrangementDeclarationGapY arrangement
            ])
         (R.planArrangements plan)
    ++ concatMap styleExpressions (R.planStyles plan)
  where
    constraintExpressions declaration =
      case R.constraintDeclarationValue declaration of
        R.NumericConstraint _ left right -> [left, right]
        R.VectorConstraint _ left right  -> left ++ right
        R.SeparationConstraint gap _ _   -> [gap]
    insetsExpressions declaration =
      case R.insetsDeclarationValue declaration of
        R.InsetsExpr top right bottom left -> [top, right, bottom, left]
    styleExpressions declaration =
      case R.styleDeclarationValue declaration of
        R.NumericStyle value                  -> [value]
        R.ColorStyle hue saturation lightness -> [hue, saturation, lightness]
        _                                     -> []

lowerDecisionDeclarations ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> ExpandedPlan
  -> Either RenderCompileError [S.Constraint]
lowerDecisionDeclarations trace plan expanded = do
  choices <- fmap concat (traverse lowerChoice (R.planChoices plan))
  presences <- fmap concat (traverse lowerPresence (presenceDeclarations plan))
  pure (choices ++ presences)
  where
    nodes = expandedNodes expanded
    lowerChoice declaration = do
      contexts <-
        contextsForScope trace plan nodes (R.choiceDeclarationScope declaration)
      concat <$> traverse (emitChoice declaration) contexts
    emitChoice declaration context = do
      decision <-
        decisionConstraint
          (choiceName declaration context)
          (R.choiceDeclarationTokens declaration)
      guardConstraint
        trace
        plan
        expanded
        context
        (R.scopeGuards (R.choiceDeclarationScope declaration))
        decision
    lowerPresence (identifier, scope) = do
      contexts <- contextsForScope trace plan nodes scope
      concat <$> traverse (emitPresence identifier scope) contexts
    emitPresence identifier scope context = do
      decision <-
        decisionConstraint
          (presenceName identifier scope context)
          ["omit", "include"]
      guardConstraint
        trace
        plan
        expanded
        context
        (filter (/= R.PresenceDecision identifier) (R.scopeGuards scope))
        decision

decisionConstraint ::
     String -> [String] -> Either RenderCompileError S.Constraint
decisionConstraint name tokens =
  case tokens of
    [] -> leftInvalid ("finite decision has no alternatives: " ++ name)
    firstToken:remaining ->
      pure
        (S.oneOf
           name
           (S.alternative firstToken [])
           [S.alternative token [] | token <- remaining])

presenceDeclarations :: R.RenderPlan -> [(R.PresenceId, R.Scope)]
presenceDeclarations plan =
  [ declaration
  | declaration@(identifier, _) <- R.planPresences plan
  , identifier `Set.member` referenced
  ]
  where
    referenced =
      Set.fromList
        [ identifier
        | scope <- nonFrameScopes plan
        , R.PresenceDecision identifier <- R.scopeGuards scope
        ]

nonFrameScopes :: R.RenderPlan -> [R.Scope]
nonFrameScopes plan =
  map R.selectionDeclarationScope (R.planSelections plan)
    ++ map R.relationSelectionDeclarationScope (R.planRelationSelections plan)
    ++ map R.nodeDeclarationScope (R.planNodes plan)
    ++ map R.rankingDeclarationScope (R.planRankings plan)
    ++ map R.arrangementDeclarationScope (R.planArrangements plan)
    ++ map R.constraintDeclarationScope (R.planConstraints plan)
    ++ map R.geometryAssignmentScope (R.planGeometry plan)
    ++ map R.insetsDeclarationScope (R.planInsets plan)
    ++ map R.fitDeclarationScope (R.planFits plan)
    ++ map R.contentDeclarationScope (R.planContents plan)
    ++ map R.styleDeclarationScope (R.planStyles plan)
    ++ map R.choiceDeclarationScope (R.planChoices plan)
    ++ map R.connectorDeclarationScope (R.planConnectors plan)

choiceName :: R.ChoiceDeclaration -> ExpansionContext -> String
choiceName declaration context =
  "render.choice."
    ++ showChoiceId (R.choiceDeclarationId declaration)
    ++ "."
    ++ scopeContextKey (R.choiceDeclarationScope declaration) context

presenceName :: R.PresenceId -> R.Scope -> ExpansionContext -> String
presenceName identifier scope context =
  "render.presence."
    ++ showPresenceId identifier
    ++ "."
    ++ scopeContextKey scope context

scopeContextKey :: R.Scope -> ExpansionContext -> String
scopeContextKey scope context =
  case R.scopeCurrentNode scope of
    Just _ -> contextKey context
    Nothing ->
      case R.scopeRelation scope of
        Just relationSelection ->
          case Map.lookup relationSelection (contextRelations context) of
            Just relation' ->
              "relation-" ++ show (Sem.traceRelationId relation')
            Nothing -> "root"
        Nothing -> "root"

guardConstraint ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> ExpandedPlan
  -> ExpansionContext
  -> [R.PresenceGuard]
  -> S.Constraint
  -> Either RenderCompileError [S.Constraint]
guardConstraint trace plan expanded context guards constraint = do
  resolved <- traverse (resolveGuard trace plan expanded context) (nub guards)
  if GuardNever `elem` resolved
    then pure []
    else do
      consolidated <-
        consolidateGuards [guard | guard@GuardDecision {} <- resolved]
      if GuardNever `elem` consolidated
        then pure []
        else pure [foldr wrap constraint consolidated]
  where
    wrap (GuardDecision name tokens required) inner =
      case tokens of
        [] -> inner
        firstToken:remaining ->
          S.oneOf
            name
            (alternativeFor required firstToken inner)
            [alternativeFor required token inner | token <- remaining]
    wrap GuardAlways inner = inner
    wrap GuardNever inner = inner
    alternativeFor required token inner =
      S.alternative token [inner | token == required]

-- Unlike 'guardConstraint', this helper makes a branch infeasible when its
-- guard is inactive.  It is used inside an exact Hug partition: an omitted
-- child cannot be selected as the edge that determines its parent's size.
requireGuardConstraint ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> ExpandedPlan
  -> ExpansionContext
  -> [R.PresenceGuard]
  -> S.Constraint
  -> Either RenderCompileError [S.Constraint]
requireGuardConstraint trace plan expanded context guards constraint = do
  resolved <- traverse (resolveGuard trace plan expanded context) (nub guards)
  if GuardNever `elem` resolved
    then pure [impossibleConstraint]
    else do
      consolidated <-
        consolidateGuards [guard | guard@GuardDecision {} <- resolved]
      if GuardNever `elem` consolidated
        then pure [impossibleConstraint]
        else pure [foldr requireDecision constraint consolidated]
  where
    requireDecision (GuardDecision name tokens required) inner =
      case tokens of
        [] -> impossibleConstraint
        firstToken:remaining ->
          S.oneOf
            name
            (requiredAlternative firstToken)
            [requiredAlternative token | token <- remaining]
      where
        requiredAlternative token =
          S.alternative
            token
            (if token == required
               then [inner]
               else [impossibleConstraint])
    requireDecision GuardAlways inner = inner
    requireDecision GuardNever _ = impossibleConstraint

guardChoiceRequirements :: [ChoiceRequirement] -> S.Constraint -> S.Constraint
guardChoiceRequirements requirements constraint =
  foldr guardOne constraint requirements
  where
    guardOne requirement inner =
      case requirementTokens requirement of
        [] -> impossibleConstraint
        firstToken:remaining ->
          S.oneOf
            (requirementName requirement)
            (alternative firstToken)
            [alternative token | token <- remaining]
      where
        alternative token =
          S.alternative token [inner | token == requirementSelected requirement]

consolidateGuards ::
     [ResolvedGuard] -> Either RenderCompileError [ResolvedGuard]
consolidateGuards guards = traverse consolidate (Map.toAscList grouped)
  where
    grouped =
      Map.fromListWith
        (++)
        [ (name, [(tokens, required)])
        | GuardDecision name tokens required <- guards
        ]
    consolidate (name, alternatives) =
      case alternatives of
        [] -> leftInvalid "empty guard group"
        (tokens, required):rest ->
          if all ((== required) . snd) rest
            then pure (GuardDecision name tokens required)
            else pure GuardNever

resolveGuard ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> ExpandedPlan
  -> ExpansionContext
  -> R.PresenceGuard
  -> Either RenderCompileError ResolvedGuard
resolveGuard trace plan expanded context guard =
  case guard of
    R.PresenceDecision identifier ->
      GuardDecision
        <$> presenceDecisionName identifier
        <*> pure ["omit", "include"]
        <*> pure "include"
    R.ChoiceDecision identifier required -> do
      declaration <- requireChoice plan identifier
      pure
        (GuardDecision
           (choiceDecisionName declaration)
           (R.choiceDeclarationTokens declaration)
           required)
    R.StyleChoiceDecision reference field required -> do
      candidates <-
        resolveReferenceCandidates trace plan expanded context reference
      assignments <-
        traverse
          (styleCategoricalAssignment trace plan expanded context field)
          candidates
      case assignments of
        [] -> leftInvalid "styleOf guard has no context-local mapping"
        assignment:rest
          | not (all (sameResolvedChoice assignment) rest) ->
            leftInvalid
              "styleOf guard resolves to inconsistent style assignments"
          | otherwise ->
            case assignment of
              Left fixed ->
                pure
                  (if fixed == required
                     then GuardAlways
                     else GuardNever)
              Right (declaration, assignmentContext) ->
                pure
                  (GuardDecision
                     (choiceName declaration assignmentContext)
                     (R.choiceDeclarationTokens declaration)
                     required)
  where
    presenceDecisionName identifier =
      case find ((== identifier) . fst) (presenceDeclarations plan) of
        Nothing ->
          leftInvalid
            ("unknown presence decision " ++ showPresenceId identifier)
        Just (_, scope) ->
          pure
            (presenceName
               identifier
               scope
               (contextForScopeDeclaration expanded context scope))
    choiceDecisionName declaration =
      choiceName
        declaration
        (contextForScopeDeclaration
           expanded
           context
           (R.choiceDeclarationScope declaration))

contextForScopeDeclaration ::
     ExpandedPlan -> ExpansionContext -> R.Scope -> ExpansionContext
contextForScopeDeclaration expanded context scope =
  case R.scopeCurrentNode scope of
    Nothing          -> context
    Just declaration -> fromMaybe context (findAncestorContext declaration)
  where
    findAncestorContext declaration = do
      current <- contextCurrentNode context
      findNode current
      where
        findNode identifier = do
          node <- lookupExpandedNode identifier (expandedNodes expanded)
          if expandedNodeDeclaration node == declaration
            then Just (expandedNodeContext node)
            else if expandedNodeParent node == -1
                   then Nothing
                   else findNode (expandedNodeParent node)

requireChoice ::
     R.RenderPlan -> R.ChoiceId -> Either RenderCompileError R.ChoiceDeclaration
requireChoice plan identifier =
  maybe
    (leftInvalid ("unknown choice " ++ showChoiceId identifier))
    Right
    (find ((== identifier) . R.choiceDeclarationId) (R.planChoices plan))

styleCategoricalAssignment ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> ExpandedPlan
  -> ExpansionContext
  -> R.StyleFieldName
  -> ConcreteNode
  -> Either
       RenderCompileError
       (Either String (R.ChoiceDeclaration, ExpansionContext))
styleCategoricalAssignment trace plan expanded context field concrete = do
  assignment <-
    requireStyleAssignment trace plan expanded context concrete field
  case assignment of
    R.FixedStyle token -> pure (Left token)
    R.ChoiceStyle reference -> resolveChoiceReference reference
    R.RemovedStyle -> leftInvalid ("styleOf reads removed field " ++ show field)
    _ ->
      leftInvalid
        ("styleOf expected a categorical field, received " ++ show field)
  where
    resolveChoiceReference reference =
      case reference of
        R.DeclaredChoice identifier -> do
          declaration <- requireChoice plan identifier
          pure
            (Right
               ( declaration
               , contextForScopeDeclaration
                   expanded
                   context
                   (R.choiceDeclarationScope declaration)))
        R.StyleChoice source sourceField -> do
          candidates <-
            resolveReferenceCandidates trace plan expanded context source
          resolved <-
            traverse
              (styleCategoricalAssignment
                 trace
                 plan
                 expanded
                 context
                 sourceField)
              candidates
          case resolved of
            [] -> leftInvalid "inherited style choice has no source mapping"
            value:rest
              | all (sameResolvedChoice value) rest -> pure value
              | otherwise ->
                leftInvalid
                  "inherited style choice has inconsistent source mappings"

sameResolvedChoice ::
     Either String (R.ChoiceDeclaration, ExpansionContext)
  -> Either String (R.ChoiceDeclaration, ExpansionContext)
  -> Bool
sameResolvedChoice (Left first) (Left second) = first == second
sameResolvedChoice (Right (first, firstContext)) (Right (second, secondContext)) =
  R.choiceDeclarationId first == R.choiceDeclarationId second
    && contextKey firstContext == contextKey secondContext
sameResolvedChoice _ _ = False

styleNumericExpression ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> ExpandedPlan
  -> ExpansionContext
  -> ConcreteNode
  -> R.StyleFieldName
  -> Either RenderCompileError SolverExpr
styleNumericExpression trace plan expanded context concrete field = do
  assignment <-
    requireStyleAssignment trace plan expanded context concrete field
  case (field, assignment) of
    (_, R.NumericStyle expression) -> lowerWith expression
    (R.FillHueField, R.ColorStyle hue _ _) -> lowerWith hue
    (R.FillSaturationField, R.ColorStyle _ saturation _) -> lowerWith saturation
    (R.FillLightnessField, R.ColorStyle _ _ lightness) -> lowerWith lightness
    (R.StrokeHueField, R.ColorStyle hue _ _) -> lowerWith hue
    (R.StrokeSaturationField, R.ColorStyle _ saturation _) ->
      lowerWith saturation
    (R.StrokeLightnessField, R.ColorStyle _ _ lightness) -> lowerWith lightness
    (_, R.RemovedStyle) ->
      leftInvalid ("styleOf reads removed field " ++ show field)
    _ ->
      leftInvalid ("styleOf expected a numeric field, received " ++ show field)
  where
    lowerWith expression = do
      let references = numericReferences expression
      environments <-
        referenceEnvironments trace plan expanded context references
      case environments of
        [environment] ->
          lowerNumeric trace plan expanded context environment expression
        [] -> leftInvalid "style expression has no visual mapping"
        _ -> leftInvalid "style expression has ambiguous visual mappings"

requireStyleAssignment ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> ExpandedPlan
  -> ExpansionContext
  -> ConcreteNode
  -> R.StyleFieldName
  -> Either RenderCompileError R.StyleAssignment
requireStyleAssignment trace plan expanded context concrete field =
  case matchingStyleDeclarations plan concrete field of
    declaration:_ -> pure (R.styleDeclarationValue declaration)
    [] ->
      case parentConcrete expanded concrete of
        Right parent ->
          requireStyleAssignment trace plan expanded context parent field
        Left _ -> leftInvalid ("style field is absent: " ++ show field)

matchingStyleDeclarations ::
     R.RenderPlan -> ConcreteNode -> R.StyleFieldName -> [R.StyleDeclaration]
matchingStyleDeclarations plan concrete field =
  reverse
    [ declaration
    | declaration <- R.planStyles plan
    , styleFieldMatches field (R.styleDeclarationField declaration)
    , styleTargetMatches concrete declaration
    ]

styleFieldMatches :: R.StyleFieldName -> R.StyleFieldName -> Bool
styleFieldMatches expected declared
  | expected `elem` fillFields = declared == R.FillHueField
  | expected `elem` strokeFields = declared == R.StrokeHueField
  | otherwise = expected == declared
  where
    fillFields = [R.FillHueField, R.FillSaturationField, R.FillLightnessField]
    strokeFields =
      [R.StrokeHueField, R.StrokeSaturationField, R.StrokeLightnessField]

styleTargetMatches :: ConcreteNode -> R.StyleDeclaration -> Bool
styleTargetMatches concrete declaration =
  case (concrete, R.styleDeclarationTarget declaration) of
    (ConcreteCanvas, R.NodeBuilderTarget R.CanvasReference) ->
      isNothing (R.scopeCurrentNode (R.styleDeclarationScope declaration))
    (ConcreteVisual node, R.NodeBuilderTarget reference) ->
      R.scopeCurrentNode (R.styleDeclarationScope declaration)
        == Just (expandedNodeDeclaration node)
        && referenceMatchesTarget reference node
    _ -> False

referenceMatchesTarget :: R.NodeReference -> ExpandedNode -> Bool
referenceMatchesTarget reference node =
  case (reference, expandedNodeTarget node) of
    (R.GeneratedReference declaration, _) ->
      declaration == expandedNodeDeclaration node
    (R.SelectionReference selection, R.SelectedNodeTarget target) ->
      selection == target
    (R.EndpointReference relation isFirst, R.RelationEndpointTarget target targetFirst) ->
      relation == target && isFirst == targetFirst
    _ -> False

lowerContainment ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> ExpandedPlan
  -> Either RenderCompileError [S.Constraint]
lowerContainment trace plan expanded =
  fmap concat (traverse containParent parents)
  where
    nodes = expandedNodes expanded
    parents = ConcreteCanvas : map ConcreteVisual nodes
    containParent parent = do
      let children =
            [ ConcreteVisual child
            | child <- nodes
            , expandedNodeParent child == concreteNodeId parent
            ]
          context = concreteContext parent
      parentPadding <- symbolicInsets R.PaddingInsets context parent
      childMargins <-
        traverse
          (\child ->
             (,) child
               <$> symbolicInsets R.MarginInsets (concreteContext child) child)
          children
      containment <-
        concat
          <$> traverse
                (\(child, margin) ->
                   containChild context parent parentPadding child margin)
                childMargins
      hugging <- hugChildren context parent parentPadding childMargins
      pure (containment ++ hugging)
    containChild context parent (paddingTop, paddingRight, paddingBottom, paddingLeft) child margin = do
      let (marginTop, marginRight, marginBottom, marginLeft) = margin
          constraints =
            [ nodeAttribute child R.GeometryLeft
                S.@-@ marginLeft
                S.@>=@ nodeAttribute parent R.GeometryLeft
                S.@+@ paddingLeft
            , nodeAttribute child R.GeometryRight
                S.@+@ marginRight
                S.@<=@ nodeAttribute parent R.GeometryRight
                S.@-@ paddingRight
            , nodeAttribute child R.GeometryTop
                S.@-@ marginTop
                S.@>=@ nodeAttribute parent R.GeometryTop
                S.@+@ paddingTop
            , nodeAttribute child R.GeometryBottom
                S.@+@ marginBottom
                S.@<=@ nodeAttribute parent R.GeometryBottom
                S.@-@ paddingBottom
            ]
          guards = nub (concreteNodeGuards parent ++ concreteNodeGuards child)
      concat
        <$> traverse
              (guardConstraint trace plan expanded context guards)
              constraints
    hugChildren context parent padding []
      | any (contentTargetMatches parent) (R.planContents plan) = pure []
      | otherwise = do
        let (paddingTop, paddingRight, paddingBottom, paddingLeft) = padding
            horizontal =
              nodeAttribute parent R.GeometryWidth
                S.@==@ paddingLeft
                S.@+@ paddingRight
            vertical =
              nodeAttribute parent R.GeometryHeight
                S.@==@ paddingTop
                S.@+@ paddingBottom
            constraints =
              [ constraint
              | (isHorizontal, constraint) <-
                  [(True, horizontal), (False, vertical)]
              , fitPolicy plan parent isHorizontal == R.Hug
              , not (geometryAxisExplicit plan parent isHorizontal)
              ]
        concat
          <$> traverse
                (guardConstraint
                   trace
                   plan
                   expanded
                   context
                   (concreteNodeGuards parent))
                constraints
    hugChildren context parent padding childMargins = do
      horizontal <-
        if fitPolicy plan parent True == R.Hug
             && not (geometryAxisExplicit plan parent True)
          then do
            leading <-
              hugPartition context parent padding childMargins True True
            trailing <-
              hugPartition context parent padding childMargins True False
            pure (leading ++ trailing)
          else pure []
      vertical <-
        if fitPolicy plan parent False == R.Hug
             && not (geometryAxisExplicit plan parent False)
          then do
            leading <-
              hugPartition context parent padding childMargins False True
            trailing <-
              hugPartition context parent padding childMargins False False
            pure (leading ++ trailing)
          else pure []
      pure (horizontal ++ vertical)
    hugPartition context parent padding childMargins horizontal leading = do
      alternatives <- traverse makeAlternative childMargins
      case alternatives of
        [] -> pure []
        firstAlternative:remaining -> do
          let axisName =
                if horizontal
                  then "horizontal"
                  else "vertical"
              edgeName =
                if leading
                  then "leading"
                  else "trailing"
              partition =
                S.algebraicOneOf
                  ("render.hug."
                     ++ show (concreteNodeId parent)
                     ++ "."
                     ++ axisName
                     ++ "."
                     ++ edgeName)
                  firstAlternative
                  remaining
          guardConstraint
            trace
            plan
            expanded
            context
            (concreteNodeGuards parent)
            partition
      where
        makeAlternative (child, margin) = do
          let (paddingTop, paddingRight, paddingBottom, paddingLeft) = padding
              (marginTop, marginRight, marginBottom, marginLeft) = margin
              equality
                | horizontal && leading =
                  nodeAttribute parent R.GeometryLeft
                    S.@+@ paddingLeft
                    S.@==@ nodeAttribute child R.GeometryLeft
                    S.@-@ marginLeft
                | horizontal =
                  nodeAttribute parent R.GeometryRight
                    S.@-@ paddingRight
                    S.@==@ nodeAttribute child R.GeometryRight
                    S.@+@ marginRight
                | leading =
                  nodeAttribute parent R.GeometryTop
                    S.@+@ paddingTop
                    S.@==@ nodeAttribute child R.GeometryTop
                    S.@-@ marginTop
                | otherwise =
                  nodeAttribute parent R.GeometryBottom
                    S.@-@ paddingBottom
                    S.@==@ nodeAttribute child R.GeometryBottom
                    S.@+@ marginBottom
          guarded <-
            requireGuardConstraint
              trace
              plan
              expanded
              context
              (concreteNodeGuards child)
              equality
          pure
            (S.alternative ("element-" ++ show (concreteNodeId child)) guarded)
    symbolicInsets kind context concrete =
      case reverse
             [ declaration
             | declaration <- R.planInsets plan
             , sameInsetsKind (R.insetsDeclarationKind declaration) kind
             , insetsTargetMatches concrete declaration
             ] of
        [] -> pure zeroInsets
        declaration:_ ->
          case R.insetsDeclarationValue declaration of
            R.InsetsExpr top right bottom left -> do
              let expressions = [top, right, bottom, left]
                  references = nub (concatMap numericReferences expressions)
              environments <-
                referenceEnvironments trace plan expanded context references
              case environments of
                [environment] -> do
                  values <-
                    traverse
                      (lowerNumeric trace plan expanded context environment)
                      expressions
                  case values of
                    [topValue, rightValue, bottomValue, leftValue] ->
                      pure (topValue, rightValue, bottomValue, leftValue)
                    _ -> leftInvalid "invalid insets arity"
                _ ->
                  leftInvalid "insets expression has ambiguous visual mappings"
    zeroInsets = (S.num 0, S.num 0, S.num 0, S.num 0)
    concreteContext ConcreteCanvas        = rootContext
    concreteContext (ConcreteVisual node) = expandedNodeContext node

insetsTargetMatches :: ConcreteNode -> R.InsetsDeclaration -> Bool
insetsTargetMatches concrete declaration =
  case concrete of
    ConcreteCanvas -> R.insetsDeclarationNode declaration == R.CanvasReference
    ConcreteVisual node ->
      R.scopeCurrentNode (R.insetsDeclarationScope declaration)
        == Just (expandedNodeDeclaration node)
        && referenceMatchesTarget (R.insetsDeclarationNode declaration) node

sameInsetsKind :: R.InsetsKind -> R.InsetsKind -> Bool
sameInsetsKind R.PaddingInsets R.PaddingInsets = True
sameInsetsKind R.MarginInsets R.MarginInsets   = True
sameInsetsKind _ _                             = False

fitPolicy :: R.RenderPlan -> ConcreteNode -> Bool -> R.ContentFit
fitPolicy plan concrete horizontal =
  case reverse
         [ R.fitDeclarationValue declaration
         | declaration <- R.planFits plan
         , fitTargetMatches concrete declaration
         , axisContains horizontal (R.fitDeclarationAxis declaration)
         ] of
    value:_ -> value
    []      -> R.Hug

axisContains :: Bool -> R.Axis -> Bool
axisContains _ R.Both          = True
axisContains True R.Horizontal = True
axisContains False R.Vertical  = True
axisContains _ _               = False

fitTargetMatches :: ConcreteNode -> R.FitDeclaration -> Bool
fitTargetMatches concrete declaration =
  case concrete of
    ConcreteCanvas -> R.fitDeclarationNode declaration == R.CanvasReference
    ConcreteVisual node ->
      R.scopeCurrentNode (R.fitDeclarationScope declaration)
        == Just (expandedNodeDeclaration node)
        && referenceMatchesTarget (R.fitDeclarationNode declaration) node

geometryAxisExplicit :: R.RenderPlan -> ConcreteNode -> Bool -> Bool
geometryAxisExplicit plan concrete horizontal =
  hasSpan || (hasLeading && hasTrailing)
  where
    attributes =
      [ R.geometryAssignmentAttribute declaration
      | declaration <- R.planGeometry plan
      , geometryTargetMatches concrete declaration
      ]
    spanAttribute =
      if horizontal
        then R.GeometryWidth
        else R.GeometryHeight
    leadingAttribute =
      if horizontal
        then R.GeometryLeft
        else R.GeometryTop
    trailingAttribute =
      if horizontal
        then R.GeometryRight
        else R.GeometryBottom
    hasSpan = spanAttribute `elem` attributes
    hasLeading = leadingAttribute `elem` attributes
    hasTrailing = trailingAttribute `elem` attributes

geometryTargetMatches :: ConcreteNode -> R.GeometryAssignment -> Bool
geometryTargetMatches concrete declaration =
  case concrete of
    ConcreteCanvas ->
      R.geometryAssignmentTarget declaration == R.CanvasReference
    ConcreteVisual node ->
      R.scopeCurrentNode (R.geometryAssignmentScope declaration)
        == Just (expandedNodeDeclaration node)
        && referenceMatchesTarget (R.geometryAssignmentTarget declaration) node

contentTargetMatches :: ConcreteNode -> R.ContentDeclaration -> Bool
contentTargetMatches concrete declaration =
  case concrete of
    ConcreteCanvas -> R.contentDeclarationNode declaration == R.CanvasReference
    ConcreteVisual node ->
      R.scopeCurrentNode (R.contentDeclarationScope declaration)
        == Just (expandedNodeDeclaration node)
        && referenceMatchesTarget (R.contentDeclarationNode declaration) node

lowerTextFits ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> ExpandedPlan
  -> [PreparedText]
  -> Either RenderCompileError [S.Constraint]
lowerTextFits trace plan expanded typography =
  fmap concat (traverse lowerContent (zip [0 :: Int ..] (R.planContents plan)))
  where
    nodes = expandedNodes expanded
    lowerContent (index, declaration) = do
      contexts <-
        contextsForScope
          trace
          plan
          nodes
          (R.contentDeclarationScope declaration)
      concat <$> traverse (contentContext index declaration) contexts
    contentContext index declaration context = do
      let reference = R.contentDeclarationNode declaration
      candidates <-
        resolveReferenceCandidates trace plan expanded context reference
      concat <$> traverse (contentNode index declaration context) candidates
    contentNode index declaration context concrete = do
      prepared <-
        requireSingle
          "prepared text mapping"
          [ candidate
          | candidate <- typography
          , preparedTextDeclaration candidate == index
          , preparedTextNode candidate == concreteNodeId concrete
          ]
      (fontSize, sizeConstraints) <-
        contentFontSize index declaration context concrete
      (paddingTop, paddingRight, paddingBottom, paddingLeft) <-
        textPadding context concrete
      let hasChildren =
            any ((== concreteNodeId concrete) . expandedNodeParent) nodes
          hugHorizontal =
            fitPolicy plan concrete True == R.Hug
              && not (geometryAxisExplicit plan concrete True)
              && not hasChildren
          hugVertical =
            fitPolicy plan concrete False == R.Hug
              && not (geometryAxisExplicit plan concrete False)
              && not hasChildren
          guards =
            nub
              (R.scopeGuards (R.contentDeclarationScope declaration)
                 ++ concreteNodeGuards concrete)
          branchConstraints branch =
            let line = preparedTextLine branch
                horizontalIntrinsic =
                  fontSize
                    S.@*@ S.num (Typography.preparedLineWidthEm line)
                    S.@+@ paddingLeft
                    S.@+@ paddingRight
                verticalIntrinsic =
                  fontSize
                    S.@*@ S.num (Typography.preparedLineHeightEm line)
                    S.@+@ paddingTop
                    S.@+@ paddingBottom
             in [ guardChoiceRequirements
                    (preparedTextRequirements branch)
                    (compareTextSize
                       hugHorizontal
                       (nodeAttribute concrete R.GeometryWidth)
                       horizontalIntrinsic)
                , guardChoiceRequirements
                    (preparedTextRequirements branch)
                    (compareTextSize
                       hugVertical
                       (nodeAttribute concrete R.GeometryHeight)
                       verticalIntrinsic)
                ]
          rejectedConstraints =
            [ guardChoiceRequirements requirements impossibleConstraint
            | requirements <- preparedTextRejected prepared
            ]
          constraints =
            concatMap branchConstraints (preparedTextBranches prepared)
              ++ rejectedConstraints
      guarded <-
        concat
          <$> traverse
                (guardConstraint trace plan expanded context guards)
                constraints
      -- A synthesized FontSize exists in the prepared model even when an
      -- optional text node is omitted.  Keep that auxiliary dimension finite;
      -- only its geometric effect is conditional.
      pure (sizeConstraints ++ guarded)
    compareTextSize exact current intrinsic =
      if exact
        then current S.@==@ intrinsic
        else current S.@>=@ intrinsic
    textPadding context concrete =
      case reverse
             [ declaration
             | declaration <- R.planInsets plan
             , sameInsetsKind
                 (R.insetsDeclarationKind declaration)
                 R.PaddingInsets
             , insetsTargetMatches concrete declaration
             ] of
        [] -> pure (S.num 0, S.num 0, S.num 0, S.num 0)
        declaration:_ ->
          case R.insetsDeclarationValue declaration of
            R.InsetsExpr top right bottom left -> do
              let expressions = [top, right, bottom, left]
                  references = nub (concatMap numericReferences expressions)
              environments <-
                referenceEnvironments trace plan expanded context references
              environment <- requireSingle "text padding" environments
              values <-
                traverse
                  (lowerNumeric trace plan expanded context environment)
                  expressions
              case values of
                [topValue, rightValue, bottomValue, leftValue] ->
                  pure (topValue, rightValue, bottomValue, leftValue)
                _ -> leftInvalid "invalid text padding arity"
    contentFontSize index declaration context concrete =
      case requireStyleAssignment
             trace
             plan
             expanded
             context
             concrete
             R.FontSizeField of
        Right (R.NumericStyle authored)
          | R.contentDeclarationFit declaration -> do
            expression <- lowerAuthored authored
            pure (expression, [])
          | numericExprIsFixed authored -> do
            expression <- lowerAuthored authored
            pure (expression, [])
          | otherwise ->
            leftInvalid
              "content uses a sampled FontSize; use fitText for variable font size"
        Right R.RemovedStyle -> pure (S.num 16, [])
        Right _ -> leftInvalid "FontSize has a non-numeric style assignment"
        Left _ -> fallback
      where
        fallback
          | R.contentDeclarationFit declaration =
            let expression = S.var (syntheticTextFontSizeName index declaration)
             in pure (expression, [S.within expression (S.Range 12 32)])
          | otherwise = pure (S.num 16, [])
        lowerAuthored authored = do
          environments <-
            referenceEnvironments
              trace
              plan
              expanded
              context
              (numericReferences authored)
          environment <- requireSingle "FontSize" environments
          lowerNumeric trace plan expanded context environment authored

numericExprIsFixed :: R.NumericExpr -> Bool
numericExprIsFixed expression =
  case expression of
    R.NumericConstant _          -> True
    R.NumericAdd left right      -> nested left right
    R.NumericSubtract left right -> nested left right
    R.NumericMultiply left right -> nested left right
    R.NumericDivide left right   -> nested left right
    _                            -> False
  where
    nested left right = numericExprIsFixed left && numericExprIsFixed right

syntheticTextFontSizeName :: Int -> R.ContentDeclaration -> String
syntheticTextFontSizeName index declaration =
  "render.text."
    ++ show index
    ++ "."
    ++ maybe
         "canvas"
         (("node-" ++) . showNodeDeclarationId)
         (R.scopeCurrentNode (R.contentDeclarationScope declaration))
    ++ ".font-size"

renderContentLine ::
     Sem.SemanticTrace
  -> ExpandedPlan
  -> ConcreteNode
  -> [R.TextPiece]
  -> Either RenderCompileError RenderedText
renderContentLine trace expanded concrete pieces = do
  (_, chunks, fragments) <- foldM appendPiece (0, [], []) pieces
  pure
    RenderedText
      { renderedTextSource = concat (reverse chunks)
      , renderedTextFragments = reverse fragments
      }
  where
    declaredSteps =
      Set.fromList
        [ Sem.traceMarkerType marker
        | (marker, category) <- Sem.semanticTraceDeclarations trace
        , category == "a step"
        ]
    appendPiece (offset, chunks, fragments) piece = do
      value <- renderPiece piece
      when (any (`elem` ("\r\n" :: String)) value)
        $ leftInvalid
            "text content must be one line; use separate positioned nodes"
      let steps = nub (R.textPieceSteps piece)
          unknown = filter (`Set.notMember` declaredSteps) steps
          byteLength = BS.length (Text.encodeUtf8 (Text.pack value))
          range = IR.TextSourceRange offset (offset + byteLength)
          fragmentRanges =
            [ Typography.FragmentRange range steps
            | not (null steps) && byteLength > 0
            ]
      unless (null unknown)
        $ leftInvalid
            ("text fragment refers to undeclared step definitions: "
               ++ intercalate ", " unknown)
      pure (offset + byteLength, value : chunks, fragmentRanges ++ fragments)
    renderPiece piece =
      case R.textPieceSource piece of
        R.LiteralText value -> pure value
        R.CurrentPayloadText declaration -> do
          node <- requireDeclarationNode declaration
          blockId <-
            maybe
              (leftInvalid "bindContent requires a selected semantic node")
              Right
              (expandedNodeSemanticBlock node)
          block <-
            maybe
              (leftInvalid "bindContent refers to an unknown block")
              Right
              (lookupTraceBlock blockId trace)
          pure (Sem.traceBlockPayloadText block)
        R.RankingText ranking declaration -> do
          node <- requireDeclarationNode declaration
          blockId <-
            maybe
              (leftInvalid "asText requires a selected semantic node")
              Right
              (expandedNodeSemanticBlock node)
          ranks <-
            maybe
              (leftInvalid ("unknown ranking " ++ showRankingId ranking))
              Right
              (Map.lookup ranking (expandedRanks expanded))
          rank <-
            maybe
              (leftInvalid "asText node is outside its ranking")
              Right
              (Map.lookup blockId ranks)
          pure (show rank)
    requireDeclarationNode declaration =
      case concrete of
        ConcreteVisual node ->
          maybe
            (leftInvalid "text source does not match its current node mapping")
            Right
            (findDeclarationAncestor declaration node)
        ConcreteCanvas ->
          leftInvalid "text source does not match its current node mapping"
    findDeclarationAncestor declaration node
      | expandedNodeDeclaration node == declaration = Just node
      | expandedNodeParent node == -1 = Nothing
      | otherwise =
        lookupExpandedNode (expandedNodeParent node) (expandedNodes expanded)
          >>= findDeclarationAncestor declaration

--------------------------------------------------------------------------------
-- Solved IR v2 materialization
--------------------------------------------------------------------------------
materializeVisualization ::
     FilePath
  -> IR.ScenarioKey
  -> Sem.SemanticTrace
  -> PreparedCompilation
  -> S.Solution
  -> Either RenderCompileError (IR.Visualization, [Resource.ResourceBlob])
materializeVisualization sourcePath key trace prepared solution = do
  let plan = preparedPlan prepared
      expanded = preparedExpanded prepared
  activeNodes <-
    filterMRight
      (\node ->
         guardsActive
           trace
           plan
           expanded
           solution
           (expandedNodeContext node)
           (expandedNodeGuards node))
      (expandedNodes expanded)
  canvasElement <- materializeCanvas trace plan expanded solution activeNodes
  materializedNodes <-
    traverse
      (materializeElement
         trace
         plan
         expanded
         (preparedText prepared)
         solution
         activeNodes)
      activeNodes
  let elements =
        canvasElement : [element | (element, _, _) <- materializedNodes]
      materializedText =
        Map.fromList
          [ (identifier, text')
          | (_, Just (identifier, text'), _) <- materializedNodes
          ]
      resources =
        deduplicateResources
          [ resource
          | (_, _, nodeResources) <- materializedNodes
          , resource <- nodeResources
          ]
  activeConnectors <-
    filterMRight
      (connectorEnabled trace plan expanded solution activeNodes)
      (expandedConnectors expanded)
  connectors <-
    traverse
      (materializeConnector trace plan expanded solution)
      activeConnectors
  steps <-
    materializeFrames
      trace
      plan
      expanded
      solution
      activeNodes
      activeConnectors
      materializedText
  let viewSeed = randomSeedInt (S.solutionSeed solution)
      visualization =
        IR.Visualization
          { IR.visualizationIrVersion = 2
          , IR.visualizationSeed = viewSeed
          , IR.visualizationScenarioKey = Just key
          , IR.visualizationScenarioSeed =
              Just (Sem.semanticTraceScenarioSeed trace)
          , IR.visualizationViewSeed = Just viewSeed
          , IR.visualizationSourcePath = sourcePath
          , IR.visualizationSampling = Just (compileSamplingProvenance solution)
          , IR.visualizationCoordinates =
              IR.CoordinateSystem
                { IR.coordinateSystemName = "sverlin-logical-y-down"
                , IR.coordinateSystemOrigin = "top-left"
                , IR.coordinateSystemYAxis = "down"
                }
          , IR.visualizationRoot = IR.VisualId (-1)
          , IR.visualizationResources =
              map Resource.resourceBlobDescriptor resources
          , IR.visualizationFindings = []
          , IR.visualizationVariables =
              compileVariables solution
                ++ compileAutomaticStyleVariables expanded solution activeNodes
                ++ compileFramePresenceVariables trace plan solution
          , IR.visualizationElements = elements
          , IR.visualizationConnectors = Just connectors
          , IR.visualizationSteps = steps
          }
  pure (visualization, resources)

filterMRight ::
     (value -> Either RenderCompileError Bool)
  -> [value]
  -> Either RenderCompileError [value]
filterMRight predicate = fmap catMaybes . traverse keep
  where
    keep value = do
      retained <- predicate value
      pure
        (if retained
           then Just value
           else Nothing)

materializeCanvas ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> ExpandedPlan
  -> S.Solution
  -> [ExpandedNode]
  -> Either RenderCompileError IR.VisualElement
materializeCanvas trace plan expanded solution activeNodes = do
  box <- materializeBox trace plan expanded solution rootContext ConcreteCanvas
  style' <-
    materializeVisualStyle
      trace
      plan
      expanded
      solution
      rootContext
      ConcreteCanvas
  pure
    IR.VisualElement
      { IR.elementId = IR.VisualId (-1)
      , IR.elementRole = "Canvas"
      , IR.elementBox = box {IR.boxMargin = zeroIrInsets}
      , IR.elementChildren =
          [ IR.VisualId (expandedNodeId node)
          | node <- activeNodes
          , expandedNodeParent node == -1
          ]
      , IR.elementContent = Nothing
      , IR.elementStyle = style'
      , IR.elementStyleVariables = []
      }

materializeElement ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> ExpandedPlan
  -> [PreparedText]
  -> S.Solution
  -> [ExpandedNode]
  -> ExpandedNode
  -> Either
       RenderCompileError
       ( IR.VisualElement
       , Maybe (Int, MaterializedText)
       , [Resource.ResourceBlob])
materializeElement trace plan expanded typography solution activeNodes node = do
  let concrete = ConcreteVisual node
      context = expandedNodeContext node
  box <- materializeBox trace plan expanded solution context concrete
  style' <- materializeVisualStyle trace plan expanded solution context concrete
  (content', materializedText, resources) <-
    materializeContent
      trace
      plan
      expanded
      typography
      solution
      concrete
      box
      style'
  let element =
        IR.VisualElement
          { IR.elementId = IR.VisualId (expandedNodeId node)
          , IR.elementRole = expandedNodeRole node
          , IR.elementBox = box
          , IR.elementChildren =
              [ IR.VisualId (expandedNodeId child)
              | child <- activeNodes
              , expandedNodeParent child == expandedNodeId node
              ]
          , IR.elementContent = content'
          , IR.elementStyle = style'
          , IR.elementStyleVariables = []
          }
  pure
    ( element
    , fmap (\text' -> (expandedNodeId node, text')) materializedText
    , resources)

materializeBox ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> ExpandedPlan
  -> S.Solution
  -> ExpansionContext
  -> ConcreteNode
  -> Either RenderCompileError IR.VisualBox
materializeBox trace plan expanded solution context concrete = do
  leftValue <- evaluateExpr solution (nodeAttribute concrete R.GeometryLeft)
  topValue <- evaluateExpr solution (nodeAttribute concrete R.GeometryTop)
  widthValue <- evaluateExpr solution (nodeAttribute concrete R.GeometryWidth)
  heightValue <- evaluateExpr solution (nodeAttribute concrete R.GeometryHeight)
  padding' <-
    materializeInsets
      trace
      plan
      expanded
      solution
      context
      concrete
      R.PaddingInsets
  margin' <-
    materializeInsets
      trace
      plan
      expanded
      solution
      context
      concrete
      R.MarginInsets
  pure
    IR.VisualBox
      { IR.boxBounds =
          IR.LayoutRect
            { IR.layoutRectX = roundLayout leftValue
            , IR.layoutRectY = roundLayout topValue
            , IR.layoutRectWidth = roundLayout (max 0 widthValue)
            , IR.layoutRectHeight = roundLayout (max 0 heightValue)
            }
      , IR.boxPadding = padding'
      , IR.boxMargin = margin'
      }

materializeInsets ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> ExpandedPlan
  -> S.Solution
  -> ExpansionContext
  -> ConcreteNode
  -> R.InsetsKind
  -> Either RenderCompileError IR.EdgeInsets
materializeInsets trace plan expanded solution context concrete kind =
  case reverse
         [ declaration
         | declaration <- R.planInsets plan
         , sameInsetsKind (R.insetsDeclarationKind declaration) kind
         , insetsTargetMatches concrete declaration
         ] of
    [] -> pure zeroIrInsets
    declaration:_ ->
      case R.insetsDeclarationValue declaration of
        R.InsetsExpr top right bottom left -> do
          values <- traverse lowerAndEvaluate [top, right, bottom, left]
          case values of
            [topValue, rightValue, bottomValue, leftValue] ->
              pure
                IR.EdgeInsets
                  { IR.insetsTop = nonnegative topValue
                  , IR.insetsRight = nonnegative rightValue
                  , IR.insetsBottom = nonnegative bottomValue
                  , IR.insetsLeft = nonnegative leftValue
                  }
            _ -> leftInvalid "invalid insets arity"
  where
    lowerAndEvaluate expression = do
      environments <-
        referenceEnvironments
          trace
          plan
          expanded
          context
          (numericReferences expression)
      environment <- requireSingle "insets" environments
      lowered <- lowerNumeric trace plan expanded context environment expression
      evaluateExpr solution lowered
    nonnegative = roundLayout . max 0

zeroIrInsets :: IR.EdgeInsets
zeroIrInsets = IR.EdgeInsets 0 0 0 0

materializeContent ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> ExpandedPlan
  -> [PreparedText]
  -> S.Solution
  -> ConcreteNode
  -> IR.VisualBox
  -> IR.VisualStyle
  -> Either
       RenderCompileError
       (Maybe IR.VisualContent, Maybe MaterializedText, [Resource.ResourceBlob])
materializeContent trace plan expanded typography solution concrete box style' =
  case concrete of
    ConcreteCanvas -> pure (Nothing, Nothing, [])
    ConcreteVisual node -> do
      declarations <-
        filterMRight
          (\(_, declaration) ->
             guardsActive
               trace
               plan
               expanded
               solution
               (expandedNodeContext node)
               (R.scopeGuards (R.contentDeclarationScope declaration)))
          [ (index, declaration)
          | (index, declaration) <- zip [0 :: Int ..] (R.planContents plan)
          , R.scopeCurrentNode (R.contentDeclarationScope declaration)
              == Just (expandedNodeDeclaration node)
          , referenceMatchesTarget (R.contentDeclarationNode declaration) node
          ]
      case reverse declarations of
        [] -> pure (Nothing, Nothing, [])
        (index, _declaration):_ -> do
          prepared <-
            requireSingle
              "materialized text mapping"
              [ candidate
              | candidate <- typography
              , preparedTextDeclaration candidate == index
              , preparedTextNode candidate == expandedNodeId node
              ]
          branch <-
            requireSingle
              "selected font branch"
              [ candidate
              | candidate <- preparedTextBranches prepared
              , requirementsMatch solution (preparedTextRequirements candidate)
              ]
          let line = preparedTextLine branch
              fontSize = fromMaybe 16 (IR.visualFontSize style')
              alignment = fromMaybe "center" (IR.visualTextAlign style')
              contentBox =
                insetContentBox (IR.boxBounds box) (IR.boxPadding box)
              (content', layout) =
                Typography.materializeLine
                  fontSize
                  fontSize
                  alignment
                  contentBox
                  line
              materialized =
                MaterializedText
                  { materializedPreparedLine = line
                  , materializedTextLayout = layout
                  , materializedFontSize = fontSize
                  }
          pure
            ( Just content'
            , Just materialized
            , Typography.preparedLineResources line)

requirementsMatch :: S.Solution -> [ChoiceRequirement] -> Bool
requirementsMatch solution =
  all
    (\requirement ->
       Map.lookup (requirementName requirement) (S.solutionChoices solution)
         == Just (requirementSelected requirement))

insetContentBox :: IR.LayoutRect -> IR.EdgeInsets -> IR.LayoutRect
insetContentBox bounds padding' =
  IR.LayoutRect
    { IR.layoutRectX =
        roundLayout (IR.layoutRectX bounds + IR.insetsLeft padding')
    , IR.layoutRectY =
        roundLayout (IR.layoutRectY bounds + IR.insetsTop padding')
    , IR.layoutRectWidth =
        roundLayout
          (max
             0
             (IR.layoutRectWidth bounds
                - IR.insetsLeft padding'
                - IR.insetsRight padding'))
    , IR.layoutRectHeight =
        roundLayout
          (max
             0
             (IR.layoutRectHeight bounds
                - IR.insetsTop padding'
                - IR.insetsBottom padding'))
    }

materializeVisualStyle ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> ExpandedPlan
  -> S.Solution
  -> ExpansionContext
  -> ConcreteNode
  -> Either RenderCompileError IR.VisualStyle
materializeVisualStyle trace plan expanded solution context concrete = do
  opacity <- numeric R.OpacityField
  fontSizeAssignment <- activeStyleAssignment R.FontSizeField
  fontSize <-
    case fontSizeAssignment of
      Just (R.NumericStyle expression) ->
        Just . roundLayout <$> evaluateStyle expression
      Just R.RemovedStyle -> pure Nothing
      Just _ -> pure Nothing
      Nothing -> contentDefaultFontSize
  radius <- numeric R.RadiusField
  strokeWidth <- numeric R.StrokeWidthField
  alpha <- numeric R.AlphaField
  fill <- color R.FillHueField R.FillSaturationField R.FillLightnessField
  stroke <-
    color R.StrokeHueField R.StrokeSaturationField R.StrokeLightnessField
  fontFamily <- categorical R.FontFamilyField
  fontWeight <- categorical R.FontWeightField
  fontStyle <- categorical R.FontStyleField
  textAlign <- categorical R.TextAlignField
  borderStyle <- categorical R.BorderStyleField
  pure
    IR.VisualStyle
      { IR.visualOpacity = opacity
      , IR.visualZIndex = Nothing
      , IR.visualFontSize = positiveMaybe fontSize
      , IR.visualRadius = nonnegativeMaybe radius
      , IR.visualStrokeWidth = nonnegativeMaybe strokeWidth
      , IR.visualAlpha = alpha
      , IR.visualFill = fill
      , IR.visualStroke = stroke
      , IR.visualFontFamily = fontFamily
      , IR.visualFontWeight = fontWeight
      , IR.visualFontStyle = fontStyle
      , IR.visualTextAlign = textAlign
      , IR.visualBorderStyle = borderStyle
      , IR.visualWhiteSpace = Nothing
      }
  where
    family = automaticStyleFamily concrete
    profile =
      if automaticStyleEligible expanded concrete
        then Theme.leafProfileFor (randomSeedInt (S.solutionSeed solution))
               <$> family
        else Nothing
    hasDeclaredContent =
      any (contentTargetMatches concrete) (R.planContents plan)
    numeric field = do
      assignment <- activeStyleAssignment field
      case assignment of
        Nothing -> automaticNumeric field
        Just (R.NumericStyle expression) ->
          Just . roundLayout <$> evaluateStyle expression
        Just R.RemovedStyle -> pure Nothing
        Just _ -> pure Nothing
    color hueField _saturationField _lightnessField = do
      assignment <- activeStyleAssignment hueField
      case assignment of
        Nothing -> automaticColor hueField
        Just (R.ColorStyle hue saturation lightness) -> do
          hueValue <- evaluateStyle hue
          saturationValue <- evaluateStyle saturation
          lightnessValue <- evaluateStyle lightness
          pure
            (Just
               IR.HslColor
                 { IR.hslHue = canonicalHue hueValue
                 , IR.hslSaturation = clampUnit saturationValue
                 , IR.hslLightness = clampUnit lightnessValue
                 })
        Just R.RemovedStyle -> pure Nothing
        Just _ -> pure Nothing
    categorical field = do
      assignment <- activeStyleAssignment field
      case assignment of
        Nothing -> automaticCategorical field
        Just (R.FixedStyle token)
          | field == R.FontWeightField -> Just <$> materializeFontWeight
          | otherwise -> pure (Just token)
        Just (R.ChoiceStyle reference)
          | field == R.FontWeightField -> Just <$> materializeFontWeight
          | otherwise -> Just <$> materializeChoice reference
        Just R.RemovedStyle -> pure Nothing
        Just _ -> pure Nothing
    automaticNumeric field =
      case (field, profile) of
        (R.RadiusField, Just Theme.LeafSoftCard) ->
          Just . roundLayout <$> automaticValue "soft-card.radius"
        (R.RadiusField, Just Theme.LeafPill) ->
          Just . roundLayout . (/ 2)
            <$> evaluateExpr solution (nodeAttribute concrete R.GeometryHeight)
        (R.StrokeWidthField, Just Theme.LeafOutline) -> pure (Just 1.5)
        _ -> pure Nothing
    automaticColor field =
      case (field, profile) of
        (R.FillHueField, Just Theme.LeafFlat)      -> Just <$> fillColor
        (R.FillHueField, Just Theme.LeafSoftCard)  -> Just <$> fillColor
        (R.FillHueField, Just Theme.LeafPill)      -> Just <$> fillColor
        (R.StrokeHueField, Just Theme.LeafOutline) -> Just <$> strokeColor
        _                                          -> pure Nothing
    fillColor = do
      hue <- automaticValue "fill.hue"
      saturation <- automaticValue "fill.saturation"
      lightness <- automaticValue "fill.lightness"
      pure
        IR.HslColor
          { IR.hslHue = canonicalHue hue
          , IR.hslSaturation = clampUnit saturation
          , IR.hslLightness = clampUnit lightness
          }
    strokeColor = do
      hue <- automaticValue "fill.hue"
      saturation <- automaticValue "stroke.saturation"
      lightness <- automaticValue "stroke.lightness"
      pure
        IR.HslColor
          { IR.hslHue = canonicalHue hue
          , IR.hslSaturation = clampUnit saturation
          , IR.hslLightness = clampUnit lightness
          }
    automaticValue field =
      case family of
        Nothing -> leftInvalid "automatic style has no visual family"
        Just familyName ->
          evaluateExpr solution (automaticStyleVariable familyName field)
    automaticCategorical field =
      case field of
        R.FontFamilyField
          | hasDeclaredContent ->
            automaticChoice
              Theme.automaticFontFamilyChoice
              Theme.automaticFontFamilies
        R.FontWeightField
          | hasDeclaredContent ->
            automaticChoice
              Theme.automaticFontWeightChoice
              Theme.automaticFontWeights
        R.FontStyleField
          | hasDeclaredContent && isJust profile -> pure (Just "normal")
        R.TextAlignField ->
          pure
            (case profile of
               Just Theme.LeafTransparent -> Just "left"
               Just _                     -> Just "center"
               Nothing                    -> Nothing)
        R.BorderStyleField ->
          pure
            (case profile of
               Just Theme.LeafOutline -> Just "solid"
               _                      -> Nothing)
        _ -> pure Nothing
    automaticChoice name tokens =
      case Map.lookup name (S.solutionChoices solution) of
        Just token
          | token `elem` tokens -> pure (Just token)
        _ -> leftInvalid ("solution omitted automatic style choice " ++ name)
    materializeFontWeight = do
      options <-
        categoricalStyleOptions
          trace
          plan
          expanded
          context
          concrete
          R.FontWeightField
          "400"
      requireSingle
        "resolved font weight"
        (nub
           [ token
           | (token, requirements) <- options
           , requirementsMatch solution requirements
           ])
    activeStyleAssignment field = do
      declarations <-
        filterMRight
          (guardsActive trace plan expanded solution context
             . R.scopeGuards
             . R.styleDeclarationScope)
          (matchingStyleDeclarations plan concrete field)
      case declarations of
        declaration:_ -> pure (Just (R.styleDeclarationValue declaration))
        [] ->
          case parentConcrete expanded concrete of
            Left _       -> pure Nothing
            Right parent -> inheritedAssignment parent field
    inheritedAssignment parent field = do
      let parentContext =
            case parent of
              ConcreteCanvas      -> rootContext
              ConcreteVisual node -> expandedNodeContext node
      parentStyleAssignment parentContext parent field
    parentStyleAssignment parentContext parent field = do
      declarations <-
        filterMRight
          (guardsActive trace plan expanded solution parentContext
             . R.scopeGuards
             . R.styleDeclarationScope)
          (matchingStyleDeclarations plan parent field)
      case declarations of
        declaration:_ -> pure (Just (R.styleDeclarationValue declaration))
        [] ->
          case parentConcrete expanded parent of
            Left _ -> pure Nothing
            Right grandparent ->
              let grandparentContext =
                    case grandparent of
                      ConcreteCanvas      -> rootContext
                      ConcreteVisual node -> expandedNodeContext node
               in parentStyleAssignment grandparentContext grandparent field
    evaluateStyle expression = do
      environments <-
        referenceEnvironments
          trace
          plan
          expanded
          context
          (numericReferences expression)
      environment <- requireSingle "style" environments
      lowered <- lowerNumeric trace plan expanded context environment expression
      evaluateExpr solution lowered
    materializeChoice reference =
      case reference of
        R.DeclaredChoice identifier -> do
          declaration <- requireChoice plan identifier
          let decisionContext =
                contextForScopeDeclaration
                  expanded
                  context
                  (R.choiceDeclarationScope declaration)
              name = choiceName declaration decisionContext
          maybe
            (leftInvalid ("solution omitted style choice " ++ name))
            Right
            (Map.lookup name (S.solutionChoices solution))
        R.StyleChoice source field -> do
          candidates <-
            resolveReferenceCandidates trace plan expanded context source
          sourceNode <- requireSingle "style choice source" candidates
          sourceStyle <-
            materializeVisualStyle
              trace
              plan
              expanded
              solution
              context
              sourceNode
          maybe
            (leftInvalid ("projected style field is absent: " ++ show field))
            Right
            (categoricalField field sourceStyle)
    categoricalField field style' =
      case field of
        R.FontFamilyField  -> IR.visualFontFamily style'
        R.FontWeightField  -> IR.visualFontWeight style'
        R.FontStyleField   -> IR.visualFontStyle style'
        R.TextAlignField   -> IR.visualTextAlign style'
        R.BorderStyleField -> IR.visualBorderStyle style'
        _                  -> Nothing
    contentDefaultFontSize =
      case concrete of
        ConcreteCanvas -> pure Nothing
        ConcreteVisual node -> do
          declarations <-
            filterMRight
              (guardsActive trace plan expanded solution context
                 . R.scopeGuards
                 . R.contentDeclarationScope
                 . snd)
              [ (index, declaration)
              | (index, declaration) <- zip [0 :: Int ..] (R.planContents plan)
              , R.scopeCurrentNode (R.contentDeclarationScope declaration)
                  == Just (expandedNodeDeclaration node)
              , referenceMatchesTarget
                  (R.contentDeclarationNode declaration)
                  node
              ]
          case reverse declarations of
            [] -> pure Nothing
            (index, declaration):_
              | R.contentDeclarationFit declaration ->
                Just . roundLayout
                  <$> evaluateExpr
                        solution
                        (S.var (syntheticTextFontSizeName index declaration))
              | otherwise -> pure (Just 16)
    positiveMaybe = fmap (max 0.001)
    nonnegativeMaybe = fmap (max 0)

connectorEnabled ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> ExpandedPlan
  -> S.Solution
  -> [ExpandedNode]
  -> ExpandedConnector
  -> Either RenderCompileError Bool
connectorEnabled trace plan expanded solution activeNodes connector' = do
  guarded <-
    guardsActive
      trace
      plan
      expanded
      solution
      (expandedConnectorContext connector')
      (expandedConnectorGuards connector')
  let activeIds = Set.fromList (map expandedNodeId activeNodes ++ [-1])
  pure
    (guarded
       && concreteNodeId (expandedConnectorStart connector')
            `Set.member` activeIds
       && concreteNodeId (expandedConnectorEnd connector')
            `Set.member` activeIds)

materializeConnector ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> ExpandedPlan
  -> S.Solution
  -> ExpandedConnector
  -> Either RenderCompileError IR.VisualConnector
materializeConnector trace plan expanded solution connector' = do
  startBox <- concreteRect (expandedConnectorStart connector')
  endBox <- concreteRect (expandedConnectorEnd connector')
  let declaration = expandedConnectorDeclaration connector'
      R.ConnectorAnchor startPlacement _ =
        R.connectorDeclarationStart declaration
      R.ConnectorAnchor endPlacement _ = R.connectorDeclarationEnd declaration
      startCenter = rectCenter startBox
      endCenter = rectCenter endBox
      startPoint = anchorPoint startPlacement startBox endCenter
      endPoint = anchorPoint endPlacement endBox startCenter
  connectorStyle <-
    materializeConnectorStyle trace plan expanded solution connector'
  pure
    IR.VisualConnector
      { IR.connectorId = IR.ConnectorId (expandedConnectorId connector')
      , IR.connectorRelationIdentity =
          fmap
            (Sem.traceMarkerType . Sem.traceRelationKind)
            (expandedConnectorRelation connector')
      , IR.connectorStartElementId =
          IR.VisualId (concreteNodeId (expandedConnectorStart connector'))
      , IR.connectorEndElementId =
          IR.VisualId (concreteNodeId (expandedConnectorEnd connector'))
      , IR.connectorStart = uncurry IR.LayoutPoint startPoint
      , IR.connectorEnd = uncurry IR.LayoutPoint endPoint
      , IR.connectorStartMarker =
          compileMarker (R.connectorDeclarationStartMarker declaration)
      , IR.connectorEndMarker =
          compileMarker (R.connectorDeclarationEndMarker declaration)
      , IR.connectorStroke = connectorStroke connectorStyle
      , IR.connectorStrokeWidth = connectorStrokeWidth connectorStyle
      , IR.connectorOpacity = connectorOpacity connectorStyle
      }
  where
    concreteRect concrete = do
      let context =
            case concrete of
              ConcreteCanvas      -> rootContext
              ConcreteVisual node -> expandedNodeContext node
      IR.boxBounds
        <$> materializeBox trace plan expanded solution context concrete

data ConnectorStyle = ConnectorStyle
  { connectorStroke      :: Maybe IR.HslColor
  , connectorStrokeWidth :: Double
  , connectorOpacity     :: Double
  }

materializeConnectorStyle ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> ExpandedPlan
  -> S.Solution
  -> ExpandedConnector
  -> Either RenderCompileError ConnectorStyle
materializeConnectorStyle trace plan expanded solution connector' = do
  active <-
    filterMRight
      (guardsActive
         trace
         plan
         expanded
         solution
         (expandedConnectorContext connector')
         . R.scopeGuards
         . R.styleDeclarationScope)
      [ declaration
      | declaration <- R.planStyles plan
      , R.styleDeclarationTarget declaration
          == R.ConnectorBuilderTarget
               (R.connectorDeclarationId
                  (expandedConnectorDeclaration connector'))
      ]
  stroke <- materializeColor R.StrokeHueField active
  strokeWidth <- materializeNumber R.StrokeWidthField 1 active
  opacity <- materializeNumber R.OpacityField 1 active
  pure
    ConnectorStyle
      { connectorStroke = stroke
      , connectorStrokeWidth = max 0 strokeWidth
      , connectorOpacity = clampUnit opacity
      }
  where
    context = expandedConnectorContext connector'
    materializeNumber field fallback declarations =
      case [ expression
           | declaration <- reverse declarations
           , R.styleDeclarationField declaration == field
           , R.NumericStyle expression <- [R.styleDeclarationValue declaration]
           ] of
        []           -> pure fallback
        expression:_ -> evaluate expression
    materializeColor field declarations =
      case [ (hue, saturation, lightness)
           | declaration <- reverse declarations
           , R.styleDeclarationField declaration == field
           , R.ColorStyle hue saturation lightness <-
               [R.styleDeclarationValue declaration]
           ] of
        [] -> pure Nothing
        (hue, saturation, lightness):_ -> do
          hueValue <- evaluate hue
          saturationValue <- evaluate saturation
          lightnessValue <- evaluate lightness
          pure
            (Just
               (IR.HslColor
                  (canonicalHue hueValue)
                  (clampUnit saturationValue)
                  (clampUnit lightnessValue)))
    evaluate expression = do
      environments <-
        referenceEnvironments
          trace
          plan
          expanded
          context
          (numericReferences expression)
      environment <- requireSingle "connector style" environments
      lowered <- lowerNumeric trace plan expanded context environment expression
      evaluateExpr solution lowered

compileMarker :: R.Marker -> IR.ConnectorMarker
compileMarker marker =
  case marker of
    R.NoMarker      -> IR.ConnectorNoMarker
    R.ArrowMarker   -> IR.ConnectorArrowMarker
    R.CircleMarker  -> IR.ConnectorCircleMarker
    R.DiamondMarker -> IR.ConnectorDiamondMarker

rectCenter :: IR.LayoutRect -> (Double, Double)
rectCenter rect =
  ( IR.layoutRectX rect + IR.layoutRectWidth rect / 2
  , IR.layoutRectY rect + IR.layoutRectHeight rect / 2)

anchorPoint ::
     R.AnchorPlacement -> IR.LayoutRect -> (Double, Double) -> (Double, Double)
anchorPoint placement rect target =
  let (centerX, centerY) = rectCenter rect
      halfWidth = IR.layoutRectWidth rect / 2
      halfHeight = IR.layoutRectHeight rect / 2
   in case placement of
        R.AtCenter -> (centerX, centerY)
        R.AtTop -> (centerX, centerY - halfHeight)
        R.AtRight -> (centerX + halfWidth, centerY)
        R.AtBottom -> (centerX, centerY + halfHeight)
        R.AtLeft -> (centerX - halfWidth, centerY)
        R.AtBoundary ->
          let (targetX, targetY) = target
              dx = targetX - centerX
              dy = targetY - centerY
              scaleX =
                if dx == 0
                  then 1 / 0
                  else halfWidth / abs dx
              scaleY =
                if dy == 0
                  then 1 / 0
                  else halfHeight / abs dy
              scale = min scaleX scaleY
           in if dx == 0 && dy == 0
                then (centerX, centerY)
                else (centerX + dx * scale, centerY + dy * scale)

materializeFrames ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> ExpandedPlan
  -> S.Solution
  -> [ExpandedNode]
  -> [ExpandedConnector]
  -> Map Int MaterializedText
  -> Either RenderCompileError [IR.TimelineStep]
materializeFrames trace plan expanded solution activeNodes activeConnectors typography = do
  let candidates = frameCandidates trace plan
      included = filter (frameIncluded solution) candidates
      includedKeys = Set.fromList (map frameCandidateKey included)
  traverse (materializeFrame includedKeys) included
  where
    frameIncluded solution' candidate
      | R.frameAlways (frameDeclaration candidate) = True
      | otherwise =
        case R.framePresence (frameDeclaration candidate) of
          Nothing -> False
          Just presence ->
            deterministicPresence
              (randomSeedInt (S.solutionSeed solution'))
              presence
              (Sem.stepOccurrencePath (frameOccurrence candidate))
    materializeFrame includedKeys candidate = do
      visibleNodes <-
        filterMRight
          (nodeVisibleAt
             trace
             (Sem.stepOccurrenceEnd (frameOccurrence candidate)))
          activeNodes
      let visibleIds = Set.fromList (map expandedNodeId visibleNodes)
          previousCandidates =
            [ earlier
            | earlier <- candidatesBefore candidate
            , frameCandidateKey earlier `Set.member` includedKeys
            ]
          previousVisible =
            case reverse previousCandidates of
              [] -> Set.empty
              previous:_ ->
                Set.fromList
                  [ expandedNodeId node
                  | node <- activeNodes
                  , fromRight
                      False
                      (nodeVisibleAt
                         trace
                         (Sem.stepOccurrenceEnd (frameOccurrence previous))
                         node)
                  ]
          instances =
            [ IR.VisualInstance
              { IR.instanceId = IR.RenderInstanceId instanceIndex
              , IR.instanceElementId = IR.VisualId (expandedNodeId node)
              , IR.instanceOriginElementId =
                  fmap
                    IR.VisualId
                    (elementOrigin
                       trace
                       expanded
                       visibleIds
                       previousVisible
                       node)
              , IR.instanceCodeEmphasisRanges = Nothing
              , IR.instanceFragmentClusters =
                  Just (fragmentClustersFor (frameOccurrence candidate) node)
              }
            | (instanceIndex, node) <- zip [0 :: Int ..] visibleNodes
            ]
          visibleConnectors =
            [ connector'
            | connector' <- activeConnectors
            , concreteNodeId (expandedConnectorStart connector')
                `Set.member` visibleIds
            , concreteNodeId (expandedConnectorEnd connector')
                `Set.member` visibleIds
            , maybe
                True
                (relationActiveAt
                   trace
                   (Sem.stepOccurrenceEnd (frameOccurrence candidate))
                   . Sem.traceRelationId)
                (expandedConnectorRelation connector')
            ]
          connectorInstances =
            [ IR.ConnectorInstance
              { IR.connectorInstanceId = IR.ConnectorInstanceId index
              , IR.connectorInstanceConnectorId =
                  IR.ConnectorId (expandedConnectorId connector')
              , IR.connectorInstanceOriginConnectorId =
                  if connectorWasVisible previousVisible connector'
                    then Just (IR.ConnectorId (expandedConnectorId connector'))
                    else Nothing
              }
            | (index, connector') <- zip [0 :: Int ..] visibleConnectors
            ]
      pure
        IR.TimelineStep
          { IR.stepLabel =
              Sem.traceMarkerType
                (Sem.stepOccurrenceDefinition (frameOccurrence candidate))
          , IR.stepInstances = instances
          , IR.stepOccurrenceKey =
              Just (IR.FrameOccurrenceKey (frameCandidateKey candidate))
          , IR.stepOrdinal = Just (frameOrdinal candidate)
          , IR.stepParentOccurrenceKey =
              IR.FrameOccurrenceKey
                <$> nearestIncludedParentWithTrace
                      trace
                      includedKeys
                      (frameOccurrence candidate)
          , IR.stepConnectorInstances = Just connectorInstances
          }
      where
        connectorWasVisible previous connector' =
          concreteNodeId (expandedConnectorStart connector')
            `Set.member` previous
            && concreteNodeId (expandedConnectorEnd connector')
                 `Set.member` previous
    fragmentClustersFor occurrence node =
      case Map.lookup (expandedNodeId node) typography of
        Nothing -> []
        Just materialized ->
          Typography.activeFragmentClusters
            (activeStepNames occurrence)
            (materializedFontSize materialized)
            (materializedTextLayout materialized)
            (materializedPreparedLine materialized)
    activeStepNames occurrence =
      Set.fromList
        [ Sem.traceMarkerType (Sem.stepOccurrenceDefinition candidate)
        | candidate <- Sem.semanticTraceSteps trace
        , Sem.stepOccurrencePath candidate
            `isPrefixOf` Sem.stepOccurrencePath occurrence
        ]
    candidatesBefore candidate =
      takeWhile
        ((/= frameCandidateKey candidate) . frameCandidateKey)
        (frameCandidates trace plan)

data FrameCandidate = FrameCandidate
  { frameDeclaration :: R.FrameDeclaration
  , frameOccurrence  :: Sem.StepOccurrence
  , frameOrdinal     :: Int
  }

frameCandidates :: Sem.SemanticTrace -> R.RenderPlan -> [FrameCandidate]
frameCandidates trace plan =
  [ FrameCandidate declaration occurrence ordinal
  | (ordinal, (declaration, occurrence)) <- zip [0 :: Int ..] ordered
  ]
  where
    ordered =
      sortOn
        (\(_, occurrence) ->
           (Sem.stepOccurrenceEnd occurrence, Sem.stepOccurrencePath occurrence))
        [ (declaration, occurrence)
        | occurrence <- Sem.semanticTraceSteps trace
        , declaration <- R.planFrames plan
        , R.frameStepIdentity declaration
            == Sem.traceMarkerType (Sem.stepOccurrenceDefinition occurrence)
        ]

frameCandidateKey :: FrameCandidate -> String
frameCandidateKey candidate = occurrenceKey (frameOccurrence candidate)

occurrenceKey :: Sem.StepOccurrence -> String
occurrenceKey occurrence =
  Sem.traceMarkerType (Sem.stepOccurrenceDefinition occurrence)
    ++ "@"
    ++ intercalate "." (map show (Sem.stepOccurrencePath occurrence))

-- Parent occurrences may have a different step definition, so resolve keys
-- by path rather than manufacturing one with the child's definition.
nearestIncludedParentWithTrace ::
     Sem.SemanticTrace -> Set String -> Sem.StepOccurrence -> Maybe String
nearestIncludedParentWithTrace trace included occurrence =
  let ancestorPaths =
        reverse [take length' path | length' <- [1 .. length path - 1]]
      path = Sem.stepOccurrencePath occurrence
   in find
        (`Set.member` included)
        [ occurrenceKey ancestor
        | ancestorPath <- ancestorPaths
        , ancestor <- Sem.semanticTraceSteps trace
        , Sem.stepOccurrencePath ancestor == ancestorPath
        ]

nodeVisibleAt ::
     Sem.SemanticTrace -> Int -> ExpandedNode -> Either RenderCompileError Bool
nodeVisibleAt trace offset node =
  pure
    (all (checkActive trace offset) (contextChecks (expandedNodeContext node)))

checkActive :: Sem.SemanticTrace -> Int -> LifetimeCheck -> Bool
checkActive trace offset check =
  case check of
    BlockLifetime identifier ->
      maybe
        False
        (intervalActive offset . blockInterval)
        (lookupTraceBlock identifier trace)
    OccupancyLifetime occupancy ->
      intervalActive
        offset
        (Sem.traceOccupancyStart occupancy, Sem.traceOccupancyEnd occupancy)
    RelationLifetime identifier -> relationActiveAt trace offset identifier

blockInterval :: Sem.TraceBlock -> (Int, Maybe Int)
blockInterval block = (Sem.traceBlockBorn block, Sem.traceBlockEnded block)

intervalActive :: Int -> (Int, Maybe Int) -> Bool
intervalActive offset (start, end) =
  start < offset && maybe True (>= offset) end

relationActiveAt :: Sem.SemanticTrace -> Int -> Int -> Bool
relationActiveAt trace offset identifier =
  case find
         ((== identifier) . Sem.traceRelationId)
         (Sem.semanticTraceRelations trace) of
    Nothing -> False
    Just relation' ->
      intervalActive
        offset
        (Sem.traceRelationStart relation', Sem.traceRelationEnd relation')

elementOrigin ::
     Sem.SemanticTrace
  -> ExpandedPlan
  -> Set Int
  -> Set Int
  -> ExpandedNode
  -> Maybe Int
elementOrigin trace expanded visibleIds previousVisible node
  | expandedNodeId node `Set.member` previousVisible =
    Just (expandedNodeId node)
  | otherwise = do
    block <- expandedNodeSemanticBlock node
    origin <- blockOrigin trace block
    source <- originSource origin
    expandedNodeId
      <$> find
            (\candidate ->
               expandedNodeDeclaration candidate == expandedNodeDeclaration node
                 && expandedNodeSemanticBlock candidate == Just source
                 && expandedNodeId candidate `Set.member` visibleIds)
            (expandedNodes expanded)
  where
    originSource origin =
      case origin of
        Sem.CreatedOrigin                        -> Nothing
        Sem.CopiedOrigin source                  -> Just source
        Sem.ReplacedOrigin source                -> Just source
        Sem.Applied1Origin _operator argument    -> Just argument
        Sem.Applied2Origin _operator left _right -> Just left

blockOrigin ::
     Sem.SemanticTrace -> Sem.BlockId -> Maybe Sem.MaterializationOrigin
blockOrigin trace identifier =
  case [ origin
       | Sem.TraceMaterialized _ block origin <- Sem.semanticTraceEvents trace
       , block == identifier
       ] of
    origin:_ -> Just origin
    []       -> Nothing

deterministicPresence :: Int -> R.PresenceId -> [Int] -> Bool
deterministicPresence seed presence path =
  let IR.Sha256 digest =
        Resource.sha256Bytes
          (Text.encodeUtf8
             (Text.pack
                (show seed
                   ++ ":"
                   ++ showPresenceId presence
                   ++ ":"
                   ++ intercalate "." (map show path))))
   in case digest of
        first:_ -> first `elem` ("02468ace" :: String)
        []      -> False

guardsActive ::
     Sem.SemanticTrace
  -> R.RenderPlan
  -> ExpandedPlan
  -> S.Solution
  -> ExpansionContext
  -> [R.PresenceGuard]
  -> Either RenderCompileError Bool
guardsActive trace plan expanded solution context guards = do
  resolved <- traverse (resolveGuard trace plan expanded context) (nub guards)
  pure (all active resolved)
  where
    active GuardAlways = True
    active GuardNever = False
    active (GuardDecision name _ required) =
      Map.lookup name (S.solutionChoices solution) == Just required

compileSamplingProvenance :: S.Solution -> IR.SamplingProvenance
compileSamplingProvenance solution =
  case S.solutionSampling solution of
    S.SampledWith strategy coverage ->
      IR.SamplingProvenance
        { IR.samplingMode =
            case strategy of
              S.BalancedDesignChoices -> IR.BalancedChoices
              S.GeometricVolume _     -> IR.GeometricMeasure
        , IR.samplingCoverage =
            case coverage of
              S.EnumeratedDecisions     -> IR.ExactEnumeration
              S.MipConditionedDecisions -> IR.MipConditioning
        }
    S.LegacySampling ->
      IR.SamplingProvenance
        { IR.samplingMode = IR.BalancedChoices
        , IR.samplingCoverage = IR.ExactEnumeration
        }

compileVariables :: S.Solution -> [IR.CspVariable]
compileVariables solution =
  [ IR.CspVariable (IR.CspVariableId name) (IR.CspNumber (roundLayout value))
  | (name, value) <- Map.toAscList (S.solutionValues solution)
  ]
    ++ [ IR.CspVariable (IR.CspVariableId name) (IR.CspCategory value)
       | (name, value) <- Map.toAscList (S.solutionChoices solution)
       ]

compileAutomaticStyleVariables ::
     ExpandedPlan -> S.Solution -> [ExpandedNode] -> [IR.CspVariable]
compileAutomaticStyleVariables expanded solution activeNodes =
  Map.elems
    (Map.fromList
       [ (family, profileVariable family)
       | node <- activeNodes
       , let concrete = ConcreteVisual node
       , automaticStyleEligible expanded concrete
       , Just family <- [automaticStyleFamily concrete]
       ])
  where
    seed = randomSeedInt (S.solutionSeed solution)
    profileVariable family =
      IR.CspVariable
        { IR.cspVariableId =
            IR.CspVariableId ("render.theme." ++ family ++ ".leaf.profile")
        , IR.cspVariableValue =
            IR.CspCategory
              (Theme.leafProfileToken (Theme.leafProfileFor seed family))
        }

deduplicateResources :: [Resource.ResourceBlob] -> [Resource.ResourceBlob]
deduplicateResources = Map.elems . Map.fromList . map keyed
  where
    keyed resource =
      ( IR.resourceDescriptorId (Resource.resourceBlobDescriptor resource)
      , resource)

-- Frame omission is deliberately sampled per runtime occurrence, outside the
-- affine branch count.  Recording each result as a categorical variable makes
-- that second stochastic layer explicit and reproducible in IR provenance.
compileFramePresenceVariables ::
     Sem.SemanticTrace -> R.RenderPlan -> S.Solution -> [IR.CspVariable]
compileFramePresenceVariables trace plan solution =
  [ IR.CspVariable
    { IR.cspVariableId =
        IR.CspVariableId
          ("render.frame-presence."
             ++ showPresenceId presence
             ++ "."
             ++ occurrenceKey occurrence)
    , IR.cspVariableValue =
        IR.CspCategory
          (if deterministicPresence
                viewSeed
                presence
                (Sem.stepOccurrencePath occurrence)
             then "include"
             else "omit")
    }
  | declaration <- R.planFrames plan
  , Just presence <- [R.framePresence declaration]
  , occurrence <- Sem.semanticTraceSteps trace
  , R.frameStepIdentity declaration
      == Sem.traceMarkerType (Sem.stepOccurrenceDefinition occurrence)
  ]
  where
    viewSeed = randomSeedInt (S.solutionSeed solution)

evaluateExpr :: S.Solution -> SolverExpr -> Either RenderCompileError Double
evaluateExpr solution expression =
  maybe
    (leftInvalid "solver result omitted a Render expression")
    Right
    (S.evalExpr solution expression)

randomSeedInt :: S.RandomSeed -> Int
randomSeedInt (S.RandomSeed value) = value

requireSingle :: String -> [value] -> Either RenderCompileError value
requireSingle operation values =
  case values of
    [value] -> pure value
    [] -> leftInvalid (operation ++ " has no context-local mapping")
    _ -> leftInvalid (operation ++ " has ambiguous context-local mappings")

canonicalHue :: Double -> Double
canonicalHue value =
  let wrapped = value - 360 * fromIntegral (floor (value / 360) :: Int)
   in if abs (wrapped - 360) < 1e-9
        then 0
        else roundLayout wrapped

clampUnit :: Double -> Double
clampUnit = roundLayout . max 0 . min 1

roundLayout :: Double -> Double
roundLayout value = fromIntegral (round (value * 1000000) :: Integer) / 1000000
