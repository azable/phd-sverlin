import { describe, expect, it } from 'vitest';

import type { NewProjectEvent } from '$lib/shared/projects/events';
import type { ProjectDocument } from '$lib/shared/projects/model';

import { MemoryProjectRepository } from './memory-repository.test-support';
import { ProjectConflictError, type ProjectResourceBlob } from './repository';

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

  it('verifies, deduplicates, and serves immutable content-addressed resources', async () => {
    const repository = new MemoryProjectRepository();
    await repository.create(rootDocument());
    const resource = resourceBlob('font bytes');

    await repository.append('repository-test', 1, [renameEvent('A')], [resource, resource]);

    expect(Buffer.from(await repository.readResource('repository-test', resource.id))).toEqual(
      Buffer.from(resource.bytes)
    );
    await expect(
      repository.append(
        'repository-test',
        2,
        [renameEvent('B')],
        [{ ...resource, byteLength: resource.byteLength + 1 }]
      )
    ).rejects.toThrow('unexpected byte length');
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

function resourceBlob(value: string): ProjectResourceBlob {
  const bytes = new TextEncoder().encode(value);
  const sha256 = createHash('sha256').update(bytes).digest('hex');
  return {
    id: `sha256-${sha256}`,
    kind: 'fontResource',
    sha256,
    mediaType: 'font/ttf',
    byteLength: bytes.byteLength,
    bytes
  };
}
import { createHash } from 'node:crypto';
