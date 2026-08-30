import { describe, expect, it } from 'vitest';

import type { ProjectEvent } from '$lib/shared/projects/events';

import { participantTimeline } from './participant-timeline';

const presentationIds = [
  '12345678-1234-4123-8123-123456789ac1',
  '12345678-1234-4123-8123-123456789ac2'
] as const;

describe('participant Timeline projection', () => {
  it('keeps structured messages, preference actions, and individual presentations', () => {
    const items = participantTimeline(events());
    expect(items.map(({ kind }) => kind)).toEqual([
      'message',
      'message',
      'presentation',
      'presentation',
      'message'
    ]);
    expect(items[0]).toMatchObject({
      kind: 'message',
      actor: 'user',
      content: [{ type: 'markdown', text: 'Show addition' }]
    });
    expect(items[1]).toMatchObject({
      kind: 'message',
      actor: 'assistant',
      context: { type: 'comparing', presentationIds: [...presentationIds] }
    });
    expect(items[4]).toMatchObject({
      kind: 'message',
      actor: 'user',
      content: expect.arrayContaining([
        { type: 'markdown', text: 'Preferred' },
        { type: 'presentation-ref', presentationId: presentationIds[0] },
        { type: 'presentation-ref', presentationId: presentationIds[1] }
      ])
    });
  });

  it('retains exact comparison and canvas references inline', () => {
    const values = events().slice(1, 5);
    values.push({
      id: 6,
      type: 'feedback.submitted',
      actor: { kind: 'user' },
      operationId: '32345678-1234-4234-8234-123456789abc',
      createdAt: '2026-08-30T00:00:06.000Z',
      payload: {
        focus: [],
        content: [
          { type: 'markdown', text: 'Compare' },
          { type: 'presentation-ref', presentationId: presentationIds[0] },
          { type: 'markdown', text: 'with' },
          { type: 'presentation-ref', presentationId: presentationIds[1] },
          {
            type: 'element-ref',
            presentationId: presentationIds[0],
            presentationEvent: 3,
            step: 0,
            instances: [0, 2]
          }
        ]
      }
    });
    expect(participantTimeline(values).at(-1)).toMatchObject({
      kind: 'message',
      actor: 'user',
      context: { type: 'comparing', presentationIds: [...presentationIds] },
      content: expect.arrayContaining([
        expect.objectContaining({ type: 'element-ref', instances: [0, 2] })
      ])
    });
  });
});

function events(): ProjectEvent[] {
  const operationId = '12345678-1234-4123-8123-123456789abc';
  const displaySetId = '12345678-1234-4123-8123-123456789abd';
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
      payload: { content: [{ type: 'markdown', text: 'Show addition' }], focus: [] }
    },
    {
      id: 2,
      type: 'assistant.responded',
      actor: { kind: 'assistant', botId: 'sverlin-assistant' },
      operationId,
      createdAt: '2026-08-30T00:00:02.000Z',
      payload: {
        content: [
          { type: 'markdown', text: 'Here are' },
          { type: 'presentation-ref', presentationId: presentationIds[0] },
          { type: 'markdown', text: 'and' },
          { type: 'presentation-ref', presentationId: presentationIds[1] }
        ]
      }
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
      operationId: '22345678-1234-4234-8234-123456789abc',
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
