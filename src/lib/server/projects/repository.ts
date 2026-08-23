/**
 * Durable filesystem storage for complete immutable project documents.
 *
 * @packageDocumentation
 */

import { createHash, randomUUID } from 'node:crypto';
import { link, mkdir, readdir, readFile, rename, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';

import { summarizeProject } from '$lib/shared/projects/projection';
import type { NewProjectEvent, ProjectEvent } from '$lib/shared/projects/events';
import type { CompilationResource } from '$lib/shared/projects/events/values';
import {
  normalizeProjectV1,
  type ProjectDocument,
  type ProjectId,
  type ProjectSummary
} from '$lib/shared/projects/model';

/** Validated document and stable events produced by one atomic append. */
export type ProjectAppendResult = {
  document: ProjectDocument;
  events: ProjectEvent[];
};

/** Verified compiler resource bytes committed alongside referencing events. */
export type ProjectResourceBlob = CompilationResource & { bytes: Uint8Array };

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
  readonly #writeTails = new Map<ProjectId, Promise<void>>();
  readonly #subscribers = new Map<ProjectId, Set<(events: ProjectEvent[]) => void>>();

  /** Create a repository rooted at the configured project directory. */
  constructor(root = projectStorageRoot()) {
    this.root = root;
  }

  /** List project summaries ordered from most recently updated. */
  async list(): Promise<ProjectSummary[]> {
    await mkdir(this.root, { recursive: true });
    const entries = await readdir(this.root, { withFileTypes: true });
    const summaries = await Promise.all(
      entries
        .filter((entry) => entry.isDirectory())
        .map(async (entry) => summarizeProject(await this.load(entry.name)))
    );
    return summaries.toSorted((left, right) => right.updatedAt.localeCompare(left.updatedAt));
  }

  /** Persist a new validated project document. */
  async create(document: ProjectDocument): Promise<ProjectDocument> {
    assertProjectId(document.projectId);
    normalizeProjectV1(document);
    const directory = this.projectDirectory(document.projectId);
    await mkdir(this.root, { recursive: true });
    await mkdir(directory, { recursive: false });
    await this.writeDocument(document);
    return structuredClone(document);
  }

  /** Load and validate a project document from disk. */
  async load(projectId: ProjectId): Promise<ProjectDocument> {
    assertProjectId(projectId);
    try {
      const source = await readFile(this.documentPath(projectId), 'utf8');
      return normalizeProjectV1(JSON.parse(source));
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
      return await readFile(this.resourcePath(projectId, resourceId));
    } catch (error) {
      if (isMissing(error)) throw new ProjectResourceNotFoundError(resourceId);
      throw error;
    }
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
      await writeFile(temporary, `${JSON.stringify(document, null, 2)}\n`, {
        encoding: 'utf8',
        flag: 'wx'
      });
      await rename(temporary, destination);
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
      await writeFile(temporary, resource.bytes, { flag: 'wx' });
      try {
        await link(temporary, destination);
      } catch (error) {
        if (!isAlreadyExists(error)) throw error;
        const existing = await readFile(destination);
        if (!Buffer.from(existing).equals(Buffer.from(resource.bytes))) {
          throw new Error(`Stored resource ${resource.id} does not match its content address.`);
        }
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

/** Default repository used by server routes and project operations. */
export const projectRepository = new FileProjectRepository();

function projectStorageRoot() {
  return path.resolve(process.cwd(), process.env.SVERLIN_PROJECT_DIR ?? 'data/projects');
}

function assertProjectId(projectId: string) {
  if (!/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}$/.test(projectId)) {
    throw new Error('Invalid project ID.');
  }
}

function assertResource(resource: ProjectResourceBlob) {
  assertResourceId(resource.id);
  if (resource.id !== `sha256-${resource.sha256}`) {
    throw new Error(`Resource ID ${resource.id} does not match its digest.`);
  }
  if (resource.byteLength !== resource.bytes.byteLength) {
    throw new Error(`Resource ${resource.id} has an unexpected byte length.`);
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
