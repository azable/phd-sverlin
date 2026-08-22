/**
 * Durable filesystem storage for immutable project documents and content-addressed blobs.
 *
 * @packageDocumentation
 */

import { createHash, randomUUID } from 'node:crypto';
import { mkdir, readdir, readFile, rename, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';

import { summarizeProject } from '$lib/projects/projection';
import type { NewProjectEvent, ProjectEvent } from '$lib/projects/events';
import type { BlobRef } from '$lib/projects/events/values';
import {
  normalizeProjectV1,
  type ProjectDocument,
  type ProjectId,
  type ProjectSummary
} from '$lib/projects/model';

/** Validated document and stable events produced by one atomic append. */
export type ProjectAppendResult = {
  document: ProjectDocument;
  events: ProjectEvent[];
};

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

  /** Persist a new validated project document and initialize its blob store. */
  async create(document: ProjectDocument): Promise<ProjectDocument> {
    assertProjectId(document.projectId);
    normalizeProjectV1(document);
    const directory = this.projectDirectory(document.projectId);
    await mkdir(this.root, { recursive: true });
    await mkdir(directory, { recursive: false });
    await mkdir(this.blobDirectory(document.projectId), { recursive: true });
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
    pendingEvents: NewProjectEvent[]
  ): Promise<ProjectAppendResult> {
    return this.withWriteLock(projectId, async () => {
      const document = await this.load(projectId);
      const head = document.events.at(-1)!;
      if (head.id !== expectedHead) throw new ProjectConflictError();

      const events = pendingEvents.map(
        (pending, index): ProjectEvent => ({ ...pending, id: head.id + index + 1 }) as ProjectEvent
      );

      const next = normalizeProjectV1({ ...document, events: [...document.events, ...events] });
      await this.writeDocument(next);
      this.publish(projectId, events);
      return { document: structuredClone(next), events: structuredClone(events) };
    });
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

  /** Store content by SHA-256 and return its immutable reference. */
  async putBlob(
    projectId: ProjectId,
    value: string | Uint8Array,
    mediaType: string
  ): Promise<BlobRef> {
    assertProjectId(projectId);
    const bytes = typeof value === 'string' ? Buffer.from(value, 'utf8') : Buffer.from(value);
    const sha256 = createHash('sha256').update(bytes).digest('hex');
    const ref: BlobRef = {
      sha256,
      byteLength: bytes.byteLength,
      mediaType
    };
    const destination = this.blobPath(projectId, sha256);
    const temporary = `${destination}.${randomUUID()}.tmp`;
    await mkdir(path.dirname(destination), { recursive: true });

    try {
      await writeFile(temporary, bytes, { flag: 'wx' });
      try {
        await rename(temporary, destination);
      } catch (error) {
        if (!isAlreadyExists(error)) throw error;
      }
    } finally {
      await rm(temporary, { force: true });
    }

    return ref;
  }

  /** Read a blob and verify its digest and byte length. */
  async readBlob(projectId: ProjectId, ref: BlobRef): Promise<Buffer> {
    assertProjectId(projectId);
    const bytes = await readFile(this.blobPath(projectId, ref.sha256));
    const actual = createHash('sha256').update(bytes).digest('hex');
    if (actual !== ref.sha256 || bytes.byteLength !== ref.byteLength) {
      throw new Error(`Project blob ${ref.sha256} failed its integrity check.`);
    }
    return bytes;
  }

  /** Read and integrity-check a UTF-8 project blob. */
  async readTextBlob(projectId: ProjectId, ref: BlobRef): Promise<string> {
    return (await this.readBlob(projectId, ref)).toString('utf8');
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

  private blobDirectory(projectId: ProjectId) {
    return path.join(this.projectDirectory(projectId), 'blobs');
  }

  private blobPath(projectId: ProjectId, sha256: string) {
    if (!/^[a-f0-9]{64}$/.test(sha256)) throw new Error('Invalid project blob hash.');
    return path.join(this.blobDirectory(projectId), sha256.slice(0, 2), sha256);
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

function isMissing(error: unknown) {
  return isNodeError(error) && error.code === 'ENOENT';
}

function isAlreadyExists(error: unknown) {
  return isNodeError(error) && error.code === 'EEXIST';
}

function isNodeError(error: unknown): error is NodeJS.ErrnoException {
  return error instanceof Error && 'code' in error;
}
