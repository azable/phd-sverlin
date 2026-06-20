{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE EmptyCase            #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE GADTs                #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module LinearTrace.Print
  ( PrintEvent(..)
  , PrintEvents(..)
  , printGraph
  , printTrace
  , printSolutionByEvent
  , printSolutionSummary
  ) where

import           Data.Char              (isDigit)
import           Data.List              (dropWhileEnd)
import           LinearTrace.Core
import qualified LinearTrace.Solver     as S
import qualified LinearTrace.View       as V
import           Numeric                (showFFloat)
import           Prelude
import           System.Console.ANSI    (ConsoleIntensity (..),
                                         ConsoleLayer (..), SGR (..),
                                         hNowSupportsANSI, setSGRCode)
import           System.IO              (stdout)
import qualified Text.PrettyPrint.Boxes as Box

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
printGraph = printReport . graphBox

printTrace :: PrintEvents events => TraceGraph events -> IO ()
printTrace = printReport . traceBox

printSolutionByEvent ::
     PrintEvents events => Bool -> S.Solution -> V.ViewGraph events -> IO ()
printSolutionByEvent showDetails solution =
  printReport . solutionByEventBox showDetails solution

printSolutionSummary :: S.Solution -> IO ()
printSolutionSummary = printReport . solutionSummaryBox

printReport :: Box.Box -> IO ()
printReport box = do
  supportsAnsi <- hNowSupportsANSI stdout
  putStr (renderReport supportsAnsi box)

renderReport :: Bool -> Box.Box -> String
renderReport supportsAnsi box =
  let plain = Box.render box ++ "\n"
   in if supportsAnsi
        then colourReport plain
        else plain

--------------------------------------------------------------------------------
-- Graph rendering
--------------------------------------------------------------------------------
graphBox :: PrintEvents events => TraceGraph events -> Box.Box
graphBox (TraceGraph blocks events) =
  sections
    [ sectionBox "Graph" (summaryBox blocks events)
    , blocksBox blocks
    , eventsBox events
    ]

traceBox :: PrintEvents events => TraceGraph events -> Box.Box
traceBox (TraceGraph _ events) = eventsBox events

summaryBox :: [BlockRecord] -> [RecordedEvent events] -> Box.Box
summaryBox blocks events =
  linesBox
    ["Blocks: " ++ show (length blocks), "Events: " ++ show (length events)]

--------------------------------------------------------------------------------
-- Solution rendering
--------------------------------------------------------------------------------
solutionByEventBox ::
     PrintEvents events => Bool -> S.Solution -> V.ViewGraph events -> Box.Box
solutionByEventBox showDetails solution graph =
  sections
    $ [ sectionBox "Solution"
          $ viewSummaryBox nodes steps constraints initialVars
      , solutionSummaryBox solution
      ]
        ++ detailBoxes
        ++ [viewTraceBox showDetails solution steps]
  where
    nodes = V.viewNodes graph
    steps = V.viewSteps graph
    constraints = V.viewConstraints graph
    initialVars = V.viewInitialVars graph
    detailBoxes
      | showDetails =
        optionalSection "View nodes" (viewNodesBox nodes)
          ++ optionalSection "Initial variables" (initialVarsBox initialVars)
      | otherwise = []

solutionSummaryBox :: S.Solution -> Box.Box
solutionSummaryBox solution =
  sectionBox "Solution summary"
    $ linesBox
        [ "Solved: " ++ show (S.solutionSuccess solution)
        , "Energy: " ++ formatSignedDouble (S.solutionEnergy solution)
        , "Seed: " ++ show seed
        ]
  where
    V.RandomSeed seed = S.solutionSeed solution

viewSummaryBox ::
     [V.ViewNode]
  -> [V.ViewStep events]
  -> [S.Constraint]
  -> [S.InitialVar]
  -> Box.Box
viewSummaryBox nodes steps constraints initialVars =
  linesBox
    [ "View nodes: " ++ show (length nodes)
    , "View steps: " ++ show (length steps)
    , "Constraints: " ++ show (length (flattenConstraints constraints))
    , "Initial vars: " ++ show (length initialVars)
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
    V.BlockViewNode block -> blockViewBox block

blockViewBox :: V.BlockView tag -> Box.Box
blockViewBox block =
  tightVcat
    [ indentBox 2
        $ rowBox
            [ fieldBox
                blockListRefWidth
                (renderBlockRefPlain (V.blockViewRef block))
            , Box.text (renderPayloadView (V.blockViewLabel block))
            ]
    , blockStyleBox block
    ]

blockStyleBox :: V.BlockView tag -> Box.Box
blockStyleBox block =
  stepSectionBox "style" $
  tightVcat (V.mapBlockViewStyleExprLeaves styleFieldBox block)

styleFieldBox :: String -> S.Expr ty -> Box.Box
styleFieldBox name expr =
  rowBox [fieldBox styleFieldWidth name, Box.text "=", Box.text (exprText expr)]

--------------------------------------------------------------------------------
-- Initial variables
--------------------------------------------------------------------------------
initialVarsBox :: [S.InitialVar] -> Box.Box
initialVarsBox initialVars =
  assignmentsBox
    2
    [ (name, renderInitialVarValue ty bounds)
    | S.InitialVar name ty bounds <- initialVars
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
        { renderedConstraintLhs = rawExprText lhs
        , renderedConstraintOp = renderEqualityOperator ty
        , renderedConstraintRhs = renderEqualityRhs ty rhs
        }
    S.LessOrEqual lhs rhs ->
      RenderedConstraint
        { renderedConstraintLhs = rawExprText lhs
        , renderedConstraintOp = "<="
        , renderedConstraintRhs = rawExprText rhs
        }
    S.Minimize expr ->
      RenderedConstraint
        { renderedConstraintLhs = ""
        , renderedConstraintOp = "minimize"
        , renderedConstraintRhs = rawExprText expr
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
    Nothing     -> rawExprText rhs
    Just period -> rawExprText rhs ++ " (mod " ++ fixed2 period ++ ")"

stepConstraintsBoxes :: [S.Constraint] -> [Box.Box]
stepConstraintsBoxes constraints =
  case filter constraintMentionsVar (flattenConstraints constraints) of
    []      -> []
    visible -> [stepSectionBox "constraints" (constraintTableBox visible)]

constraintTableBox :: [S.Constraint] -> Box.Box
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

stepSolutionBoxes :: S.Solution -> [V.ViewNode] -> [S.Constraint] -> [Box.Box]
stepSolutionBoxes solution nodes _constraints =
  case dedupeSolvedExprs (concatMap (solveViewNodeExprs solution) nodes) of
    []     -> []
    solved -> [stepSectionBox "solution" (solvedExprsBox solved)]

solveViewNodeExprs :: S.Solution -> V.ViewNode -> [SolvedExpr]
solveViewNodeExprs solution node =
  case node of
    V.BlockViewNode block -> solveBlockViewExprs solution block

solveBlockViewExprs :: S.Solution -> V.BlockView tag -> [SolvedExpr]
solveBlockViewExprs solution block =
  let blockName = renderBlockRefPlain (V.blockViewRef block)
   in [ SolvedExpr (blockName ++ "." ++ name) value
      | (name, value) <- V.solvedBlockViewExprs solution block
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
viewTraceBox ::
     PrintEvents events => Bool -> S.Solution -> [V.ViewStep events] -> Box.Box
viewTraceBox showDetails solution steps =
  sectionBox "View trace"
    $ spacedVcat
    $ zipWith (viewTraceStepBox showDetails solution) [0 :: Int ..] steps

viewTraceStepBox ::
     PrintEvents events
  => Bool
  -> S.Solution
  -> Int
  -> V.ViewStep events
  -> Box.Box
viewTraceStepBox showDetails solution ix step =
  case step of
    V.ViewStep event nodes constraints _renderIntents ->
      if showDetails
        then spacedVcat (eventBox ix event : detailBoxes)
        else eventBox ix event
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
    V.BlockViewNode block ->
      rowBox
        [ Box.text (renderBlockRefPlain (V.blockViewRef block))
        , Box.text (renderPayloadView (V.blockViewLabel block))
        ]

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
eventsBox :: PrintEvents events => [RecordedEvent events] -> Box.Box
eventsBox events =
  sectionBox "Events" $ spacedVcat $ zipWith eventBox [0 :: Int ..] events

eventBox :: PrintEvents events => Int -> RecordedEvent events -> Box.Box
eventBox ix (RecordedEvent event audit) =
  case audit of
    EmptyAudit -> eventHeaderBox ix event
    _          -> tightVcat [eventHeaderBox ix event, auditBox audit]

eventHeaderBox ::
     PrintEvents events => Int -> EventChoice events acts -> Box.Box
eventHeaderBox ix event =
  rowBox
    [ rightFieldBox eventIndexWidth ("E" ++ show ix)
    , Box.text "|"
    , Box.text (printEventChoice event)
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
exprText :: S.Expr ty -> String
exprText = rawExprText . S.exprRaw

rawExprText :: S.RawExpr -> String
rawExprText = rawExprTextPrec 0

rawExprTextPrec :: Int -> S.RawExpr -> String
rawExprTextPrec precedence expr =
  case expr of
    S.EVar _ variable -> S.varName variable
    S.ELit value -> fixed2 value
    S.EAdd lhs rhs ->
      infixExprText
        precedence
        addPrecedence
        "+"
        (rawExprTextPrec addPrecedence lhs)
        (rawExprTextPrec addPrecedence rhs)
    S.ESub lhs rhs ->
      infixExprText
        precedence
        addPrecedence
        "-"
        (rawExprTextPrec addPrecedence lhs)
        (rawExprTextPrec (addPrecedence + 1) rhs)
    S.EMul lhs rhs ->
      infixExprText
        precedence
        mulPrecedence
        "*"
        (rawExprTextPrec mulPrecedence lhs)
        (rawExprTextPrec mulPrecedence rhs)
    S.EDiv lhs rhs ->
      infixExprText
        precedence
        mulPrecedence
        "/"
        (rawExprTextPrec mulPrecedence lhs)
        (rawExprTextPrec (mulPrecedence + 1) rhs)
    S.ENeg inner ->
      parenthesizeText (precedence > unaryPrecedence)
        $ "-" ++ rawExprTextPrec unaryPrecedence inner
    S.EAbs inner -> functionExprText "abs" inner
    S.ESignum inner -> functionExprText "signum" inner
    S.EPow base to ->
      infixExprText
        precedence
        powerPrecedence
        "^"
        (rawExprTextPrec powerPrecedence base)
        (rawExprTextPrec (powerPrecedence + 1) to)

infixExprText :: Int -> Int -> String -> String -> String -> String
infixExprText outerPrecedence innerPrecedence operator lhs rhs =
  parenthesizeText (outerPrecedence > innerPrecedence)
    $ lhs ++ " " ++ operator ++ " " ++ rhs

functionExprText :: String -> S.RawExpr -> String
functionExprText name inner =
  name ++ " " ++ rawExprTextPrec unaryPrecedence inner

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
optionalSection title body =
  [sectionBox title body | not (isNullBox body)]

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
  | isEventHeaderLine line = colourEventHeaderLine line
  | otherwise = colourStepNameLine line

isEventHeaderLine :: String -> Bool
isEventHeaderLine line =
  let (prefix, rest) = splitAt eventIndexWidth line
   in looksLikeEventIndex prefix && take 3 rest == " | "

looksLikeEventIndex :: String -> Bool
looksLikeEventIndex textValue =
  case trimLeft textValue of
    'E':digits -> not (null digits) && all isDigit digits
    _          -> False

colourEventHeaderLine :: String -> String
colourEventHeaderLine line =
  let prefixWidth = eventIndexWidth + length " | "
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
