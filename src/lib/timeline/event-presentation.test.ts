import { describe, expect, it } from 'vitest';

import type { CompilationFailedEvent, SystemNotifiedEvent } from '$lib/projects/types';

import { presentProjectEvent } from './event-presentation';

describe('project event presentation', () => {
  it('describes repairable compilation failures as visible repair progress', () => {
    const presentation = presentProjectEvent(compilationFailure());

    expect(presentation).toMatchObject({
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

function compilationFailure(): CompilationFailedEvent {
  return {
    eventId: 'compile-failed',
    sequence: 1,
    parentEventId: 'root',
    type: 'compilation.failed',
    actor: { kind: 'system' },
    correlationId: 'correlation',
    createdAt: '2026-01-01T00:00:01.000Z',
    payload: {
      requestEventId: 'compile-request',
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

function systemNotice(severity: SystemNotifiedEvent['payload']['severity']): SystemNotifiedEvent {
  return {
    eventId: `notice-${severity}`,
    sequence: 1,
    parentEventId: 'root',
    type: 'system.notified',
    actor: { kind: 'system' },
    correlationId: 'correlation',
    createdAt: '2026-01-01T00:00:01.000Z',
    payload: { severity, message: severity, relatedEventIds: [] }
  };
}

function blob() {
  return {
    sha256: '0'.repeat(64),
    byteLength: 0,
    mediaType: 'text/plain',
    encoding: 'utf-8' as const
  };
}
