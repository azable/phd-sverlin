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
  , printVisualization
  , printSolvedVisualization
  , printVisualizationCSPSolution
  ) where

import qualified Data.Map.Strict       as Map
import           LinearTrace.Core
import qualified LinearTrace.Solver    as S
import qualified LinearTrace.Visualize as V
import           Numeric               (showFFloat)
import           Prelude

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

solutionNameWidth :: Int
solutionNameWidth = 24

stepIndent :: String
stepIndent = "    "

--------------------------------------------------------------------------------
-- Colour/style constants
--------------------------------------------------------------------------------
eventTitleStyle :: [Ansi]
eventTitleStyle = [AnsiBold]

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
-- Step styles
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- Event printing
--------------------------------------------------------------------------------
class PrintEvent event where
  printEvent :: event -> String

class PrintEvents events where
  printEventUnion :: EventUnion events acts -> String

instance PrintEvents '[] where
  printEventUnion union = case union of {}

instance (PrintEvent event, PrintEvents events) => PrintEvents (event : events) where
  printEventUnion union =
    case union of
      Here event -> printEvent event
      There rest -> printEventUnion rest

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
renderGraph (TraceGraph blocks events) =
  concat
    [ renderHeader "Graph"
    , renderSummary blocks events
    , "\n"
    , renderBlocks blocks
    , "\n"
    , renderEvents events
    ]

renderTrace :: PrintEvents events => TraceGraph events -> String
renderTrace (TraceGraph _ events) = renderEvents events

--------------------------------------------------------------------------------
-- Visualization rendering
--------------------------------------------------------------------------------
renderVisualization ::
     PrintEvents events
  => Bool
  -> Maybe S.Solution
  -> V.ViewGraph events
  -> String
renderVisualization showDetails maybeSolution (V.ViewGraph nodes steps constraints) =
  concat
    [ renderHeader "Visualization"
    , renderVisualizationSummary nodes steps constraints
    , renderMaybeSolutionSummary maybeSolution
    , "\n"
    , renderWhen showDetails (renderViewNodes nodes ++ "\n")
    , renderViewTrace showDetails maybeSolution steps
    ]

renderMaybeSolutionSummary :: Maybe S.Solution -> String
renderMaybeSolutionSummary maybeSolution =
  case maybeSolution of
    Nothing -> ""
    Just solution ->
      concat
        [ "Solved: "
        , show (S.solutionSuccess solution)
        , "\n"
        , "Energy: "
        , formatSignedDouble (S.solutionEnergy solution)
        , "\n"
        ]

--------------------------------------------------------------------------------
-- Standalone solution rendering
--------------------------------------------------------------------------------
renderSolution :: S.Solution -> String
renderSolution solution =
  concat
    [ renderHeader "Solution"
    , renderSolutionSummary solution
    , "\n"
    , renderSolutionValues (S.solutionValues solution)
    ]

renderSolutionSummary :: S.Solution -> String
renderSolutionSummary solution =
  concat
    [ "Success: "
    , show (S.solutionSuccess solution)
    , "\n"
    , "Energy: "
    , formatSignedDouble (S.solutionEnergy solution)
    , "\n"
    , "Variables: "
    , show (Map.size (S.solutionValues solution))
    , "\n"
    ]

renderSolutionValues :: Map.Map String Double -> String
renderSolutionValues values =
  concat
    [ renderHeader "Solution values"
    , renderAlignedAssignments
        "  "
        [ (name, formatSignedDouble value)
        | (name, value) <- Map.toAscList values
        ]
    ]

--------------------------------------------------------------------------------
-- Summary
--------------------------------------------------------------------------------
renderSummary :: [BlockRecord] -> [TraceEvent events] -> String
renderSummary blocks events =
  concat
    [ "Blocks: "
    , show (length blocks)
    , "\n"
    , "Events: "
    , show (length events)
    , "\n"
    ]

renderVisualizationSummary ::
     [V.ViewNode] -> [V.ViewStep events] -> [V.Constraint] -> String
renderVisualizationSummary nodes steps constraints =
  concat
    [ "View nodes: "
    , show (length nodes)
    , "\n"
    , "View steps: "
    , show (length steps)
    , "\n"
    , "Constraints: "
    , show (length constraints)
    , "\n"
    ]

--------------------------------------------------------------------------------
-- Blocks
--------------------------------------------------------------------------------
renderBlocks :: [BlockRecord] -> String
renderBlocks blocks = renderHeader "Blocks" ++ concatMap renderBlock blocks

renderBlock :: BlockRecord -> String
renderBlock (BlockRecord snapshot) =
  concat
    [ "  "
    , padRight blockListRefWidth (renderBlockRefPlain (snapshotRef snapshot))
    , renderSnapshotPayload snapshot
    , "\n"
    ]

--------------------------------------------------------------------------------
-- View nodes
--------------------------------------------------------------------------------
renderViewNodes :: [V.ViewNode] -> String
renderViewNodes nodes =
  renderHeader "View nodes" ++ concatMap renderViewNode nodes

renderViewNode :: V.ViewNode -> String
renderViewNode node =
  case node of
    V.BlockViewNode block -> renderBlockView block

renderBlockView :: V.BlockView tag -> String
renderBlockView block =
  concat
    [ "  "
    , padRight blockListRefWidth (renderBlockRefPlain (V.blockRef block))
    , renderPayloadView (V.blockLabel block)
    , "\n"
    , renderStyle (V.blockStyle block)
    ]

renderStyle :: V.Style -> String
renderStyle style =
  concat
    [ stepIndent
    , "style\n"
    , renderStyleField "top" (V.top style)
    , renderStyleField "left" (V.left style)
    , renderStyleField "width" (V.width style)
    , renderStyleField "height" (V.height style)
    ]

renderStyleField :: String -> V.Expr -> String
renderStyleField name expr =
  concat [stepIndent, stepIndent, padRight 8 name, " = ", renderExpr expr, "\n"]

--------------------------------------------------------------------------------
-- View constraints
--------------------------------------------------------------------------------
data RenderedConstraint = RenderedConstraint
  { renderedConstraintLhs :: String
  , renderedConstraintOp  :: String
  , renderedConstraintRhs :: String
  }

renderConstraintParts :: V.Constraint -> RenderedConstraint
renderConstraintParts constraint =
  case constraint of
    V.Equals lhs rhs ->
      RenderedConstraint
        { renderedConstraintLhs = renderExpr lhs
        , renderedConstraintOp = "="
        , renderedConstraintRhs = renderExpr rhs
        }
    V.LessThan lhs rhs ->
      RenderedConstraint
        { renderedConstraintLhs = renderExpr lhs
        , renderedConstraintOp = "<"
        , renderedConstraintRhs = renderExpr rhs
        }
    V.Minimize expr ->
      RenderedConstraint
        { renderedConstraintLhs = ""
        , renderedConstraintOp = "minimize"
        , renderedConstraintRhs = renderExpr expr
        }

renderStepConstraints :: [V.Constraint] -> String
renderStepConstraints constraints =
  let visibleConstraints = filter constraintMentionsVar constraints
   in case visibleConstraints of
        [] -> ""
        _ ->
          concat
            [ stepIndent
            , "constraints\n"
            , renderIndentedConstraints visibleConstraints
            , "\n"
            ]

renderIndentedConstraints :: [V.Constraint] -> String
renderIndentedConstraints constraints =
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
   in concatMap (renderIndentedConstraint lhsWidth opWidth) rendered

renderIndentedConstraint :: Int -> Int -> RenderedConstraint -> String
renderIndentedConstraint lhsWidth opWidth constraint =
  concat
    [ stepIndent
    , stepIndent
    , padRight lhsWidth (renderedConstraintLhs constraint)
    , " "
    , padRight opWidth (renderedConstraintOp constraint)
    , " "
    , renderedConstraintRhs constraint
    , "\n"
    ]

constraintMentionsVar :: V.Constraint -> Bool
constraintMentionsVar constraint =
  case constraint of
    V.Equals lhs rhs   -> exprMentionsVar lhs || exprMentionsVar rhs
    V.LessThan lhs rhs -> exprMentionsVar lhs || exprMentionsVar rhs
    V.Minimize expr    -> exprMentionsVar expr

exprMentionsVar :: V.Expr -> Bool
exprMentionsVar expr =
  case expr of
    V.EVar _        -> True
    V.ELit _        -> False
    V.EAdd lhs rhs  -> exprMentionsVar lhs || exprMentionsVar rhs
    V.ESub lhs rhs  -> exprMentionsVar lhs || exprMentionsVar rhs
    V.EMul lhs rhs  -> exprMentionsVar lhs || exprMentionsVar rhs
    V.EDiv lhs rhs  -> exprMentionsVar lhs || exprMentionsVar rhs
    V.ENeg inner    -> exprMentionsVar inner
    V.ESquare inner -> exprMentionsVar inner

--------------------------------------------------------------------------------
-- Solved view values
--------------------------------------------------------------------------------
data SolvedExpr =
  SolvedExpr String Double

renderStepSolution ::
     Maybe S.Solution -> [V.ViewNode] -> [V.Constraint] -> String
renderStepSolution maybeSolution nodes _constraints =
  case maybeSolution of
    Nothing -> ""
    Just solution ->
      let solved =
            dedupeSolvedExprs (concatMap (solveViewNodeExprs solution) nodes)
       in case solved of
            [] -> ""
            _ ->
              concat [stepIndent, "solution\n", renderSolvedExprs solved, "\n"]

solveViewNodeExprs :: S.Solution -> V.ViewNode -> [SolvedExpr]
solveViewNodeExprs solution node =
  case node of
    V.BlockViewNode block -> solveBlockViewExprs solution block

solveBlockViewExprs :: S.Solution -> V.BlockView tag -> [SolvedExpr]
solveBlockViewExprs solution block =
  let blockName = renderBlockRefPlain (V.blockRef block)
      style = V.blockStyle block
   in concat
        [ solveNamedExpr solution (blockName ++ ".top") (V.top style)
        , solveNamedExpr solution (blockName ++ ".left") (V.left style)
        , solveNamedExpr solution (blockName ++ ".width") (V.width style)
        , solveNamedExpr solution (blockName ++ ".height") (V.height style)
        , solveMaybeExpr
            solution
            (blockName ++ ".opacity")
            (V.styleOpacity style)
        , solveMaybeExpr solution (blockName ++ ".zIndex") (V.styleZIndex style)
        , solveMaybeExpr
            solution
            (blockName ++ ".fontSize")
            (V.styleFontSize style)
        , solveMaybeExpr solution (blockName ++ ".radius") (V.styleRadius style)
        , solveMaybeHsl solution (blockName ++ ".fill") (V.styleFill style)
        , solveMaybeHsl solution (blockName ++ ".stroke") (V.styleStroke style)
        , solveMaybeExpr
            solution
            (blockName ++ ".strokeWidth")
            (V.styleStrokeWidth style)
        , solveMaybeExpr solution (blockName ++ ".alpha") (V.styleAlpha style)
        ]

solveMaybeExpr :: S.Solution -> String -> Maybe V.Expr -> [SolvedExpr]
solveMaybeExpr solution name maybeExpr =
  case maybeExpr of
    Nothing   -> []
    Just expr -> solveNamedExpr solution name expr

solveMaybeHsl :: S.Solution -> String -> Maybe (V.Hsl V.Expr) -> [SolvedExpr]
solveMaybeHsl solution name maybeHsl =
  case maybeHsl of
    Nothing -> []
    Just hsl ->
      concat
        [ solveNamedExpr solution (name ++ ".hue") (V.hue hsl)
        , solveNamedExpr solution (name ++ ".saturation") (V.saturation hsl)
        , solveNamedExpr solution (name ++ ".lightness") (V.lightness hsl)
        ]

solveNamedExpr :: S.Solution -> String -> V.Expr -> [SolvedExpr]
solveNamedExpr solution name expr =
  case S.evalExpr solution expr of
    Nothing    -> []
    Just value -> [SolvedExpr name value]

dedupeSolvedExprs :: [SolvedExpr] -> [SolvedExpr]
dedupeSolvedExprs = go []
  where
    go _ [] = []
    go seen (solved@(SolvedExpr name _):rest)
      | name `elem` seen = go seen rest
      | otherwise = solved : go (name : seen) rest

renderSolvedExprs :: [SolvedExpr] -> String
renderSolvedExprs solved =
  renderAlignedAssignments
    (stepIndent ++ stepIndent)
    [(name, formatSignedDouble value) | SolvedExpr name value <- solved]

--------------------------------------------------------------------------------
-- View trace
--------------------------------------------------------------------------------
renderViewTrace ::
     PrintEvents events
  => Bool
  -> Maybe S.Solution
  -> [V.ViewStep events]
  -> String
renderViewTrace showDetails maybeSolution steps =
  renderHeader "View trace"
    ++ concat
         (zipWith
            (renderViewTraceStep showDetails maybeSolution)
            [0 :: Int ..]
            steps)

renderViewTraceStep ::
     PrintEvents events
  => Bool
  -> Maybe S.Solution
  -> Int
  -> V.ViewStep events
  -> String
renderViewTraceStep showDetails maybeSolution ix step =
  case step of
    V.ViewStep event nodes constraints ->
      concat
        [ renderEvent ix event
        , renderWhen
            showDetails
            (concat
               [ renderStepViewNodes nodes
               , renderStepConstraints constraints
               , renderStepSolution maybeSolution nodes constraints
               ])
        ]

renderStepViewNodes :: [V.ViewNode] -> String
renderStepViewNodes nodes =
  case nodes of
    [] -> ""
    _ ->
      concat
        [ stepIndent
        , "view nodes\n"
        , concatMap renderIndentedViewNode nodes
        , "\n"
        ]

renderIndentedViewNode :: V.ViewNode -> String
renderIndentedViewNode node =
  case node of
    V.BlockViewNode block ->
      concat
        [ stepIndent
        , stepIndent
        , renderBlockRefPlain (V.blockRef block)
        , " "
        , renderPayloadView (V.blockLabel block)
        , "\n"
        ]

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
renderEvents :: PrintEvents events => [TraceEvent events] -> String
renderEvents events =
  renderHeader "Events" ++ concat (zipWith renderEvent [0 :: Int ..] events)

renderEvent :: PrintEvents events => Int -> TraceEvent events -> String
renderEvent ix (TraceEvent event audit) =
  concat
    [ padLeft eventIndexWidth ("E" ++ show ix)
    , " | "
    , ansiText eventTitleStyle (printEventUnion event)
    , "\n"
    , renderAudit audit
    , "\n"
    ]

--------------------------------------------------------------------------------
-- Audit rendering
--------------------------------------------------------------------------------
renderAudit :: Audit acts -> String
renderAudit EmptyAudit     = ""
renderAudit (step :> rest) = renderAuditStep step ++ renderAudit rest

renderAuditStep :: AuditStep act -> String
renderAuditStep step =
  case step of
    CreateStep snapshot -> renderSnapshotStep1 createStyle snapshot
    ObserveStep snapshot -> renderSnapshotStep1 observeStyle snapshot
    InspectStep snapshot -> renderSnapshotStep1 inspectStyle snapshot
    UseStep snapshot -> renderSnapshotStep1 useStyle snapshot
    CopyStep original copy' -> renderSnapshotStep2 copyStyle original copy'
    ReplaceStep old incoming output ->
      renderSnapshotStep3 replaceStyle old incoming output
    ComputeStep snapshot -> renderSnapshotStep1 computeStyle snapshot
    DestroyStep snapshot -> renderSnapshotStep1 destroyStyle snapshot
    SealStep owner child -> renderSnapshotStep2 sealStyle owner child
    UnsealStep owner child -> renderSnapshotStep2 unsealStyle owner child
    DecideStep snapshot -> renderSnapshotStep1 decideStyle snapshot

renderSnapshotStep1 :: StepStyle -> BlockSnapshot tag -> String
renderSnapshotStep1 style snapshot =
  concat [renderStepName style, " ", renderSnapshot snapshot, "\n"]

renderSnapshotStep2 ::
     StepStyle -> BlockSnapshot first -> BlockSnapshot second -> String
renderSnapshotStep2 style first second =
  concat
    [ renderStepName style
    , " "
    , renderSnapshot first
    , "\n"
    , renderEmptyStepName
    , " "
    , renderSnapshot second
    , "\n"
    ]

renderSnapshotStep3 ::
     StepStyle
  -> BlockSnapshot first
  -> BlockSnapshot second
  -> BlockSnapshot third
  -> String
renderSnapshotStep3 style first second third =
  concat
    [ renderStepName style
    , " "
    , renderSnapshot first
    , "\n"
    , renderEmptyStepName
    , " "
    , renderSnapshot second
    , "\n"
    , renderEmptyStepName
    , " "
    , renderSnapshot third
    , "\n"
    ]

--------------------------------------------------------------------------------
-- Snapshot rendering
--------------------------------------------------------------------------------
renderSnapshot :: BlockSnapshot tag -> String
renderSnapshot snapshot =
  padRight snapshotRefWidth (renderBlockRef (snapshotRef snapshot))
    ++ " "
    ++ renderSnapshotPayload snapshot

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
renderExpr :: V.Expr -> String
renderExpr = renderExprPrec 0

renderExprPrec :: Int -> V.Expr -> String
renderExprPrec precedence expr =
  case expr of
    V.EVar variable -> V.varName variable
    V.ELit value -> fixed2 value
    V.EAdd lhs rhs ->
      parenthesize
        (precedence > addPrecedence)
        (renderExprPrec addPrecedence lhs
           ++ " + "
           ++ renderExprPrec addPrecedence rhs)
    V.ESub lhs rhs ->
      parenthesize
        (precedence > addPrecedence)
        (renderExprPrec addPrecedence lhs
           ++ " - "
           ++ renderExprPrec (addPrecedence + 1) rhs)
    V.EMul lhs rhs ->
      parenthesize
        (precedence > mulPrecedence)
        (renderExprPrec mulPrecedence lhs
           ++ " * "
           ++ renderExprPrec mulPrecedence rhs)
    V.EDiv lhs rhs ->
      parenthesize
        (precedence > mulPrecedence)
        (renderExprPrec mulPrecedence lhs
           ++ " / "
           ++ renderExprPrec (mulPrecedence + 1) rhs)
    V.ENeg inner ->
      parenthesize
        (precedence > unaryPrecedence)
        ("-" ++ renderExprPrec unaryPrecedence inner)
    V.ESquare inner ->
      parenthesize
        (precedence > powerPrecedence)
        (renderExprPrec powerPrecedence inner ++ "^2")

addPrecedence :: Int
addPrecedence = 6

mulPrecedence :: Int
mulPrecedence = 7

unaryPrecedence :: Int
unaryPrecedence = 8

powerPrecedence :: Int
powerPrecedence = 9

parenthesize :: Bool -> String -> String
parenthesize shouldParenthesize text =
  if shouldParenthesize
    then "(" ++ text ++ ")"
    else text

--------------------------------------------------------------------------------
-- Text helpers
--------------------------------------------------------------------------------
renderHeader :: String -> String
renderHeader title = title ++ "\n" ++ replicate (length title) '-' ++ "\n"

renderWhen :: Bool -> String -> String
renderWhen enabled text =
  if enabled
    then text
    else ""

renderStepName :: StepStyle -> String
renderStepName (StepStyle name colour) =
  stepIndent ++ ansiText [colour] (padLeft stepNameWidth name)

renderEmptyStepName :: String
renderEmptyStepName = stepIndent ++ padLeft stepNameWidth ""

renderAlignedAssignments :: String -> [(String, String)] -> String
renderAlignedAssignments indent assignments =
  let nameWidth = maximum (0 : [length name | (name, _) <- assignments])
   in concatMap (renderAlignedAssignment indent nameWidth) assignments

renderAlignedAssignment :: String -> Int -> (String, String) -> String
renderAlignedAssignment indent nameWidth (name, value) =
  concat [indent, padRight nameWidth name, " = ", value, "\n"]

padRight :: Int -> String -> String
padRight n text = text ++ replicate (max 0 (n - length text)) ' '

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
  | AnsiDim
  | AnsiItalic
  | AnsiUnderline
  | AnsiFg Int
  | AnsiBg Int
  | Ansi256Fg Int
  | Ansi256Bg Int
  | AnsiRgbFg Int Int Int
  | AnsiRgbBg Int Int Int

ansiText :: [Ansi] -> String -> String
ansiText styles text = concatMap ansiCode styles ++ text ++ ansiCode AnsiReset

ansiCode :: Ansi -> String
ansiCode ansi =
  case ansi of
    AnsiReset -> "\ESC[0m"
    AnsiBold -> "\ESC[1m"
    AnsiDim -> "\ESC[2m"
    AnsiItalic -> "\ESC[3m"
    AnsiUnderline -> "\ESC[4m"
    AnsiFg n -> "\ESC[" ++ show n ++ "m"
    AnsiBg n -> "\ESC[" ++ show n ++ "m"
    Ansi256Fg n -> "\ESC[38;5;" ++ show n ++ "m"
    Ansi256Bg n -> "\ESC[48;5;" ++ show n ++ "m"
    AnsiRgbFg r g b ->
      "\ESC[38;2;" ++ show r ++ ";" ++ show g ++ ";" ++ show b ++ "m"
    AnsiRgbBg r g b ->
      "\ESC[48;2;" ++ show r ++ ";" ++ show g ++ ";" ++ show b ++ "m"
