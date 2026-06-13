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

printGraph :: (PrintDesc desc) => G desc -> P.IO ()
printGraph graph = P.putStr (renderGraph graph)

printTrace :: (PrintDesc desc) => G desc -> P.IO ()
printTrace graph = P.putStr (renderTrace graph)

renderGraph :: (PrintDesc desc) => G desc -> P.String
renderGraph (G ns es) =
  renderHeader "Graph"
    P.++ renderSummary ns es
    P.++ "\n"
    P.++ renderNodes ns
    P.++ "\n"
    P.++ renderTraceEvents es

renderTrace :: (PrintDesc desc) => G desc -> P.String
renderTrace (G _ es) = renderTraceEvents es

renderSummary :: [NRecord] -> [Event desc] -> P.String
renderSummary ns es =
  "Nodes:  "
    P.++ P.show (P.length ns)
    P.++ "\n"
    P.++ "Events: "
    P.++ P.show (P.length es)
    P.++ "\n"

renderNodes :: [NRecord] -> P.String
renderNodes ns = renderHeader "Nodes" P.++ P.concatMap renderNode ns

renderNode :: NRecord -> P.String
renderNode (NRecord nid payload) =
  "  " P.++ padRight 8 ("N" P.++ P.show nid) P.++ renderSome payload P.++ "\n"

renderSome :: Some -> P.String
renderSome (Some _ payload) = renderPayloadView payload

renderPayloadView :: PayloadView -> P.String
renderPayloadView (PayloadView text) = text

renderNRef :: NRef tag -> P.String
renderNRef (NRef nid) = "[N" P.++ P.show nid P.++ "]"

renderObservation :: Observation tag -> P.String
renderObservation (Observation r payload) =
  padRight 6 (renderNRef r) P.++ " " P.++ renderPayloadView payload

renderSomeObservation :: SomeObservation -> P.String
renderSomeObservation (SomeObservation obs) = renderObservation obs

renderTraceEvents :: (PrintDesc desc) => [Event desc] -> P.String
renderTraceEvents es =
  renderHeader "Trace"
    P.++ P.concat (P.zipWith renderEvent (P.enumFrom (0 :: P.Int)) es)

renderEvent :: (PrintDesc desc) => P.Int -> Event desc -> P.String
renderEvent ix (Event desc ops) =
  padLeft 3 (P.show ix)
    P.++ " | "
    P.++ ansiBold
    P.++ printDesc desc
    P.++ ansiReset
    P.++ "\n"
    P.++ P.concatMap renderTraceOp ops
    P.++ "\n"

renderTraceOp :: SomeTraceOp -> P.String
renderTraceOp (SomeTraceOp (TraceOp action observations)) =
  case observations of
    [] -> renderTraceActionName action P.++ "\n"
    first:rest ->
      renderTaggedObservation action first
        P.++ P.concatMap renderUntaggedObservation rest

renderTaggedObservation :: TraceAction act -> SomeObservation -> P.String
renderTaggedObservation action observation =
  renderTraceActionName action
    P.++ " "
    P.++ renderSomeObservation observation
    P.++ "\n"

renderUntaggedObservation :: SomeObservation -> P.String
renderUntaggedObservation observation =
  renderEmptyTraceActionName
    P.++ " "
    P.++ renderSomeObservation observation
    P.++ "\n"

renderTraceActionName :: TraceAction act -> P.String
renderTraceActionName action =
  "    " P.++ colourTraceAction action (padLeft 16 (traceActionName action))

renderEmptyTraceActionName :: P.String
renderEmptyTraceActionName = "    " P.++ padLeft 16 ""

renderHeader :: P.String -> P.String
renderHeader title =
  title P.++ "\n" P.++ P.replicate (P.length title) '-' P.++ "\n"

padRight :: P.Int -> P.String -> P.String
padRight n s = s P.++ P.replicate (P.max 0 (n P.- P.length s)) ' '

padLeft :: P.Int -> P.String -> P.String
padLeft n s = P.replicate (P.max 0 (n P.- P.length s)) ' ' P.++ s

colourTraceAction :: TraceAction act -> P.String -> P.String
colourTraceAction action text = traceActionAnsi action P.++ text P.++ ansiReset

traceActionAnsi :: TraceAction act -> P.String
traceActionAnsi TraceCreate  = ansiGreen
traceActionAnsi TraceObserve = ansiCyan
traceActionAnsi TraceUse     = ansiYellow
traceActionAnsi TraceCopy    = ansiBlue
traceActionAnsi TraceReplace = ansiMagenta
traceActionAnsi TraceCompute = ansiLime
traceActionAnsi TraceDestroy = ansiRed

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
