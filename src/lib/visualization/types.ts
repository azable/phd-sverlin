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

export type VisualizationSuccess = {
  ok: true;
  trace: CompiledVisualization;
  seed: number;
  revision: number;
};

export type VisualizationFailure = {
  ok: false;
  error: string;
  seed?: number;
  revision?: number;
  debug?: CompileDebug;
};

export type CompileStreamStatus = {
  ok: true;
  status: 'starting' | 'running' | 'complete';
  seed: number;
  revision: number;
  debug?: CompileDebug;
};

export type CompileStreamOutput = { ok: true; chunk: string };
export type CompileStreamSuccess = VisualizationSuccess;
export type CompileStreamFailure = VisualizationFailure & { status: number };
