/** Participant-facing conversational projection of the complete immutable Timeline. */

import type { ProjectEvent } from '$lib/shared/projects/events';
import {
  structureKnownPresentationReferences,
  type MessageContent
} from '$lib/shared/projects/events/message-content';

import {
  timelinePresentations,
  type TimelinePresentation
} from '$lib/client/visualization/presentation-history';

export type ParticipantTimelineItem =
  | {
      id: string;
      kind: 'message';
      actor: 'user' | 'assistant';
      content: MessageContent;
      eventId: number;
    }
  | { id: string; kind: 'presentation'; value: TimelinePresentation }
  | { id: string; kind: 'error'; text: string; eventId: number };

/** Keep research data lossless while deriving a concise participant conversation locally. */
export function participantTimeline(events: readonly ProjectEvent[]): ParticipantTimelineItem[] {
  const presentations = new Map(
    timelinePresentations(events).map((entry) => [entry.eventId, entry] as const)
  );
  const presentationIds = [...presentations.values()].map(
    ({ presentation }) => presentation.presentationId
  );
  const groups = Map.groupBy(events, ({ operationId }) => operationId);
  return [...groups.values()]
    .toSorted((left, right) => left[0].id - right[0].id)
    .flatMap((related) => {
      const items: ParticipantTimelineItem[] = [];
      for (const event of related) {
        if (event.type === 'feedback.submitted') {
          items.push(messageItem(`user-${event.id}`, 'user', event.payload.content, event.id));
        } else if (event.type === 'visualization.preference-recorded') {
          const other = event.payload.presentations.find((id) => id !== event.payload.preferred);
          if (!other) continue;
          items.push(
            messageItem(
              `preference-${event.id}`,
              'user',
              [
                { type: 'markdown', text: 'Preferred' },
                { type: 'presentation-ref', presentationId: event.payload.preferred },
                { type: 'markdown', text: 'over' },
                { type: 'presentation-ref', presentationId: other },
                { type: 'markdown', text: `at step ${event.payload.step + 1}.` }
              ],
              event.id
            )
          );
        }
      }
      for (const event of related) {
        if (event.type === 'assistant.responded') {
          items.push(
            messageItem(
              `assistant-${event.id}`,
              'assistant',
              structureKnownPresentationReferences(event.payload.content, presentationIds),
              event.id
            )
          );
        }
      }
      for (const event of related) {
        if (event.type !== 'visualization.presented') continue;
        const value = presentations.get(event.id);
        if (value) items.push({ id: `presentation-${event.id}`, kind: 'presentation', value });
      }
      const failure = related.findLast(({ type }) => type === 'operation.failed');
      if (failure?.type === 'operation.failed' && failure.payload.kind !== 'presentation-refill') {
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

function messageItem(
  id: string,
  actor: 'user' | 'assistant',
  content: MessageContent,
  eventId: number
): Extract<ParticipantTimelineItem, { kind: 'message' }> {
  return { id, kind: 'message', actor, content, eventId };
}
