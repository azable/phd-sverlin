/** Client-side projection of immutable visualization events into selectable presentations. */

import type { ProjectEvent } from '$lib/shared/projects/events';
import {
  legacyPresentationId,
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

/** One render recorded in the Timeline, with its display-set context retained. */
export type TimelinePresentation = {
  eventId: number;
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

/** Return every render in Timeline order. */
export function timelinePresentations(events: readonly ProjectEvent[]): TimelinePresentation[] {
  return events.flatMap<TimelinePresentation>((event): TimelinePresentation[] => {
    if (event.type === 'visualization.presented') {
      return [
        {
          eventId: event.id,
          operationId: event.operationId,
          displaySetId: event.payload.displaySetId,
          slot: event.payload.slot,
          presentation: event.payload.presentation
        }
      ];
    }
    if (event.type !== 'visualization.rendered') return [];
    const presentationId = legacyPresentationId(event.id);
    return [
      {
        eventId: event.id,
        operationId: event.operationId,
        slot: 0 as const,
        presentation: {
          presentationId,
          format: 'sverlin-ir-v1' as const,
          stepSignature: `legacy-${event.id}`,
          seed: event.payload.seed,
          source: event.payload.source,
          render: event.payload.render,
          resources: event.payload.resources,
          provenance: event.payload.provenance,
          targetDiagnostics: event.payload.targetDiagnostics
        }
      }
    ];
  });
}

/** Return the most recently generated single render or compatible comparison pair. */
export function latestPresentations(
  presentations: readonly TimelinePresentation[],
  layout: PresentationLayout
): TimelinePresentation[] {
  const latest = presentations.at(-1);
  if (!latest) return [];
  return presentationGroup(presentations, latest, layout);
}

/** Return the generated set containing a selected render, subject to the current layout. */
export function presentationGroup(
  presentations: readonly TimelinePresentation[],
  selected: TimelinePresentation,
  layout: PresentationLayout
): TimelinePresentation[] {
  if (layout !== 'comparison' || selected.presentation.format !== 'sverlin-ir-v1') {
    return [selected];
  }
  const group = presentations
    .filter((candidate) => sameDisplaySet(candidate, selected))
    .toSorted((left, right) => left.slot - right.slot || left.eventId - right.eventId)
    .slice(0, 2);
  return group.length === 2 && compatibleSverlinPair(group[0], group[1]) ? group : [selected];
}

/** Whether two renders can share one playback position in a custom comparison. */
export function compatibleSverlinPair(
  left: TimelinePresentation,
  right: TimelinePresentation
): boolean {
  return (
    left.presentation.format === 'sverlin-ir-v1' &&
    right.presentation.format === 'sverlin-ir-v1' &&
    left.presentation.source.sha256 === right.presentation.source.sha256 &&
    left.presentation.stepSignature === right.presentation.stepSignature
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
