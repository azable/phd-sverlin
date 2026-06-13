{-# LANGUAGE GADTs #-}

module LinearTrace.Print
  ( PrintDesc(..)
  , renderGraph
  , renderTrace
  , printGraph
  , printTrace
  ) where

import           LinearTrace.Core
import qualified Prelude          as P

class PrintDesc desc where
  printDesc :: desc acts -> P.String

printGraph :: (PrintDesc desc) => TraceGraph desc -> P.IO ()
printGraph graph = P.putStr (renderGraph graph)

printTrace :: (PrintDesc desc) => TraceGraph desc -> P.IO ()
printTrace graph = P.putStr (renderTrace graph)

renderGraph :: (PrintDesc desc) => TraceGraph desc -> P.String
renderGraph (TraceGraph nodes events) =
  renderHeader "Graph"
    P.++ renderSummary nodes events
    P.++ "\n"
    P.++ renderNodes nodes
    P.++ "\n"
    P.++ renderEvents events

renderTrace :: (PrintDesc desc) => TraceGraph desc -> P.String
renderTrace (TraceGraph _ events) = renderEvents events

renderSummary :: [NodeRecord] -> [Event desc] -> P.String
renderSummary nodes events =
  "Nodes:  "
    P.++ P.show (P.length nodes)
    P.++ "\n"
    P.++ "Events: "
    P.++ P.show (P.length events)
    P.++ "\n"

renderNodes :: [NodeRecord] -> P.String
renderNodes nodes = renderHeader "Nodes" P.++ P.concatMap renderNode nodes

renderNode :: NodeRecord -> P.String
renderNode (NodeRecord snapshot) =
  "  "
    P.++ padRight 8 (renderNodeRefPlain (snapshotRef snapshot))
    P.++ renderSnapshotPayload snapshot
    P.++ "\n"

renderEvents :: (PrintDesc desc) => [Event desc] -> P.String
renderEvents events =
  renderHeader "Trace"
    P.++ P.concat (P.zipWith renderEvent (P.enumFrom (0 :: P.Int)) events)

renderEvent :: (PrintDesc desc) => P.Int -> Event desc -> P.String
renderEvent ix (Event desc trace) =
  padLeft 3 (P.show ix)
    P.++ " | "
    P.++ ansiBold
    P.++ printDesc desc
    P.++ ansiReset
    P.++ "\n"
    P.++ renderSteps trace
    P.++ "\n"

renderSteps :: Trace acts -> P.String
renderSteps EmptyTrace     = ""
renderSteps (step :> rest) = renderStep step P.++ renderSteps rest

renderStep :: TraceStep act -> P.String
renderStep (CreateStep snapshot) =
  renderOneSnapshotStep "create" ansiGreen snapshot
renderStep (ObserveStep snapshot) =
  renderOneSnapshotStep "observe" ansiCyan snapshot
renderStep (InspectStep snapshot) =
  renderOneSnapshotStep "inspect" ansiBrightCyan snapshot
renderStep (UseStep snapshot) = renderOneSnapshotStep "use" ansiYellow snapshot
renderStep (CopyStep original copy') =
  renderTwoSnapshotStep "copy" ansiBlue original copy'
renderStep (ReplaceStep old new) =
  renderTwoSnapshotStep "replace" ansiMagenta old new
renderStep (ComputeStep snapshot) =
  renderOneSnapshotStep "compute" ansiLime snapshot
renderStep (DestroyStep snapshot) =
  renderOneSnapshotStep "destroy" ansiRed snapshot

renderOneSnapshotStep :: P.String -> P.String -> NodeSnapshot tag -> P.String
renderOneSnapshotStep name colour snapshot =
  renderStepName name colour P.++ " " P.++ renderSnapshot snapshot P.++ "\n"

renderTwoSnapshotStep ::
     P.String -> P.String -> NodeSnapshot tag -> NodeSnapshot tag -> P.String
renderTwoSnapshotStep name colour first second =
  renderStepName name colour
    P.++ " "
    P.++ renderSnapshot first
    P.++ "\n"
    P.++ renderEmptyStepName
    P.++ " "
    P.++ renderSnapshot second
    P.++ "\n"

renderSnapshot :: NodeSnapshot tag -> P.String
renderSnapshot snapshot =
  padRight 6 (renderNodeRef (snapshotRef snapshot))
    P.++ " "
    P.++ renderSnapshotPayload snapshot

renderSnapshotPayload :: NodeSnapshot tag -> P.String
renderSnapshotPayload (NodeSnapshot _ _ view) = renderPayloadView view

snapshotRef :: NodeSnapshot tag -> NodeRef tag
snapshotRef (NodeSnapshot ref _ _) = ref

renderNodeRef :: NodeRef tag -> P.String
renderNodeRef (NodeRef nodeId) = "[N" P.++ P.show nodeId P.++ "]"

renderNodeRefPlain :: NodeRef tag -> P.String
renderNodeRefPlain (NodeRef nodeId) = "N" P.++ P.show nodeId

renderPayloadView :: PayloadView -> P.String
renderPayloadView (PayloadView text) = text

renderStepName :: P.String -> P.String -> P.String
renderStepName name colour = "    " P.++ colourText colour (padLeft 16 name)

renderEmptyStepName :: P.String
renderEmptyStepName = "    " P.++ padLeft 16 ""

renderHeader :: P.String -> P.String
renderHeader title =
  title P.++ "\n" P.++ P.replicate (P.length title) '-' P.++ "\n"

padRight :: P.Int -> P.String -> P.String
padRight n s = s P.++ P.replicate (P.max 0 (n P.- P.length s)) ' '

padLeft :: P.Int -> P.String -> P.String
padLeft n s = P.replicate (P.max 0 (n P.- P.length s)) ' ' P.++ s

colourText :: P.String -> P.String -> P.String
colourText colour text = colour P.++ text P.++ ansiReset

ansiReset :: P.String
ansiReset = "\ESC[0m"

ansiBold :: P.String
ansiBold = "\ESC[1m"

ansiGreen :: P.String
ansiGreen = "\ESC[32m"

ansiCyan :: P.String
ansiCyan = "\ESC[36m"

ansiBrightCyan :: P.String
ansiBrightCyan = "\ESC[96m"

ansiYellow :: P.String
ansiYellow = "\ESC[33m"

ansiBlue :: P.String
ansiBlue = "\ESC[34m"

ansiMagenta :: P.String
ansiMagenta = "\ESC[35m"

ansiLime :: P.String
ansiLime = "\ESC[92m"

ansiRed :: P.String
ansiRed = "\ESC[31m"
