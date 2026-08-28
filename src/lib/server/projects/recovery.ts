/** Terminal Timeline events for lifecycle work interrupted between durable appends. */

import type { NewProjectEvent, ProjectEvent, ProjectEventOf } from '$lib/shared/projects/events';

import { recordText } from './fingerprints';

/** Derive terminal cancellation events for lifecycle requests left open by a process crash. */
export function recoveryEventsForInterruptedOperations(events: ProjectEvent[]): NewProjectEvent[] {
  const compilations = new Map<string, ProjectEventOf<'compilation.requested'>>();
  const generations = new Map<string, ProjectEventOf<'ai.generation-requested'>>();
  for (const event of events) {
    if (event.type === 'compilation.requested') compilations.set(event.operationId, event);
    if (event.type === 'compilation.succeeded' || event.type === 'compilation.failed') {
      compilations.delete(event.operationId);
    }
    if (event.type === 'ai.generation-requested') {
      generations.set(`${event.operationId}:${event.payload.attempt}`, event);
    }
    if (event.type === 'ai.generation-succeeded' || event.type === 'ai.generation-failed') {
      generations.delete(`${event.operationId}:${event.payload.attempt}`);
    }
  }

  const recoveredAt = new Date().toISOString();
  const emptyText = recordText('', 'text/plain');
  const pending = [
    ...[...compilations.values()].map((request) => ({ request, kind: 'compile' as const })),
    ...[...generations.values()].map((request) => ({ request, kind: 'generation' as const }))
  ].sort((left, right) => left.request.id - right.request.id);

  return pending.map(({ request, kind }) => {
    if (kind === 'compile') {
      const message = 'Compilation was interrupted by a server restart.';
      const event: NewProjectEvent<'compilation.failed'> = {
        type: 'compilation.failed',
        actor: { kind: 'system' },
        operationId: request.operationId,
        createdAt: recoveredAt,
        payload: {
          durationMs: 0,
          exitCode: null,
          failureKind: 'cancelled',
          diagnostics: [{ severity: 'unknown', message, raw: message }],
          stdout: emptyText,
          stderr: recordText(message, 'text/plain'),
          timedOut: false,
          repairEligible: false,
          error: message
        }
      };
      return event;
    }

    const event: NewProjectEvent<'ai.generation-failed'> = {
      type: 'ai.generation-failed',
      actor: { kind: 'system' },
      operationId: request.operationId,
      createdAt: recoveredAt,
      payload: {
        attempt: request.payload.attempt,
        failureKind: 'cancelled',
        durationMs: 0,
        message: 'AI generation was interrupted by a server restart.'
      }
    };
    return event;
  });
}
