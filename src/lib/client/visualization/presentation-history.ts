/** Client-side projection of immutable visualization events into selectable presentations. */

import type { ProjectEvent } from '$lib/shared/projects/events';
import { presentationBufferState } from '$lib/shared/projects/presentation-buffer';
import {
  isSverlinPresentation,
  presentationScenarioKey,
  type PresentationLayout,
  type RenderablePresentation
} from '$lib/shared/presentations';

const presentationAdjectives = [
  'Amber',
  'Arctic',
  'Azure',
  'Bold',
  'Bright',
  'Calm',
  'Clear',
  'Coral',
  'Cosmic',
  'Crisp',
  'Dawn',
  'Deep',
  'Ember',
  'Emerald',
  'Gentle',
  'Golden',
  'Indigo',
  'Keen',
  'Lunar',
  'Misty',
  'Noble',
  'Ocean',
  'Olive',
  'Quiet',
  'Rapid',
  'Silver',
  'Solar',
  'Swift',
  'Teal',
  'Vivid',
  'Warm',
  'Wild'
] as const;

const presentationNouns = [
  'Badger',
  'Comet',
  'Crane',
  'Dolphin',
  'Falcon',
  'Finch',
  'Fox',
  'Gecko',
  'Heron',
  'Koala',
  'Lark',
  'Lynx',
  'Maple',
  'Otter',
  'Owl',
  'Panda',
  'Pebble',
  'Pine',
  'Raven',
  'Reef',
  'Robin',
  'Seal',
  'Sparrow',
  'Star',
  'Tiger',
  'Turtle',
  'Wattle',
  'Whale',
  'Willow',
  'Wombat',
  'Wren',
  'Zebra'
] as const;

/** One presentation recorded in the Timeline, with its display-set context retained. */
export type TimelinePresentation = {
  eventId: number;
  eventType: 'visualization.presented';
  operationId: string;
  displaySetId?: string;
  slot: 0 | 1;
  presentation: RenderablePresentation;
};

/** Stable participant-friendly label derived from the retained presentation UUID. */
export function presentationDisplayId(presentationId: string): string {
  let hash = 2166136261;
  for (const character of presentationId) {
    hash = Math.imul(hash ^ character.charCodeAt(0), 16777619);
  }
  const value = hash >>> 0;
  const adjective = presentationAdjectives[value & 31];
  const noun = presentationNouns[(value >>> 5) & 31];
  const number = String((value >>> 10) % 100).padStart(2, '0');
  return `${adjective}-${noun}-${number}`;
}

/** Return every presentation in Timeline order. */
export function timelinePresentations(events: readonly ProjectEvent[]): TimelinePresentation[] {
  return events.flatMap<TimelinePresentation>((event): TimelinePresentation[] => {
    if (event.type === 'visualization.presented') {
      return [
        {
          eventId: event.id,
          eventType: 'visualization.presented',
          operationId: event.operationId,
          displaySetId: event.payload.displaySetId,
          slot: event.payload.slot,
          presentation: event.payload.presentation
        }
      ];
    }
    return [];
  });
}

/** Return the most recently generated presentation or compatible comparison pair. */
export function latestPresentations(
  presentations: readonly TimelinePresentation[],
  layout: PresentationLayout
): TimelinePresentation[] {
  const latest = presentations.at(-1);
  if (!latest) return [];
  if (latest.presentation.format === 'html-frames-v1' && latest.displaySetId) {
    return presentations
      .filter(({ displaySetId }) => displaySetId === latest.displaySetId)
      .toSorted((left, right) => left.slot - right.slot)
      .slice(0, 1);
  }
  return presentationGroup(presentations, latest, layout);
}

/** Return the FIFO current-source candidates not consumed by committed participant actions. */
export function availablePresentations(
  events: readonly ProjectEvent[],
  layout: PresentationLayout
): TimelinePresentation[] {
  const all = timelinePresentations(events);
  const latest = all.findLast(({ presentation }) => isSverlinPresentation(presentation));
  if (!latest || !isSverlinPresentation(latest.presentation)) {
    return latestPresentations(all, layout);
  }
  const availableIds = new Set(
    presentationBufferState(events, 0, latest.presentation.source.sha256).available.map(
      ({ presentationId }) => presentationId
    )
  );
  const available = all.filter(({ presentation }) => availableIds.has(presentation.presentationId));
  if (layout !== 'comparison') return available.slice(0, 1);
  const groups = new Map<string, TimelinePresentation[]>();
  for (const entry of available) {
    const key = isSverlinPresentation(entry.presentation)
      ? presentationScenarioKey(entry.presentation)
      : entry.presentation.presentationId;
    groups.set(key, [...(groups.get(key) ?? []), entry]);
  }
  const pair = [...groups.values()].find((group) => group.length >= 2);
  return pair?.slice(0, 2) ?? available.slice(0, 1);
}

/** Return the generated set containing a selected presentation, subject to the current layout. */
export function presentationGroup(
  presentations: readonly TimelinePresentation[],
  selected: TimelinePresentation,
  layout: PresentationLayout
): TimelinePresentation[] {
  if (layout !== 'comparison' || !isSverlinPresentation(selected.presentation)) {
    return [selected];
  }
  const group = presentations
    .filter((candidate) => sameDisplaySet(candidate, selected))
    .toSorted((left, right) => left.slot - right.slot || left.eventId - right.eventId)
    .slice(0, 2);
  return group.length === 2 && compatibleSverlinPair(group[0], group[1]) ? group : [selected];
}

/** Whether two presentations can share one playback position in a custom comparison. */
export function compatibleSverlinPair(
  left: TimelinePresentation,
  right: TimelinePresentation
): boolean {
  return (
    isSverlinPresentation(left.presentation) &&
    isSverlinPresentation(right.presentation) &&
    presentationScenarioKey(left.presentation) === presentationScenarioKey(right.presentation)
  );
}

/** Find presentations by stable IDs while preserving the requested order. */
export function presentationsById(
  presentations: readonly TimelinePresentation[],
  ids: readonly string[]
): TimelinePresentation[] {
  const byId = new Map(
    presentations.map((entry) => [entry.presentation.presentationId, entry] as const)
  );
  return ids.flatMap((id) => {
    const entry = byId.get(id);
    return entry ? [entry] : [];
  });
}

function sameDisplaySet(left: TimelinePresentation, right: TimelinePresentation): boolean {
  if (left.displaySetId || right.displaySetId) return left.displaySetId === right.displaySetId;
  return left.operationId === right.operationId;
}
