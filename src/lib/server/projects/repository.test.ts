import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

import { afterEach, describe, expect, it } from 'vitest';

import type { NewProjectEvent, ProjectDocument } from '$lib/projects/types';

import { FileProjectRepository, ProjectConflictError } from './repository';

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

  it('allows only one concurrent append to extend an expected head', async () => {
    const repository = await temporaryRepository();
    await repository.create(rootDocument());
    const published: string[][] = [];
    const unsubscribe = repository.subscribe('repository-test', (events) => {
      published.push(events.map(({ eventId }) => eventId));
    });

    const results = await Promise.allSettled([
      repository.append('repository-test', 'root', [renameEvent('rename-a', 'A')]),
      repository.append('repository-test', 'root', [renameEvent('rename-b', 'B')])
    ]);

    expect(results.filter((result) => result.status === 'fulfilled')).toHaveLength(1);
    const failure = results.find((result) => result.status === 'rejected');
    expect(failure).toMatchObject({ reason: expect.any(ProjectConflictError) });
    expect((await repository.load('repository-test')).events).toHaveLength(2);
    expect(published).toHaveLength(1);

    const head = (await repository.load('repository-test')).events.at(-1)!;
    unsubscribe();
    await repository.append('repository-test', head.eventId, [renameEvent('rename-c', 'C')]);
    expect(published).toHaveLength(1);
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
        eventId: 'root',
        sequence: 0,
        parentEventId: null,
        type: 'project.created',
        actor: { kind: 'user' },
        correlationId: 'correlation',
        createdAt: '2026-01-01T00:00:00.000Z',
        payload: { title: 'Repository test', entryArtifactId: 'dsl-main' }
      }
    ]
  };
}

function renameEvent(eventId: string, title: string): NewProjectEvent<'project.renamed'> {
  return {
    eventId,
    type: 'project.renamed',
    actor: { kind: 'user' },
    correlationId: 'correlation',
    createdAt: '2026-01-01T00:00:01.000Z',
    payload: { previousTitle: 'Repository test', title }
  };
}
