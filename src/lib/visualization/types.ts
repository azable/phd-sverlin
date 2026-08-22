/**
 * Shared visualization wire types and frontend rendering types.
 *
 * @packageDocumentation
 */

/** Canonical visualization IR types generated from the Haskell model. */
export type * from './generated/visualization-ir';

import type { RenderInstanceId, VisualElement, Visualization } from './generated/visualization-ir';

/** A visual element paired with its identity in the current scene snapshot. */
export type LiveElement = VisualElement & {
  instanceId: RenderInstanceId;
};

/** Process and diagnostic metadata captured for one compiler invocation. */
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

/** A structured diagnostic parsed from compiler output. */
export type CompilerDiagnostic = {
  severity: 'error' | 'warning' | 'unknown';
  code?: string;
  sourcePath?: string;
  line?: number;
  column?: number;
  message: string;
  raw: string;
};

/** Stable categories used to route and present compilation failures. */
export type CompileFailureKind =
  | 'source'
  | 'pipeline'
  | 'infrastructure'
  | 'timeout'
  | 'invalid-output'
  | 'cancelled';

/** Decode the trusted, Haskell-generated visualization wire format at its boundary. */
export function decodeVisualization(json: string): Visualization {
  const visualization = JSON.parse(json) as Visualization;

  for (const element of visualization.elements) {
    if ((element.kind as { kind: string }).kind === 'trace') {
      element.kind = { kind: 'leaf' };
    }
  }

  return visualization;
}
