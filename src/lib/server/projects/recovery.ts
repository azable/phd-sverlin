/** Terminal Timeline events for lifecycle work interrupted between durable appends. */

import type { NewProjectEvent, ProjectEvent, ProjectEventOf } from '$lib/shared/projects/events';

/** Derive terminal cancellation events for lifecycle requests left open by a process crash. */
export function recoveryEventsForInterruptedOperations(events: ProjectEvent[]): NewProjectEvent[] {
  const builds = new Map<string, ProjectEventOf<'build.requested'>>();
  const generations = new Map<string, ProjectEventOf<'ai.generation-requested'>>();
  for (const event of events) {
    if (event.type === 'build.requested') builds.set(event.operationId, event);
    if (event.type === 'build.succeeded' || event.type === 'build.failed') {
      builds.delete(event.operationId);
    }
    if (event.type === 'ai.generation-requested') {
      generations.set(`${event.operationId}:${event.payload.attempt}`, event);
    }
    if (event.type === 'ai.generation-succeeded' || event.type === 'ai.generation-failed') {
      generations.delete(`${event.operationId}:${event.payload.attempt}`);
    }
  }

  const recoveredAt = new Date().toISOString();
  const pending = [
    ...[...builds.values()].map((request) => ({ request, kind: 'build' as const })),
    ...[...generations.values()].map((request) => ({ request, kind: 'generation' as const }))
  ].sort((left, right) => left.request.id - right.request.id);

  return pending.map(({ request, kind }) => {
    if (kind === 'build') {
      const message = 'Presentation building was interrupted by a server restart.';
      const event: NewProjectEvent<'build.failed'> = {
        type: 'build.failed',
        actor: { kind: 'system' },
        operationId: request.operationId,
        createdAt: recoveredAt,
        payload: {
          durationMs: 0,
          failureKind: 'cancelled',
          diagnostics: [{ severity: 'unknown', message, raw: message }],
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
