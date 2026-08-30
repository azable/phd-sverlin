import { randomUUID } from 'node:crypto';

import { describe, expect, it, vi } from 'vitest';

import type { ProjectDocument } from '$lib/shared/projects/model';
import { recordText } from './fingerprints';
import { MemoryProjectRepository } from './memory-repository.test-support';
import { recordProjectPreference } from './presentations';
import type { ProjectServiceDependencies } from './service';

describe('presentation commands', () => {
  it('records preferences against stable presentation UUIDs rather than event positions', async () => {
    const repository = new MemoryProjectRepository();
    const displaySetId = randomUUID();
    const presentations = [randomUUID(), randomUUID()] as [string, string];
    const document = comparisonDocument(randomUUID(), displaySetId, presentations);
    await repository.create(document, 'owner');
    const projectService = {
      repository,
      compiler: {} as ProjectServiceDependencies['compiler'],
      readDslRevision: vi.fn()
    };

    const result = await recordProjectPreference(
      {
        projectId: document.projectId,
        expectedHead: document.events.length,
        displaySetId,
        presentations,
        preferred: presentations[1],
        step: 0,
        operationId: randomUUID()
      },
      { repository, projectService }
    );

    expect(result.appendedEvents).toEqual([
      expect.objectContaining({
        type: 'visualization.preference-recorded',
        payload: {
          displaySetId,
          presentations,
          preferred: presentations[1],
          step: 0
        }
      })
    ]);
  });
});

function comparisonDocument(
  projectId: string,
  displaySetId: string,
  presentationIds: [string, string]
): ProjectDocument {
  const operationId = randomUUID();
  const authored = recordText(
    JSON.stringify({
      format: 'sverlin-html-frames',
      version: 1,
      frames: [{ label: 'Only step', html: '<p>Hello</p>' }]
    }),
    'application/vnd.sverlin.html-frames+json'
  );
  const base = {
    format: 'html-frames-v1' as const,
    stepSignature: 'shared-step-signature',
    authored,
    rendered: authored
  };
  return {
    schemaVersion: 1,
    projectId,
    events: [
      {
        id: 1,
        type: 'project.created',
        actor: { kind: 'user' },
        operationId,
        createdAt: '2026-08-30T00:00:00.000Z',
        payload: {
          title: 'Comparison',
          entryArtifactId: 'html-main',
          creation: { templateId: 'blank', renderer: 'html' }
        }
      },
      {
        id: 2,
        type: 'artifact.version-created',
        actor: { kind: 'system' },
        operationId,
        createdAt: '2026-08-30T00:00:01.000Z',
        payload: {
          origin: { kind: 'initial' },
          changes: [
            {
              operation: 'upsert',
              artifact: {
                artifactId: 'html-main',
                path: 'Visualization.html.json',
                language: 'json',
                content: authored
              }
            }
          ]
        }
      },
      ...presentationIds.map((presentationId, slot) => ({
        id: slot + 3,
        type: 'visualization.presented' as const,
        actor: { kind: 'system' as const },
        operationId,
        createdAt: `2026-08-30T00:00:0${slot + 2}.000Z`,
        payload: {
          displaySetId,
          slot: slot as 0 | 1,
          presentation: { ...base, presentationId }
        }
      }))
    ]
  };
}
