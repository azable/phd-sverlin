/** One verified export pipeline for project, study-version, and participant scopes. */

import { createHash } from 'node:crypto';
import { createReadStream, createWriteStream } from 'node:fs';
import { mkdir, mkdtemp, rm, stat, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { Readable } from 'node:stream';
import { finished } from 'node:stream/promises';

import { type Archiver, ZipArchive } from 'archiver';
import { and, asc, eq, inArray, isNotNull, isNull } from 'drizzle-orm';

import { database } from '$lib/server/db';
import * as schema from '$lib/server/db/schema';
import {
  projectRepository,
  ProjectNotFoundError,
  type ProjectReader
} from '$lib/server/projects/repository';
import type { ProjectDocument } from '$lib/shared/projects/model';
import { activeProjectOperation } from '$lib/shared/projects/operations';
import type { VisualizationMode } from '$lib/shared/presentations';
import type { StudyDefinition } from '$lib/shared/study/definition';
import { projectStudyFlow, type StudyFlow } from '$lib/shared/study/projection';
import { registeredStudyDefinitions, studyDefinition } from '$lib/shared/study/registry';

const exportFormat = 'sverlin-data-export';
const exportVersion = 1;

export type ExportScope =
  | { type: 'projects'; projectId?: string }
  | { type: 'study'; studyId?: string; studyVersion?: number }
  | { type: 'participant'; userId: string };

export type ExportOwner = { id: string; label: string; role: string; enabled: boolean };
export type ExportParticipant = {
  id: string;
  participantId: string;
  enabled: boolean;
  createdAt: string;
};
export type ExportResource = {
  projectId: string;
  resourceId: string;
  sha256: string;
  byteLength: number;
  mediaType: string;
  createdAt: string;
};
export type ExportProject = {
  id: string;
  ownerUserId: string;
  title: string;
  templateId: string;
  renderer: VisualizationMode;
  createdAt: string;
  updatedAt: string;
  document: ProjectDocument;
  resources: ExportResource[];
};
export type ExportSnapshot = {
  owners: ExportOwner[];
  participants: ExportParticipant[];
  projects: ExportProject[];
  study: {
    definitions: StudyDefinition[];
    enrollments: Array<Record<string, unknown>>;
    runs: Array<Record<string, unknown>>;
    phases: Array<Record<string, unknown>>;
    flows: StudyFlow[];
  };
};

export interface ExportDataSource {
  collect(scope: ExportScope): Promise<ExportSnapshot>;
  readResource(projectId: string, resourceId: string): Promise<Uint8Array>;
}

export interface ExportSink {
  write(pathname: string, bytes: Uint8Array, mediaType: string): Promise<void> | void;
}

export type DataExportManifest = {
  format: typeof exportFormat;
  version: typeof exportVersion;
  scope: ExportScope;
  exportedAt: string;
  application: { version: string; buildSha: string | null };
  ownerCount: number;
  participantCount: number;
  projectCount: number;
  files: Array<{ path: string; sha256: string; byteLength: number; mediaType: string }>;
};

export type PreparedDataExport = {
  filename: string;
  response(): Promise<Response>;
  dispose(): Promise<void>;
};

/** PostgreSQL source with one safe allowlist and phase-link-based research selection. */
export class PostgresExportDataSource implements ExportDataSource {
  constructor(private readonly repository: ProjectReader = projectRepository) {}

  async collect(scope: ExportScope): Promise<ExportSnapshot> {
    return database().transaction(
      async (transaction) => {
        let participantRows: Array<{
          id: string;
          participantId: string;
          username: string | null;
          banned: boolean | null;
          createdAt: Date;
          runId: string;
          enrolledAt: Date;
        }> = [];
        let runRows: Array<typeof schema.studyRuns.$inferSelect> = [];
        let phaseRows: Array<typeof schema.studyPhaseRuns.$inferSelect> = [];

        if (scope.type !== 'projects') {
          const conditions = [eq(schema.studyRuns.mode, 'participant')];
          if (scope.type === 'participant') conditions.push(eq(schema.user.id, scope.userId));
          if (scope.type === 'study' && scope.studyId) {
            conditions.push(eq(schema.studyRuns.studyId, scope.studyId));
          }
          if (scope.type === 'study' && scope.studyVersion !== undefined) {
            conditions.push(eq(schema.studyRuns.studyVersion, scope.studyVersion));
          }
          participantRows = await transaction
            .select({
              id: schema.user.id,
              participantId: schema.user.name,
              username: schema.user.username,
              banned: schema.user.banned,
              createdAt: schema.user.createdAt,
              runId: schema.studyRuns.id,
              enrolledAt: schema.studyEnrollments.enrolledAt
            })
            .from(schema.studyEnrollments)
            .innerJoin(schema.studyRuns, eq(schema.studyRuns.id, schema.studyEnrollments.runId))
            .innerJoin(schema.user, eq(schema.user.id, schema.studyEnrollments.userId))
            .where(
              and(...conditions, eq(schema.user.role, 'user'), isNotNull(schema.user.username))
            )
            .orderBy(asc(schema.studyEnrollments.enrolledAt));
          if (scope.type === 'participant' && !participantRows.length) {
            throw new Error('Participant not found.');
          }
          const runIds = participantRows.map(({ runId }) => runId);
          runRows = runIds.length
            ? await transaction
                .select()
                .from(schema.studyRuns)
                .where(inArray(schema.studyRuns.id, runIds))
                .orderBy(asc(schema.studyRuns.createdAt))
            : [];
          phaseRows = runIds.length
            ? await transaction
                .select()
                .from(schema.studyPhaseRuns)
                .where(inArray(schema.studyPhaseRuns.runId, runIds))
                .orderBy(asc(schema.studyPhaseRuns.runId), asc(schema.studyPhaseRuns.sequenceIndex))
            : [];
        }

        const researchProjectIds = phaseRows.flatMap(({ projectId }) =>
          projectId ? [projectId] : []
        );
        const projectRows = await transaction
          .select({
            id: schema.projects.id,
            ownerUserId: schema.projects.ownerUserId,
            title: schema.projects.title,
            templateId: schema.projects.templateId,
            renderer: schema.projects.renderer,
            createdAt: schema.projects.createdAt,
            updatedAt: schema.projects.updatedAt
          })
          .from(schema.projects)
          .where(
            scope.type === 'projects'
              ? scope.projectId
                ? and(eq(schema.projects.id, scope.projectId), isNull(schema.projects.deletedAt))
                : isNull(schema.projects.deletedAt)
              : researchProjectIds.length
                ? and(
                    inArray(schema.projects.id, researchProjectIds),
                    isNull(schema.projects.deletedAt)
                  )
                : eq(schema.projects.id, '__no_research_projects__')
          )
          .orderBy(asc(schema.projects.createdAt), asc(schema.projects.id));
        if (scope.type === 'projects' && scope.projectId && !projectRows.length) {
          throw new ProjectNotFoundError(scope.projectId);
        }

        const projectIds = projectRows.map(({ id }) => id);
        if (scope.type === 'projects' && projectIds.length) {
          const associatedPhases = await transaction
            .select()
            .from(schema.studyPhaseRuns)
            .where(inArray(schema.studyPhaseRuns.projectId, projectIds))
            .orderBy(asc(schema.studyPhaseRuns.runId), asc(schema.studyPhaseRuns.sequenceIndex));
          const runIds = [...new Set(associatedPhases.map(({ runId }) => runId))];
          runRows = runIds.length
            ? await transaction
                .select()
                .from(schema.studyRuns)
                .where(inArray(schema.studyRuns.id, runIds))
            : [];
          phaseRows = runIds.length
            ? await transaction
                .select()
                .from(schema.studyPhaseRuns)
                .where(inArray(schema.studyPhaseRuns.runId, runIds))
                .orderBy(asc(schema.studyPhaseRuns.runId), asc(schema.studyPhaseRuns.sequenceIndex))
            : [];
          participantRows = runIds.length
            ? await transaction
                .select({
                  id: schema.user.id,
                  participantId: schema.user.name,
                  username: schema.user.username,
                  banned: schema.user.banned,
                  createdAt: schema.user.createdAt,
                  runId: schema.studyRuns.id,
                  enrolledAt: schema.studyEnrollments.enrolledAt
                })
                .from(schema.studyEnrollments)
                .innerJoin(schema.studyRuns, eq(schema.studyRuns.id, schema.studyEnrollments.runId))
                .innerJoin(schema.user, eq(schema.user.id, schema.studyEnrollments.userId))
                .where(
                  and(
                    inArray(schema.studyRuns.id, runIds),
                    eq(schema.studyRuns.mode, 'participant'),
                    eq(schema.user.role, 'user'),
                    isNotNull(schema.user.username)
                  )
                )
                .orderBy(asc(schema.studyEnrollments.enrolledAt))
            : [];
        }
        const ownerIds = [...new Set(projectRows.map(({ ownerUserId }) => ownerUserId))];
        const ownerRows = ownerIds.length
          ? await transaction
              .select({
                id: schema.user.id,
                name: schema.user.name,
                username: schema.user.username,
                role: schema.user.role,
                banned: schema.user.banned
              })
              .from(schema.user)
              .where(inArray(schema.user.id, ownerIds))
              .orderBy(asc(schema.user.createdAt), asc(schema.user.id))
          : [];
        const eventRows = projectIds.length
          ? await transaction
              .select({
                projectId: schema.projectEvents.projectId,
                event: schema.projectEvents.event
              })
              .from(schema.projectEvents)
              .where(inArray(schema.projectEvents.projectId, projectIds))
              .orderBy(asc(schema.projectEvents.projectId), asc(schema.projectEvents.eventId))
          : [];
        const resourceRows = projectIds.length
          ? await transaction
              .select({
                projectId: schema.projectResources.projectId,
                resourceId: schema.projectResources.resourceId,
                sha256: schema.projectResources.sha256,
                byteLength: schema.projectResources.byteLength,
                mediaType: schema.projectResources.mediaType,
                createdAt: schema.projectResources.createdAt
              })
              .from(schema.projectResources)
              .where(inArray(schema.projectResources.projectId, projectIds))
              .orderBy(
                asc(schema.projectResources.projectId),
                asc(schema.projectResources.resourceId)
              )
          : [];

        const projectDocuments = new Map(
          projectRows.map((project) => {
            const document: ProjectDocument = {
              schemaVersion: 2,
              projectId: project.id,
              events: eventRows
                .filter((row) => row.projectId === project.id)
                .map(({ event }) => event)
            };
            if (activeProjectOperation(document)) {
              throw new Error(
                'A project operation is currently running. Wait for it to finish and try again.'
              );
            }
            return [project.id, document] as const;
          })
        );

        let definitions = [
          ...new Map(
            runRows.map((run) => [
              `${run.studyId}:${run.studyVersion}`,
              studyDefinition(run.studyId, run.studyVersion)
            ])
          ).values()
        ];
        if (scope.type === 'study') {
          definitions =
            scope.studyId && scope.studyVersion !== undefined
              ? [studyDefinition(scope.studyId, scope.studyVersion)]
              : registeredStudyDefinitions();
        }
        const flows = runRows.map((run) =>
          projectStudyFlow(
            studyDefinition(run.studyId, run.studyVersion),
            {
              id: run.id,
              mode: run.mode,
              studyId: run.studyId,
              studyVersion: run.studyVersion,
              armId: run.armId,
              currentPhaseIndex: run.currentPhaseIndex,
              startPhaseIndex: run.startPhaseIndex,
              ...(run.stopAfterPhaseIndex === null
                ? {}
                : { stopAfterPhaseIndex: run.stopAfterPhaseIndex }),
              ...(run.startedAt ? { startedAt: run.startedAt.toISOString() } : {}),
              ...(run.completedAt ? { completedAt: run.completedAt.toISOString() } : {})
            },
            phaseRows
              .filter(({ runId }) => runId === run.id)
              .map((phase) => ({
                phaseId: phase.phaseId,
                sequenceIndex: phase.sequenceIndex,
                status: phase.status,
                ...(phase.projectId ? { projectId: phase.projectId } : {}),
                ...(phase.startedAt ? { startedAt: phase.startedAt.toISOString() } : {}),
                ...(phase.deadlineAt ? { deadlineAt: phase.deadlineAt.toISOString() } : {}),
                ...(phase.endedAt ? { endedAt: phase.endedAt.toISOString() } : {}),
                ...(phase.endReason ? { endReason: phase.endReason } : {})
              }))
          )
        );

        return {
          owners: ownerRows.map((owner) => ({
            id: owner.id,
            label: owner.name || owner.username || owner.id,
            role: owner.role ?? 'user',
            enabled: !owner.banned
          })),
          participants: participantRows.map((participant) => ({
            id: participant.id,
            participantId: participant.participantId || participant.username || participant.id,
            enabled: !participant.banned,
            createdAt: participant.createdAt.toISOString()
          })),
          projects: projectRows.map((project) => ({
            ...project,
            createdAt: project.createdAt.toISOString(),
            updatedAt: project.updatedAt.toISOString(),
            document: requiredProjectDocument(projectDocuments, project.id),
            resources: resourceRows
              .filter((row) => row.projectId === project.id)
              .map((row) => ({ ...row, createdAt: row.createdAt.toISOString() }))
          })),
          study: {
            definitions,
            enrollments: participantRows.map(({ id, runId, enrolledAt }) => ({
              userId: id,
              runId,
              enrolledAt: enrolledAt.toISOString()
            })),
            runs: runRows.map(serializeDates),
            phases: phaseRows.map(serializeDates),
            flows
          }
        };
      },
      { isolationLevel: 'repeatable read', accessMode: 'read only' }
    );
  }

  readResource(projectId: string, resourceId: string): Promise<Uint8Array> {
    return this.repository.readResource(projectId, resourceId);
  }
}

function requiredProjectDocument(
  documents: ReadonlyMap<string, ProjectDocument>,
  projectId: string
): ProjectDocument {
  const document = documents.get(projectId);
  if (!document) throw new Error(`Export snapshot is missing project ${projectId}.`);
  return document;
}

/** Write one canonical tree regardless of scope or destination. */
export async function writeDataExport(
  source: ExportDataSource,
  sink: ExportSink,
  scope: ExportScope,
  exportedAt = new Date().toISOString()
): Promise<DataExportManifest> {
  const snapshot = await source.collect(scope);
  const files: DataExportManifest['files'] = [];
  await appendJson(sink, files, 'owners.json', snapshot.owners);
  await appendJson(sink, files, 'participants.json', snapshot.participants);
  await appendJson(sink, files, 'study/definitions.json', snapshot.study.definitions);
  await appendJson(sink, files, 'study/enrollments.json', snapshot.study.enrollments);
  await appendJson(sink, files, 'study/runs.json', snapshot.study.runs);
  await appendJson(sink, files, 'study/phases.json', snapshot.study.phases);
  await appendJson(sink, files, 'study/flows.json', snapshot.study.flows);
  for (const project of snapshot.projects) {
    const root = `projects/${safePathSegment(project.id)}`;
    await appendJson(sink, files, `${root}/project.json`, {
      id: project.id,
      ownerUserId: project.ownerUserId,
      title: project.title,
      templateId: project.templateId,
      renderer: project.renderer,
      createdAt: project.createdAt,
      updatedAt: project.updatedAt,
      document: project.document
    });
    await appendJson(sink, files, `${root}/resources.json`, project.resources);
    for (const resource of project.resources) {
      const bytes = await source.readResource(project.id, resource.resourceId);
      verifyExportResource(bytes, resource);
      await appendBytes(
        sink,
        files,
        `${root}/resources/${safePathSegment(resource.resourceId)}`,
        bytes,
        resource.mediaType
      );
    }
  }
  const manifest: DataExportManifest = {
    format: exportFormat,
    version: exportVersion,
    scope,
    exportedAt,
    application: {
      version: process.env.npm_package_version ?? '0.0.1',
      buildSha:
        process.env.RENDER_GIT_COMMIT?.trim() || process.env.SVERLIN_BUILD_SHA?.trim() || null
    },
    ownerCount: snapshot.owners.length,
    participantCount: snapshot.participants.length,
    projectCount: snapshot.projects.length,
    files
  };
  await sink.write('manifest.json', jsonBytes(manifest), 'application/json');
  return manifest;
}

export async function writeDataDirectory(
  outputDirectory: string,
  scope: ExportScope,
  source: ExportDataSource = new PostgresExportDataSource(),
  exportedAt?: string
): Promise<DataExportManifest> {
  const destination = path.resolve(outputDirectory);
  await mkdir(path.dirname(destination), { recursive: true });
  await mkdir(destination);
  try {
    return await writeDataExport(
      source,
      {
        async write(relativePath, bytes) {
          const target = path.join(destination, relativePath);
          await mkdir(path.dirname(target), { recursive: true });
          await writeFile(target, bytes, { flag: 'wx' });
        }
      },
      scope,
      exportedAt
    );
  } catch (cause) {
    await rm(destination, { recursive: true, force: true });
    throw cause;
  }
}

export async function prepareDataExport(
  scope: ExportScope,
  filenameLabel: string,
  source: ExportDataSource = new PostgresExportDataSource(),
  exportedAt = new Date().toISOString()
): Promise<PreparedDataExport> {
  const root = await mkdtemp(path.join(tmpdir(), 'sverlin-data-export-'));
  const archivePath = path.join(root, 'export.zip');
  const output = createWriteStream(archivePath, { flags: 'wx' });
  const zip = new ZipArchive({ zlib: { level: 9 } });
  zip.pipe(output);
  try {
    await writeDataExport(source, zipSink(zip), scope, exportedAt);
    await zip.finalize();
    await finished(output);
  } catch (cause) {
    zip.abort();
    output.destroy();
    await rm(root, { recursive: true, force: true });
    throw cause;
  }
  const filename = `sverlin-${safePathSegment(filenameLabel)}-${exportedAt.slice(0, 10)}.zip`;
  return {
    filename,
    async response() {
      const details = await stat(archivePath);
      const stream = createReadStream(archivePath);
      stream.once('close', () => void rm(root, { recursive: true, force: true }));
      return new Response(Readable.toWeb(stream) as ReadableStream, {
        headers: {
          'Content-Type': 'application/zip',
          'Content-Length': String(details.size),
          'Content-Disposition': `attachment; filename="${filename}"`,
          'Cache-Control': 'private, no-store'
        }
      });
    },
    async dispose() {
      await rm(root, { recursive: true, force: true });
    }
  };
}

export function verifyExportResource(
  bytes: Uint8Array,
  expected: Pick<ExportResource, 'resourceId' | 'sha256' | 'byteLength'>
): void {
  if (bytes.byteLength !== expected.byteLength) {
    throw new Error(`Resource ${expected.resourceId} has an unexpected byte length.`);
  }
  const digest = sha256(bytes);
  if (digest !== expected.sha256 || expected.resourceId !== `sha256-${digest}`) {
    throw new Error(`Resource ${expected.resourceId} failed SHA-256 verification.`);
  }
}

function zipSink(zip: Archiver): ExportSink {
  return {
    write(pathname, bytes) {
      zip.append(Buffer.from(bytes), { name: pathname });
    }
  };
}

async function appendJson(
  sink: ExportSink,
  files: DataExportManifest['files'],
  pathname: string,
  value: unknown
): Promise<void> {
  await appendBytes(sink, files, pathname, jsonBytes(value), 'application/json');
}

async function appendBytes(
  sink: ExportSink,
  files: DataExportManifest['files'],
  pathname: string,
  bytes: Uint8Array,
  mediaType: string
): Promise<void> {
  const value = Uint8Array.from(bytes);
  files.push({ path: pathname, sha256: sha256(value), byteLength: value.byteLength, mediaType });
  await sink.write(pathname, value, mediaType);
}

function serializeDates(value: Record<string, unknown>): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(value).map(([key, item]) => [
      key,
      item instanceof Date ? item.toISOString() : item
    ])
  );
}

function jsonBytes(value: unknown): Uint8Array {
  return Buffer.from(`${JSON.stringify(value, null, 2)}\n`);
}

function sha256(bytes: Uint8Array): string {
  return createHash('sha256').update(bytes).digest('hex');
}

export function safeExportPathSegment(value: string): string {
  return safePathSegment(value);
}

function safePathSegment(value: string): string {
  const safe = value.replace(/[^A-Za-z0-9_-]+/g, '_').replace(/^_+|_+$/g, '');
  return safe || 'unknown';
}
