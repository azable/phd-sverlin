import { randomUUID } from 'node:crypto';

import { afterAll, expect, it } from 'vitest';

import type { ProjectDocument } from '$lib/shared/projects/model';
import { closeDatabase, database } from '$lib/server/db';
import * as schema from '$lib/server/db/schema';
import { PostgresProjectRepository } from '$lib/server/projects/repository';

import { requireProjectAccess } from './authorization';

const enabled = Boolean(process.env.DATABASE_URL) && process.env.SVERLIN_RUN_POSTGRES_TESTS === '1';

afterAll(closeDatabase);

it.skipIf(!enabled)('enforces participant ownership while allowing administrators', async () => {
  const suffix = randomUUID();
  const ownerId = `access-owner-${suffix}`;
  const strangerId = `access-stranger-${suffix}`;
  const adminId = `access-admin-${suffix}`;
  const projectId = `access-project-${suffix}`;
  await database()
    .insert(schema.user)
    .values([user(ownerId, 'user'), user(strangerId, 'user'), user(adminId, 'admin')]);
  await new PostgresProjectRepository().create(rootDocument(projectId), ownerId);

  await expect(
    requireProjectAccess(locals('participant', ownerId), projectId)
  ).resolves.toMatchObject({ user: { id: ownerId } });
  await expect(
    requireProjectAccess(locals('participant', strangerId), projectId)
  ).rejects.toMatchObject({ status: 404 });
  await expect(requireProjectAccess(locals('admin', adminId), projectId)).resolves.toMatchObject({
    user: { id: adminId }
  });
});

function user(id: string, role: 'user' | 'admin') {
  return {
    id,
    name: id,
    email: `${id}@sverlin.invalid`,
    emailVerified: true,
    username: role === 'user' ? id : null,
    role
  };
}

function locals(kind: 'participant' | 'admin', id: string): App.Locals {
  const principal = {
    kind,
    user: { id },
    session: {},
    ...(kind === 'participant' ? { participant: { participantId: id } } : {})
  };
  return { principal } as unknown as App.Locals;
}

function rootDocument(projectId: string): ProjectDocument {
  return {
    schemaVersion: 1,
    projectId,
    events: [
      {
        id: 1,
        type: 'project.created',
        actor: { kind: 'user' },
        operationId: randomUUID(),
        createdAt: '2026-08-30T00:00:00.000Z',
        payload: {
          title: 'Access project',
          entryArtifactId: 'dsl-main',
          creation: { templateId: 'blank' }
        }
      }
    ]
  };
}
