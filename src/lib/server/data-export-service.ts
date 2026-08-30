/** Scope resolution and lifecycle guards shared by every data-export delivery path. */

import { and, eq, isNotNull } from 'drizzle-orm';

import {
  PostgresExportDataSource,
  prepareDataExport,
  writeDataDirectory,
  type DataExportManifest,
  type ExportDataSource,
  type ExportScope,
  type PreparedDataExport
} from '$lib/server/data-export';
import { database } from '$lib/server/db';
import * as schema from '$lib/server/db/schema';
import {
  assertNoActiveProjectOperations,
  assertProjectOperationsIdle
} from '$lib/server/projects/operations';
import { projectRepository } from '$lib/server/projects/repository';
import { activeProjectOperation } from '$lib/shared/projects/operations';
import { studyDefinition } from '$lib/shared/study/registry';

export type DataExportSelection =
  | { type: 'projects'; projectId?: string }
  | { type: 'study'; studyId?: string; studyVersion?: number }
  | {
      type: 'participant';
      participant: { type: 'user-id' | 'participant-id'; value: string };
    };

export type ResolvedDataExport = {
  scope: ExportScope;
  filenameLabel: string;
};

type ServiceDependencies = {
  source: ExportDataSource;
  resolveParticipant: typeof resolveParticipant;
  assertIdle: typeof assertExportIdle;
};

const defaultDependencies: ServiceDependencies = {
  source: new PostgresExportDataSource(),
  resolveParticipant,
  assertIdle: assertExportIdle
};

/** Prepare the canonical ZIP used by the administrator interface. */
export async function prepareSelectedDataExport(
  selection: DataExportSelection,
  options: { exportedAt?: string } = {},
  dependencies: ServiceDependencies = defaultDependencies
): Promise<PreparedDataExport> {
  const resolved = await resolveDataExport(selection, dependencies.resolveParticipant);
  await dependencies.assertIdle(resolved.scope);
  return prepareDataExport(
    resolved.scope,
    resolved.filenameLabel,
    dependencies.source,
    options.exportedAt
  );
}

/** Write the same canonical tree as the administrator ZIP into a new directory. */
export async function writeSelectedDataDirectory(
  outputDirectory: string,
  selection: DataExportSelection,
  options: { exportedAt?: string } = {},
  dependencies: ServiceDependencies = defaultDependencies
): Promise<DataExportManifest> {
  const resolved = await resolveDataExport(selection, dependencies.resolveParticipant);
  await dependencies.assertIdle(resolved.scope);
  return writeDataDirectory(
    outputDirectory,
    resolved.scope,
    dependencies.source,
    options.exportedAt
  );
}

/** Resolve human-facing selections to the internal, manifest-recorded export scope. */
export async function resolveDataExport(
  selection: DataExportSelection,
  participantResolver: typeof resolveParticipant = resolveParticipant
): Promise<ResolvedDataExport> {
  if (selection.type === 'projects') {
    return {
      scope: {
        type: 'projects',
        ...(selection.projectId ? { projectId: selection.projectId } : {})
      },
      filenameLabel: selection.projectId ? `project-${selection.projectId}` : 'all-projects'
    };
  }
  if (selection.type === 'study') {
    const hasId = selection.studyId !== undefined;
    const hasVersion = selection.studyVersion !== undefined;
    if (hasId !== hasVersion) throw new Error('Study ID and version must be supplied together.');
    if (selection.studyId && selection.studyVersion !== undefined) {
      studyDefinition(selection.studyId, selection.studyVersion);
      return {
        scope: {
          type: 'study',
          studyId: selection.studyId,
          studyVersion: selection.studyVersion
        },
        filenameLabel: `study-${selection.studyId}-v${selection.studyVersion}`
      };
    }
    return { scope: { type: 'study' }, filenameLabel: 'all-studies' };
  }

  const participant = await participantResolver(selection.participant);
  return {
    scope: { type: 'participant', userId: participant.userId },
    filenameLabel: `participant-${participant.participantId}`
  };
}

async function assertExportIdle(scope: ExportScope): Promise<void> {
  if (scope.type === 'participant') {
    await assertNoActiveProjectOperations(scope.userId);
    return;
  }
  if (scope.type === 'projects' && scope.projectId) {
    const document = await projectRepository.load(scope.projectId);
    if (activeProjectOperation(document)) {
      throw new Error(
        'A project operation is currently running. Wait for it to finish and try again.'
      );
    }
    return;
  }
  await assertProjectOperationsIdle();
}

async function resolveParticipant(selector: {
  type: 'user-id' | 'participant-id';
  value: string;
}): Promise<{ userId: string; participantId: string }> {
  const value = selector.value.trim();
  if (!value) throw new Error('Participant identifier cannot be empty.');
  const [participant] = await database()
    .select({ id: schema.user.id, name: schema.user.name, username: schema.user.username })
    .from(schema.user)
    .where(
      and(
        selector.type === 'user-id' ? eq(schema.user.id, value) : eq(schema.user.username, value),
        eq(schema.user.role, 'user'),
        isNotNull(schema.user.username)
      )
    )
    .limit(1);
  if (!participant) throw new Error('Participant not found.');
  return {
    userId: participant.id,
    participantId: participant.name || participant.username || participant.id
  };
}
