import { createHash, randomUUID } from 'node:crypto';
import { mkdir, readdir, readFile, rename, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';

import { normalizeProjectV1 } from '$lib/projects/schema';
import { summarizeProject } from '$lib/projects/project';
import type {
  BlobRef,
  NewProjectEvent,
  ProjectDocument,
  ProjectEvent,
  ProjectId,
  ProjectSummary
} from '$lib/projects/types';

export class ProjectNotFoundError extends Error {
  constructor(projectId: string) {
    super(`Unknown project ${projectId}.`);
    this.name = 'ProjectNotFoundError';
  }
}

export class ProjectConflictError extends Error {
  constructor() {
    super('The project changed before this operation completed.');
    this.name = 'ProjectConflictError';
  }
}

export class FileProjectRepository {
  readonly root: string;
  readonly #writeTails = new Map<ProjectId, Promise<void>>();
  readonly #subscribers = new Map<ProjectId, Set<(events: ProjectEvent[]) => void>>();

  constructor(root = projectStorageRoot()) {
    this.root = root;
  }

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

  async create(document: ProjectDocument) {
    assertProjectId(document.projectId);
    normalizeProjectV1(document);
    const directory = this.projectDirectory(document.projectId);
    await mkdir(this.root, { recursive: true });
    await mkdir(directory, { recursive: false });
    await mkdir(this.blobDirectory(document.projectId), { recursive: true });
    await this.writeDocument(document);
    return structuredClone(document);
  }

  async load(projectId: ProjectId) {
    assertProjectId(projectId);
    try {
      const source = await readFile(this.documentPath(projectId), 'utf8');
      return normalizeProjectV1(JSON.parse(source));
    } catch (error) {
      if (isMissing(error)) throw new ProjectNotFoundError(projectId);
      throw error;
    }
  }

  async append(
    projectId: ProjectId,
    expectedHeadEventId: string,
    pendingEvents: NewProjectEvent[]
  ) {
    return this.withWriteLock(projectId, async () => {
      const document = await this.load(projectId);
      const head = document.events.at(-1)!;
      if (head.eventId !== expectedHeadEventId) throw new ProjectConflictError();

      const events: ProjectEvent[] = [];
      let parentEventId = head.eventId;
      let sequence = head.sequence + 1;
      for (const pending of pendingEvents) {
        const event = {
          ...pending,
          sequence,
          parentEventId
        } as ProjectEvent;
        events.push(event);
        parentEventId = event.eventId;
        sequence += 1;
      }

      const next = normalizeProjectV1({ ...document, events: [...document.events, ...events] });
      await this.writeDocument(next);
      this.publish(projectId, events);
      return { document: structuredClone(next), events: structuredClone(events) };
    });
  }

  subscribe(projectId: ProjectId, listener: (events: ProjectEvent[]) => void) {
    assertProjectId(projectId);
    const subscribers = this.#subscribers.get(projectId) ?? new Set();
    subscribers.add(listener);
    this.#subscribers.set(projectId, subscribers);

    return () => {
      subscribers.delete(listener);
      if (subscribers.size === 0) this.#subscribers.delete(projectId);
    };
  }

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
      mediaType,
      ...(typeof value === 'string' ? { encoding: 'utf-8' as const } : {})
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

  async readBlob(projectId: ProjectId, ref: BlobRef) {
    assertProjectId(projectId);
    const bytes = await readFile(this.blobPath(projectId, ref.sha256));
    const actual = createHash('sha256').update(bytes).digest('hex');
    if (actual !== ref.sha256 || bytes.byteLength !== ref.byteLength) {
      throw new Error(`Project blob ${ref.sha256} failed its integrity check.`);
    }
    return bytes;
  }

  async readTextBlob(projectId: ProjectId, ref: BlobRef) {
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
