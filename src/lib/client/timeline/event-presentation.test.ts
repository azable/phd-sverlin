import { describe, expect, it } from 'vitest';

import type { ProjectEventOf } from '$lib/shared/projects/events';

import { presentProjectEvent } from './event-presentation';

const operationId = '12345678-1234-4123-8123-123456789abc';

describe('project event presentation', () => {
  it('describes repairable build failures as visible repair progress', () => {
    expect(presentProjectEvent(buildFailure())).toMatchObject({
      icon: 'failure',
      progress: 'Build failed; checking repair…',
      tone: 'destructive'
    });
  });

  it('uses destructive presentation only for error notices', () => {
    expect(presentProjectEvent(systemNotice('warning')).tone).toBe('default');
    expect(presentProjectEvent(systemNotice('error')).tone).toBe('destructive');
  });
});

function buildFailure(): ProjectEventOf<'build.failed'> {
  return {
    ...base(),
    type: 'build.failed',
    payload: {
      durationMs: 10,
      failureKind: 'source',
      diagnostics: [],
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
