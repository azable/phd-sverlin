{-# LANGUAGE GADTs #-}

module LinearTrace.Print
  ( PrintEvent(..)
  , renderGraph
  , renderTrace
  , printGraph
  , printTrace
  ) where

import           LinearTrace.Core
import           Prelude

-- Layout constants
eventIndexWidth :: Int
eventIndexWidth = 3

nodeListRefWidth :: Int
nodeListRefWidth = 8

snapshotRefWidth :: Int
snapshotRefWidth = 6

stepNameWidth :: Int
stepNameWidth = 16

stepIndent :: String
stepIndent = "    "

-- Colour/style constants
eventTitleStyle :: [Ansi]
eventTitleStyle = [AnsiBold]

createColour :: Ansi
createColour = Ansi256Fg 82 -- green

observeColour :: Ansi
observeColour = Ansi256Fg 51 -- cyan

inspectColour :: Ansi
inspectColour = Ansi256Fg 123 -- pale cyan

useColour :: Ansi
useColour = Ansi256Fg 220 -- yellow

copyColour :: Ansi
copyColour = Ansi256Fg 75 -- blue

replaceColour :: Ansi
replaceColour = Ansi256Fg 171 -- purple

computeColour :: Ansi
computeColour = Ansi256Fg 118 -- lime

destroyColour :: Ansi
destroyColour = Ansi256Fg 196 -- red

sealColour :: Ansi
sealColour = Ansi256Fg 37 --teal

unsealColour :: Ansi
unsealColour = Ansi256Fg 208 -- orange

-- Step styles
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

class PrintEvent event where
  printEvent :: event acts -> String

printGraph :: (PrintEvent event) => TraceGraph event -> IO ()
printGraph graph = putStr (renderGraph graph)

printTrace :: (PrintEvent event) => TraceGraph event -> IO ()
printTrace graph = putStr (renderTrace graph)

renderGraph :: (PrintEvent event) => TraceGraph event -> String
renderGraph (TraceGraph nodes events) =
  concat
    [ renderHeader "Graph"
    , renderSummary nodes events
    , "\n"
    , renderNodes nodes
    , "\n"
    , renderEvents events
    ]

renderTrace :: (PrintEvent event) => TraceGraph event -> String
renderTrace (TraceGraph _ events) = renderEvents events

renderSummary :: [NodeRecord] -> [TraceEvent event] -> String
renderSummary nodes events =
  concat
    [ "Nodes:  "
    , show (length nodes)
    , "\n"
    , "Events: "
    , show (length events)
    , "\n"
    ]

renderNodes :: [NodeRecord] -> String
renderNodes nodes = renderHeader "Nodes" ++ concatMap renderNode nodes

renderNode :: NodeRecord -> String
renderNode (NodeRecord snapshot) =
  concat
    [ "  "
    , padRight nodeListRefWidth (renderNodeRefPlain (snapshotRef snapshot))
    , renderSnapshotPayload snapshot
    , "\n"
    ]

renderEvents :: (PrintEvent event) => [TraceEvent event] -> String
renderEvents events =
  renderHeader "Events" ++ concat (zipWith renderEvent [0 :: Int ..] events)

renderEvent :: (PrintEvent event) => Int -> TraceEvent event -> String
renderEvent ix (TraceEvent event audit) =
  concat
    [ padLeft eventIndexWidth (show ix)
    , " | "
    , ansiText eventTitleStyle (printEvent event)
    , "\n"
    , renderAudit audit
    , "\n"
    ]

renderAudit :: Audit acts -> String
renderAudit EmptyAudit     = ""
renderAudit (step :> rest) = renderAuditStep step ++ renderAudit rest

renderAuditStep :: AuditStep act -> String
renderAuditStep (CreateStep snapshot) = renderSnapshotStep1 createStyle snapshot
renderAuditStep (ObserveStep snapshot) =
  renderSnapshotStep1 observeStyle snapshot
renderAuditStep (InspectStep snapshot) =
  renderSnapshotStep1 inspectStyle snapshot
renderAuditStep (UseStep snapshot) = renderSnapshotStep1 useStyle snapshot
renderAuditStep (CopyStep original copy') =
  renderSnapshotStep2 copyStyle original copy'
renderAuditStep (ReplaceStep old new) = renderSnapshotStep2 replaceStyle old new
renderAuditStep (ComputeStep snapshot) =
  renderSnapshotStep1 computeStyle snapshot
renderAuditStep (DestroyStep snapshot) =
  renderSnapshotStep1 destroyStyle snapshot
renderAuditStep (SealStep owner child) =
  renderSnapshotStep2 sealStyle owner child
renderAuditStep (UnsealStep owner child) =
  renderSnapshotStep2 unsealStyle owner child

renderSnapshotStep1 :: StepStyle -> NodeSnapshot tag -> String
renderSnapshotStep1 style snapshot =
  concat [renderStepName style, " ", renderSnapshot snapshot, "\n"]

renderSnapshotStep2 ::
     StepStyle -> NodeSnapshot first -> NodeSnapshot second -> String
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

renderSnapshot :: NodeSnapshot tag -> String
renderSnapshot snapshot =
  padRight snapshotRefWidth (renderNodeRef (snapshotRef snapshot))
    ++ " "
    ++ renderSnapshotPayload snapshot

renderSnapshotPayload :: NodeSnapshot tag -> String
renderSnapshotPayload (NodeSnapshot _ _ view) = renderPayloadView view

snapshotRef :: NodeSnapshot tag -> NodeRef tag
snapshotRef (NodeSnapshot ref _ _) = ref

renderNodeRef :: NodeRef tag -> String
renderNodeRef (NodeRef nodeId) = "[N" ++ show nodeId ++ "]"

renderNodeRefPlain :: NodeRef tag -> String
renderNodeRefPlain (NodeRef nodeId) = "N" ++ show nodeId

renderPayloadView :: PayloadView -> String
renderPayloadView (PayloadView text) = text

renderHeader :: String -> String
renderHeader title = title ++ "\n" ++ replicate (length title) '-' ++ "\n"

renderStepName :: StepStyle -> String
renderStepName (StepStyle name colour) =
  stepIndent ++ ansiText [colour] (padLeft stepNameWidth name)

renderEmptyStepName :: String
renderEmptyStepName = stepIndent ++ padLeft stepNameWidth ""

padRight :: Int -> String -> String
padRight n s = s ++ replicate (max 0 (n - length s)) ' '

padLeft :: Int -> String -> String
padLeft n s = replicate (max 0 (n - length s)) ' ' ++ s

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
ansiCode AnsiReset = "\ESC[0m"
ansiCode AnsiBold = "\ESC[1m"
ansiCode AnsiDim = "\ESC[2m"
ansiCode AnsiItalic = "\ESC[3m"
ansiCode AnsiUnderline = "\ESC[4m"
ansiCode (AnsiFg n) = "\ESC[" ++ show n ++ "m"
ansiCode (AnsiBg n) = "\ESC[" ++ show n ++ "m"
ansiCode (Ansi256Fg n) = "\ESC[38;5;" ++ show n ++ "m"
ansiCode (Ansi256Bg n) = "\ESC[48;5;" ++ show n ++ "m"
ansiCode (AnsiRgbFg r g b) =
  "\ESC[38;2;" ++ show r ++ ";" ++ show g ++ ";" ++ show b ++ "m"
ansiCode (AnsiRgbBg r g b) =
  "\ESC[48;2;" ++ show r ++ ";" ++ show g ++ ";" ++ show b ++ "m"
