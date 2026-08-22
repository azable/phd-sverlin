import { describe, expect, it } from 'vitest';

import type { ProjectEventOf } from '$lib/projects/events';

import { projectConversationMessages, projectPromptEvent } from './prompt-context';

const operationId = '12345678-1234-4123-8123-123456789abc';
const blob = { sha256: '0'.repeat(64), byteLength: 0, mediaType: 'application/json' };

describe('project prompt projections', () => {
  it('derives conversation only from feedback and assistant responses', () => {
    const feedback: ProjectEventOf<'feedback.submitted'> = {
      ...base(1),
      type: 'feedback.submitted',
      actor: { kind: 'user' },
      payload: { text: 'Make this clearer', focus: [] }
    };
    const compilation: ProjectEventOf<'compilation.requested'> = {
      ...base(2),
      type: 'compilation.requested',
      payload: {
        purpose: 'assistant-edit',
        input: 'assistant-candidate',
        source: blob,
        sourceLabel: 'Main.sverlin',
        seed: 7,
        attempt: 1
      }
    };
    const response: ProjectEventOf<'assistant.responded'> = {
      ...base(3),
      type: 'assistant.responded',
      actor: { kind: 'assistant', botId: 'ai-assistant' },
      payload: { text: 'Updated' }
    };

    expect(projectConversationMessages([feedback, compilation, response])).toEqual([
      { role: 'user', content: 'Make this clearer' },
      { role: 'assistant', content: 'Updated' }
    ]);
  });

  it('projects audit blobs to compact hashes instead of nested content references', () => {
    const request: ProjectEventOf<'ai.generation-requested'> = {
      ...base(1),
      type: 'ai.generation-requested',
      payload: {
        attempt: 1,
        purpose: 'initial',
        prompt: blob,
        promptTemplateSha256: '1'.repeat(64),
        requestedModel: 'test-model',
        parameters: {}
      }
    };

    expect(projectPromptEvent(request)).toMatchObject({
      type: 'ai.generation-requested',
      payload: {
        attempt: 1,
        promptSha256: blob.sha256,
        promptTemplateSha256: '1'.repeat(64)
      }
    });
    expect(projectPromptEvent(request).payload).not.toHaveProperty('prompt');
  });
});

function base(id: number) {
  return {
    id,
    operationId,
    actor: { kind: 'system' as const },
    createdAt: `2026-01-01T00:00:0${id}.000Z`
  };
}
