import { describe, expect, it } from 'vitest';

import { mergeProjectEvents } from './project-session.svelte';
import type { ProjectEvent, ProjectRenamedEvent } from './types';

describe('mergeProjectEvents', () => {
  it('appends contiguous events in sequence and ignores events already loaded', () => {
    const root = rootEvent();
    const first = renameEvent('first', 1, root.eventId);
    const second = renameEvent('second', 2, first.eventId);

    expect(mergeProjectEvents([root, first], [second, first])).toEqual([root, first, second]);
  });

  it('stops before a gap or conflicting parent', () => {
    const root = rootEvent();
    const gap = renameEvent('gap', 2, root.eventId);

    expect(mergeProjectEvents([root], [gap])).toEqual([root]);
  });
});

function rootEvent(): ProjectEvent {
  return {
    eventId: 'root',
    sequence: 0,
    parentEventId: null,
    type: 'project.created',
    actor: { kind: 'user' },
    correlationId: 'correlation',
    createdAt: '2026-01-01T00:00:00.000Z',
    payload: { title: 'Session test', entryArtifactId: 'dsl-main' }
  };
}

function renameEvent(
  eventId: string,
  sequence: number,
  parentEventId: string
): ProjectRenamedEvent {
  return {
    eventId,
    sequence,
    parentEventId,
    type: 'project.renamed',
    actor: { kind: 'user' },
    correlationId: 'correlation',
    createdAt: '2026-01-01T00:00:01.000Z',
    payload: { previousTitle: 'Session test', title: eventId }
  };
}
