import { randomUUID } from 'node:crypto';

import { inArray } from 'drizzle-orm';
import { afterAll, expect, it } from 'vitest';

import { closeDatabase, database } from '$lib/server/db';
import * as schema from '$lib/server/db/schema';
import { PostgresProjectRepository } from '$lib/server/projects/repository';
import type { ProjectDocument } from '$lib/shared/projects/model';
import { pilotStudyV1 } from '$lib/shared/study/pilot-v1';

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
  'scopes study data by participant phase links while project data retains previews',
  async () => {
    const suffix = randomUUID();
    const participantId = `export-participant-${suffix}`;
    const adminId = `export-admin-${suffix}`;
    const studyProjectId = `export-study-${suffix}`;
    const ordinaryProjectId = `export-ordinary-${suffix}`;
    const previewProjectId = `export-preview-${suffix}`;
    createdUsers.push(participantId, adminId);
    createdProjects.push(studyProjectId, ordinaryProjectId, previewProjectId);
    await database()
      .insert(schema.user)
      .values([
        {
          id: participantId,
          name: 'P-Export',
          username: 'P-Export',
          email: `${participantId}@sverlin.invalid`,
          emailVerified: true,
          role: 'user'
        },
        {
          id: adminId,
          name: 'Export administrator',
          email: `${adminId}@sverlin.invalid`,
          emailVerified: true,
          role: 'admin'
        }
      ]);
    const repository = new PostgresProjectRepository();
    await repository.create(document(studyProjectId), participantId);
    await repository.create(document(ordinaryProjectId), participantId);
    await repository.create(document(previewProjectId), adminId);

    const [participantRun] = await database()
      .insert(schema.studyRuns)
      .values({
        mode: 'participant',
        ownerUserId: participantId,
        studyId: pilotStudyV1.id,
        studyVersion: pilotStudyV1.version,
        armId: 'sverlin-first',
        currentPhaseIndex: 1,
        startedAt: new Date()
      })
      .returning({ id: schema.studyRuns.id });
    const [previewRun] = await database()
      .insert(schema.studyRuns)
      .values({
        mode: 'preview',
        ownerUserId: adminId,
        studyId: pilotStudyV1.id,
        studyVersion: pilotStudyV1.version,
        armId: 'html-first',
        currentPhaseIndex: 1,
        startedAt: new Date()
      })
      .returning({ id: schema.studyRuns.id });
    if (!participantRun || !previewRun) throw new Error('Export test runs were not created.');
    await database().insert(schema.studyEnrollments).values({
      userId: participantId,
      runId: participantRun.id
    });
    await database()
      .insert(schema.studyPhaseRuns)
      .values([
        {
          runId: participantRun.id,
          phaseId: 'task-one',
          sequenceIndex: 1,
          kind: 'task',
          projectId: studyProjectId,
          status: 'active'
        },
        {
          runId: previewRun.id,
          phaseId: 'task-one',
          sequenceIndex: 1,
          kind: 'task',
          projectId: previewProjectId,
          status: 'active'
        }
      ]);

    const source = new PostgresExportDataSource(repository);
    const research = await source.collect({
      type: 'study',
      studyId: pilotStudyV1.id,
      studyVersion: pilotStudyV1.version
    });
    expect(research.projects.map(({ id }) => id)).toEqual([studyProjectId]);
    expect(research.study.runs).toHaveLength(1);
    expect(research.study.flows[0]).toMatchObject({ mode: 'participant' });
    expect(JSON.stringify(research)).not.toContain('giftCardUrl');

    const projects = await source.collect({ type: 'projects' });
    expect(projects.projects.map(({ id }) => id)).toEqual(
      expect.arrayContaining([studyProjectId, ordinaryProjectId, previewProjectId])
    );
    expect(projects.study.runs).toEqual(
      expect.arrayContaining([expect.objectContaining({ mode: 'preview' })])
    );
    expect(projects.participants).toEqual([
      expect.objectContaining({ id: participantId, participantId: 'P-Export' })
    ]);
    expect(projects.study.enrollments).toEqual([
      expect.objectContaining({ userId: participantId, runId: participantRun.id })
    ]);
  }
);

function document(projectId: string): ProjectDocument {
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
          title: projectId,
          entryArtifactId: 'dsl-main',
          creation: { templateId: 'blank' }
        }
      }
    ]
  };
}
