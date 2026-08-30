/**
 * Public visualization-generation service.
 *
 * Callers provide Sverlin source and seeds. Process execution and the concrete
 * compiler implementation remain private to this module.
 *
 * @packageDocumentation
 */

import type { Visualization } from '$lib/shared/visualization';
import type {
  CompilationProvenance,
  CompilationResource,
  CompilerDiagnostic,
  TargetDiagnostic
} from '$lib/shared/projects/events/values';

import { compileSource, type CompileVisualizationResult } from './compile';
import { formatDiagnosticSummary } from './diagnostics';
import { readPreparedCompiler } from './prepared-compiler.js';
import { compilerScheduler } from './scheduler';

/** Source supplied to visualization generation without a physical filesystem path. */
export type SverlinSource = { name: string; content: string };

/** Portable execution details useful for provenance and diagnostics. */
export type VisualizationExecution = {
  durationMs: number;
  exitCode: number | null;
  stdout: string;
  stderr: string;
  timedOut: boolean;
};

/** Verified immutable resource bytes emitted beside one visualization. */
export type VisualizationResource = CompilationResource & { bytes: Uint8Array };

/** Stable failure categories independent from transport or implementation details. */
export type VisualizationFailureKind =
  | 'source'
  | 'pipeline'
  | 'infrastructure'
  | 'timeout'
  | 'invalid-output'
  | 'cancelled';

/** Non-sensitive admission state for readiness and operational diagnostics. */
export type VisualizationServiceStatus = {
  accepting: boolean;
  active: boolean;
  queued: number;
};

/** One success or failure, always correlated with its requested seed. */
export type VisualizationGenerationResult =
  | {
      ok: true;
      seed: number;
      visualization: Visualization;
      resources: VisualizationResource[];
      provenance: CompilationProvenance;
      targetDiagnostics: TargetDiagnostic[];
      compilerSourceSha256?: string;
      execution: VisualizationExecution;
    }
  | {
      ok: false;
      seed: number;
      error: string;
      diagnostics: CompilerDiagnostic[];
      failureKind: VisualizationFailureKind;
      execution: VisualizationExecution;
    };

export type GenerateVisualizationRequest = {
  source: SverlinSource;
  seed: number;
  signal?: AbortSignal;
};

export type GenerateVisualizationBatchRequest = {
  source: SverlinSource;
  seeds: readonly number[];
  signal?: AbortSignal;
};

/** The sole server-facing compiler contract. */
export interface SverlinVisualizationService {
  generate(request: GenerateVisualizationRequest): Promise<VisualizationGenerationResult>;
  generateBatch(
    request: GenerateVisualizationBatchRequest
  ): Promise<VisualizationGenerationResult[]>;
  readiness(): Promise<{ sourceSha256: string; preparedAt: string }>;
  status(): VisualizationServiceStatus;
  shutdown(): void;
}

class DefaultSverlinVisualizationService implements SverlinVisualizationService {
  async generate(request: GenerateVisualizationRequest): Promise<VisualizationGenerationResult> {
    assertSource(request.source);
    assertSeed(request.seed);
    const result = await compileSource({
      sourceContent: request.source.content,
      sourceLabel: request.source.name,
      seed: request.seed,
      owner: 'visualization-service',
      signal: request.signal
    });
    return publicResult(request.seed, result);
  }

  async generateBatch(
    request: GenerateVisualizationBatchRequest
  ): Promise<VisualizationGenerationResult[]> {
    assertSource(request.source);
    const results: VisualizationGenerationResult[] = [];
    for (const seed of request.seeds) {
      results.push(await this.generate({ source: request.source, seed, signal: request.signal }));
    }
    return results;
  }

  async readiness(): Promise<{ sourceSha256: string; preparedAt: string }> {
    const prepared = await readPreparedCompiler();
    return { sourceSha256: prepared.sourceSha256, preparedAt: prepared.preparedAt };
  }

  status(): VisualizationServiceStatus {
    return compilerScheduler.status();
  }

  shutdown(): void {
    compilerScheduler.shutdown();
  }
}

export const visualizationService: SverlinVisualizationService =
  new DefaultSverlinVisualizationService();

export { formatDiagnosticSummary };

function publicResult(
  seed: number,
  result: CompileVisualizationResult
): VisualizationGenerationResult {
  const execution = {
    durationMs: result.debug.durationMs,
    exitCode: result.debug.exitCode,
    stdout: result.debug.stdout,
    stderr: result.debug.stderr,
    timedOut: result.debug.timedOut ?? false
  };
  return result.ok
    ? {
        ok: true,
        seed,
        visualization: result.visualization,
        resources: result.resources,
        provenance: result.provenance,
        targetDiagnostics: result.targetDiagnostics,
        ...(result.compilerSourceSha256
          ? { compilerSourceSha256: result.compilerSourceSha256 }
          : {}),
        execution
      }
    : {
        ok: false,
        seed,
        error: result.error,
        diagnostics: result.diagnostics,
        failureKind: result.failureKind ?? 'pipeline',
        execution
      };
}

function assertSource(source: SverlinSource): void {
  if (
    !source.name.endsWith('.sverlin') ||
    source.name.includes('/') ||
    source.name.includes('\\')
  ) {
    throw new Error('Sverlin source name must be a logical .sverlin filename.');
  }
}

function assertSeed(seed: number): void {
  if (!Number.isSafeInteger(seed) || seed < 1) throw new Error('Seed must be a positive integer.');
}
