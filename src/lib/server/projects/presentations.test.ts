import { randomUUID } from 'node:crypto';
import { describe, expect, it } from 'vitest';

import type { ProjectDocument } from '$lib/shared/projects/model';
import { recordText } from './fingerprints';
import { MemoryProjectRepository } from './memory-repository.test-support';
import { recordProjectPreference } from './presentations';

describe('presentation preferences', () => {
  it('records compatible presentation UUIDs and a common display set', async () => {
    const repository = new MemoryProjectRepository();
    const ids = [randomUUID(), randomUUID()] as [string, string];
    const displaySetId = randomUUID();
    const document = comparisonDocument(randomUUID(), displaySetId, ids);
    await repository.create(document);
    const result = await recordProjectPreference(
      {
        projectId: document.projectId,
        expectedHead: document.events.length,
        presentations: ids,
        preferred: ids[1],
        step: 1,
        operationId: randomUUID()
      },
      { repository, projectService: { repository } }
    );
    expect(result.appendedEvents[0]).toMatchObject({
      type: 'visualization.preference-recorded',
      payload: { displaySetId, presentations: ids, preferred: ids[1], step: 1 }
    });
  });

  it('allows compatible historical views without inventing a shared display set', async () => {
    const repository = new MemoryProjectRepository();
    const ids = [randomUUID(), randomUUID()] as [string, string];
    const document = comparisonDocument(randomUUID(), [randomUUID(), randomUUID()], ids);
    await repository.create(document);
    const result = await recordProjectPreference(
      {
        projectId: document.projectId,
        expectedHead: document.events.length,
        presentations: ids,
        preferred: ids[0],
        step: 0,
        operationId: randomUUID()
      },
      { repository, projectService: { repository } }
    );
    expect(
      result.appendedEvents[0].type === 'visualization.preference-recorded'
        ? result.appendedEvents[0].payload.displaySetId
        : 'unexpected'
    ).toBeUndefined();
  });

  it('rejects unknown presentation steps', async () => {
    const repository = new MemoryProjectRepository();
    const ids = [randomUUID(), randomUUID()] as [string, string];
    const document = comparisonDocument(randomUUID(), randomUUID(), ids);
    await repository.create(document);
    const base = {
      projectId: document.projectId,
      expectedHead: document.events.length,
      presentations: ids,
      preferred: ids[0],
      operationId: randomUUID()
    };
    const dependencies = { repository, projectService: { repository } };
    await expect(recordProjectPreference({ ...base, step: 4 }, dependencies)).rejects.toThrow(
      'unknown presentation step'
    );
  });
});

function comparisonDocument(
  projectId: string,
  displaySetId: string | [string, string],
  ids: [string, string]
): ProjectDocument {
  const operationId = randomUUID();
  const source = recordText('<h1>Search</h1>', 'text/x-svelte');
  const presentation = {
    format: 'browser-bundle-v1' as const,
    mode: 'sverlin' as const,
    stepSignature: 'shared',
    labels: ['Start', 'Result'],
    source,
    html: recordText('', 'text/html'),
    javascript: recordText('void 0;', 'text/javascript')
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
          entryArtifactId: 'main',
          assistantId: 'sverlin-assistant',
          creation: { templateId: 'blank', mode: 'sverlin' }
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
                artifactId: 'main',
                path: 'Main.svelte',
                language: 'svelte',
                content: source
              }
            }
          ]
        }
      },
      ...ids.map((presentationId, slot) => ({
        id: slot + 3,
        type: 'visualization.presented' as const,
        actor: { kind: 'system' as const },
        operationId,
        createdAt: `2026-08-30T00:00:0${slot + 2}.000Z`,
        payload: {
          displaySetId: Array.isArray(displaySetId) ? displaySetId[slot] : displaySetId,
          slot: slot as 0 | 1,
          presentation: { ...presentation, presentationId, seed: slot + 1 }
        }
      }))
    ]
  };
}
