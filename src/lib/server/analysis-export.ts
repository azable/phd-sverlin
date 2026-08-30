/** Debugging-oriented project exports with interchangeable directory and ZIP sinks. */

import { createHash } from 'node:crypto';
import { createReadStream, createWriteStream } from 'node:fs';
import { mkdir, mkdtemp, rm, stat, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { Readable } from 'node:stream';
import { finished } from 'node:stream/promises';

import { type Archiver, ZipArchive } from 'archiver';
import { and, asc, eq, inArray, isNull } from 'drizzle-orm';

import type { ProjectDocument } from '$lib/shared/projects/model';
import { database } from '$lib/server/db';
import * as schema from '$lib/server/db/schema';
import {
  projectRepository,
  ProjectNotFoundError,
  type ProjectReader
} from '$lib/server/projects/repository';

const analysisExportFormat = 'sverlin-project-analysis';
const analysisExportVersion = 1;

export type AnalysisOwner = {
  id: string;
  label: string;
  role: string;
  enabled: boolean;
};

export type AnalysisResource = {
  projectId: string;
  resourceId: string;
  sha256: string;
  byteLength: number;
  mediaType: string;
  createdAt: string;
};

export type AnalysisProject = {
  id: string;
  ownerUserId: string;
  title: string;
  templateId: string;
  createdAt: string;
  updatedAt: string;
  document: ProjectDocument;
  resources: AnalysisResource[];
};

export type AnalysisSnapshot = {
  owners: AnalysisOwner[];
  projects: AnalysisProject[];
};

/** Source boundary that can be replaced with deterministic fixtures in unit tests. */
export interface AnalysisDataSource {
  collect(projectId?: string): Promise<AnalysisSnapshot>;
  readResource(projectId: string, resourceId: string): Promise<Uint8Array>;
}

/** Destination boundary shared by local directories and HTTP ZIP downloads. */
export interface AnalysisExportSink {
  write(pathname: string, bytes: Uint8Array, mediaType: string): Promise<void> | void;
}

export type AnalysisExportManifest = {
  format: typeof analysisExportFormat;
  version: typeof analysisExportVersion;
  scope: { type: 'all-active-projects' } | { type: 'project'; projectId: string };
  exportedAt: string;
  application: { version: string; buildSha: string | null };
  ownerCount: number;
  projectCount: number;
  files: Array<{ path: string; sha256: string; byteLength: number; mediaType: string }>;
};

export type PreparedAnalysisExport = {
  filename: string;
  response(): Promise<Response>;
  dispose(): Promise<void>;
};

/** Production analysis source. Its queries contain no authentication credentials or sessions. */
export class PostgresAnalysisDataSource implements AnalysisDataSource {
  constructor(private readonly repository: ProjectReader = projectRepository) {}

  async collect(projectId?: string): Promise<AnalysisSnapshot> {
    const snapshot = await database().transaction(
      async (transaction) => {
        const projectRows = await transaction
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
            projectId
              ? and(eq(schema.projects.id, projectId), isNull(schema.projects.deletedAt))
              : isNull(schema.projects.deletedAt)
          )
          .orderBy(asc(schema.projects.createdAt), asc(schema.projects.id));
        if (projectId && projectRows.length === 0) throw new ProjectNotFoundError(projectId);

        const projectIds = projectRows.map(({ id }) => id);
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

        return {
          owners: ownerRows.map((owner) => ({
            id: owner.id,
            label: owner.name || owner.username || owner.id,
            role: owner.role ?? 'user',
            enabled: !owner.banned
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

  readResource(projectId: string, resourceId: string): Promise<Uint8Array> {
    return this.repository.readResource(projectId, resourceId);
  }
}

/** Write the canonical analysis tree. All delivery methods call this traversal. */
export async function writeAnalysisExport(
  source: AnalysisDataSource,
  sink: AnalysisExportSink,
  options: { projectId?: string; exportedAt?: string } = {}
): Promise<AnalysisExportManifest> {
  const exportedAt = options.exportedAt ?? new Date().toISOString();
  const snapshot = await source.collect(options.projectId);
  const files: AnalysisExportManifest['files'] = [];

  await appendJson(sink, files, 'owners.json', snapshot.owners);
  for (const project of snapshot.projects) {
    const root = `projects/${safePathSegment(project.id)}`;
    await appendJson(sink, files, `${root}/project.json`, {
      id: project.id,
      ownerUserId: project.ownerUserId,
      title: project.title,
      templateId: project.templateId,
      createdAt: project.createdAt,
      updatedAt: project.updatedAt,
      document: project.document
    });
    await appendJson(sink, files, `${root}/resources.json`, project.resources);
    for (const resource of project.resources) {
      const bytes = await source.readResource(project.id, resource.resourceId);
      verifyAnalysisResource(bytes, resource);
      await appendBytes(
        sink,
        files,
        `${root}/resources/${safePathSegment(resource.resourceId)}`,
        bytes,
        resource.mediaType
      );
    }
  }

  const manifest: AnalysisExportManifest = {
    format: analysisExportFormat,
    version: analysisExportVersion,
    scope: options.projectId
      ? { type: 'project', projectId: options.projectId }
      : { type: 'all-active-projects' },
    exportedAt,
    application: {
      version: process.env.npm_package_version ?? '0.0.1',
      buildSha:
        process.env.RENDER_GIT_COMMIT?.trim() || process.env.SVERLIN_BUILD_SHA?.trim() || null
    },
    ownerCount: snapshot.owners.length,
    projectCount: snapshot.projects.length,
    files
  };
  await sink.write('manifest.json', jsonBytes(manifest), 'application/json');
  return manifest;
}

/** Create a local readable analysis tree and refuse accidental overwrite. */
export async function writeAnalysisDirectory(
  outputDirectory: string,
  projectId?: string,
  source: AnalysisDataSource = new PostgresAnalysisDataSource()
): Promise<AnalysisExportManifest> {
  const destination = path.resolve(outputDirectory);
  await mkdir(path.dirname(destination), { recursive: true });
  await mkdir(destination);
  try {
    return await writeAnalysisExport(
      source,
      {
        async write(relativePath, bytes) {
          const target = path.join(destination, relativePath);
          await mkdir(path.dirname(target), { recursive: true });
          await writeFile(target, bytes, { flag: 'wx' });
        }
      },
      { ...(projectId ? { projectId } : {}) }
    );
  } catch (cause) {
    await rm(destination, { recursive: true, force: true });
    throw cause;
  }
}

/** Prepare the HTTP ZIP adapter over the same canonical analysis traversal. */
export async function prepareAnalysisExport(
  projectId?: string,
  source: AnalysisDataSource = new PostgresAnalysisDataSource()
): Promise<PreparedAnalysisExport> {
  const root = await mkdtemp(path.join(tmpdir(), 'sverlin-analysis-export-'));
  const archivePath = path.join(root, 'analysis.zip');
  const output = createWriteStream(archivePath, { flags: 'wx' });
  const zip = new ZipArchive({ zlib: { level: 9 } });
  zip.pipe(output);
  try {
    await writeAnalysisExport(source, zipSink(zip), { ...(projectId ? { projectId } : {}) });
    await zip.finalize();
    await finished(output);
  } catch (cause) {
    zip.abort();
    output.destroy();
    await rm(root, { recursive: true, force: true });
    throw cause;
  }

  const date = new Date().toISOString().slice(0, 10);
  const label = projectId ? `project-${safePathSegment(projectId)}` : 'all-projects';
  const filename = `sverlin-analysis-${label}-${date}.zip`;
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

export function verifyAnalysisResource(
  bytes: Uint8Array,
  expected: Pick<AnalysisResource, 'resourceId' | 'sha256' | 'byteLength'>
): void {
  if (bytes.byteLength !== expected.byteLength) {
    throw new Error(`Resource ${expected.resourceId} has an unexpected byte length.`);
  }
  const digest = sha256(bytes);
  if (digest !== expected.sha256 || expected.resourceId !== `sha256-${digest}`) {
    throw new Error(`Resource ${expected.resourceId} failed SHA-256 verification.`);
  }
}

function zipSink(zip: Archiver): AnalysisExportSink {
  return {
    write(pathname, bytes) {
      zip.append(Buffer.from(bytes), { name: pathname });
    }
  };
}

async function appendJson(
  sink: AnalysisExportSink,
  files: AnalysisExportManifest['files'],
  pathname: string,
  value: unknown
): Promise<void> {
  await appendBytes(sink, files, pathname, jsonBytes(value), 'application/json');
}

async function appendBytes(
  sink: AnalysisExportSink,
  files: AnalysisExportManifest['files'],
  pathname: string,
  bytes: Uint8Array,
  mediaType: string
): Promise<void> {
  const value = Uint8Array.from(bytes);
  files.push({ path: pathname, sha256: sha256(value), byteLength: value.byteLength, mediaType });
  await sink.write(pathname, value, mediaType);
}

function jsonBytes(value: unknown): Uint8Array {
  return Buffer.from(`${JSON.stringify(value, null, 2)}\n`);
}

function sha256(bytes: Uint8Array): string {
  return createHash('sha256').update(bytes).digest('hex');
}

function safePathSegment(value: string): string {
  const safe = value.replace(/[^A-Za-z0-9_-]+/g, '_').replace(/^_+|_+$/g, '');
  return safe || 'unknown';
}
