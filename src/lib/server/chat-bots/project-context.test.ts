import { describe, expect, it } from 'vitest';

import type { ProjectDocument } from '$lib/shared/projects/model';

import {
  projectAiContext,
  projectAiTimelineEntry,
  projectConversationMessages
} from './project-context';

const operationId = '12345678-1234-4123-8123-123456789abc';
const sha256 = 'a'.repeat(64);
const recorded = (text: string, mediaType = 'text/plain') => ({ text, sha256, mediaType });

function document(): ProjectDocument {
  return {
    schemaVersion: 2,
    projectId: 'project-test',
    events: [
      {
        id: 1,
        type: 'project.created',
        operationId,
        actor: { kind: 'user' },
        createdAt: '2026-01-01T00:00:01.000Z',
        payload: {
          title: 'Test',
          entryArtifactId: 'dsl-main',
          assistantId: 'sverlin-assistant',
          creation: { templateId: 'blank', renderer: 'sverlin' }
        }
      },
      {
        id: 2,
        type: 'artifact.version-created',
        operationId,
        actor: { kind: 'system' },
        createdAt: '2026-01-01T00:00:02.000Z',
        payload: {
          origin: { kind: 'initial' },
          changes: [
            {
              operation: 'upsert',
              artifact: {
                artifactId: 'dsl-main',
                path: 'Main.svelte',
                language: 'svelte',
                content: recorded('<h1>Hello</h1>', 'text/x-svelte')
              }
            }
          ]
        }
      },
      {
        id: 3,
        type: 'ai.generation-requested',
        operationId,
        actor: { kind: 'system' },
        createdAt: '2026-01-01T00:00:03.000Z',
        payload: {
          attempt: 1,
          purpose: 'initial',
          prompt: recorded('private prompt', 'application/json'),
          promptTemplateSha256: sha256,
          requestedModel: 'test-model',
          parameters: {}
        }
      }
    ]
  };
}

describe('mode-neutral AI project context', () => {
  it('keeps prompt bodies out of the timeline index while expanding selected events', () => {
    const value = document();
    expect(projectAiTimelineEntry(value.events[2]).summary).not.toContain('private prompt');
    expect(JSON.stringify(projectAiContext(value).timeline)).not.toContain('private prompt');
    expect(projectAiContext(value, { eventIds: [3] }).selected.events[0].event).toEqual(
      value.events[2]
    );
  });

  it('exposes presentation steps and preference interaction without executable bytes', () => {
    const value = document();
    const presentationId = '12345678-1234-4123-8123-123456789ac1';
    const otherId = '12345678-1234-4123-8123-123456789ac2';
    for (const [slot, id] of [presentationId, otherId].entries()) {
      value.events.push({
        id: slot + 4,
        type: 'visualization.presented',
        operationId,
        actor: { kind: 'system' },
        createdAt: `2026-01-01T00:00:0${slot + 4}.000Z`,
        payload: {
          displaySetId: '12345678-1234-4123-8123-123456789abd',
          slot: slot as 0 | 1,
          presentation: {
            presentationId: id,
            format: 'browser-bundle-v1',
            mode: 'sverlin',
            stepSignature: 'shared',
            labels: ['Start', 'Result'],
            seed: slot + 1,
            source: recorded('<h1>Hello</h1>', 'text/x-svelte'),
            html: recorded('', 'text/html'),
            javascript: recorded('private executable bytes', 'text/javascript')
          }
        }
      });
    }
    value.events.push({
      id: 6,
      type: 'visualization.preference-recorded',
      operationId,
      actor: { kind: 'user' },
      createdAt: '2026-01-01T00:00:06.000Z',
      payload: { presentations: [presentationId, otherId], preferred: presentationId, step: 1 }
    });
    const context = projectAiContext(value, {
      eventIds: [],
      presentationIds: [presentationId, otherId],
      interactionEventIds: [6]
    });
    expect(context.interaction).toMatchObject({
      kind: 'preference',
      preferredPresentationId: presentationId
    });
    expect(context.selected.presentations[0]).toMatchObject({
      presentationId,
      steps: [{ label: 'Start' }, { label: 'Result' }]
    });
    expect(JSON.stringify(context.selected.presentations)).not.toContain(
      'private executable bytes'
    );
    expect(projectConversationMessages(value.events)).toEqual([
      { role: 'user', content: expect.stringContaining(presentationId) }
    ]);
  });
});
