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

class PrintEvent event where
  printEvent :: event acts -> String

printGraph :: (PrintEvent event) => TraceGraph event -> IO ()
printGraph graph = putStr (renderGraph graph)

printTrace :: (PrintEvent event) => TraceGraph event -> IO ()
printTrace graph = putStr (renderTrace graph)

renderGraph :: (PrintEvent event) => TraceGraph event -> String
renderGraph (TraceGraph nodes events) =
  renderHeader "Graph"
    ++ renderSummary nodes events
    ++ "\n"
    ++ renderNodes nodes
    ++ "\n"
    ++ renderEvents events

renderTrace :: (PrintEvent event) => TraceGraph event -> String
renderTrace (TraceGraph _ events) = renderEvents events

renderSummary :: [NodeRecord] -> [TraceEvent event] -> String
renderSummary nodes events =
  "Nodes:  "
    ++ show (length nodes)
    ++ "\n"
    ++ "Events: "
    ++ show (length events)
    ++ "\n"

renderNodes :: [NodeRecord] -> String
renderNodes nodes = renderHeader "Nodes" ++ concatMap renderNode nodes

renderNode :: NodeRecord -> String
renderNode (NodeRecord snapshot) =
  "  "
    ++ padRight 8 (renderNodeRefPlain (snapshotRef snapshot))
    ++ renderSnapshotPayload snapshot
    ++ "\n"

renderEvents :: (PrintEvent event) => [TraceEvent event] -> String
renderEvents events =
  renderHeader "Events"
    ++ concat (zipWith renderEvent (enumFrom (0 :: Int)) events)

renderEvent :: (PrintEvent event) => Int -> TraceEvent event -> String
renderEvent ix (TraceEvent event audit) =
  padLeft 3 (show ix)
    ++ " | "
    ++ ansiBold
    ++ printEvent event
    ++ ansiReset
    ++ "\n"
    ++ renderAudit audit
    ++ "\n"

renderAudit :: Audit acts -> String
renderAudit EmptyAudit     = ""
renderAudit (step :> rest) = renderAuditStep step ++ renderAudit rest

renderAuditStep :: AuditStep act -> String
renderAuditStep (CreateStep snapshot) =
  renderSnapshotStep1 "create" ansiCreate snapshot
renderAuditStep (ObserveStep snapshot) =
  renderSnapshotStep1 "observe" ansiObserve snapshot
renderAuditStep (InspectStep snapshot) =
  renderSnapshotStep1 "inspect" ansiInspect snapshot
renderAuditStep (UseStep snapshot) = renderSnapshotStep1 "use" ansiUse snapshot
renderAuditStep (CopyStep original copy') =
  renderSnapshotStep2 "copy" ansiCopy original copy'
renderAuditStep (ReplaceStep old new) =
  renderSnapshotStep2 "replace" ansiReplace old new
renderAuditStep (ComputeStep snapshot) =
  renderSnapshotStep1 "compute" ansiCompute snapshot
renderAuditStep (DestroyStep snapshot) =
  renderSnapshotStep1 "destroy" ansiDestroy snapshot
renderAuditStep (SealStep owner child) =
  renderSnapshotStep2 "seal" ansiSeal owner child
renderAuditStep (UnsealStep owner child) =
  renderSnapshotStep2 "unseal" ansiUnseal owner child

renderSnapshotStep1 :: String -> String -> NodeSnapshot tag -> String
renderSnapshotStep1 name colour snapshot =
  renderStepName name colour ++ " " ++ renderSnapshot snapshot ++ "\n"

renderSnapshotStep2 ::
     String -> String -> NodeSnapshot first -> NodeSnapshot second -> String
renderSnapshotStep2 name colour first second =
  renderStepName name colour
    ++ " "
    ++ renderSnapshot first
    ++ "\n"
    ++ renderEmptyStepName
    ++ " "
    ++ renderSnapshot second
    ++ "\n"

renderSnapshot :: NodeSnapshot tag -> String
renderSnapshot snapshot =
  padRight 6 (renderNodeRef (snapshotRef snapshot))
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

renderStepName :: String -> String -> String
renderStepName name colour = "    " ++ colourText colour (padLeft 16 name)

renderEmptyStepName :: String
renderEmptyStepName = "    " ++ padLeft 16 ""

renderHeader :: String -> String
renderHeader title = title ++ "\n" ++ replicate (length title) '-' ++ "\n"

padRight :: Int -> String -> String
padRight n s = s ++ replicate (max 0 (n - length s)) ' '

padLeft :: Int -> String -> String
padLeft n s = replicate (max 0 (n - length s)) ' ' ++ s

colourText :: String -> String -> String
colourText colour text = colour ++ text ++ ansiReset

ansiReset :: String
ansiReset = "\ESC[0m"

ansiBold :: String
ansiBold = "\ESC[1m"

ansi256Fg :: Int -> String
ansi256Fg n = "\ESC[38;5;" ++ show n ++ "m"

ansiCreate :: String
ansiCreate = ansi256Fg 82 -- green

ansiObserve :: String
ansiObserve = ansi256Fg 51 -- cyan

ansiInspect :: String
ansiInspect = ansi256Fg 123 -- pale cyan

ansiUse :: String
ansiUse = ansi256Fg 220 -- yellow

ansiCopy :: String
ansiCopy = ansi256Fg 75 -- blue

ansiReplace :: String
ansiReplace = ansi256Fg 171 -- purple

ansiCompute :: String
ansiCompute = ansi256Fg 118 -- lime

ansiDestroy :: String
ansiDestroy = ansi256Fg 196 -- red

ansiSeal :: String
ansiSeal = ansi256Fg 213 -- pink

ansiUnseal :: String
ansiUnseal = ansi256Fg 208 -- orange
