/**
 * Durable filesystem storage for complete immutable project documents.
 *
 * @packageDocumentation
 */

import { createHash, randomUUID } from 'node:crypto';
import { link, mkdir, open, readdir, readFile, rename, rm, stat } from 'node:fs/promises';
import path from 'node:path';

import { and, asc, desc, eq, gt, isNull } from 'drizzle-orm';

import { summarizeProject } from '$lib/shared/projects/projection';
import type { NewProjectEvent, ProjectEvent } from '$lib/shared/projects/events';
import type { CompilationResource } from '$lib/shared/projects/events/values';
import {
  normalizeProjectV1,
  type ProjectDocument,
  type ProjectId,
  type ProjectSummary
} from '$lib/shared/projects/model';
import { runtimeProjectDir } from '$lib/server/runtime-config';
import { database } from '$lib/server/db';
import * as schema from '$lib/server/db/schema';

const maxProjectDocumentBytes = 64 * 1024 * 1024;
const maxProjectResourceBytes = 16 * 1024 * 1024;

/** Validated document and stable events produced by one atomic append. */
export type ProjectAppendResult = {
  document: ProjectDocument;
  events: ProjectEvent[];
};

/** Verified compiler resource bytes committed alongside referencing events. */
export type ProjectResourceBlob = CompilationResource & { bytes: Uint8Array };

/** Storage contract shared by the local filesystem and PostgreSQL backends. */
export interface ProjectRepository {
  initialize(): Promise<void>;
  list(ownerUserId?: string): Promise<ProjectSummary[]>;
  create(document: ProjectDocument, ownerUserId?: string): Promise<ProjectDocument>;
  load(projectId: ProjectId): Promise<ProjectDocument>;
  append(
    projectId: ProjectId,
    expectedHead: number,
    pendingEvents: NewProjectEvent[],
    resources?: readonly ProjectResourceBlob[]
  ): Promise<ProjectAppendResult>;
  readResource(projectId: ProjectId, resourceId: string): Promise<Uint8Array>;
  eventsAfter(projectId: ProjectId, after: number): Promise<ProjectEvent[]>;
  deleteAll(): Promise<void>;
}

type RepositoryCoordination = {
  writeTails: Map<ProjectId, Promise<void>>;
  subscribers: Map<ProjectId, Set<(events: ProjectEvent[]) => void>>;
};

const repositoryCoordinationKey = Symbol.for('sverlin.project-repository-coordination');
const sharedRepositoryState = globalThis as typeof globalThis & {
  [repositoryCoordinationKey]?: RepositoryCoordination;
};
const sharedRepositoryCoordination = (sharedRepositoryState[repositoryCoordinationKey] ??= {
  writeTails: new Map(),
  subscribers: new Map()
});

/** Raised when a requested project directory does not exist. */
export class ProjectNotFoundError extends Error {
  constructor(projectId: string) {
    super(`Unknown project ${projectId}.`);
    this.name = 'ProjectNotFoundError';
  }
}

/** Raised when an append targets a project head that has already advanced. */
export class ProjectConflictError extends Error {
  constructor() {
    super('The project changed before this operation completed.');
    this.name = 'ProjectConflictError';
  }
}

/** Filesystem-backed project repository with atomic appends and live subscribers. */
export class FileProjectRepository {
  /** Absolute storage root containing project directories. */
  readonly root: string;
  readonly #writeTails: Map<ProjectId, Promise<void>>;
  readonly #subscribers: Map<ProjectId, Set<(events: ProjectEvent[]) => void>>;

  /** Create a repository rooted at the configured project directory. */
  constructor(root = projectStorageRoot(), shareProcessCoordination = false) {
    this.root = root;
    const coordination = shareProcessCoordination
      ? sharedRepositoryCoordination
      : { writeTails: new Map(), subscribers: new Map() };
    this.#writeTails = coordination.writeTails;
    this.#subscribers = coordination.subscribers;
  }

  /** Prepare the durable root and remove only unmistakable abandoned staging entries. */
  async initialize(): Promise<void> {
    await mkdir(this.root, { recursive: true });
    const entries = await readdir(this.root, { withFileTypes: true });
    await Promise.all(
      entries
        .filter((entry) => entry.name.startsWith('.') && entry.name.endsWith('.tmp'))
        .map((entry) => rm(path.join(this.root, entry.name), { recursive: true, force: true }))
    );
  }

  /** List project summaries ordered from most recently updated. */
  async list(_ownerUserId?: string): Promise<ProjectSummary[]> {
    await mkdir(this.root, { recursive: true });
    const entries = await readdir(this.root, { withFileTypes: true });
    const summaries = await Promise.allSettled(
      entries
        .filter((entry) => entry.isDirectory() && isProjectId(entry.name))
        .map(async (entry) => summarizeProject(await this.load(entry.name)))
    );
    return summaries
      .filter(
        (result): result is PromiseFulfilledResult<ProjectSummary> => result.status === 'fulfilled'
      )
      .map(({ value }) => value)
      .toSorted((left, right) => right.updatedAt.localeCompare(left.updatedAt));
  }

  /** Persist a new validated project document. */
  async create(document: ProjectDocument, _ownerUserId?: string): Promise<ProjectDocument> {
    assertProjectId(document.projectId);
    normalizeProjectV1(document);
    const directory = this.projectDirectory(document.projectId);
    const staging = path.join(this.root, `.${document.projectId}.${randomUUID()}.tmp`);
    await mkdir(this.root, { recursive: true });
    await mkdir(staging, { recursive: false });
    try {
      await writeDurableFile(path.join(staging, 'project.json'), encodeDocument(document));
      await syncDirectory(staging);
      await rename(staging, directory);
      await syncDirectory(this.root);
    } finally {
      await rm(staging, { recursive: true, force: true });
    }
    return structuredClone(document);
  }

  /** Load and validate a project document from disk. */
  async load(projectId: ProjectId): Promise<ProjectDocument> {
    assertProjectId(projectId);
    try {
      const source = await readBoundedFile(
        this.documentPath(projectId),
        maxProjectDocumentBytes,
        'Project document'
      );
      return normalizeProjectV1(JSON.parse(source.toString('utf8')));
    } catch (error) {
      if (isMissing(error)) throw new ProjectNotFoundError(projectId);
      throw error;
    }
  }

  /** Atomically append events if the supplied project head is still current. */
  async append(
    projectId: ProjectId,
    expectedHead: number,
    pendingEvents: NewProjectEvent[],
    resources: readonly ProjectResourceBlob[] = []
  ): Promise<ProjectAppendResult> {
    return this.withWriteLock(projectId, async () => {
      const document = await this.load(projectId);
      const head = document.events.at(-1)!;
      if (head.id !== expectedHead) throw new ProjectConflictError();

      const events = pendingEvents.map(
        (pending, index): ProjectEvent => ({ ...pending, id: head.id + index + 1 }) as ProjectEvent
      );

      const next = normalizeProjectV1({ ...document, events: [...document.events, ...events] });
      await Promise.all(resources.map((resource) => this.writeResource(projectId, resource)));
      await this.writeDocument(next);
      this.publish(projectId, events);
      return { document: structuredClone(next), events: structuredClone(events) };
    });
  }

  /** Read one immutable content-addressed resource belonging to a project. */
  async readResource(projectId: ProjectId, resourceId: string): Promise<Uint8Array> {
    assertProjectId(projectId);
    assertResourceId(resourceId);
    try {
      return await readBoundedFile(
        this.resourcePath(projectId, resourceId),
        maxProjectResourceBytes,
        'Project resource'
      );
    } catch (error) {
      if (isMissing(error)) throw new ProjectResourceNotFoundError(resourceId);
      throw error;
    }
  }

  /** Return a stable suffix of the immutable Timeline. */
  async eventsAfter(projectId: ProjectId, after: number): Promise<ProjectEvent[]> {
    const document = await this.load(projectId);
    return document.events.filter(({ id }) => id > after);
  }

  /** Remove all local projects; intended only for explicit administrative reset. */
  async deleteAll(): Promise<void> {
    await rm(this.root, { recursive: true, force: true });
    await mkdir(this.root, { recursive: true });
  }

  /** Subscribe to events after they have been durably appended. */
  subscribe(projectId: ProjectId, listener: (events: ProjectEvent[]) => void): () => void {
    assertProjectId(projectId);
    const subscribers = this.#subscribers.get(projectId) ?? new Set();
    subscribers.add(listener);
    this.#subscribers.set(projectId, subscribers);

    return () => {
      subscribers.delete(listener);
      if (subscribers.size === 0) this.#subscribers.delete(projectId);
    };
  }

  private async writeDocument(document: ProjectDocument) {
    const destination = this.documentPath(document.projectId);
    const temporary = `${destination}.${randomUUID()}.tmp`;
    await mkdir(path.dirname(destination), { recursive: true });
    try {
      await writeDurableFile(temporary, encodeDocument(document));
      await rename(temporary, destination);
      await syncDirectory(path.dirname(destination));
    } finally {
      await rm(temporary, { force: true });
    }
  }

  private async writeResource(projectId: ProjectId, resource: ProjectResourceBlob) {
    assertResource(resource);
    const destination = this.resourcePath(projectId, resource.id);
    const temporary = `${destination}.${randomUUID()}.tmp`;
    await mkdir(path.dirname(destination), { recursive: true });

    try {
      const existing = await readBoundedFile(
        destination,
        maxProjectResourceBytes,
        `Stored resource ${resource.id}`
      );
      assertMatchingResource(existing, resource);
      return;
    } catch (error) {
      if (!isMissing(error)) throw error;
    }

    try {
      await writeDurableFile(temporary, resource.bytes);
      try {
        await link(temporary, destination);
        await syncDirectory(path.dirname(destination));
      } catch (error) {
        if (!isAlreadyExists(error)) throw error;
        const existing = await readBoundedFile(
          destination,
          maxProjectResourceBytes,
          `Stored resource ${resource.id}`
        );
        assertMatchingResource(existing, resource);
      }
    } finally {
      await rm(temporary, { force: true });
    }
  }

  private async withWriteLock<T>(projectId: ProjectId, operation: () => Promise<T>) {
    const previous = this.#writeTails.get(projectId) ?? Promise.resolve();
    let release!: () => void;
    const tail = new Promise<void>((resolve) => {
      release = resolve;
    });
    const chain = previous.then(() => tail);
    this.#writeTails.set(projectId, chain);

    await previous;
    try {
      return await operation();
    } finally {
      release();
      if (this.#writeTails.get(projectId) === chain) this.#writeTails.delete(projectId);
    }
  }

  private publish(projectId: ProjectId, events: ProjectEvent[]) {
    for (const listener of this.#subscribers.get(projectId) ?? []) {
      try {
        listener(structuredClone(events));
      } catch {
        // A live delivery failure cannot undo or fail a durable append.
      }
    }
  }

  private projectDirectory(projectId: ProjectId) {
    return path.join(this.root, projectId);
  }

  private documentPath(projectId: ProjectId) {
    return path.join(this.projectDirectory(projectId), 'project.json');
  }

  private resourcePath(projectId: ProjectId, resourceId: string) {
    return path.join(this.projectDirectory(projectId), 'resources', resourceId);
  }
}

/** PostgreSQL event and resource repository shared by the web and worker services. */
export class PostgresProjectRepository implements ProjectRepository {
  async initialize(): Promise<void> {
    // Migrations own schema creation; application processes never mutate it implicitly.
  }

  async list(ownerUserId?: string): Promise<ProjectSummary[]> {
    const condition = ownerUserId
      ? and(eq(schema.projects.ownerUserId, ownerUserId), isNull(schema.projects.deletedAt))
      : isNull(schema.projects.deletedAt);
    const rows = await database()
      .select({
        projectId: schema.projects.id,
        title: schema.projects.title,
        updatedAt: schema.projects.updatedAt,
        eventCount: schema.projects.head,
        templateId: schema.projects.templateId
      })
      .from(schema.projects)
      .where(condition)
      .orderBy(desc(schema.projects.updatedAt));
    return rows.map((row) => ({ ...row, updatedAt: row.updatedAt.toISOString() }));
  }

  async create(document: ProjectDocument, ownerUserId?: string): Promise<ProjectDocument> {
    assertProjectId(document.projectId);
    const normalized = normalizeProjectV1(document);
    if (!ownerUserId) throw new Error('A project owner is required for PostgreSQL storage.');
    const summary = summarizeProject(normalized);
    await database().transaction(async (transaction) => {
      await transaction.insert(schema.projects).values({
        id: normalized.projectId,
        ownerUserId,
        head: summary.eventCount,
        title: summary.title,
        templateId: summary.templateId,
        createdAt: new Date(normalized.events[0].createdAt),
        updatedAt: new Date(summary.updatedAt)
      });
      await transaction.insert(schema.projectEvents).values(
        normalized.events.map((event) => ({
          projectId: normalized.projectId,
          eventId: event.id,
          operationId: event.operationId,
          event,
          createdAt: new Date(event.createdAt)
        }))
      );
    });
    return structuredClone(normalized);
  }

  async load(projectId: ProjectId): Promise<ProjectDocument> {
    assertProjectId(projectId);
    const project = await database()
      .select({ id: schema.projects.id })
      .from(schema.projects)
      .where(and(eq(schema.projects.id, projectId), isNull(schema.projects.deletedAt)))
      .limit(1);
    if (!project[0]) throw new ProjectNotFoundError(projectId);
    const rows = await database()
      .select({ event: schema.projectEvents.event })
      .from(schema.projectEvents)
      .where(eq(schema.projectEvents.projectId, projectId))
      .orderBy(asc(schema.projectEvents.eventId));
    return normalizeProjectV1({
      schemaVersion: 1,
      projectId,
      events: rows.map(({ event }) => event)
    });
  }

  async append(
    projectId: ProjectId,
    expectedHead: number,
    pendingEvents: NewProjectEvent[],
    resources: readonly ProjectResourceBlob[] = []
  ): Promise<ProjectAppendResult> {
    assertProjectId(projectId);
    resources.forEach(assertResource);

    return database().transaction(async (transaction) => {
      const locked = await transaction
        .select({ head: schema.projects.head })
        .from(schema.projects)
        .where(and(eq(schema.projects.id, projectId), isNull(schema.projects.deletedAt)))
        .for('update')
        .limit(1);
      if (!locked[0]) throw new ProjectNotFoundError(projectId);
      if (locked[0].head !== expectedHead) throw new ProjectConflictError();

      const events = pendingEvents.map(
        (pending, index): ProjectEvent =>
          ({ ...pending, id: expectedHead + index + 1 }) as ProjectEvent
      );
      const rows = await transaction
        .select({ event: schema.projectEvents.event })
        .from(schema.projectEvents)
        .where(eq(schema.projectEvents.projectId, projectId))
        .orderBy(asc(schema.projectEvents.eventId));
      const document = normalizeProjectV1({
        schemaVersion: 1,
        projectId,
        events: [...rows.map(({ event }) => event), ...events]
      });
      const summary = summarizeProject(document);

      if (events.length) {
        await transaction.insert(schema.projectEvents).values(
          events.map((event) => ({
            projectId,
            eventId: event.id,
            operationId: event.operationId,
            event,
            createdAt: new Date(event.createdAt)
          }))
        );
      }
      for (const resource of resources) {
        await transaction
          .insert(schema.projectResources)
          .values({
            projectId,
            resourceId: resource.id,
            bytes: resource.bytes,
            sha256: resource.sha256,
            byteLength: resource.byteLength,
            mediaType: resource.mediaType
          })
          .onConflictDoNothing();
      }
      await transaction
        .update(schema.projects)
        .set({
          head: summary.eventCount,
          title: summary.title,
          templateId: summary.templateId,
          updatedAt: new Date(summary.updatedAt)
        })
        .where(eq(schema.projects.id, projectId));
      return { document: structuredClone(document), events: structuredClone(events) };
    });
  }

  async readResource(projectId: ProjectId, resourceId: string): Promise<Uint8Array> {
    assertProjectId(projectId);
    assertResourceId(resourceId);
    const row = await database()
      .select({
        bytes: schema.projectResources.bytes,
        sha256: schema.projectResources.sha256,
        byteLength: schema.projectResources.byteLength
      })
      .from(schema.projectResources)
      .where(
        and(
          eq(schema.projectResources.projectId, projectId),
          eq(schema.projectResources.resourceId, resourceId)
        )
      )
      .limit(1);
    if (!row[0]) throw new ProjectResourceNotFoundError(resourceId);
    if (!row[0].bytes) {
      throw new Error(`Resource ${resourceId} has not been migrated into PostgreSQL.`);
    }
    const bytes = Uint8Array.from(row[0].bytes);
    if (
      bytes.byteLength !== row[0].byteLength ||
      createHash('sha256').update(bytes).digest('hex') !== row[0].sha256
    ) {
      throw new Error(`Stored resource ${resourceId} failed integrity verification.`);
    }
    return bytes;
  }

  async eventsAfter(projectId: ProjectId, after: number): Promise<ProjectEvent[]> {
    const project = await database()
      .select({ head: schema.projects.head })
      .from(schema.projects)
      .where(and(eq(schema.projects.id, projectId), isNull(schema.projects.deletedAt)))
      .limit(1);
    if (!project[0]) throw new ProjectNotFoundError(projectId);
    if (after > project[0].head) throw new ProjectConflictError();
    const rows = await database()
      .select({ event: schema.projectEvents.event })
      .from(schema.projectEvents)
      .where(
        and(eq(schema.projectEvents.projectId, projectId), gt(schema.projectEvents.eventId, after))
      )
      .orderBy(asc(schema.projectEvents.eventId));
    return rows.map(({ event }) => event);
  }

  async deleteAll(): Promise<void> {
    await database().delete(schema.projects);
  }
}

/** Default repository used by server routes and project operations. */
export const usesPostgresProjectStore = process.env.SVERLIN_PROJECT_STORE === 'postgres';

export const projectRepository: ProjectRepository = usesPostgresProjectStore
  ? new PostgresProjectRepository()
  : new FileProjectRepository(projectStorageRoot(), true);

function projectStorageRoot() {
  return runtimeProjectDir();
}

function assertProjectId(projectId: string) {
  if (!isProjectId(projectId)) {
    throw new Error('Invalid project ID.');
  }
}

function isProjectId(projectId: string) {
  return /^[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}$/.test(projectId);
}

function encodeDocument(document: ProjectDocument) {
  const bytes = Buffer.from(`${JSON.stringify(document, null, 2)}\n`);
  if (bytes.byteLength > maxProjectDocumentBytes) {
    throw new Error(`Project document exceeds the ${maxProjectDocumentBytes} byte limit.`);
  }
  return bytes;
}

async function writeDurableFile(destination: string, bytes: Uint8Array) {
  const handle = await open(destination, 'wx');
  try {
    await handle.writeFile(bytes);
    await handle.sync();
  } finally {
    await handle.close();
  }
}

async function readBoundedFile(destination: string, maximum: number, label: string) {
  const details = await stat(destination);
  if (!details.isFile()) throw new Error(`${label} is not a regular file.`);
  if (details.size > maximum) throw new Error(`${label} exceeds the ${maximum} byte limit.`);
  const bytes = await readFile(destination);
  if (bytes.byteLength > maximum) throw new Error(`${label} exceeds the ${maximum} byte limit.`);
  return bytes;
}

function assertMatchingResource(existing: Uint8Array, resource: ProjectResourceBlob) {
  if (!Buffer.from(existing).equals(Buffer.from(resource.bytes))) {
    throw new Error(`Stored resource ${resource.id} does not match its content address.`);
  }
}

async function syncDirectory(directory: string) {
  if (process.platform === 'win32') return;
  let handle;
  try {
    handle = await open(directory, 'r');
  } catch (error) {
    if (isUnsupportedDirectorySync(error)) return;
    throw error;
  }
  try {
    try {
      await handle.sync();
    } catch (error) {
      if (!isUnsupportedDirectorySync(error)) throw error;
    }
  } finally {
    await handle.close();
  }
}

function isUnsupportedDirectorySync(error: unknown) {
  return (
    isNodeError(error) &&
    (error.code === 'EINVAL' || error.code === 'ENOTSUP' || error.code === 'EBADF')
  );
}

function assertResource(resource: ProjectResourceBlob) {
  assertResourceId(resource.id);
  if (resource.id !== `sha256-${resource.sha256}`) {
    throw new Error(`Resource ID ${resource.id} does not match its digest.`);
  }
  if (resource.byteLength !== resource.bytes.byteLength) {
    throw new Error(`Resource ${resource.id} has an unexpected byte length.`);
  }
  if (resource.byteLength > maxProjectResourceBytes) {
    throw new Error(`Resource ${resource.id} exceeds the ${maxProjectResourceBytes} byte limit.`);
  }
  const digest = createHash('sha256').update(resource.bytes).digest('hex');
  if (digest !== resource.sha256)
    throw new Error(`Resource ${resource.id} failed SHA-256 verification.`);
}

function assertResourceId(resourceId: string) {
  if (!/^sha256-[a-f0-9]{64}$/.test(resourceId)) throw new Error('Invalid resource ID.');
}

/** Raised when a content-addressed project resource does not exist. */
export class ProjectResourceNotFoundError extends Error {
  constructor(resourceId: string) {
    super(`Unknown project resource ${resourceId}.`);
    this.name = 'ProjectResourceNotFoundError';
  }
}

function isMissing(error: unknown) {
  return isNodeError(error) && error.code === 'ENOENT';
}

function isAlreadyExists(error: unknown) {
  return isNodeError(error) && error.code === 'EEXIST';
}

function isNodeError(error: unknown): error is NodeJS.ErrnoException {
  return error instanceof Error && 'code' in error;
}
