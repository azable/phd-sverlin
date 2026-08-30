import { createHash, randomUUID } from 'node:crypto';

import { eq } from 'drizzle-orm';
import { afterAll, expect, it } from 'vitest';

import type { NewProjectEvent } from '$lib/shared/projects/events';
import type { ProjectDocument } from '$lib/shared/projects/model';
import { closeDatabase, database } from '$lib/server/db';
import * as schema from '$lib/server/db/schema';

import { PostgresProjectRepository, type ProjectResourceBlob } from './repository';

const postgresTestsEnabled =
  Boolean(process.env.DATABASE_URL) && process.env.SVERLIN_RUN_POSTGRES_TESTS === '1';

afterAll(closeDatabase);

it.skipIf(!postgresTestsEnabled)(
  'stores and verifies immutable project resources in PostgreSQL',
  async () => {
    const suffix = randomUUID();
    const ownerUserId = `resource-owner-${suffix}`;
    const projectId = `resource-project-${suffix}`;
    const operationId = randomUUID();
    const repository = new PostgresProjectRepository();
    const resource = resourceBlob('font bytes');

    await database()
      .insert(schema.user)
      .values({
        id: ownerUserId,
        name: 'Resource owner',
        email: `${ownerUserId}@sverlin.invalid`,
        emailVerified: true,
        role: 'user'
      });

    try {
      await repository.create(rootDocument(projectId, operationId), ownerUserId);
      await repository.append(projectId, 1, [renameEvent(operationId)], [resource]);

      expect(Buffer.from(await repository.readResource(projectId, resource.id))).toEqual(
        Buffer.from(resource.bytes)
      );

      const [stored] = await database()
        .select({ bytes: schema.projectResources.bytes })
        .from(schema.projectResources)
        .where(eq(schema.projectResources.projectId, projectId));
      expect(Buffer.from(stored?.bytes ?? [])).toEqual(Buffer.from(resource.bytes));

      const concurrent = await Promise.allSettled([
        repository.append(projectId, 2, [renameEvent(randomUUID(), 'Concurrent A')]),
        repository.append(projectId, 2, [renameEvent(randomUUID(), 'Concurrent B')])
      ]);
      expect(concurrent.filter(({ status }) => status === 'fulfilled')).toHaveLength(1);
      expect(concurrent.filter(({ status }) => status === 'rejected')).toHaveLength(1);
      expect((await repository.load(projectId)).events).toHaveLength(3);

      await database()
        .update(schema.projectResources)
        .set({ bytes: new TextEncoder().encode('font bytez') })
        .where(eq(schema.projectResources.projectId, projectId));
      await expect(repository.readResource(projectId, resource.id)).rejects.toThrow(
        'integrity verification'
      );
    } finally {
      await database().delete(schema.projects).where(eq(schema.projects.id, projectId));
      await database().delete(schema.user).where(eq(schema.user.id, ownerUserId));
    }
  },
  30_000
);

function rootDocument(projectId: string, operationId: string): ProjectDocument {
  return {
    schemaVersion: 2,
    projectId,
    events: [
      {
        id: 1,
        type: 'project.created',
        actor: { kind: 'user' },
        operationId,
        createdAt: '2026-01-01T00:00:00.000Z',
        payload: {
          title: 'Repository test',
          entryArtifactId: 'dsl-main',
          assistantId: 'sverlin-assistant',
          creation: { templateId: 'blank' }
        }
      }
    ]
  };
}

function renameEvent(
  operationId: string,
  title = 'Stored in PostgreSQL'
): NewProjectEvent<'project.renamed'> {
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
