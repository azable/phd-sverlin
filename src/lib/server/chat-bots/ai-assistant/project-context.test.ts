import { describe, expect, it } from 'vitest';

import type { ProjectEvent, ProjectEventOf } from '$lib/shared/projects/events';
import type { ProjectDocument } from '$lib/shared/projects/model';

import {
  projectAiContext,
  projectAiTimelineEntry,
  projectConversationMessages
} from './project-context';

const operationId = '12345678-1234-4123-8123-123456789abc';
const hash = '0'.repeat(64);

describe('AI project context projection', () => {
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
        source: recorded('secret source', 'text/x-sverlin'),
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

  it('indexes raw audit bodies by hash and expands only selected events', () => {
    const request: ProjectEventOf<'ai.generation-requested'> = {
      ...base(3),
      type: 'ai.generation-requested',
      payload: {
        attempt: 1,
        purpose: 'initial',
        prompt: recorded('private prompt', 'application/json'),
        promptTemplateSha256: '1'.repeat(64),
        requestedModel: 'test-model',
        parameters: {}
      }
    };
    const document = projectDocument(request);

    expect(projectAiTimelineEntry(request).summary).not.toContain('private prompt');
    const compact = projectAiContext(document);
    expect(JSON.stringify(compact.timeline)).not.toContain('private prompt');
    expect(compact.currentWorkspace.artifacts[0].source).toBe('current source');
    expect(compact.selected.events).toEqual([]);

    const expanded = projectAiContext(document, { eventIds: [request.id] });
    expect(expanded.selected.events[0].event).toEqual(request);
    expect(JSON.stringify(expanded.selected.events[0])).toContain('private prompt');
  });
});

function projectDocument(request: ProjectEventOf<'ai.generation-requested'>): ProjectDocument {
  return {
    schemaVersion: 1,
    projectId: 'project-test',
    events: [
      event(1, 'project.created', { title: 'Test', entryArtifactId: 'dsl-main' }),
      event(2, 'artifact.version-created', {
        origin: { kind: 'initial' },
        changes: [
          {
            operation: 'upsert',
            artifact: {
              artifactId: 'dsl-main',
              path: 'Main.sverlin',
              language: 'sverlin',
              content: recorded('current source', 'text/x-sverlin')
            }
          }
        ]
      }),
      request
    ]
  };
}

function recorded(text: string, mediaType: string) {
  return { text, sha256: hash, mediaType };
}

function base(id: number) {
  return {
    id,
    operationId,
    actor: { kind: 'system' as const },
    createdAt: `2026-01-01T00:00:0${id}.000Z`
  };
}

function event<Type extends ProjectEvent['type']>(
  id: number,
  type: Type,
  payload: ProjectEventOf<Type>['payload']
): ProjectEventOf<Type> {
  return { ...base(id), type, payload } as ProjectEventOf<Type>;
}
