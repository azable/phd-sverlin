import { createHash, randomUUID } from 'node:crypto';

import { eq } from 'drizzle-orm';
import { afterAll, expect, it } from 'vitest';

import type { ProjectDocument } from '$lib/shared/projects/model';
import { activeStudyDefinition } from '$lib/shared/study/registry';
import { closeDatabase, database } from '$lib/server/db';
import * as schema from '$lib/server/db/schema';
import { PostgresProjectRepository } from '$lib/server/projects/repository';

import { setParticipantGiftCardUrl } from './participants';
import {
  continueParticipantStudy,
  participantCompletionGiftCardUrl,
  studyTaskProjectId
} from './study';

const enabled = Boolean(process.env.DATABASE_URL) && process.env.SVERLIN_RUN_POSTGRES_TESTS === '1';
const users: string[] = [];
const projects: string[] = [];

afterAll(async () => {
  for (const projectId of projects) {
    await database().delete(schema.projects).where(eq(schema.projects.id, projectId));
  }
  for (const userId of users) {
    await database().delete(schema.user).where(eq(schema.user.id, userId));
  }
  await closeDatabase();
});

it.skipIf(!enabled)(
  'serializes repeated progression and reuses the deterministic ready task project',
  async () => {
    const userId = `study-user-${randomUUID()}`;
    const projectId = studyTaskProjectId(
      activeStudyDefinition.id,
      activeStudyDefinition.version,
      userId,
      'task-one'
    );
    users.push(userId);
    projects.push(projectId);
    await database()
      .insert(schema.user)
      .values({
        id: userId,
        name: userId,
        email: `${userId}@sverlin.invalid`,
        emailVerified: true,
        username: userId,
        role: 'user'
      });
    await database().insert(schema.studyEnrollments).values({
      userId,
      studyId: activeStudyDefinition.id,
      studyVersion: activeStudyDefinition.version,
      armId: 'sverlin-first'
    });
    await new PostgresProjectRepository().create(readyComparison(projectId), userId);

    const [first, retry] = await Promise.all([
      continueParticipantStudy(userId),
      continueParticipantStudy(userId)
    ]);
    const runs = await database()
      .select()
      .from(schema.studyPhaseRuns)
      .where(eq(schema.studyPhaseRuns.userId, userId));
    const [enrollment] = await database()
      .select()
      .from(schema.studyEnrollments)
      .where(eq(schema.studyEnrollments.userId, userId));

    expect(first.projectId).toBe(projectId);
    expect(retry.projectId).toBe(projectId);
    expect(first.deadlineAt).toBe(retry.deadlineAt);
    expect(enrollment?.currentPhaseIndex).toBe(1);
    expect(runs.filter(({ phaseId }) => phaseId === 'task-one')).toHaveLength(1);
    expect(runs).toHaveLength(2);
  },
  30_000
);

it.skipIf(!enabled)('reveals a configured gift card only at completion', async () => {
  const userId = `gift-user-${randomUUID()}`;
  users.push(userId);
  await database()
    .insert(schema.user)
    .values({
      id: userId,
      name: userId,
      email: `${userId}@sverlin.invalid`,
      emailVerified: true,
      username: userId,
      role: 'user'
    });
  await database().insert(schema.studyEnrollments).values({
    userId,
    studyId: activeStudyDefinition.id,
    studyVersion: activeStudyDefinition.version,
    armId: 'sverlin-first'
  });

  await setParticipantGiftCardUrl(userId, 'https://gift.example/card/static');
  expect(await participantCompletionGiftCardUrl(userId)).toBeUndefined();

  await database()
    .update(schema.studyEnrollments)
    .set({ currentPhaseIndex: activeStudyDefinition.flow.length - 1 })
    .where(eq(schema.studyEnrollments.userId, userId));
  expect(await participantCompletionGiftCardUrl(userId)).toBe('https://gift.example/card/static');

  await setParticipantGiftCardUrl(userId, '');
  expect(await participantCompletionGiftCardUrl(userId)).toBeUndefined();
});

function readyComparison(projectId: string): ProjectDocument {
  const operationId = randomUUID();
  const source = recorded('main = pure ()', 'text/x-sverlin');
  const render = recorded(JSON.stringify({ steps: [{ label: 'Only step' }] }), 'application/json');
  const displaySetId = randomUUID();
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
          title: 'Prepared study project',
          entryArtifactId: 'dsl-main',
          creation: { templateId: 'blank', renderer: 'sverlin' }
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
                artifactId: 'dsl-main',
                path: 'Main.sverlin',
                language: 'sverlin',
                content: source
              }
            }
          ]
        }
      },
      ...([0, 1] as const).map((slot) => ({
        id: slot + 3,
        type: 'visualization.presented' as const,
        actor: { kind: 'system' as const },
        operationId,
        createdAt: `2026-08-30T00:00:0${slot + 2}.000Z`,
        payload: {
          displaySetId,
          slot,
          presentation: {
            presentationId: randomUUID(),
            format: 'sverlin-ir-v1' as const,
            stepSignature: 'shared-step-signature',
            seed: slot + 1,
            source,
            render
          }
        }
      }))
    ]
  };
}

function recorded(text: string, mediaType: string) {
  return {
    text,
    mediaType,
    sha256: createHash('sha256').update(text).digest('hex')
  };
}
