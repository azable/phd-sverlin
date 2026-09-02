import { describe, expect, it } from 'vitest';

import type { CompilationMetrics, ProjectEvent } from './events';

import { projectCompilationMetrics } from './compilation-metrics';

const compilationId = '12345678-1234-4123-8123-123456789abc';
const metrics: CompilationMetrics = {
  schemaVersion: 1,
  compilationId,
  viewSeeds: [1, 2],
  requestedViewCount: 2,
  producedViewCount: 2,
  service: {
    totalMs: 10,
    requestPreparationMs: 1,
    queueWaitMs: 2,
    compilerProcessMs: 5,
    outputValidationMs: 1,
    cleanupMs: 1
  },
  compiler: {
    schemaVersion: 1,
    viewSeeds: [1, 2],
    phasesMs: {
      sourceInterpretation: 6,
      compilerInternalTotal: 8
    },
    counts: {
      outputViews: 2
    },
    views: [
      {
        seed: 1,
        materializationMs: 0.2,
        counts: { outputElements: 3 },
        labels: {
          solverBackend: 'affine-sampler',
          decisionCoverage: 'exact-enumeration'
        }
      },
      {
        seed: 2,
        materializationMs: 0.3,
        counts: { outputElements: 3 },
        labels: {
          solverBackend: 'affine-sampler',
          decisionCoverage: 'exact-enumeration'
        }
      }
    ],
    failedPhase: null
  }
};

describe('project compilation metrics', () => {
  it('returns one invocation for metrics repeated across a seeded batch', () => {
    const events = [outcome(1, 0), outcome(2, 1)];
    expect(projectCompilationMetrics(events)).toEqual([metrics]);
    expect(projectCompilationMetrics(events)[0]?.compiler?.phasesMs.sourceInterpretation).toBe(6);
  });

  it('ignores historical outcomes without structured metrics', () => {
    const event = outcome(1, 0);
    delete (event.payload as { metrics?: CompilationMetrics }).metrics;
    expect(projectCompilationMetrics([event])).toEqual([]);
  });
});

function outcome(id: number, batchIndex: number): ProjectEvent {
  return {
    id,
    type: 'compilation.failed',
    actor: { kind: 'system' },
    operationId: '12345678-1234-4123-8123-123456789abd',
    createdAt: `2026-09-01T00:00:0${id}.000Z`,
    payload: {
      durationMs: 5,
      compilationId,
      seed: batchIndex + 1,
      batchIndex,
      batchSize: 2,
      metrics,
      exitCode: 1,
      failureKind: 'source',
      diagnostics: [],
      stdout: recorded(''),
      stderr: recorded('error'),
      timedOut: false,
      repairEligible: true
    }
  };
}

function recorded(text: string) {
  return { text, mediaType: 'text/plain', sha256: 'a'.repeat(64) };
}
