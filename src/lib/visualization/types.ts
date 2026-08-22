export type {
  CanvasSpec,
  CspValue,
  CspVariable,
  CspVariableId,
  HslColor,
  RenderInstanceId,
  StyleVariableBinding,
  TimelineStep,
  VisualElement,
  VisualElementKind,
  VisualId,
  VisualInstance,
  VisualStyle,
  VisualizationPackage
} from './generated/visualization-ir';

import type {
  RenderInstanceId,
  VisualElement,
  VisualizationPackage
} from './generated/visualization-ir';

/** The canonical Haskell-owned wire payload returned by the compile API. */
export type CompiledVisualization = VisualizationPackage;

/** A registry element paired with its identity in the current scene snapshot. */
export type LiveElement = VisualElement & {
  instanceId: RenderInstanceId;
};

export type CompileDebug = {
  command: string;
  args: string[];
  cwd: string;
  outputPath?: string;
  timeoutMs?: number;
  timedOut?: boolean;
  durationMs: number;
  exitCode: number | null;
  stdout: string;
  stderr: string;
  error?: string;
};

export type CompilerDiagnostic = {
  severity: 'error' | 'warning' | 'unknown';
  code?: string;
  sourcePath?: string;
  line?: number;
  column?: number;
  message: string;
  raw: string;
};

export type CompileFailureKind =
  | 'source'
  | 'pipeline'
  | 'infrastructure'
  | 'timeout'
  | 'invalid-output'
  | 'cancelled';

/** Decode the trusted, Haskell-generated visualization wire format at its boundary. */
export function decodeVisualization(json: string): CompiledVisualization {
  return JSON.parse(json) as CompiledVisualization;
}
