import { describe, expect, it } from 'vitest';

import type { ProjectEvent, ProjectEventOf } from './events';
import { presentationBufferState } from './presentation-buffer';

const operationId = '12345678-1234-4123-8123-123456789abc';
const displaySetId = '12345678-1234-4123-8123-123456789abd';
const sourceA = 'a'.repeat(64);
const sourceB = 'b'.repeat(64);
const ids = [
  '12345678-1234-4123-8123-123456789ac1',
  '12345678-1234-4123-8123-123456789ac2',
  '12345678-1234-4123-8123-123456789ac3',
  '12345678-1234-4123-8123-123456789ac4'
] as const;

describe('presentation buffer projection', () => {
  it('counts only unconsumed candidates for the current source', () => {
    const events: ProjectEvent[] = [
      presented(1, ids[0], sourceA, 0),
      presented(2, ids[1], sourceA, 1),
      presented(3, ids[2], sourceA, 0),
      presented(4, ids[3], sourceA, 1),
      {
        id: 5,
        type: 'visualization.preference-recorded',
        actor: { kind: 'user' },
        operationId,
        createdAt: '2026-08-30T00:00:05.000Z',
        payload: {
          presentations: [ids[0], ids[1]],
          preferred: ids[0],
          step: 0
        }
      }
    ];

    const state = presentationBufferState(events, 4, sourceA);

    expect(state.available.map(({ presentationId }) => presentationId)).toEqual(ids.slice(2));
    expect(state.deficit).toBe(2);
  });

  it('excludes superseded-source candidates without deleting their history', () => {
    const events = [
      presented(1, ids[0], sourceA, 0),
      presented(2, ids[1], sourceA, 1),
      presented(3, ids[2], sourceB, 0),
      presented(4, ids[3], sourceB, 1)
    ];

    expect(
      presentationBufferState(events, 4, sourceB).available.map(
        ({ presentationId }) => presentationId
      )
    ).toEqual(ids.slice(2));
    expect(events).toHaveLength(4);
  });
});

function presented(
  id: number,
  presentationId: string,
  sourceSha256: string,
  slot: 0 | 1
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
        stepSignature: 'shared',
        seed: id,
        source: { text: 'source', sha256: sourceSha256, mediaType: 'text/x-sverlin' },
        render: {
          text: JSON.stringify({ steps: [{ label: 'Only step' }] }),
          sha256: String(id).repeat(64).slice(0, 64),
          mediaType: 'application/json'
        }
      }
    }
  };
}
