import { describe, expect, it } from 'vitest';

import type { ProjectEvent } from '$lib/shared/projects/events';

import { participantTimeline } from './participant-timeline';

describe('participant Timeline projection', () => {
  it('keeps messages and individual renders while hiding internal preference mechanics', () => {
    const items = participantTimeline(events());

    expect(items.map(({ kind }) => kind)).toEqual([
      'message',
      'message',
      'presentation',
      'presentation'
    ]);
    expect(items[0]).toMatchObject({ kind: 'message', actor: 'user', text: 'Show addition' });
    expect(items[1]).toMatchObject({
      kind: 'message',
      actor: 'assistant',
      text: 'Here are two versions.'
    });
  });
});

function events(): ProjectEvent[] {
  const operationId = '12345678-1234-4123-8123-123456789abc';
  const displaySetId = '12345678-1234-4123-8123-123456789abd';
  const presentationIds = [
    '12345678-1234-4123-8123-123456789ac1',
    '12345678-1234-4123-8123-123456789ac2'
  ] as const;
  const base = {
    format: 'sverlin-ir-v1' as const,
    stepSignature: 'shared',
    source: { text: 'source', sha256: 'a'.repeat(64), mediaType: 'text/x-sverlin' },
    render: {
      text: JSON.stringify({ steps: [{ label: 'Only step' }] }),
      sha256: 'b'.repeat(64),
      mediaType: 'application/json'
    }
  };
  return [
    {
      id: 1,
      type: 'feedback.submitted',
      actor: { kind: 'user' },
      operationId,
      createdAt: '2026-08-30T00:00:01.000Z',
      payload: { text: 'Show addition', focus: [] }
    },
    {
      id: 2,
      type: 'assistant.responded',
      actor: { kind: 'assistant', botId: 'sverlin-assistant' },
      operationId,
      createdAt: '2026-08-30T00:00:02.000Z',
      payload: { text: 'Here are two versions.' }
    },
    ...presentationIds.map(
      (presentationId, slot): ProjectEvent => ({
        id: slot + 3,
        type: 'visualization.presented',
        actor: { kind: 'assistant', botId: 'sverlin-assistant' },
        operationId,
        createdAt: `2026-08-30T00:00:0${slot + 3}.000Z`,
        payload: {
          displaySetId,
          slot: slot as 0 | 1,
          presentation: { ...base, presentationId, seed: slot + 1 }
        }
      })
    ),
    {
      id: 5,
      type: 'visualization.preference-recorded',
      actor: { kind: 'user' },
      operationId,
      createdAt: '2026-08-30T00:00:05.000Z',
      payload: {
        displaySetId,
        presentations: [...presentationIds],
        preferred: presentationIds[0],
        step: 0
      }
    }
  ];
}
