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
renderVisualization showDetails maybeSolution graph =
  concat
    [ renderHeader "Visualization"
    , renderVisualizationSummary nodes steps constraints initialVars
    , renderMaybeSolutionSummary maybeSolution
    , "\n"
    , renderWhen
        showDetails
        (concat [renderViewNodes nodes, "\n", renderInitialVars initialVars])
    , renderViewTrace showDetails maybeSolution steps
    ]
  where
    nodes = V.viewNodes graph
    steps = V.viewSteps graph
    constraints = V.viewConstraints graph
    initialVars = V.viewInitialVars graph

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
  renderHeader "Solution values"
    ++ renderAlignedAssignments
         "  "
         [ (name, formatSignedDouble value)
         | (name, value) <- Map.toAscList values
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
     [V.ViewNode]
  -> [V.ViewStep events]
  -> [V.Constraint]
  -> [S.InitialVar]
  -> String
renderVisualizationSummary nodes steps constraints initialVars =
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
    , "Initial vars: "
    , show (length initialVars)
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
    , renderMaybeStyleField "opacity" (V.styleOpacity style)
    , renderMaybeStyleField "zIndex" (V.styleZIndex style)
    , renderMaybeStyleField "fontSize" (V.styleFontSize style)
    , renderMaybeStyleField "radius" (V.styleRadius style)
    , renderMaybeHslStyleField "fill" (V.styleFill style)
    , renderMaybeHslStyleField "stroke" (V.styleStroke style)
    , renderMaybeStyleField "strokeWidth" (V.styleStrokeWidth style)
    , renderMaybeStyleField "alpha" (V.styleAlpha style)
    ]

renderStyleField :: String -> V.Expr ty -> String
renderStyleField name expr =
  concat
    [stepIndent, stepIndent, padRight 12 name, " = ", renderExpr expr, "\n"]

renderMaybeStyleField :: String -> Maybe (V.Expr ty) -> String
renderMaybeStyleField name maybeExpr =
  case maybeExpr of
    Nothing   -> ""
    Just expr -> renderStyleField name expr

renderMaybeHslStyleField :: String -> Maybe V.HslExpr -> String
renderMaybeHslStyleField name maybeHsl =
  case maybeHsl of
    Nothing -> ""
    Just hsl ->
      concat
        [ renderStyleField (name ++ ".hue") (V.hue hsl)
        , renderStyleField (name ++ ".saturation") (V.saturation hsl)
        , renderStyleField (name ++ ".lightness") (V.lightness hsl)
        ]

--------------------------------------------------------------------------------
-- Initial variables
--------------------------------------------------------------------------------
renderInitialVars :: [S.InitialVar] -> String
renderInitialVars initialVars =
  case initialVars of
    [] -> ""
    _ ->
      concat
        [ renderHeader "Initial variables"
        , renderAlignedAssignments
            "  "
            [ (name, renderInitialVarValue ty bounds)
            | S.InitialVar name ty bounds <- initialVars
            ]
        , "\n"
        ]

renderInitialVarValue :: S.ScalarType -> S.InitialBounds -> String
renderInitialVarValue ty bounds =
  concat [S.typeName ty, " ", renderInitialBounds bounds]

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

renderConstraintParts :: V.Constraint -> RenderedConstraint
renderConstraintParts constraint =
  case constraint of
    S.Equals ty lhs rhs ->
      RenderedConstraint
        { renderedConstraintLhs = renderRawExpr lhs
        , renderedConstraintOp = renderEqualityOperator ty
        , renderedConstraintRhs = renderEqualityRhs ty rhs
        }
    S.LessThan lhs rhs ->
      RenderedConstraint
        { renderedConstraintLhs = renderRawExpr lhs
        , renderedConstraintOp = "<"
        , renderedConstraintRhs = renderRawExpr rhs
        }
    S.Minimize expr ->
      RenderedConstraint
        { renderedConstraintLhs = ""
        , renderedConstraintOp = "minimize"
        , renderedConstraintRhs = renderRawExpr expr
        }

renderEqualityOperator :: S.ScalarType -> String
renderEqualityOperator ty =
  case S.typeCircularPeriod ty of
    Nothing -> "="
    Just _  -> "≡"

renderEqualityRhs :: S.ScalarType -> S.RawExpr -> String
renderEqualityRhs ty rhs =
  case S.typeCircularPeriod ty of
    Nothing     -> renderRawExpr rhs
    Just period -> renderRawExpr rhs ++ " (mod " ++ fixed2 period ++ ")"

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
    S.Equals _ lhs rhs -> rawExprMentionsVar lhs || rawExprMentionsVar rhs
    S.LessThan lhs rhs -> rawExprMentionsVar lhs || rawExprMentionsVar rhs
    S.Minimize expr    -> rawExprMentionsVar expr

rawExprMentionsVar :: S.RawExpr -> Bool
rawExprMentionsVar expr =
  case expr of
    S.EVar _ _ -> True
    S.ELit _ -> False
    S.EAdd lhs rhs -> rawExprMentionsVar lhs || rawExprMentionsVar rhs
    S.ESub lhs rhs -> rawExprMentionsVar lhs || rawExprMentionsVar rhs
    S.EMul lhs rhs -> rawExprMentionsVar lhs || rawExprMentionsVar rhs
    S.EDiv lhs rhs -> rawExprMentionsVar lhs || rawExprMentionsVar rhs
    S.ENeg inner -> rawExprMentionsVar inner
    S.EAbs inner -> rawExprMentionsVar inner
    S.ESignum inner -> rawExprMentionsVar inner
    S.EPow base exponent ->
      rawExprMentionsVar base || rawExprMentionsVar exponent

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

solveMaybeExpr :: S.Solution -> String -> Maybe (V.Expr ty) -> [SolvedExpr]
solveMaybeExpr solution name maybeExpr =
  case maybeExpr of
    Nothing   -> []
    Just expr -> solveNamedExpr solution name expr

solveMaybeHsl :: S.Solution -> String -> Maybe V.HslExpr -> [SolvedExpr]
solveMaybeHsl solution name maybeHsl =
  case maybeHsl of
    Nothing -> []
    Just hsl ->
      concat
        [ solveNamedExpr solution (name ++ ".hue") (V.hue hsl)
        , solveNamedExpr solution (name ++ ".saturation") (V.saturation hsl)
        , solveNamedExpr solution (name ++ ".lightness") (V.lightness hsl)
        ]

solveNamedExpr :: S.Solution -> String -> V.Expr ty -> [SolvedExpr]
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
renderExpr :: V.Expr ty -> String
renderExpr = renderRawExpr . S.exprRaw

renderRawExpr :: S.RawExpr -> String
renderRawExpr = renderRawExprPrec 0

renderRawExprPrec :: Int -> S.RawExpr -> String
renderRawExprPrec precedence expr =
  case expr of
    S.EVar _ variable -> S.varName variable
    S.ELit value -> fixed2 value
    S.EAdd lhs rhs ->
      parenthesize
        (precedence > addPrecedence)
        (renderRawExprPrec addPrecedence lhs
           ++ " + "
           ++ renderRawExprPrec addPrecedence rhs)
    S.ESub lhs rhs ->
      parenthesize
        (precedence > addPrecedence)
        (renderRawExprPrec addPrecedence lhs
           ++ " - "
           ++ renderRawExprPrec (addPrecedence + 1) rhs)
    S.EMul lhs rhs ->
      parenthesize
        (precedence > mulPrecedence)
        (renderRawExprPrec mulPrecedence lhs
           ++ " * "
           ++ renderRawExprPrec mulPrecedence rhs)
    S.EDiv lhs rhs ->
      parenthesize
        (precedence > mulPrecedence)
        (renderRawExprPrec mulPrecedence lhs
           ++ " / "
           ++ renderRawExprPrec (mulPrecedence + 1) rhs)
    S.ENeg inner ->
      parenthesize
        (precedence > unaryPrecedence)
        ("-" ++ renderRawExprPrec unaryPrecedence inner)
    S.EAbs inner -> "abs " ++ renderRawExprPrec unaryPrecedence inner
    S.ESignum inner -> "signum " ++ renderRawExprPrec unaryPrecedence inner
    S.EPow base exponent ->
      parenthesize
        (precedence > powerPrecedence)
        (renderRawExprPrec powerPrecedence base
           ++ " ^ "
           ++ renderRawExprPrec (powerPrecedence + 1) exponent)

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
