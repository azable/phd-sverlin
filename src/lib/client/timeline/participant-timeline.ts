/** Participant-facing conversational projection of the complete immutable Timeline. */

import type { ProjectEvent } from '$lib/shared/projects/events';

import {
  presentationDisplayId,
  timelinePresentations,
  type TimelinePresentation
} from '$lib/client/visualization/presentation-history';

export type ParticipantTimelineItem =
  | {
      id: string;
      kind: 'message';
      actor: 'user' | 'assistant';
      text: string;
      details?: string[];
      eventId: number;
    }
  | { id: string; kind: 'presentation'; value: TimelinePresentation }
  | { id: string; kind: 'error'; text: string; eventId: number };

/** Keep research data lossless while deriving a concise participant conversation locally. */
export function participantTimeline(events: readonly ProjectEvent[]): ParticipantTimelineItem[] {
  const presentations = new Map(
    timelinePresentations(events).map((entry) => [entry.eventId, entry] as const)
  );
  const presentationsById = new Map(
    [...presentations.values()].map((entry) => [entry.presentation.presentationId, entry] as const)
  );
  const groups = Map.groupBy(events, ({ operationId }) => operationId);
  return [...groups.values()]
    .toSorted((left, right) => left[0].id - right[0].id)
    .flatMap((related) => {
      const items: ParticipantTimelineItem[] = [];
      for (const event of related) {
        if (event.type === 'feedback.submitted') {
          const text = event.payload.text?.trim();
          const details = feedbackDetails(event, presentations, presentationsById);
          if (!text && details.length === 0) continue;
          items.push({
            id: `user-${event.id}`,
            kind: 'message',
            actor: 'user',
            text: text || 'Submitted visual feedback',
            ...(details.length ? { details } : {}),
            eventId: event.id
          });
        } else if (event.type === 'visualization.preference-recorded') {
          const preferred = presentationLabel(event.payload.preferred, presentationsById);
          const otherId = event.payload.presentations.find((id) => id !== event.payload.preferred);
          const other = otherId ? presentationLabel(otherId, presentationsById) : 'visualization';
          items.push({
            id: `preference-${event.id}`,
            kind: 'message',
            actor: 'user',
            text: `Preferred ${preferred} over ${other}`,
            details: [`Step ${event.payload.step + 1}`],
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

function feedbackDetails(
  event: Extract<ProjectEvent, { type: 'feedback.submitted' }>,
  presentations: ReadonlyMap<number, TimelinePresentation>,
  presentationsById: ReadonlyMap<string, TimelinePresentation>
): string[] {
  const details: string[] = [];
  if (event.payload.presentations?.length) {
    const labels = event.payload.presentations.map((id) =>
      presentationLabel(id, presentationsById)
    );
    details.push(
      labels.length === 2 ? `Compared ${labels[0]} and ${labels[1]}` : `Viewing ${labels[0]}`
    );
  }
  if (event.payload.selection) {
    const selection = event.payload.selection;
    const eventId =
      'presentationEvent' in selection ? selection.presentationEvent : selection.render;
    const presentation = presentations.get(eventId);
    details.push(
      `${selection.instances.length} selected element${selection.instances.length === 1 ? '' : 's'}${presentation ? ` in ${presentationDisplayId(presentation.presentation.presentationId)}` : ''} · Step ${selection.step + 1}`
    );
  }
  return details;
}

function presentationLabel(
  id: string,
  presentations: ReadonlyMap<string, TimelinePresentation>
): string {
  return presentations.has(id) ? presentationDisplayId(id) : id;
}
