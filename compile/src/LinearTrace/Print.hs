{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE GADTs                #-}
{-# LANGUAGE UndecidableInstances #-}

-- | Human-readable diagnostics for core traces, view graphs, and solver
-- summaries. The executable and top-level facade use this module for terminal
-- output; JSON output is handled separately by 'LinearTrace.Compile'.
module LinearTrace.Print
  ( -- * Stdout printers
    -- | Convenience printers for direct terminal diagnostics.
    printGraph
  , printTrace
  , printSolutionByStep
  , printSolutionSummary
  , -- * Handle printers
    -- | Handle-parametric printers used by the CLI/app workflow and tests.
    hPrintGraph
  , hPrintTrace
  , hPrintSolutionByStep
  , hPrintSolutionSummary
  ) where

import           Data.Char                 (isDigit)
import           Data.List                 (dropWhileEnd)
import           LinearTrace.Core.Internal
import qualified LinearTrace.View          as V
import           Numeric                   (showFFloat)
import           Prelude
import qualified Solver                    as S
import           System.Console.ANSI       (ConsoleIntensity (..),
                                            ConsoleLayer (..), SGR (..),
                                            hNowSupportsANSI, setSGRCode)
import           System.IO                 (Handle, hPutStr, stdout)
import qualified Text.PrettyPrint.Boxes    as Box

--------------------------------------------------------------------------------
-- Layout constants
--------------------------------------------------------------------------------
traceIndexWidth :: Int
traceIndexWidth = 3

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

--------------------------------------------------------------------------------
-- Colour/style constants
--------------------------------------------------------------------------------
createStyle :: StepStyle
createStyle = StepStyle "create" 82

observeStyle :: StepStyle
observeStyle = StepStyle "observe" 51

useStyle :: StepStyle
useStyle = StepStyle "use" 220

copyStyle :: StepStyle
copyStyle = StepStyle "copy" 75

replaceStyle :: StepStyle
replaceStyle = StepStyle "replace" 171

computeStyle :: StepStyle
computeStyle = StepStyle "compute" 118

destroyStyle :: StepStyle
destroyStyle = StepStyle "destroy" 196

sealStyle :: StepStyle
sealStyle = StepStyle "seal" 37

unsealStyle :: StepStyle
unsealStyle = StepStyle "unseal" 208

decideStyle :: StepStyle
decideStyle = StepStyle "decide" 201

allStepStyles :: [StepStyle]
allStepStyles =
  [ createStyle
  , observeStyle
  , useStyle
  , copyStyle
  , replaceStyle
  , computeStyle
  , destroyStyle
  , sealStyle
  , unsealStyle
  , decideStyle
  ]

data StepStyle = StepStyle
  { stepStyleName   :: String
  , stepStyleColour :: Int
  }

--------------------------------------------------------------------------------
-- Public rendering API
--------------------------------------------------------------------------------
printGraph :: TraceGraphWith payload -> IO ()
printGraph = hPrintGraph stdout

printTrace :: TraceGraphWith payload -> IO ()
printTrace = hPrintTrace stdout

printSolutionByStep :: Bool -> S.Solution -> V.ViewGraph -> IO ()
printSolutionByStep = hPrintSolutionByStep stdout

printSolutionSummary :: S.Solution -> IO ()
printSolutionSummary = hPrintSolutionSummary stdout

hPrintGraph :: Handle -> TraceGraphWith payload -> IO ()
hPrintGraph handle = printReport handle . graphBox

hPrintTrace :: Handle -> TraceGraphWith payload -> IO ()
hPrintTrace handle = printReport handle . traceBox

hPrintSolutionByStep :: Handle -> Bool -> S.Solution -> V.ViewGraph -> IO ()
hPrintSolutionByStep handle showDetails solution =
  printReport handle . solutionByStepBox showDetails solution

hPrintSolutionSummary :: Handle -> S.Solution -> IO ()
hPrintSolutionSummary handle = printReport handle . solutionSummaryBox

printReport :: Handle -> Box.Box -> IO ()
printReport handle box = do
  supportsAnsi <- hNowSupportsANSI handle
  hPutStr handle (renderReport supportsAnsi box)

renderReport :: Bool -> Box.Box -> String
renderReport supportsAnsi box =
  let plain = Box.render box ++ "\n"
   in if supportsAnsi
        then colourReport plain
        else plain

--------------------------------------------------------------------------------
-- Graph rendering
--------------------------------------------------------------------------------
graphBox :: TraceGraphWith payload -> Box.Box
graphBox (TraceGraph blocks steps) =
  sections
    [ sectionBox "Graph" (summaryBox blocks steps)
    , blocksBox blocks
    , stepsBox steps
    ]

traceBox :: TraceGraphWith payload -> Box.Box
traceBox (TraceGraph _ steps) = stepsBox steps

summaryBox :: [BlockRecord] -> [TraceStepWith payload] -> Box.Box
summaryBox blocks steps =
  linesBox
    ["Blocks: " ++ show (length blocks), "Steps: " ++ show (length steps)]

--------------------------------------------------------------------------------
-- Solution rendering
--------------------------------------------------------------------------------
solutionByStepBox :: Bool -> S.Solution -> V.ViewGraph -> Box.Box
solutionByStepBox showDetails solution graph =
  sections
    $ [ sectionBox "Solution" $ viewSummaryBox nodes steps constraints
      , solutionSummaryBox solution
      ]
        ++ detailBoxes
        ++ [viewTraceBox showDetails solution steps]
  where
    nodes = V.viewNodes graph
    steps = V.viewSteps graph
    constraints = V.viewConstraints graph
    detailBoxes
      | showDetails = optionalSection "View nodes" (viewNodesBox nodes)
      | otherwise = []

solutionSummaryBox :: S.Solution -> Box.Box
solutionSummaryBox solution =
  sectionBox "Solution summary"
    $ linesBox
        [ "Solved: " ++ show (S.solutionSuccess solution)
        , "Energy: " ++ formatSignedDouble (S.solutionEnergy solution)
        , "Seed: " ++ show seed
        , "Variables: " ++ show (S.inspectedVariableCount inspection)
        , "Native bounds: " ++ show (S.inspectedNativeBoundCount inspection)
        , "Energy terms: " ++ show (S.inspectedEnergyTermCount inspection)
        , "Raw constraints: " ++ show (S.inspectedRawCount inspection)
        , "Canonical constraints: "
            ++ show (S.inspectedCanonicalCount inspection)
        , "Eliminated constraints: "
            ++ show (S.inspectedEliminatedCount inspection)
        , "Iterations: " ++ show (S.solutionIterations solution)
        , "Function evals: " ++ show (S.solutionFunctionEvaluations solution)
        , "Gradient evals: " ++ show (S.solutionGradientEvaluations solution)
        ]
  where
    V.RandomSeed seed = S.solutionSeed solution
    inspection = S.solutionInspection solution

viewSummaryBox :: [V.ViewNode] -> [V.ViewStep] -> [S.Constraint] -> Box.Box
viewSummaryBox nodes steps constraints =
  linesBox
    [ "View nodes: " ++ show (length nodes)
    , "View steps: " ++ show (length steps)
    , "Constraints: " ++ show (S.constraintCount constraints)
    ]

--------------------------------------------------------------------------------
-- Blocks
--------------------------------------------------------------------------------
blocksBox :: [BlockRecord] -> Box.Box
blocksBox blocks = sectionBox "Blocks" $ tightVcat (map blockBox blocks)

blockBox :: BlockRecord -> Box.Box
blockBox (BlockRecord snapshot) =
  indentBox 2
    $ rowBox
        [ fieldBox
            blockListRefWidth
            (renderBlockRefPlain (snapshotRef snapshot))
        , Box.text (renderSnapshotPayload snapshot)
        ]

--------------------------------------------------------------------------------
-- View nodes
--------------------------------------------------------------------------------
viewNodesBox :: [V.ViewNode] -> Box.Box
viewNodesBox nodes = spacedVcat (map viewNodeBox nodes)

viewNodeBox :: V.ViewNode -> Box.Box
viewNodeBox node =
  case node of
    V.ViewNode viewNode -> nodeBox viewNode

nodeBox :: V.Node tag -> Box.Box
nodeBox node =
  tightVcat
    [ indentBox 2
        $ rowBox
            [ fieldBox blockListRefWidth (renderViewRefPlain (V.nodeRef node))
            , Box.text (renderViewLabel (V.nodeLabel node))
            ]
    , nodeStyleBox node
    ]

nodeStyleBox :: V.Node tag -> Box.Box
nodeStyleBox node =
  stepSectionBox "style"
    $ tightVcat (V.mapNodeStyleExprLeaves styleFieldBox node)

styleFieldBox :: String -> S.Expr ty -> Box.Box
styleFieldBox name expr =
  rowBox [fieldBox styleFieldWidth name, Box.text "=", Box.text (exprText expr)]

--------------------------------------------------------------------------------
-- View constraints
--------------------------------------------------------------------------------
data RenderedConstraint = RenderedConstraint
  { renderedConstraintLhs :: String
  , renderedConstraintOp  :: String
  , renderedConstraintRhs :: String
  }

renderConstraintParts :: S.ConstraintView -> RenderedConstraint
renderConstraintParts constraint =
  case constraint of
    S.ConstraintEqual domain lhs rhs ->
      RenderedConstraint
        { renderedConstraintLhs = rawExprText lhs
        , renderedConstraintOp = renderEqualityOperator domain
        , renderedConstraintRhs = renderEqualityRhs domain rhs
        }
    S.ConstraintLessOrEqual lhs rhs ->
      RenderedConstraint
        { renderedConstraintLhs = rawExprText lhs
        , renderedConstraintOp = "<="
        , renderedConstraintRhs = rawExprText rhs
        }
    S.ConstraintMinimize expr ->
      RenderedConstraint
        { renderedConstraintLhs = ""
        , renderedConstraintOp = "minimize"
        , renderedConstraintRhs = rawExprText expr
        }
    S.ConstraintSoft inner ->
      let rendered = renderConstraintParts inner
       in rendered
            { renderedConstraintOp =
                "encourage " ++ renderedConstraintOp rendered
            }
    S.ConstraintAll constraints ->
      RenderedConstraint
        { renderedConstraintLhs = ""
        , renderedConstraintOp = "all"
        , renderedConstraintRhs = show (length constraints) ++ " constraints"
        }

renderEqualityOperator :: S.Domain -> String
renderEqualityOperator domain =
  case S.domainCircularPeriod domain of
    Nothing -> "=="
    Just _  -> "≡"

renderEqualityRhs :: S.Domain -> S.ExprView -> String
renderEqualityRhs domain rhs =
  case S.domainCircularPeriod domain of
    Nothing     -> rawExprText rhs
    Just period -> rawExprText rhs ++ " (mod " ++ fixed2 period ++ ")"

stepConstraintsBoxes :: [S.Constraint] -> [Box.Box]
stepConstraintsBoxes constraints =
  case filter constraintMentionsVar (S.constraintViews constraints) of
    []      -> []
    visible -> [stepSectionBox "constraints" (constraintTableBox visible)]

constraintTableBox :: [S.ConstraintView] -> Box.Box
constraintTableBox constraints = tightVcat (map row rendered)
  where
    rendered = map renderConstraintParts constraints
    lhsWidth =
      maximum
        (0
           : [ length (renderedConstraintLhs constraint)
             | constraint <- rendered
             ])
    opWidth =
      maximum
        (0 : [length (renderedConstraintOp constraint) | constraint <- rendered])
    row constraint =
      rowBox
        [ fieldBox lhsWidth (renderedConstraintLhs constraint)
        , fieldBox opWidth (renderedConstraintOp constraint)
        , Box.text (renderedConstraintRhs constraint)
        ]

constraintMentionsVar :: S.ConstraintView -> Bool
constraintMentionsVar constraint =
  case constraint of
    S.ConstraintEqual _ lhs rhs ->
      rawExprMentionsVar lhs || rawExprMentionsVar rhs
    S.ConstraintLessOrEqual lhs rhs ->
      rawExprMentionsVar lhs || rawExprMentionsVar rhs
    S.ConstraintMinimize expr -> rawExprMentionsVar expr
    S.ConstraintSoft inner -> constraintMentionsVar inner
    S.ConstraintAll constraints -> any constraintMentionsVar constraints

rawExprMentionsVar :: S.ExprView -> Bool
rawExprMentionsVar expr =
  case expr of
    S.ExprVar _ _      -> True
    S.ExprLit _        -> False
    S.ExprAdd lhs rhs  -> rawExprMentionsVar lhs || rawExprMentionsVar rhs
    S.ExprSub lhs rhs  -> rawExprMentionsVar lhs || rawExprMentionsVar rhs
    S.ExprMul lhs rhs  -> rawExprMentionsVar lhs || rawExprMentionsVar rhs
    S.ExprDiv lhs rhs  -> rawExprMentionsVar lhs || rawExprMentionsVar rhs
    S.ExprNeg inner    -> rawExprMentionsVar inner
    S.ExprAbs inner    -> rawExprMentionsVar inner
    S.ExprSignum inner -> rawExprMentionsVar inner
    S.ExprPow base to  -> rawExprMentionsVar base || rawExprMentionsVar to
    S.ExprMin lhs rhs  -> rawExprMentionsVar lhs || rawExprMentionsVar rhs
    S.ExprMax lhs rhs  -> rawExprMentionsVar lhs || rawExprMentionsVar rhs

--------------------------------------------------------------------------------
-- Solved view values
--------------------------------------------------------------------------------
data SolvedExpr =
  SolvedExpr String Double

stepSolutionBoxes :: S.Solution -> [V.ViewNode] -> [S.Constraint] -> [Box.Box]
stepSolutionBoxes solution nodes _constraints =
  case dedupeSolvedExprs (concatMap (solveViewNodeExprs solution) nodes) of
    []     -> []
    solved -> [stepSectionBox "solution" (solvedExprsBox solved)]

solveViewNodeExprs :: S.Solution -> V.ViewNode -> [SolvedExpr]
solveViewNodeExprs solution node =
  case node of
    V.ViewNode viewNode -> solveNodeExprs solution viewNode

solveNodeExprs :: S.Solution -> V.Node tag -> [SolvedExpr]
solveNodeExprs solution node =
  let blockName = renderViewRefPlain (V.nodeRef node)
   in [ SolvedExpr (blockName ++ "." ++ name) value
      | (name, value) <- V.solvedNodeExprs solution node
      ]

dedupeSolvedExprs :: [SolvedExpr] -> [SolvedExpr]
dedupeSolvedExprs = go []
  where
    go _ [] = []
    go seen (solved@(SolvedExpr name _):rest)
      | name `elem` seen = go seen rest
      | otherwise = solved : go (name : seen) rest

solvedExprsBox :: [SolvedExpr] -> Box.Box
solvedExprsBox solved =
  assignmentsBox
    0
    [(name, formatSignedDouble value) | SolvedExpr name value <- solved]

--------------------------------------------------------------------------------
-- View trace
--------------------------------------------------------------------------------
viewTraceBox :: Bool -> S.Solution -> [V.ViewStep] -> Box.Box
viewTraceBox showDetails solution steps =
  sectionBox "View trace"
    $ spacedVcat
    $ zipWith (viewTraceStepBox showDetails solution) [0 :: Int ..] steps

viewTraceStepBox :: Bool -> S.Solution -> Int -> V.ViewStep -> Box.Box
viewTraceStepBox showDetails solution ix step =
  case step of
    V.ViewStep traceStep nodes constraints _renderIntents ->
      if showDetails
        then spacedVcat (viewStepLabelBox ix traceStep : detailBoxes)
        else viewStepLabelBox ix traceStep
      where
        detailBoxes =
          concat
            [ stepViewNodeBoxes nodes
            , stepConstraintsBoxes constraints
            , stepSolutionBoxes solution nodes constraints
            ]

stepViewNodeBoxes :: [V.ViewNode] -> [Box.Box]
stepViewNodeBoxes nodes =
  case nodes of
    [] -> []
    _ ->
      [stepSectionBox "view nodes" (tightVcat (map indentedViewNodeBox nodes))]

indentedViewNodeBox :: V.ViewNode -> Box.Box
indentedViewNodeBox node =
  case node of
    V.ViewNode viewNode ->
      rowBox
        [ Box.text (renderViewRefPlain (V.nodeRef viewNode))
        , Box.text (renderViewLabel (V.nodeLabel viewNode))
        ]

--------------------------------------------------------------------------------
-- Steps
--------------------------------------------------------------------------------
stepsBox :: [TraceStepWith payload] -> Box.Box
stepsBox steps =
  sectionBox "Steps" $ spacedVcat $ zipWith stepBox [0 :: Int ..] steps

stepBox :: Int -> TraceStepWith payload -> Box.Box
stepBox ix step =
  case step of
    ExplainedStep label _payload audit -> labelledStepBox ix label audit
    DiscardedStep reason audit ->
      labelledStepBox ix ("Discarded: " ++ reason) audit

labelledStepBox :: Int -> String -> Audit acts -> Box.Box
labelledStepBox ix label audit =
  case audit of
    EmptyAudit -> stepHeaderBox ix label
    _          -> tightVcat [stepHeaderBox ix label, auditBox audit]

stepHeaderBox :: Int -> String -> Box.Box
stepHeaderBox ix label =
  rowBox
    [ rightFieldBox traceIndexWidth ("S" ++ show ix)
    , Box.text "|"
    , Box.text label
    ]

--------------------------------------------------------------------------------
-- Audit rendering
--------------------------------------------------------------------------------
auditBox :: Audit acts -> Box.Box
auditBox audit =
  case audit of
    EmptyAudit -> Box.nullBox
    step :> rest ->
      case rest of
        EmptyAudit -> auditStepBox step
        _          -> tightVcat [auditStepBox step, auditBox rest]

auditStepBox :: AuditStep act -> Box.Box
auditStepBox step =
  case step of
    CreateStep snapshot -> snapshotStep1Box createStyle snapshot
    ObserveStep snapshot -> snapshotStep1Box observeStyle snapshot
    UseStep snapshot -> snapshotStep1Box useStyle snapshot
    CopyStep original copy' -> snapshotStep2Box copyStyle original copy'
    ReplaceStep old incoming output ->
      snapshotStep3Box replaceStyle old incoming output
    ComputeStep snapshot -> snapshotStep1Box computeStyle snapshot
    DestroyStep snapshot -> snapshotStep1Box destroyStyle snapshot
    SealStep owner child -> snapshotStep2Box sealStyle owner child
    UnsealStep owner child -> snapshotStep2Box unsealStyle owner child
    DecideStep snapshot -> snapshotStep1Box decideStyle snapshot

snapshotStep1Box :: StepStyle -> BlockSnapshot tag -> Box.Box
snapshotStep1Box style snapshot =
  rowBox [renderStepNameBox style, snapshotBox snapshot]

snapshotStep2Box ::
     StepStyle -> BlockSnapshot first -> BlockSnapshot second -> Box.Box
snapshotStep2Box style first second =
  tightVcat
    [ rowBox [renderStepNameBox style, snapshotBox first]
    , rowBox [renderEmptyStepNameBox, snapshotBox second]
    ]

snapshotStep3Box ::
     StepStyle
  -> BlockSnapshot first
  -> BlockSnapshot second
  -> BlockSnapshot third
  -> Box.Box
snapshotStep3Box style first second third =
  tightVcat
    [ rowBox [renderStepNameBox style, snapshotBox first]
    , rowBox [renderEmptyStepNameBox, snapshotBox second]
    , rowBox [renderEmptyStepNameBox, snapshotBox third]
    ]

renderStepNameBox :: StepStyle -> Box.Box
renderStepNameBox style =
  indentBox stepIndentWidth $ rightFieldBox stepNameWidth (stepStyleName style)

renderEmptyStepNameBox :: Box.Box
renderEmptyStepNameBox =
  indentBox stepIndentWidth $ rightFieldBox stepNameWidth ""

--------------------------------------------------------------------------------
-- Snapshot rendering
--------------------------------------------------------------------------------
snapshotBox :: BlockSnapshot tag -> Box.Box
snapshotBox snapshot =
  rowBox
    [ fieldBox snapshotRefWidth (renderBlockRef (snapshotRef snapshot))
    , Box.text (renderSnapshotPayload snapshot)
    ]

renderSnapshotPayload :: BlockSnapshot tag -> String
renderSnapshotPayload (BlockSnapshot _ payload view _) =
  renderPayloadView view ++ ": " ++ payloadText payload

snapshotRef :: BlockSnapshot tag -> BlockRef tag
snapshotRef (BlockSnapshot ref _ _ _) = ref

renderBlockRef :: BlockRef tag -> String
renderBlockRef (BlockRef blockId) = "[B" ++ show blockId ++ "]"

renderBlockRefPlain :: BlockRef tag -> String
renderBlockRefPlain (BlockRef blockId) = "B" ++ show blockId

renderViewRefPlain :: V.ViewRef tag -> String
renderViewRefPlain ref = "B" ++ show (V.viewRefInt ref)

renderViewLabel :: V.ViewLabel -> String
renderViewLabel = V.viewLabelKind

viewStepLabelBox :: Int -> String -> Box.Box
viewStepLabelBox ix label = labelledStepBox ix label EmptyAudit

renderPayloadView :: PayloadView -> String
renderPayloadView (PayloadView kind) = kind

--------------------------------------------------------------------------------
-- Expression rendering
--------------------------------------------------------------------------------
exprText :: S.Expr ty -> String
exprText = rawExprText . S.exprView

rawExprText :: S.ExprView -> String
rawExprText = rawExprTextPrec 0

rawExprTextPrec :: Int -> S.ExprView -> String
rawExprTextPrec precedence expr =
  case expr of
    S.ExprVar _ variable -> variable
    S.ExprLit value -> fixed2 value
    S.ExprAdd lhs rhs ->
      infixExprText
        precedence
        addPrecedence
        "+"
        (rawExprTextPrec addPrecedence lhs)
        (rawExprTextPrec addPrecedence rhs)
    S.ExprSub lhs rhs ->
      infixExprText
        precedence
        addPrecedence
        "-"
        (rawExprTextPrec addPrecedence lhs)
        (rawExprTextPrec (addPrecedence + 1) rhs)
    S.ExprMul lhs rhs ->
      infixExprText
        precedence
        mulPrecedence
        "*"
        (rawExprTextPrec mulPrecedence lhs)
        (rawExprTextPrec mulPrecedence rhs)
    S.ExprDiv lhs rhs ->
      infixExprText
        precedence
        mulPrecedence
        "/"
        (rawExprTextPrec mulPrecedence lhs)
        (rawExprTextPrec (mulPrecedence + 1) rhs)
    S.ExprNeg inner ->
      parenthesizeText (precedence > unaryPrecedence)
        $ "-" ++ rawExprTextPrec unaryPrecedence inner
    S.ExprAbs inner -> functionExprText "abs" inner
    S.ExprSignum inner -> functionExprText "signum" inner
    S.ExprPow base to ->
      infixExprText
        precedence
        powerPrecedence
        "^"
        (rawExprTextPrec powerPrecedence base)
        (rawExprTextPrec (powerPrecedence + 1) to)
    S.ExprMin lhs rhs ->
      binaryFunctionExprText
        "min"
        (rawExprTextPrec 0 lhs)
        (rawExprTextPrec 0 rhs)
    S.ExprMax lhs rhs ->
      binaryFunctionExprText
        "max"
        (rawExprTextPrec 0 lhs)
        (rawExprTextPrec 0 rhs)

infixExprText :: Int -> Int -> String -> String -> String -> String
infixExprText outerPrecedence innerPrecedence operator lhs rhs =
  parenthesizeText (outerPrecedence > innerPrecedence)
    $ lhs ++ " " ++ operator ++ " " ++ rhs

functionExprText :: String -> S.ExprView -> String
functionExprText name inner =
  name ++ " " ++ rawExprTextPrec unaryPrecedence inner

binaryFunctionExprText :: String -> String -> String -> String
binaryFunctionExprText name lhs rhs = name ++ "(" ++ lhs ++ ", " ++ rhs ++ ")"

addPrecedence :: Int
addPrecedence = 6

mulPrecedence :: Int
mulPrecedence = 7

unaryPrecedence :: Int
unaryPrecedence = 8

powerPrecedence :: Int
powerPrecedence = 9

parenthesizeText :: Bool -> String -> String
parenthesizeText shouldParenthesize textValue =
  if shouldParenthesize
    then "(" ++ textValue ++ ")"
    else textValue

--------------------------------------------------------------------------------
-- Box helpers
--------------------------------------------------------------------------------
sectionBox :: String -> Box.Box -> Box.Box
sectionBox title body =
  tightVcat [Box.text title, Box.text (replicate (length title) '-'), body]

optionalSection :: String -> Box.Box -> [Box.Box]
optionalSection title body = [sectionBox title body | not (isNullBox body)]

stepSectionBox :: String -> Box.Box -> Box.Box
stepSectionBox title body =
  indentBox stepIndentWidth
    $ tightVcat [Box.text title, indentBox stepIndentWidth body]

sections :: [Box.Box] -> Box.Box
sections = spacedVcat

tightVcat :: [Box.Box] -> Box.Box
tightVcat boxes =
  case filter (not . isNullBox) boxes of
    []      -> Box.nullBox
    visible -> Box.vcat Box.left visible

spacedVcat :: [Box.Box] -> Box.Box
spacedVcat boxes =
  case filter (not . isNullBox) boxes of
    []      -> Box.nullBox
    [box]   -> box
    visible -> Box.vsep 1 Box.left visible

linesBox :: [String] -> Box.Box
linesBox = tightVcat . map Box.text

rowBox :: [Box.Box] -> Box.Box
rowBox = Box.hsep 1 Box.top

fieldBox :: Int -> String -> Box.Box
fieldBox width value = Box.alignHoriz Box.left width (Box.text value)

rightFieldBox :: Int -> String -> Box.Box
rightFieldBox width value = Box.alignHoriz Box.right width (Box.text value)

indentBox :: Int -> Box.Box -> Box.Box
indentBox amount box =
  if isNullBox box
    then Box.nullBox
    else Box.hcat Box.top [Box.emptyBox (Box.rows box) amount, box]

assignmentsBox :: Int -> [(String, String)] -> Box.Box
assignmentsBox indentWidth assignments =
  indentBox indentWidth $ tightVcat (map assignmentRow assignments)
  where
    nameWidth = maximum (0 : [length name | (name, _) <- assignments])
    assignmentRow (name, value) =
      rowBox [fieldBox nameWidth name, Box.text "=", Box.text value]

isNullBox :: Box.Box -> Bool
isNullBox box = Box.rows box == 0 && Box.cols box == 0

--------------------------------------------------------------------------------
-- ANSI post-processing
--------------------------------------------------------------------------------
colourReport :: String -> String
colourReport = unlines . map colourLine . lines

colourLine :: String -> String
colourLine line
  | isTraceHeaderLine line = colourTraceHeaderLine line
  | otherwise = colourStepNameLine line

isTraceHeaderLine :: String -> Bool
isTraceHeaderLine line =
  let (prefix, rest) = splitAt traceIndexWidth line
   in looksLikeTraceIndex prefix && take 3 rest == " | "

looksLikeTraceIndex :: String -> Bool
looksLikeTraceIndex textValue =
  case trimLeft textValue of
    'S':digits -> not (null digits) && all isDigit digits
    _          -> False

colourTraceHeaderLine :: String -> String
colourTraceHeaderLine line =
  let prefixWidth = traceIndexWidth + length " | "
      (prefix, title) = splitAt prefixWidth line
   in prefix ++ sgrBold ++ title ++ sgrReset

colourStepNameLine :: String -> String
colourStepNameLine line =
  case splitStepNameLine line of
    Nothing -> line
    Just (before, nameField, after) ->
      case lookup (trim nameField) stepColourMap of
        Nothing -> line
        Just colour ->
          before ++ sgrPalette colour ++ nameField ++ sgrReset ++ after

splitStepNameLine :: String -> Maybe (String, String, String)
splitStepNameLine line =
  let (before, rest) = splitAt stepIndentWidth line
      (nameField, after) = splitAt stepNameWidth rest
   in if length before == stepIndentWidth
           && all (== ' ') before
           && length nameField == stepNameWidth
        then Just (before, nameField, after)
        else Nothing

stepColourMap :: [(String, Int)]
stepColourMap =
  [(stepStyleName style, stepStyleColour style) | style <- allStepStyles]

sgrBold :: String
sgrBold = setSGRCode [SetConsoleIntensity BoldIntensity]

sgrPalette :: Int -> String
sgrPalette colour =
  setSGRCode [SetPaletteColor Foreground (fromIntegral colour)]

sgrReset :: String
sgrReset = setSGRCode [Reset]

--------------------------------------------------------------------------------
-- Text helpers
--------------------------------------------------------------------------------
trim :: String -> String
trim = trimLeft . trimRight

trimLeft :: String -> String
trimLeft = dropWhile (== ' ')

trimRight :: String -> String
trimRight = dropWhileEnd (== ' ')

--------------------------------------------------------------------------------
-- Numeric helpers
--------------------------------------------------------------------------------
formatSignedDouble :: Double -> String
formatSignedDouble value =
  let cleaned = cleanNegativeZero value
      text = fixed2 (abs cleaned)
   in if cleaned < 0
        then "-" ++ text
        else text

fixed2 :: Double -> String
fixed2 value = showFFloat (Just 2) value ""

cleanNegativeZero :: Double -> Double
cleanNegativeZero value =
  if abs value < 0.005
    then 0
    else value
