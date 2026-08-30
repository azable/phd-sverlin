/** Participant-facing conversational projection of the complete immutable Timeline. */

import type { ProjectEvent } from '$lib/shared/projects/events';

import {
  timelinePresentations,
  type TimelinePresentation
} from '$lib/client/visualization/presentation-history';

export type ParticipantTimelineItem =
  | { id: string; kind: 'message'; actor: 'user' | 'assistant'; text: string; eventId: number }
  | { id: string; kind: 'presentation'; value: TimelinePresentation }
  | { id: string; kind: 'error'; text: string; eventId: number };

/** Keep research data lossless while deriving a concise participant conversation locally. */
export function participantTimeline(events: readonly ProjectEvent[]): ParticipantTimelineItem[] {
  const presentations = new Map(
    timelinePresentations(events).map((entry) => [entry.eventId, entry] as const)
  );
  const groups = Map.groupBy(events, ({ operationId }) => operationId);
  return [...groups.values()]
    .toSorted((left, right) => left[0].id - right[0].id)
    .flatMap((related) => {
      const items: ParticipantTimelineItem[] = [];
      for (const event of related) {
        if (event.type === 'feedback.submitted' && event.payload.text?.trim()) {
          items.push({
            id: `user-${event.id}`,
            kind: 'message',
            actor: 'user',
            text: event.payload.text,
            eventId: event.id
          });
        }
      }
      for (const event of related) {
        if (event.type === 'assistant.responded') {
          items.push({
            id: `assistant-${event.id}`,
            kind: 'message',
            actor: 'assistant',
            text: event.payload.text,
            eventId: event.id
          });
        }
      }
      for (const event of related) {
        if (event.type !== 'visualization.rendered' && event.type !== 'visualization.presented') {
          continue;
        }
        const value = presentations.get(event.id);
        if (value) items.push({ id: `presentation-${event.id}`, kind: 'presentation', value });
      }
      const failure = related.findLast(({ type }) => type === 'operation.failed');
      if (failure?.type === 'operation.failed') {
        items.push({
          id: `error-${failure.id}`,
          kind: 'error',
          text: failure.payload.message,
          eventId: failure.id
        });
      }
      return items;
    });
}
