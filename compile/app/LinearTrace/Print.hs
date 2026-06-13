{-# LANGUAGE GADTs        #-}
{-# LANGUAGE TypeFamilies #-}

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

printGraph :: (PrintDesc desc) => G model desc -> P.IO ()
printGraph graph = P.putStr (renderGraph graph)

printTrace :: (PrintDesc desc) => G model desc -> P.IO ()
printTrace graph = P.putStr (renderTrace graph)

renderGraph :: (PrintDesc desc) => G model desc -> P.String
renderGraph (G ns es) =
  renderHeader "Graph"
    P.++ renderSummary ns es
    P.++ "\n"
    P.++ renderNodes ns
    P.++ "\n"
    P.++ renderTraceEvents es

renderTrace :: (PrintDesc desc) => G model desc -> P.String
renderTrace (G _ es) = renderTraceEvents es

renderSummary :: [NRecord model] -> [Event model desc] -> P.String
renderSummary ns es =
  "Nodes:  "
    P.++ P.show (P.length ns)
    P.++ "\n"
    P.++ "Events: "
    P.++ P.show (P.length es)
    P.++ "\n"

renderNodes :: [NRecord model] -> P.String
renderNodes ns = renderHeader "Nodes" P.++ P.concatMap renderNode ns

renderNode :: NRecord model -> P.String
renderNode (NRecord nid snapshot) =
  "  "
    P.++ padRight 8 ("N" P.++ P.show nid)
    P.++ renderSomeNodeSnapshotPayload snapshot
    P.++ "\n"

renderSomeNodeSnapshotPayload :: SomeNodeSnapshot model -> P.String
renderSomeNodeSnapshotPayload (SomeNodeSnapshot snapshot) =
  renderNodeSnapshotPayload snapshot

renderNodeSnapshotPayload :: NodeSnapshot model tag -> P.String
renderNodeSnapshotPayload (NodeSnapshot _ payloadView' _) =
  renderPayloadView payloadView'

renderPayloadView :: PayloadView -> P.String
renderPayloadView (PayloadView text) = text

renderNRef :: NRef tag -> P.String
renderNRef (NRef nid) = "[N" P.++ P.show nid P.++ "]"

renderNodeSnapshot :: NodeSnapshot model tag -> P.String
renderNodeSnapshot (NodeSnapshot ref payloadView' _) =
  padRight 6 (renderNRef ref) P.++ " " P.++ renderPayloadView payloadView'

renderTraceEvents :: (PrintDesc desc) => [Event model desc] -> P.String
renderTraceEvents es =
  renderHeader "Trace"
    P.++ P.concat (P.zipWith renderEvent (P.enumFrom (0 :: P.Int)) es)

renderEvent :: (PrintDesc desc) => P.Int -> Event model desc -> P.String
renderEvent ix (Event desc ops) =
  padLeft 3 (P.show ix)
    P.++ " | "
    P.++ ansiBold
    P.++ printDesc desc
    P.++ ansiReset
    P.++ "\n"
    P.++ renderTraceOps ops
    P.++ "\n"

renderTraceOps :: TraceOps model acts -> P.String
renderTraceOps TraceNil     = ""
renderTraceOps (op :> rest) = renderTraceOp op P.++ renderTraceOps rest

renderTraceOp :: TraceOp model act -> P.String
renderTraceOp (TraceCreate snapshot) =
  renderOneSnapshotOp "create" ansiGreen snapshot
renderTraceOp (TraceObserve snapshot) =
  renderOneSnapshotOp "observe" ansiCyan snapshot
renderTraceOp (TraceUse snapshot) =
  renderOneSnapshotOp "use" ansiYellow snapshot
renderTraceOp (TraceCopy original copy') =
  renderTwoSnapshotOp "copy" ansiBlue original copy'
renderTraceOp (TraceReplace old new) =
  renderTwoSnapshotOp "replace" ansiMagenta old new
renderTraceOp (TraceCompute snapshot) =
  renderOneSnapshotOp "compute" ansiLime snapshot
renderTraceOp (TraceDestroy snapshot) =
  renderOneSnapshotOp "destroy" ansiRed snapshot

renderOneSnapshotOp ::
     P.String -> P.String -> NodeSnapshot model tag -> P.String
renderOneSnapshotOp name colour snapshot =
  renderTraceActionName name colour
    P.++ " "
    P.++ renderNodeSnapshot snapshot
    P.++ "\n"

renderTwoSnapshotOp ::
     P.String
  -> P.String
  -> NodeSnapshot model tag
  -> NodeSnapshot model tag
  -> P.String
renderTwoSnapshotOp name colour first second =
  renderTraceActionName name colour
    P.++ " "
    P.++ renderNodeSnapshot first
    P.++ "\n"
    P.++ renderEmptyTraceActionName
    P.++ " "
    P.++ renderNodeSnapshot second
    P.++ "\n"

renderTraceActionName :: P.String -> P.String -> P.String
renderTraceActionName name colour =
  "    " P.++ colourText colour (padLeft 16 name)

renderEmptyTraceActionName :: P.String
renderEmptyTraceActionName = "    " P.++ padLeft 16 ""

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

ansiGreen :: P.String
ansiGreen = "\ESC[32m"

ansiCyan :: P.String
ansiCyan = "\ESC[36m"

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

ansiBold :: P.String
ansiBold = "\ESC[1m"
