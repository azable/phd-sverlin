import { createHash, randomUUID } from 'node:crypto';

import { inArray } from 'drizzle-orm';
import { afterAll, expect, it } from 'vitest';

import type { NewProjectEvent } from '$lib/shared/projects/events';
import type { ProjectDocument } from '$lib/shared/projects/model';
import { closeDatabase, database } from '$lib/server/db';
import * as schema from '$lib/server/db/schema';
import {
  PostgresProjectRepository,
  type ProjectResourceBlob
} from '$lib/server/projects/repository';

import { PostgresExportDataSource } from './data-export';

const enabled = Boolean(process.env.DATABASE_URL) && process.env.SVERLIN_RUN_POSTGRES_TESTS === '1';
const createdProjects: string[] = [];
const createdUsers: string[] = [];

afterAll(async () => {
  if (createdProjects.length) {
    await database().delete(schema.projects).where(inArray(schema.projects.id, createdProjects));
  }
  if (createdUsers.length) {
    await database().delete(schema.user).where(inArray(schema.user.id, createdUsers));
  }
  await closeDatabase();
});

it.skipIf(!enabled)(
  'collects active project data with minimal owner identity and resource metadata',
  async () => {
    const suffix = randomUUID();
    const ownerUserId = `project-owner-${suffix}`;
    const projectId = `project-export-${suffix}`;
    const operationId = randomUUID();
    const repository = new PostgresProjectRepository();
    const resource = resourceBlob('project bytes');
    createdUsers.push(ownerUserId);
    createdProjects.push(projectId);
    await database()
      .insert(schema.user)
      .values({
        id: ownerUserId,
        name: 'Project administrator',
        email: `${ownerUserId}@sverlin.invalid`,
        emailVerified: true,
        role: 'admin'
      });
    await repository.create(rootDocument(projectId, operationId), ownerUserId);
    await repository.append(projectId, 1, [renameEvent(operationId)], [resource]);

    const source = new PostgresExportDataSource(repository);
    const snapshot = await source.collect({ type: 'projects', projectId });

    expect(snapshot.owners).toEqual([
      {
        id: ownerUserId,
        label: 'Project administrator',
        role: 'admin',
        enabled: true
      }
    ]);
    expect(snapshot.projects[0]).toMatchObject({
      id: projectId,
      ownerUserId,
      document: { projectId, events: [{ id: 1 }, { id: 2 }] },
      resources: [{ resourceId: resource.id, byteLength: resource.byteLength }]
    });
    expect(snapshot.owners[0]).not.toHaveProperty('email');
    expect(Buffer.from(await source.readResource(projectId, resource.id))).toEqual(
      Buffer.from(resource.bytes)
    );
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
        createdAt: '2026-08-30T00:00:00.000Z',
        payload: {
          title: 'Project export integration',
          entryArtifactId: 'dsl-main',
          assistantId: 'sverlin-assistant',
          creation: { templateId: 'blank' }
        }
      }
    ]
  };
}

function renameEvent(operationId: string): NewProjectEvent<'project.renamed'> {
  return {
    type: 'project.renamed',
    actor: { kind: 'user' },
    operationId,
    createdAt: '2026-08-30T00:00:01.000Z',
    payload: { previousTitle: 'Project export integration', title: 'Ready to inspect' }
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
