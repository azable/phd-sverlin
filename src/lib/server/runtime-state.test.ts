import { describe, expect, it } from 'vitest';

import type { ProjectEvent } from '$lib/shared/projects/events';

import { recoveryEventsForInterruptedOperations } from './projects/recovery';

describe('runtime crash recovery', () => {
  it('terminates unmatched compiler and AI requests without duplicating completed work', () => {
    const events = [
      event('compilation.requested', 1, '11111111-1111-4111-8111-111111111111', {
        purpose: 'seed-change',
        input: 'committed-artifact',
        source: recorded('source'),
        sourceLabel: 'Main.sverlin',
        seed: 1
      }),
      event('compilation.failed', 2, '11111111-1111-4111-8111-111111111111', {
        durationMs: 1,
        exitCode: 1,
        failureKind: 'source',
        diagnostics: [],
        stdout: recorded(''),
        stderr: recorded('failed'),
        timedOut: false,
        repairEligible: true
      }),
      event('ai.generation-requested', 3, '22222222-2222-4222-8222-222222222222', {
        attempt: 1,
        purpose: 'initial',
        prompt: recorded('{}', 'application/json'),
        promptTemplateSha256: 'a'.repeat(64),
        requestedModel: 'test-model',
        parameters: {}
      }),
      event('compilation.requested', 4, '33333333-3333-4333-8333-333333333333', {
        purpose: 'seed-change',
        input: 'committed-artifact',
        source: recorded('source'),
        sourceLabel: 'Main.sverlin',
        seed: 2
      })
    ] as ProjectEvent[];

    const recovered = recoveryEventsForInterruptedOperations(events);
    expect(recovered.map(({ type }) => type)).toEqual([
      'ai.generation-failed',
      'compilation.failed'
    ]);
    expect(
      recovered.every(
        ({ payload }) => 'failureKind' in payload && payload.failureKind === 'cancelled'
      )
    ).toBe(true);
  });
});

function event(type: string, id: number, operationId: string, payload: unknown) {
  return {
    id,
    type,
    operationId,
    actor: { kind: 'system' },
    createdAt: '2026-08-28T00:00:00.000Z',
    payload
  };
}

function recorded(text: string, mediaType = 'text/plain') {
  return { text, mediaType, sha256: 'a'.repeat(64) };
}
