import { createHash, randomUUID } from 'node:crypto';

import { afterAll, expect, it } from 'vitest';

import type { NewProjectEvent } from '$lib/shared/projects/events';
import type { ProjectDocument } from '$lib/shared/projects/model';
import { closeDatabase, database } from '$lib/server/db';
import * as schema from '$lib/server/db/schema';
import {
  PostgresProjectRepository,
  type ProjectResourceBlob
} from '$lib/server/projects/repository';

import { PostgresAnalysisDataSource } from './analysis-export';

const enabled = Boolean(process.env.DATABASE_URL) && process.env.SVERLIN_RUN_POSTGRES_TESTS === '1';

afterAll(closeDatabase);

it.skipIf(!enabled)(
  'collects active project analysis with minimal owner identity and resource metadata',
  async () => {
    const suffix = randomUUID();
    const ownerUserId = `analysis-owner-${suffix}`;
    const projectId = `analysis-project-${suffix}`;
    const operationId = randomUUID();
    const repository = new PostgresProjectRepository();
    const resource = resourceBlob('analysis bytes');
    await database()
      .insert(schema.user)
      .values({
        id: ownerUserId,
        name: 'Analysis administrator',
        email: `${ownerUserId}@sverlin.invalid`,
        emailVerified: true,
        role: 'admin'
      });
    await repository.create(rootDocument(projectId, operationId), ownerUserId);
    await repository.append(projectId, 1, [renameEvent(operationId)], [resource]);

    const source = new PostgresAnalysisDataSource(repository);
    const snapshot = await source.collect(projectId);

    expect(snapshot.owners).toEqual([
      {
        id: ownerUserId,
        label: 'Analysis administrator',
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
          title: 'Analysis integration',
          entryArtifactId: 'dsl-main',
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
    payload: { previousTitle: 'Analysis integration', title: 'Ready to inspect' }
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
