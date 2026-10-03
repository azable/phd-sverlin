import { describe, expect, it } from 'vitest';

import type { NewProjectEvent } from '$lib/shared/projects/events';
import type { ProjectDocument } from '$lib/shared/projects/model';

import { MemoryProjectRepository } from './memory-repository.test-support';
import { ProjectConflictError } from './repository';

const operationId = '12345678-1234-4123-8123-123456789abc';
describe('MemoryProjectRepository test fake', () => {
  it('stores, loads, and owner-scopes validated documents', async () => {
    const repository = new MemoryProjectRepository();
    await repository.create(rootDocument());

    expect(await repository.load('repository-test')).toEqual(rootDocument());
    expect((await repository.list())[0]).toMatchObject({
      projectId: 'repository-test',
      eventCount: 1
    });
  });

  it('assigns numeric IDs and rejects a concurrent stale head', async () => {
    const repository = new MemoryProjectRepository();
    await repository.create(rootDocument());

    const results = await Promise.allSettled([
      repository.append('repository-test', 1, [renameEvent('A')]),
      repository.append('repository-test', 1, [renameEvent('B')])
    ]);

    expect(results.filter((result) => result.status === 'fulfilled')).toHaveLength(1);
    expect(results.find((result) => result.status === 'rejected')).toMatchObject({
      reason: expect.any(ProjectConflictError)
    });
    expect((await repository.load('repository-test')).events.map(({ id }) => id)).toEqual([1, 2]);
  });
});

function rootDocument(): ProjectDocument {
  return {
    schemaVersion: 1,
    projectId: 'repository-test',
    events: [
      {
        id: 1,
        type: 'project.created',
        actor: { kind: 'user' },
        operationId,
        createdAt: '2026-01-01T00:00:00.000Z',
        payload: {
          title: 'Repository test',
          entryArtifactId: 'main',
          assistantId: 'sverlin-assistant',
          creation: { templateId: 'blank' }
        }
      }
    ]
  };
}

function renameEvent(title: string): NewProjectEvent<'project.renamed'> {
  return {
    type: 'project.renamed',
    actor: { kind: 'user' },
    operationId,
    createdAt: '2026-01-01T00:00:01.000Z',
    payload: { previousTitle: 'Repository test', title }
  };
}
