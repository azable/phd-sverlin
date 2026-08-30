import { describe, expect, it } from 'vitest';

import type { ProjectEvent, ProjectEventOf } from '$lib/shared/projects/events';

import {
  latestPresentations,
  presentationDisplayId,
  timelinePresentations
} from './presentation-history';
import { PresentationSelection } from './presentation-selection.svelte';

const operationId = '12345678-1234-4123-8123-123456789abc';
const setOne = '12345678-1234-4123-8123-123456789abd';
const setTwo = '12345678-1234-4123-8123-123456789abe';
const presentationIds = [
  '12345678-1234-4123-8123-123456789ac1',
  '12345678-1234-4123-8123-123456789ac2',
  '12345678-1234-4123-8123-123456789ac3',
  '12345678-1234-4123-8123-123456789ac4'
];

describe('presentation history', () => {
  it('derives stable readable labels from retained presentation IDs', () => {
    const label = presentationDisplayId(presentationIds[0]);

    expect(label).toMatch(/^[A-Z][a-z]+-[A-Z][a-z]+-\d{2}$/);
    expect(presentationDisplayId(presentationIds[0])).toBe(label);
    expect(presentationDisplayId(presentationIds[1])).not.toBe(label);
  });

  it('projects the latest generated comparison from retained events', () => {
    const events = comparisonEvents();

    expect(
      latestPresentations(timelinePresentations(events), 'comparison').map(
        ({ presentation }) => presentation.presentationId
      )
    ).toEqual(presentationIds.slice(2));
  });

  it('builds a custom compatible pair and rejects a third selection', () => {
    const events = comparisonEvents();
    const entries = timelinePresentations(events);
    const selection = new PresentationSelection(true);

    expect(
      selection
        .selected(events, 'comparison')
        .map(({ presentation }) => presentation.presentationId)
    ).toEqual(presentationIds.slice(0, 2));

    selection.activate(entries[2], events, 'comparison');
    expect(selection.selectedIds).toEqual([presentationIds[2]]);
    expect(selection.followingLatest).toBe(false);

    selection.activate(entries[0], events, 'comparison', true);
    expect(selection.selectedIds).toEqual([presentationIds[2], presentationIds[0]]);

    selection.activate(entries[3], events, 'comparison', true);
    expect(selection.selectedIds).toEqual([presentationIds[2], presentationIds[0]]);
    expect(selection.notice).toContain('Deselect one');

    selection.activate(entries[0], events, 'comparison', true);
    expect(selection.selectedIds).toEqual([presentationIds[2]]);
  });

  it('advances the automatic comparison after a committed preference consumes a pair', () => {
    const events = comparisonEvents();
    events.push({
      id: 5,
      type: 'visualization.preference-recorded',
      actor: { kind: 'user' },
      operationId,
      createdAt: '2026-08-30T00:00:05.000Z',
      payload: {
        displaySetId: setOne,
        presentations: [presentationIds[0], presentationIds[1]],
        preferred: presentationIds[0],
        step: 0
      }
    });

    expect(
      new PresentationSelection(true)
        .selected(events, 'comparison')
        .map(({ presentation }) => presentation.presentationId)
    ).toEqual(presentationIds.slice(2));
  });

  it('pins the evaluated pair while a preference operation is running', () => {
    const events = comparisonEvents();
    const entries = timelinePresentations(events);
    const selection = new PresentationSelection(true);

    selection.pin(entries.slice(0, 2));
    events.push({
      id: 5,
      type: 'visualization.preference-recorded',
      actor: { kind: 'user' },
      operationId,
      createdAt: '2026-08-30T00:00:05.000Z',
      payload: {
        displaySetId: setOne,
        presentations: [presentationIds[0], presentationIds[1]],
        preferred: presentationIds[0],
        step: 0,
        visualSelections: []
      }
    });

    expect(selection.followingLatest).toBe(false);
    expect(
      selection
        .selected(events, 'comparison')
        .map(({ presentation }) => presentation.presentationId)
    ).toEqual(presentationIds.slice(0, 2));
  });

  it('keeps non-buffered workspaces on the latest generated display set', () => {
    expect(
      new PresentationSelection()
        .selected(comparisonEvents(), 'comparison')
        .map(({ presentation }) => presentation.presentationId)
    ).toEqual(presentationIds.slice(2));
  });
});

function comparisonEvents(): ProjectEvent[] {
  return [
    presentationEvent(1, setOne, 0, presentationIds[0], 1),
    presentationEvent(2, setOne, 1, presentationIds[1], 2),
    presentationEvent(3, setTwo, 0, presentationIds[2], 3),
    presentationEvent(4, setTwo, 1, presentationIds[3], 4)
  ];
}

function presentationEvent(
  id: number,
  displaySetId: string,
  slot: 0 | 1,
  presentationId: string,
  seed: number
): ProjectEventOf<'visualization.presented'> {
  return {
    id,
    type: 'visualization.presented',
    actor: { kind: 'system' },
    operationId,
    createdAt: `2026-08-30T00:00:0${id}.000Z`,
    payload: {
      displaySetId,
      slot,
      presentation: {
        presentationId,
        format: 'sverlin-ir-v1',
        stepSignature: 'shared-steps',
        seed,
        source: { text: 'source', sha256: 'a'.repeat(64), mediaType: 'text/x-sverlin' },
        render: {
          text: JSON.stringify({ steps: [{ label: 'Only step' }] }),
          sha256: String(seed).repeat(64).slice(0, 64),
          mediaType: 'application/json'
        }
      }
    }
  };
}
