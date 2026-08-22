import { describe, expect, it } from 'vitest';

import type { ProjectEventOf } from '$lib/projects/events';

import { presentProjectEvent } from './event-presentation';

const operationId = '12345678-1234-4123-8123-123456789abc';

describe('project event presentation', () => {
  it('describes repairable compilation failures as visible repair progress', () => {
    expect(presentProjectEvent(compilationFailure())).toMatchObject({
      icon: 'failure',
      progress: 'Compilation failed; checking repair…',
      tone: 'destructive'
    });
  });

  it('uses destructive presentation only for error notices', () => {
    expect(presentProjectEvent(systemNotice('warning')).tone).toBe('default');
    expect(presentProjectEvent(systemNotice('error')).tone).toBe('destructive');
  });
});

function compilationFailure(): ProjectEventOf<'compilation.failed'> {
  return {
    ...base(),
    type: 'compilation.failed',
    payload: {
      durationMs: 10,
      exitCode: 1,
      failureKind: 'source',
      diagnostics: [],
      stdout: blob(),
      stderr: blob(),
      timedOut: false,
      repairEligible: true,
      error: 'Source failed'
    }
  };
}

function systemNotice(
  severity: ProjectEventOf<'system.notified'>['payload']['severity']
): ProjectEventOf<'system.notified'> {
  return { ...base(), type: 'system.notified', payload: { severity, message: severity } };
}

function base() {
  return {
    id: 2,
    actor: { kind: 'system' as const },
    operationId,
    createdAt: '2026-01-01T00:00:01.000Z'
  };
}

function blob() {
  return { sha256: '0'.repeat(64), byteLength: 0, mediaType: 'text/plain' };
}
