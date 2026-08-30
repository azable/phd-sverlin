/** Read-only participant and study export adapters over the unified verified pipeline. */

import { and, eq, isNotNull } from 'drizzle-orm';

import {
  PostgresExportDataSource,
  prepareDataExport,
  verifyExportResource,
  type PreparedDataExport
} from '$lib/server/data-export';
import { database } from '$lib/server/db';
import * as schema from '$lib/server/db/schema';
import {
  assertNoActiveProjectOperations,
  assertProjectOperationsIdle
} from '$lib/server/projects/operations';
import type { StudyDefinition } from '$lib/shared/study/definition';
import { studyDefinition, type StudyRef } from '$lib/shared/study/registry';

export type PreparedResearchExport = PreparedDataExport;

export async function prepareParticipantResearchExport(
  userId: string
): Promise<PreparedResearchExport> {
  await assertNoActiveProjectOperations(userId);
  const participantId = await participantLabel(userId);
  return prepareDataExport(
    { type: 'participant', userId },
    `participant-${participantId}`,
    new PostgresExportDataSource()
  );
}

export async function prepareStudyResearchExport(ref?: StudyRef): Promise<PreparedResearchExport> {
  await assertProjectOperationsIdle();
  if (ref) studyDefinition(ref.id, ref.version);
  return prepareDataExport(
    { type: 'study', ...(ref ? { studyId: ref.id, studyVersion: ref.version } : {}) },
    ref ? `study-${ref.id}-v${ref.version}` : 'all-studies',
    new PostgresExportDataSource()
  );
}

/** Resolve each exact registered definition represented by run-like records once. */
export function studyDefinitionsForEnrollments(
  enrollments: readonly { studyId: string; studyVersion: number }[]
): StudyDefinition[] {
  return [
    ...new Map(
      enrollments.map((row) => [
        `${row.studyId}:${row.studyVersion}`,
        studyDefinition(row.studyId, row.studyVersion)
      ])
    ).values()
  ];
}

export const verifyResearchResource = verifyExportResource;

async function participantLabel(userId: string): Promise<string> {
  const [participant] = await database()
    .select({ id: schema.user.id, name: schema.user.name, username: schema.user.username })
    .from(schema.user)
    .where(
      and(eq(schema.user.id, userId), eq(schema.user.role, 'user'), isNotNull(schema.user.username))
    )
    .limit(1);
  if (!participant) throw new Error('Participant not found.');
  return participant.name || participant.username || participant.id;
}
