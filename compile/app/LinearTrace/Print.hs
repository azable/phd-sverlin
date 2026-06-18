{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE EmptyCase            #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE GADTs                #-}
{-# LANGUAGE OverloadedStrings    #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module LinearTrace.Print
  ( PrintEvent(..)
  , PrintEvents(..)
  , printGraph
  , printTrace
  , printVisualization
  , printSolvedVisualization
  , printVisualizationCSPSolution
  ) where

import qualified Data.Map.Strict                  as Map
import           LinearTrace.Core
import qualified LinearTrace.Solver               as S
import qualified LinearTrace.View                  as V
import           Numeric                          (showFFloat)
import           Prelude
import           Prettyprinter
import           Prettyprinter.Render.String      (renderString)

--------------------------------------------------------------------------------
-- Layout constants
--------------------------------------------------------------------------------
eventIndexWidth :: Int
eventIndexWidth = 3

blockListRefWidth :: Int
blockListRefWidth = 8

snapshotRefWidth :: Int
snapshotRefWidth = 6

stepNameWidth :: Int
stepNameWidth = 16

styleFieldWidth :: Int
styleFieldWidth = 18

stepIndentWidth :: Int
stepIndentWidth = 4

stepIndent :: Doc ann
stepIndent = pretty (replicate stepIndentWidth ' ')

--------------------------------------------------------------------------------
-- Colour/style constants
--------------------------------------------------------------------------------
eventTitleStyle :: [Ansi]
eventTitleStyle = [AnsiBold]

createStyle :: StepStyle
createStyle = StepStyle "create" createColour

observeStyle :: StepStyle
observeStyle = StepStyle "observe" observeColour

inspectStyle :: StepStyle
inspectStyle = StepStyle "inspect" inspectColour

useStyle :: StepStyle
useStyle = StepStyle "use" useColour

copyStyle :: StepStyle
copyStyle = StepStyle "copy" copyColour

replaceStyle :: StepStyle
replaceStyle = StepStyle "replace" replaceColour

computeStyle :: StepStyle
computeStyle = StepStyle "compute" computeColour

destroyStyle :: StepStyle
destroyStyle = StepStyle "destroy" destroyColour

sealStyle :: StepStyle
sealStyle = StepStyle "seal" sealColour

unsealStyle :: StepStyle
unsealStyle = StepStyle "unseal" unsealColour

decideStyle :: StepStyle
decideStyle = StepStyle "decide" decideColour

createColour :: Ansi
createColour = Ansi256Fg 82

observeColour :: Ansi
observeColour = Ansi256Fg 51

inspectColour :: Ansi
inspectColour = Ansi256Fg 123

useColour :: Ansi
useColour = Ansi256Fg 220

copyColour :: Ansi
copyColour = Ansi256Fg 75

replaceColour :: Ansi
replaceColour = Ansi256Fg 171

computeColour :: Ansi
computeColour = Ansi256Fg 118

destroyColour :: Ansi
destroyColour = Ansi256Fg 196

sealColour :: Ansi
sealColour = Ansi256Fg 37

unsealColour :: Ansi
unsealColour = Ansi256Fg 208

decideColour :: Ansi
decideColour = Ansi256Fg 201

--------------------------------------------------------------------------------
-- Event printing
--------------------------------------------------------------------------------
class PrintEvent event where
  printEvent :: event -> String

class PrintEvents events where
  printEventChoice :: EventChoice events acts -> String

instance PrintEvents '[] where
  printEventChoice choice = case choice of {}

instance (PrintEvent event, PrintEvents events) => PrintEvents (event : events) where
  printEventChoice choice =
    case choice of
      Here event -> printEvent event
      There rest -> printEventChoice rest

--------------------------------------------------------------------------------
-- Public rendering API
--------------------------------------------------------------------------------
printGraph :: PrintEvents events => TraceGraph events -> IO ()
printGraph graph = putStr (renderGraph graph)

printTrace :: PrintEvents events => TraceGraph events -> IO ()
printTrace graph = putStr (renderTrace graph)

printVisualization :: PrintEvents events => V.ViewGraph events -> IO ()
printVisualization graph = putStr (renderVisualization True Nothing graph)

printSolvedVisualization ::
     PrintEvents events => Bool -> S.Solution -> V.ViewGraph events -> IO ()
printSolvedVisualization showDetails solution graph =
  putStr (renderVisualization showDetails (Just solution) graph)

printVisualizationCSPSolution :: S.Solution -> IO ()
printVisualizationCSPSolution solution = putStr (renderSolution solution)

--------------------------------------------------------------------------------
-- Graph rendering
--------------------------------------------------------------------------------
renderGraph :: PrintEvents events => TraceGraph events -> String
renderGraph = renderDoc . graphDoc

graphDoc :: PrintEvents events => TraceGraph events -> RenderDoc
graphDoc (TraceGraph blocks events) =
  mconcat
    [ headerDoc "Graph"
    , summaryDoc blocks events
    , hardline
    , blocksDoc blocks
    , hardline
    , eventsDoc events
    ]

renderTrace :: PrintEvents events => TraceGraph events -> String
renderTrace = renderDoc . traceDoc

traceDoc :: PrintEvents events => TraceGraph events -> RenderDoc
traceDoc (TraceGraph _ events) = eventsDoc events

--------------------------------------------------------------------------------
-- Visualization rendering
--------------------------------------------------------------------------------
renderVisualization ::
     PrintEvents events
  => Bool
  -> Maybe S.Solution
  -> V.ViewGraph events
  -> String
renderVisualization showDetails maybeSolution =
  renderDoc . visualizationDoc showDetails maybeSolution

visualizationDoc ::
     PrintEvents events
  => Bool
  -> Maybe S.Solution
  -> V.ViewGraph events
  -> RenderDoc
visualizationDoc showDetails maybeSolution graph =
  mconcat
    [ headerDoc "Visualization"
    , visualizationSummaryDoc nodes steps constraints initialVars
    , maybeSolutionSummaryDoc maybeSolution
    , hardline
    , whenDoc
        showDetails
        (mconcat [viewNodesDoc nodes, hardline, initialVarsDoc initialVars])
    , viewTraceDoc showDetails maybeSolution steps
    ]
  where
    nodes = V.viewNodes graph
    steps = V.viewSteps graph
    constraints = V.viewConstraints graph
    initialVars = V.viewInitialVars graph

maybeSolutionSummaryDoc :: Maybe S.Solution -> RenderDoc
maybeSolutionSummaryDoc maybeSolution =
  case maybeSolution of
    Nothing -> mempty
    Just solution ->
      vsep
        [ "Solved:" <+> pretty (show (S.solutionSuccess solution))
        , "Energy:" <+> pretty (formatSignedDouble (S.solutionEnergy solution))
        ] <> hardline

--------------------------------------------------------------------------------
-- Standalone solution rendering
--------------------------------------------------------------------------------
renderSolution :: S.Solution -> String
renderSolution = renderDoc . solutionDoc

solutionDoc :: S.Solution -> RenderDoc
solutionDoc solution =
  mconcat
    [ headerDoc "Solution"
    , solutionSummaryDoc solution
    , hardline
    , solutionValuesDoc (S.solutionValues solution)
    ]

solutionSummaryDoc :: S.Solution -> RenderDoc
solutionSummaryDoc solution =
  vsep
    [ "Success:" <+> pretty (show (S.solutionSuccess solution))
    , "Energy:" <+> pretty (formatSignedDouble (S.solutionEnergy solution))
    , "Variables:" <+> pretty (show (Map.size (S.solutionValues solution)))
    ] <> hardline

solutionValuesDoc :: Map.Map String Double -> RenderDoc
solutionValuesDoc values =
  headerDoc "Solution values"
    <> alignedAssignmentsDoc
         "  "
         [ (name, formatSignedDouble value)
         | (name, value) <- Map.toAscList values
         ]

--------------------------------------------------------------------------------
-- Summary
--------------------------------------------------------------------------------
summaryDoc :: [BlockRecord] -> [RecordedEvent events] -> RenderDoc
summaryDoc blocks events =
  vsep
    [ "Blocks:" <+> pretty (show (length blocks))
    , "Events:" <+> pretty (show (length events))
    ] <> hardline

visualizationSummaryDoc ::
     [V.ViewNode]
  -> [V.ViewStep events]
  -> [S.Constraint]
  -> [S.InitialVar]
  -> RenderDoc
visualizationSummaryDoc nodes steps constraints initialVars =
  vsep
    [ "View nodes:" <+> pretty (show (length nodes))
    , "View steps:" <+> pretty (show (length steps))
    , "Constraints:" <+> pretty (show (length (flattenConstraints constraints)))
    , "Initial vars:" <+> pretty (show (length initialVars))
    ] <> hardline

--------------------------------------------------------------------------------
-- Blocks
--------------------------------------------------------------------------------
blocksDoc :: [BlockRecord] -> RenderDoc
blocksDoc blocks = headerDoc "Blocks" <> mconcat (map blockDoc blocks)

blockDoc :: BlockRecord -> RenderDoc
blockDoc (BlockRecord snapshot) =
  "  "
    <> fixedWidth blockListRefWidth (renderBlockRefPlain (snapshotRef snapshot))
    <> pretty (renderSnapshotPayload snapshot)
    <> hardline

--------------------------------------------------------------------------------
-- View nodes
--------------------------------------------------------------------------------
viewNodesDoc :: [V.ViewNode] -> RenderDoc
viewNodesDoc nodes = headerDoc "View nodes" <> mconcat (map viewNodeDoc nodes)

viewNodeDoc :: V.ViewNode -> RenderDoc
viewNodeDoc node =
  case node of
    V.BlockViewNode block -> blockViewDoc block

blockViewDoc :: V.BlockView tag -> RenderDoc
blockViewDoc block =
  mconcat
    [ "  "
    , fixedWidth blockListRefWidth (renderBlockRefPlain (V.blockRef block))
    , pretty (renderPayloadView (V.blockLabel block))
    , hardline
    , styleDoc (V.blockStyle block)
    ]

styleDoc :: V.Style -> RenderDoc
styleDoc style =
  mconcat
    [ stepIndent
    , "style"
    , hardline
    , mconcat (V.mapStyleExprLeaves styleFieldDoc style)
    ]

styleFieldDoc :: String -> S.Expr ty -> RenderDoc
styleFieldDoc name expr =
  stepIndent
    <> stepIndent
    <> fixedWidth styleFieldWidth name
    <> " = "
    <> exprDoc expr
    <> hardline

--------------------------------------------------------------------------------
-- Initial variables
--------------------------------------------------------------------------------
initialVarsDoc :: [S.InitialVar] -> RenderDoc
initialVarsDoc initialVars =
  case initialVars of
    [] -> mempty
    _ ->
      mconcat
        [ headerDoc "Initial variables"
        , alignedAssignmentsDoc
            "  "
            [ (name, renderInitialVarValue ty bounds)
            | S.InitialVar name ty bounds <- initialVars
            ]
        , hardline
        ]

renderInitialVarValue :: S.ScalarType -> S.InitialBounds -> String
renderInitialVarValue ty bounds =
  S.typeName ty ++ " " ++ renderInitialBounds bounds

renderInitialBounds :: S.InitialBounds -> String
renderInitialBounds bounds =
  case (S.initialLower bounds, S.initialUpper bounds) of
    (Just lo, Just hi) -> "[" ++ fixed2 lo ++ ", " ++ fixed2 hi ++ "]"
    (Just lo, Nothing) -> "[" ++ fixed2 lo ++ ", ∞)"
    (Nothing, Just hi) -> "(-∞, " ++ fixed2 hi ++ "]"
    (Nothing, Nothing) -> "(-∞, ∞)"

--------------------------------------------------------------------------------
-- View constraints
--------------------------------------------------------------------------------
data RenderedConstraint = RenderedConstraint
  { renderedConstraintLhs :: String
  , renderedConstraintOp  :: String
  , renderedConstraintRhs :: String
  }

flattenConstraints :: [S.Constraint] -> [S.Constraint]
flattenConstraints = concatMap S.flattenConstraint

renderConstraintParts :: S.Constraint -> RenderedConstraint
renderConstraintParts constraint =
  case constraint of
    S.Equals ty lhs rhs ->
      RenderedConstraint
        { renderedConstraintLhs = renderRawExpr lhs
        , renderedConstraintOp = renderEqualityOperator ty
        , renderedConstraintRhs = renderEqualityRhs ty rhs
        }
    S.LessOrEqual lhs rhs ->
      RenderedConstraint
        { renderedConstraintLhs = renderRawExpr lhs
        , renderedConstraintOp = "<="
        , renderedConstraintRhs = renderRawExpr rhs
        }
    S.Minimize expr ->
      RenderedConstraint
        { renderedConstraintLhs = ""
        , renderedConstraintOp = "minimize"
        , renderedConstraintRhs = renderRawExpr expr
        }
    S.All constraints ->
      RenderedConstraint
        { renderedConstraintLhs = ""
        , renderedConstraintOp = "all"
        , renderedConstraintRhs =
            show (length (flattenConstraints constraints)) ++ " constraints"
        }

renderEqualityOperator :: S.ScalarType -> String
renderEqualityOperator ty =
  case S.typeCircularPeriod ty of
    Nothing -> "=="
    Just _  -> "≡"

renderEqualityRhs :: S.ScalarType -> S.RawExpr -> String
renderEqualityRhs ty rhs =
  case S.typeCircularPeriod ty of
    Nothing     -> renderRawExpr rhs
    Just period -> renderRawExpr rhs ++ " (mod " ++ fixed2 period ++ ")"

stepConstraintsDoc :: [S.Constraint] -> RenderDoc
stepConstraintsDoc constraints =
  let visibleConstraints =
        filter constraintMentionsVar (flattenConstraints constraints)
   in case visibleConstraints of
        [] -> mempty
        _ ->
          mconcat
            [ stepIndent
            , "constraints"
            , hardline
            , indentedConstraintsDoc visibleConstraints
            , hardline
            ]

indentedConstraintsDoc :: [S.Constraint] -> RenderDoc
indentedConstraintsDoc constraints =
  let rendered = map renderConstraintParts constraints
      lhsWidth =
        maximum
          (0
             : [ length (renderedConstraintLhs constraint)
               | constraint <- rendered
               ])
      opWidth =
        maximum
          (0
             : [ length (renderedConstraintOp constraint)
               | constraint <- rendered
               ])
   in mconcat (map (indentedConstraintDoc lhsWidth opWidth) rendered)

indentedConstraintDoc :: Int -> Int -> RenderedConstraint -> RenderDoc
indentedConstraintDoc lhsWidth opWidth constraint =
  mconcat
    [ stepIndent
    , stepIndent
    , fixedWidth lhsWidth (renderedConstraintLhs constraint)
    , " "
    , fixedWidth opWidth (renderedConstraintOp constraint)
    , " "
    , pretty (renderedConstraintRhs constraint)
    , hardline
    ]

constraintMentionsVar :: S.Constraint -> Bool
constraintMentionsVar constraint =
  case constraint of
    S.Equals _ lhs rhs    -> rawExprMentionsVar lhs || rawExprMentionsVar rhs
    S.LessOrEqual lhs rhs -> rawExprMentionsVar lhs || rawExprMentionsVar rhs
    S.Minimize expr       -> rawExprMentionsVar expr
    S.All constraints     -> any constraintMentionsVar constraints

rawExprMentionsVar :: S.RawExpr -> Bool
rawExprMentionsVar expr =
  case expr of
    S.EVar _ _      -> True
    S.ELit _        -> False
    S.EAdd lhs rhs  -> rawExprMentionsVar lhs || rawExprMentionsVar rhs
    S.ESub lhs rhs  -> rawExprMentionsVar lhs || rawExprMentionsVar rhs
    S.EMul lhs rhs  -> rawExprMentionsVar lhs || rawExprMentionsVar rhs
    S.EDiv lhs rhs  -> rawExprMentionsVar lhs || rawExprMentionsVar rhs
    S.ENeg inner    -> rawExprMentionsVar inner
    S.EAbs inner    -> rawExprMentionsVar inner
    S.ESignum inner -> rawExprMentionsVar inner
    S.EPow base to  -> rawExprMentionsVar base || rawExprMentionsVar to

--------------------------------------------------------------------------------
-- Solved view values
--------------------------------------------------------------------------------
data SolvedExpr =
  SolvedExpr String Double

stepSolutionDoc ::
     Maybe S.Solution -> [V.ViewNode] -> [S.Constraint] -> RenderDoc
stepSolutionDoc maybeSolution nodes _constraints =
  case maybeSolution of
    Nothing -> mempty
    Just solution ->
      let solved =
            dedupeSolvedExprs (concatMap (solveViewNodeExprs solution) nodes)
       in case solved of
            [] -> mempty
            _ ->
              mconcat
                [ stepIndent
                , "solution"
                , hardline
                , solvedExprsDoc solved
                , hardline
                ]

solveViewNodeExprs :: S.Solution -> V.ViewNode -> [SolvedExpr]
solveViewNodeExprs solution node =
  case node of
    V.BlockViewNode block -> solveBlockViewExprs solution block

solveBlockViewExprs :: S.Solution -> V.BlockView tag -> [SolvedExpr]
solveBlockViewExprs solution block =
  let blockName = renderBlockRefPlain (V.blockRef block)
   in [ SolvedExpr (blockName ++ "." ++ name) value
      | (name, value) <- V.solvedStyleExprs solution (V.blockStyle block)
      ]

dedupeSolvedExprs :: [SolvedExpr] -> [SolvedExpr]
dedupeSolvedExprs = go []
  where
    go _ [] = []
    go seen (solved@(SolvedExpr name _):rest)
      | name `elem` seen = go seen rest
      | otherwise = solved : go (name : seen) rest

solvedExprsDoc :: [SolvedExpr] -> RenderDoc
solvedExprsDoc solved =
  alignedAssignmentsDoc
    (replicate (stepIndentWidth * 2) ' ')
    [(name, formatSignedDouble value) | SolvedExpr name value <- solved]

--------------------------------------------------------------------------------
-- View trace
--------------------------------------------------------------------------------
viewTraceDoc ::
     PrintEvents events
  => Bool
  -> Maybe S.Solution
  -> [V.ViewStep events]
  -> RenderDoc
viewTraceDoc showDetails maybeSolution steps =
  headerDoc "View trace"
    <> mconcat
         (zipWith
            (viewTraceStepDoc showDetails maybeSolution)
            [0 :: Int ..]
            steps)

viewTraceStepDoc ::
     PrintEvents events
  => Bool
  -> Maybe S.Solution
  -> Int
  -> V.ViewStep events
  -> RenderDoc
viewTraceStepDoc showDetails maybeSolution ix step =
  case step of
    V.ViewStep event nodes constraints ->
      eventDoc ix event
        <> whenDoc
             showDetails
             (mconcat
                [ stepViewNodesDoc nodes
                , stepConstraintsDoc constraints
                , stepSolutionDoc maybeSolution nodes constraints
                ])

stepViewNodesDoc :: [V.ViewNode] -> RenderDoc
stepViewNodesDoc nodes =
  case nodes of
    [] -> mempty
    _ ->
      mconcat
        [ stepIndent
        , "view nodes"
        , hardline
        , mconcat (map indentedViewNodeDoc nodes)
        , hardline
        ]

indentedViewNodeDoc :: V.ViewNode -> RenderDoc
indentedViewNodeDoc node =
  case node of
    V.BlockViewNode block ->
      mconcat
        [ stepIndent
        , stepIndent
        , pretty (renderBlockRefPlain (V.blockRef block))
        , " "
        , pretty (renderPayloadView (V.blockLabel block))
        , hardline
        ]

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
eventsDoc :: PrintEvents events => [RecordedEvent events] -> RenderDoc
eventsDoc events =
  headerDoc "Events" <> mconcat (zipWith eventDoc [0 :: Int ..] events)

eventDoc :: PrintEvents events => Int -> RecordedEvent events -> RenderDoc
eventDoc ix (RecordedEvent event audit) =
  mconcat
    [ fixedLeft eventIndexWidth ("E" ++ show ix)
    , " | "
    , pretty (ansiText eventTitleStyle (printEventChoice event))
    , hardline
    , auditDoc audit
    , hardline
    ]

--------------------------------------------------------------------------------
-- Audit rendering
--------------------------------------------------------------------------------
auditDoc :: Audit acts -> RenderDoc
auditDoc EmptyAudit     = mempty
auditDoc (step :> rest) = auditStepDoc step <> auditDoc rest

auditStepDoc :: AuditStep act -> RenderDoc
auditStepDoc step =
  case step of
    CreateStep snapshot -> snapshotStep1Doc createStyle snapshot
    ObserveStep snapshot -> snapshotStep1Doc observeStyle snapshot
    InspectStep snapshot -> snapshotStep1Doc inspectStyle snapshot
    UseStep snapshot -> snapshotStep1Doc useStyle snapshot
    CopyStep original copy' -> snapshotStep2Doc copyStyle original copy'
    ReplaceStep old incoming output ->
      snapshotStep3Doc replaceStyle old incoming output
    ComputeStep snapshot -> snapshotStep1Doc computeStyle snapshot
    DestroyStep snapshot -> snapshotStep1Doc destroyStyle snapshot
    SealStep owner child -> snapshotStep2Doc sealStyle owner child
    UnsealStep owner child -> snapshotStep2Doc unsealStyle owner child
    DecideStep snapshot -> snapshotStep1Doc decideStyle snapshot

snapshotStep1Doc :: StepStyle -> BlockSnapshot tag -> RenderDoc
snapshotStep1Doc style snapshot =
  renderStepName style <+> snapshotDoc snapshot <> hardline

snapshotStep2Doc ::
     StepStyle -> BlockSnapshot first -> BlockSnapshot second -> RenderDoc
snapshotStep2Doc style first second =
  mconcat
    [ renderStepName style <+> snapshotDoc first
    , hardline
    , renderEmptyStepName <+> snapshotDoc second
    , hardline
    ]

snapshotStep3Doc ::
     StepStyle
  -> BlockSnapshot first
  -> BlockSnapshot second
  -> BlockSnapshot third
  -> RenderDoc
snapshotStep3Doc style first second third =
  mconcat
    [ renderStepName style <+> snapshotDoc first
    , hardline
    , renderEmptyStepName <+> snapshotDoc second
    , hardline
    , renderEmptyStepName <+> snapshotDoc third
    , hardline
    ]

--------------------------------------------------------------------------------
-- Snapshot rendering
--------------------------------------------------------------------------------
snapshotDoc :: BlockSnapshot tag -> RenderDoc
snapshotDoc snapshot =
  fixedWidth snapshotRefWidth (renderBlockRef (snapshotRef snapshot))
    <> " "
    <> pretty (renderSnapshotPayload snapshot)

renderSnapshotPayload :: BlockSnapshot tag -> String
renderSnapshotPayload (BlockSnapshot _ _ view) = renderPayloadView view

snapshotRef :: BlockSnapshot tag -> BlockRef tag
snapshotRef (BlockSnapshot ref _ _) = ref

renderBlockRef :: BlockRef tag -> String
renderBlockRef (BlockRef blockId) = "[B" ++ show blockId ++ "]"

renderBlockRefPlain :: BlockRef tag -> String
renderBlockRefPlain (BlockRef blockId) = "B" ++ show blockId

renderPayloadView :: PayloadView -> String
renderPayloadView (PayloadView kind content) = kind ++ ": " ++ content

--------------------------------------------------------------------------------
-- Expression rendering
--------------------------------------------------------------------------------
exprDoc :: S.Expr ty -> RenderDoc
exprDoc = rawExprDoc . S.exprRaw

renderRawExpr :: S.RawExpr -> String
renderRawExpr = renderDoc . rawExprDoc

rawExprDoc :: S.RawExpr -> RenderDoc
rawExprDoc = rawExprDocPrec 0

rawExprDocPrec :: Int -> S.RawExpr -> RenderDoc
rawExprDocPrec precedence expr =
  case expr of
    S.EVar _ variable -> pretty (S.varName variable)
    S.ELit value -> pretty (fixed2 value)
    S.EAdd lhs rhs ->
      parenthesizeDoc
        (precedence > addPrecedence)
        (rawExprDocPrec addPrecedence lhs
           <+> "+"
           <+> rawExprDocPrec addPrecedence rhs)
    S.ESub lhs rhs ->
      parenthesizeDoc
        (precedence > addPrecedence)
        (rawExprDocPrec addPrecedence lhs
           <+> "-"
           <+> rawExprDocPrec (addPrecedence + 1) rhs)
    S.EMul lhs rhs ->
      parenthesizeDoc
        (precedence > mulPrecedence)
        (rawExprDocPrec mulPrecedence lhs
           <+> "*"
           <+> rawExprDocPrec mulPrecedence rhs)
    S.EDiv lhs rhs ->
      parenthesizeDoc
        (precedence > mulPrecedence)
        (rawExprDocPrec mulPrecedence lhs
           <+> "/"
           <+> rawExprDocPrec (mulPrecedence + 1) rhs)
    S.ENeg inner ->
      parenthesizeDoc
        (precedence > unaryPrecedence)
        ("-" <> rawExprDocPrec unaryPrecedence inner)
    S.EAbs inner -> "abs" <+> rawExprDocPrec unaryPrecedence inner
    S.ESignum inner -> "signum" <+> rawExprDocPrec unaryPrecedence inner
    S.EPow base to ->
      parenthesizeDoc
        (precedence > powerPrecedence)
        (rawExprDocPrec powerPrecedence base
           <+> "^"
           <+> rawExprDocPrec (powerPrecedence + 1) to)

addPrecedence :: Int
addPrecedence = 6

mulPrecedence :: Int
mulPrecedence = 7

unaryPrecedence :: Int
unaryPrecedence = 8

powerPrecedence :: Int
powerPrecedence = 9

parenthesizeDoc :: Bool -> RenderDoc -> RenderDoc
parenthesizeDoc shouldParenthesize doc =
  if shouldParenthesize
    then parens doc
    else doc

--------------------------------------------------------------------------------
-- Text helpers
--------------------------------------------------------------------------------
type RenderDoc = Doc ()

renderDoc :: RenderDoc -> String
renderDoc = renderString . layoutPretty defaultLayoutOptions

headerDoc :: String -> RenderDoc
headerDoc title =
  pretty title <> hardline <> pretty (replicate (length title) '-') <> hardline

whenDoc :: Bool -> RenderDoc -> RenderDoc
whenDoc enabled doc =
  if enabled
    then doc
    else mempty

renderStepName :: StepStyle -> RenderDoc
renderStepName (StepStyle name style) =
  stepIndent <> pretty (ansiText [style] (padLeft stepNameWidth name))

renderEmptyStepName :: RenderDoc
renderEmptyStepName = stepIndent <> fixedLeft stepNameWidth ""

alignedAssignmentsDoc :: String -> [(String, String)] -> RenderDoc
alignedAssignmentsDoc leading assignments =
  let nameWidth = maximum (0 : [length name | (name, _) <- assignments])
   in mconcat (map (alignedAssignmentDoc leading nameWidth) assignments)

alignedAssignmentDoc :: String -> Int -> (String, String) -> RenderDoc
alignedAssignmentDoc leading nameWidth (name, value) =
  pretty leading <> fixedWidth nameWidth name <> " = " <> pretty value <> hardline

fixedWidth :: Int -> String -> Doc ann
fixedWidth targetWidth text =
  pretty text <> pretty (replicate (max 0 (targetWidth - length text)) ' ')

fixedLeft :: Int -> String -> Doc ann
fixedLeft targetWidth text = pretty (padLeft targetWidth text)

padLeft :: Int -> String -> String
padLeft n text = replicate (max 0 (n - length text)) ' ' ++ text

formatSignedDouble :: Double -> String
formatSignedDouble value =
  let cleaned = cleanNegativeZero value
      text = fixed2 (abs cleaned)
   in if cleaned < 0
        then "-" ++ text
        else " " ++ text

fixed2 :: Double -> String
fixed2 value = showFFloat (Just 2) value ""

cleanNegativeZero :: Double -> Double
cleanNegativeZero value =
  if abs value < 0.005
    then 0
    else value

--------------------------------------------------------------------------------
-- ANSI helpers
--------------------------------------------------------------------------------
data StepStyle =
  StepStyle String Ansi

data Ansi
  = AnsiReset
  | AnsiBold
  | Ansi256Fg Int

ansiText :: [Ansi] -> String -> String
ansiText styles text = concatMap ansiCode styles ++ text ++ ansiCode AnsiReset

ansiCode :: Ansi -> String
ansiCode ansi =
  case ansi of
    AnsiReset   -> "\ESC[0m"
    AnsiBold    -> "\ESC[1m"
    Ansi256Fg n -> "\ESC[38;5;" ++ show n ++ "m"
