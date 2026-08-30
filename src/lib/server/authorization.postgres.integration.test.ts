import { randomUUID } from 'node:crypto';

import { inArray } from 'drizzle-orm';
import { afterAll, expect, it } from 'vitest';

import type { ProjectDocument } from '$lib/shared/projects/model';
import { closeDatabase, database } from '$lib/server/db';
import * as schema from '$lib/server/db/schema';
import { PostgresProjectRepository } from '$lib/server/projects/repository';

import { requireProjectAccess, requireProjectMutationAccess } from './authorization';

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

it.skipIf(!enabled)('enforces participant ownership while allowing administrators', async () => {
  const suffix = randomUUID();
  const ownerId = `access-owner-${suffix}`;
  const strangerId = `access-stranger-${suffix}`;
  const adminId = `access-admin-${suffix}`;
  const projectId = `access-project-${suffix}`;
  createdUsers.push(ownerId, strangerId, adminId);
  createdProjects.push(projectId);
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
  await expect(
    requireProjectMutationAccess(locals('admin', adminId), projectId)
  ).rejects.toMatchObject({ status: 403 });
  await expect(
    requireProjectMutationAccess(locals('participant', ownerId), projectId)
  ).rejects.toThrow('read-only');
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
    schemaVersion: 2,
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
