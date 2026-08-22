import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

import { afterEach, describe, expect, it } from 'vitest';

import type { NewProjectEvent, ProjectDocument } from '$lib/projects/types';

import { FileProjectRepository, ProjectConflictError } from './repository';

const operationId = '12345678-1234-4123-8123-123456789abc';
const temporaryRoots: string[] = [];

afterEach(async () => {
  await Promise.all(
    temporaryRoots.splice(0).map((root) => rm(root, { recursive: true, force: true }))
  );
});

describe('FileProjectRepository', () => {
  it('persists validated documents and content-addressed blobs', async () => {
    const repository = await temporaryRepository();
    await repository.create(rootDocument());
    const ref = await repository.putBlob('repository-test', 'source', 'text/plain');

    expect(await repository.readTextBlob('repository-test', ref)).toBe('source');
    expect(await repository.load('repository-test')).toEqual(rootDocument());
    expect((await repository.list())[0]).toMatchObject({
      projectId: 'repository-test',
      eventCount: 1
    });
  });

  it('assigns numeric IDs, publishes only durable appends, and rejects a stale head', async () => {
    const repository = await temporaryRepository();
    await repository.create(rootDocument());
    const published: number[][] = [];
    const unsubscribe = repository.subscribe('repository-test', (events) => {
      published.push(events.map(({ id }) => id));
    });

    const results = await Promise.allSettled([
      repository.append('repository-test', 1, [renameEvent('A')]),
      repository.append('repository-test', 1, [renameEvent('B')])
    ]);

    expect(results.filter((result) => result.status === 'fulfilled')).toHaveLength(1);
    expect(results.find((result) => result.status === 'rejected')).toMatchObject({
      reason: expect.any(ProjectConflictError)
    });
    expect((await repository.load('repository-test')).events.map(({ id }) => id)).toEqual([1, 2]);
    expect(published).toEqual([[2]]);

    unsubscribe();
    await repository.append('repository-test', 2, [renameEvent('C')]);
    expect(published).toEqual([[2]]);
  });
});

async function temporaryRepository() {
  const root = await mkdtemp(path.join(tmpdir(), 'sverlin-project-repository-'));
  temporaryRoots.push(root);
  return new FileProjectRepository(root);
}

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
        payload: { title: 'Repository test', entryArtifactId: 'dsl-main' }
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
