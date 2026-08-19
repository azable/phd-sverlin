export type {
  CanvasSpec,
  CspValue,
  CspVariable,
  CspVariableId,
  HslColor,
  RenderInstanceId,
  StyleVariableBinding,
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

export type CompileLockHolder = {
  owner: string;
  pid: number;
  startedAt: string;
  cwd: string;
  command: string;
  args: string[];
  seed?: number;
  details?: boolean;
  outputPath?: string;
  lockPath: string;
};

export type CompileStatus = { running: false } | ({ running: true } & CompileLockHolder);

export type VisualizationSuccess = {
  ok: true;
  trace: CompiledVisualization;
  seed: number;
  details: boolean;
};

export type VisualizationFailure = {
  ok: false;
  error: string;
  seed?: number;
  details?: boolean;
  debug?: CompileDebug;
  lock?: CompileLockHolder;
};

export type CompileStreamStatus = {
  ok: true;
  status: 'starting' | 'running' | 'complete';
  seed: number;
  details: boolean;
  debug?: CompileDebug;
};

export type CompileStreamOutput = { ok: true; chunk: string };
export type CompileStreamSuccess = VisualizationSuccess;
export type CompileStreamFailure = VisualizationFailure & { status: number };
