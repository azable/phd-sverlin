/** Verified research-data exports and retry-safe live-data purging. */

import { createHash } from 'node:crypto';
import { createReadStream, createWriteStream } from 'node:fs';
import { mkdtemp, rm, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { Readable } from 'node:stream';
import { finished } from 'node:stream/promises';

import { type Archiver, ZipArchive } from 'archiver';
import { and, asc, eq, inArray, isNotNull, isNull } from 'drizzle-orm';

import { auth } from '$lib/server/auth';
import { database } from '$lib/server/db';
import * as schema from '$lib/server/db/schema';
import {
  assertNoActiveProjectOperations,
  assertProjectOperationsIdle
} from '$lib/server/projects/operations';
import { projectRepository } from '$lib/server/projects/repository';
import { setParticipantEnabled } from '$lib/server/participants';
import type { ProjectDocument } from '$lib/shared/projects/model';

const exportFormat = 'sverlin-research-export';
const exportVersion = 2;

type ParticipantSnapshot = {
  id: string;
  participantId: string;
  enabled: boolean;
  createdAt: string;
};

type ProjectSnapshot = {
  id: string;
  ownerUserId: string;
  title: string;
  templateId: string;
  createdAt: string;
  updatedAt: string;
  document: ProjectDocument;
  resources: ResourceSnapshot[];
};

type ResourceSnapshot = {
  projectId: string;
  resourceId: string;
  sha256: string;
  byteLength: number;
  mediaType: string;
  createdAt: string;
};

type ResearchSnapshot = {
  participants: ParticipantSnapshot[];
  projects: ProjectSnapshot[];
};

export type ResearchExportManifest = {
  format: typeof exportFormat;
  version: typeof exportVersion;
  scope: { type: 'participant'; userId: string; participantId: string } | { type: 'study' };
  exportedAt: string;
  application: { version: string; buildSha: string | null };
  participantCount: number;
  projectCount: number;
  files: Array<{ path: string; sha256: string; byteLength: number; mediaType: string }>;
};

export type PreparedResearchExport = {
  filename: string;
  response(): Promise<Response>;
  dispose(): Promise<void>;
};

/** Build a verified participant archive after confirming no command is active. */
export async function prepareParticipantResearchExport(
  userId: string
): Promise<PreparedResearchExport> {
  await assertNoActiveProjectOperations(userId);
  const snapshot = await collectSnapshot(userId);
  const participant = snapshot.participants[0];
  if (!participant) throw new Error('Participant not found.');
  return prepareArchive(snapshot, {
    type: 'participant',
    userId,
    participantId: participant.participantId
  });
}

/** Build a verified whole-study checkpoint only when no project work is pending. */
export async function prepareStudyResearchExport(): Promise<PreparedResearchExport> {
  await assertProjectOperationsIdle();
  return prepareArchive(await collectSnapshot(), { type: 'study' });
}

/** Delete one participant's data after server-side verification of the exact confirmation text. */
export async function purgeParticipantResearchData(
  userId: string,
  confirmation: string,
  headers: Headers
): Promise<string> {
  const participant = await participantIdentity(userId);
  const expected = participantPurgeConfirmation(participant.participantId);
  if (confirmation !== expected) {
    throw new Error(`Enter ${expected} to confirm participant deletion.`);
  }
  await purgeParticipant(participant, headers);
  return participant.participantId;
}

/** Delete every participant and their live research data while preserving administrators. */
export async function purgeStudyResearchData(headers: Headers): Promise<number> {
  await assertProjectOperationsIdle();
  const participants = await database()
    .select({ id: schema.user.id, name: schema.user.name, username: schema.user.username })
    .from(schema.user)
    .where(and(eq(schema.user.role, 'user'), isNotNull(schema.user.username)));
  for (const participant of participants) {
    await purgeParticipant(
      {
        id: participant.id,
        participantId: participant.name || participant.username || participant.id
      },
      headers
    );
  }
  return participants.length;
}

/** Exact confirmation text required for an individual participant purge. */
export function participantPurgeConfirmation(participantId: string): string {
  return `DELETE ${participantId}`;
}

/** Verify bytes against immutable resource metadata before adding them to an archive. */
export function verifyResearchResource(
  bytes: Uint8Array,
  expected: Pick<ResourceSnapshot, 'resourceId' | 'sha256' | 'byteLength'>
): void {
  if (bytes.byteLength !== expected.byteLength) {
    throw new Error(`Resource ${expected.resourceId} has an unexpected byte length.`);
  }
  const digest = sha256(bytes);
  if (digest !== expected.sha256 || expected.resourceId !== `sha256-${digest}`) {
    throw new Error(`Resource ${expected.resourceId} failed SHA-256 verification.`);
  }
}

async function collectSnapshot(ownerUserId?: string): Promise<ResearchSnapshot> {
  const snapshot = await database().transaction(
    async (transaction) => {
      const participantCondition = ownerUserId
        ? and(
            eq(schema.user.id, ownerUserId),
            eq(schema.user.role, 'user'),
            isNotNull(schema.user.username)
          )
        : and(eq(schema.user.role, 'user'), isNotNull(schema.user.username));
      const participantRows = await transaction
        .select({
          id: schema.user.id,
          participantId: schema.user.name,
          username: schema.user.username,
          banned: schema.user.banned,
          createdAt: schema.user.createdAt
        })
        .from(schema.user)
        .where(participantCondition)
        .orderBy(asc(schema.user.createdAt));
      const participantIds = participantRows.map(({ id }) => id);
      const projectRows = participantIds.length
        ? await transaction
            .select({
              id: schema.projects.id,
              ownerUserId: schema.projects.ownerUserId,
              title: schema.projects.title,
              templateId: schema.projects.templateId,
              createdAt: schema.projects.createdAt,
              updatedAt: schema.projects.updatedAt
            })
            .from(schema.projects)
            .where(
              and(
                inArray(schema.projects.ownerUserId, participantIds),
                isNull(schema.projects.deletedAt)
              )
            )
            .orderBy(asc(schema.projects.createdAt))
        : [];
      const projectIds = projectRows.map(({ id }) => id);
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

      return {
        participants: participantRows.map((row) => ({
          id: row.id,
          participantId: row.participantId || row.username || row.id,
          enabled: !row.banned,
          createdAt: row.createdAt.toISOString()
        })),
        projects: projectRows.map((project) => ({
          ...project,
          createdAt: project.createdAt.toISOString(),
          updatedAt: project.updatedAt.toISOString(),
          document: {
            schemaVersion: 1 as const,
            projectId: project.id,
            events: eventRows
              .filter((row) => row.projectId === project.id)
              .map(({ event }) => event)
          },
          resources: resourceRows
            .filter((row) => row.projectId === project.id)
            .map((row) => ({ ...row, createdAt: row.createdAt.toISOString() }))
        }))
      };
    },
    { isolationLevel: 'repeatable read', accessMode: 'read only' }
  );

  return snapshot;
}

async function prepareArchive(
  snapshot: ResearchSnapshot,
  scope: ResearchExportManifest['scope']
): Promise<PreparedResearchExport> {
  const exportedAt = new Date().toISOString();
  const root = await mkdtemp(path.join(tmpdir(), 'sverlin-research-export-'));
  const archivePath = path.join(root, 'export.zip');
  const output = createWriteStream(archivePath, { flags: 'wx' });
  const zip = new ZipArchive({ zlib: { level: 9 } });
  const files: ResearchExportManifest['files'] = [];

  zip.pipe(output);
  try {
    appendJson(zip, files, 'participants.json', snapshot.participants);
    for (const participant of snapshot.participants) {
      const participantRoot = `participants/${safePathSegment(participant.participantId)}-${safePathSegment(participant.id)}`;
      appendJson(zip, files, `${participantRoot}/participant.json`, participant);
      const projects = snapshot.projects.filter(
        ({ ownerUserId }) => ownerUserId === participant.id
      );
      for (const project of projects) {
        const projectRoot = `${participantRoot}/projects/${safePathSegment(project.id)}`;
        appendJson(zip, files, `${projectRoot}/project.json`, {
          id: project.id,
          title: project.title,
          templateId: project.templateId,
          createdAt: project.createdAt,
          updatedAt: project.updatedAt,
          document: project.document
        });
        appendJson(zip, files, `${projectRoot}/resources.json`, project.resources);
        for (const resource of project.resources) {
          const bytes = await projectRepository.readResource(project.id, resource.resourceId);
          verifyResearchResource(bytes, resource);
          appendBytes(
            zip,
            files,
            `${projectRoot}/resources/${resource.resourceId}`,
            bytes,
            resource.mediaType
          );
        }
      }
    }

    const manifest: ResearchExportManifest = {
      format: exportFormat,
      version: exportVersion,
      scope,
      exportedAt,
      application: {
        version: process.env.npm_package_version ?? '0.0.1',
        buildSha:
          process.env.RENDER_GIT_COMMIT?.trim() || process.env.SVERLIN_BUILD_SHA?.trim() || null
      },
      participantCount: snapshot.participants.length,
      projectCount: snapshot.projects.length,
      files
    };
    zip.append(jsonBytes(manifest), { name: 'manifest.json' });
    await zip.finalize();
    await finished(output);
  } catch (cause) {
    zip.abort();
    output.destroy();
    await rm(root, { recursive: true, force: true });
    throw cause;
  }

  const date = exportedAt.slice(0, 10);
  const label =
    scope.type === 'study' ? 'study' : `participant-${safePathSegment(scope.participantId)}`;
  const filename = `sverlin-${label}-${date}.zip`;
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

async function participantIdentity(userId: string): Promise<{ id: string; participantId: string }> {
  const rows = await database()
    .select({ id: schema.user.id, name: schema.user.name, username: schema.user.username })
    .from(schema.user)
    .where(
      and(eq(schema.user.id, userId), eq(schema.user.role, 'user'), isNotNull(schema.user.username))
    )
    .limit(1);
  if (!rows[0]) throw new Error('Participant not found.');
  return { id: rows[0].id, participantId: rows[0].name || rows[0].username || rows[0].id };
}

async function participantProjectIds(userId: string): Promise<string[]> {
  const rows = await database()
    .select({ id: schema.projects.id })
    .from(schema.projects)
    .where(eq(schema.projects.ownerUserId, userId));
  return rows.map(({ id }) => id);
}

async function purgeParticipant(
  participant: { id: string; participantId: string },
  headers: Headers
): Promise<void> {
  await setParticipantEnabled(participant.id, false, headers);
  await assertNoActiveProjectOperations(participant.id);

  const projectIds = await participantProjectIds(participant.id);
  if (projectIds.length) {
    await database().delete(schema.projects).where(inArray(schema.projects.id, projectIds));
  }
  await auth.api.removeUser({ headers, body: { userId: participant.id } });
}

function appendJson(
  zip: Archiver,
  files: ResearchExportManifest['files'],
  pathname: string,
  value: unknown
): void {
  appendBytes(zip, files, pathname, jsonBytes(value), 'application/json');
}

function appendBytes(
  zip: Archiver,
  files: ResearchExportManifest['files'],
  pathname: string,
  bytes: Uint8Array,
  mediaType: string
): void {
  const buffer = Buffer.from(bytes);
  files.push({ path: pathname, sha256: sha256(buffer), byteLength: buffer.byteLength, mediaType });
  zip.append(buffer, { name: pathname });
}

function jsonBytes(value: unknown): Buffer {
  return Buffer.from(`${JSON.stringify(value, null, 2)}\n`);
}

function sha256(bytes: Uint8Array): string {
  return createHash('sha256').update(bytes).digest('hex');
}

function safePathSegment(value: string): string {
  const safe = value.replace(/[^A-Za-z0-9_-]+/g, '_').replace(/^_+|_+$/g, '');
  return safe || 'unknown';
}
