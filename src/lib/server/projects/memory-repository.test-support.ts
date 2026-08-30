/** In-memory ProjectRepository fake for database-free unit tests. */

import { createHash } from 'node:crypto';

import type { NewProjectEvent, ProjectEvent } from '$lib/shared/projects/events';
import {
  normalizeProjectV2,
  type ProjectDocument,
  type ProjectId,
  type ProjectSummary
} from '$lib/shared/projects/model';
import { summarizeProject } from '$lib/shared/projects/projection';

import {
  ProjectConflictError,
  ProjectNotFoundError,
  ProjectResourceNotFoundError,
  type ProjectAppendResult,
  type ProjectRepository,
  type ProjectResourceBlob
} from './repository';

type StoredProject = { document: ProjectDocument; ownerUserId?: string };

export class MemoryProjectRepository implements ProjectRepository {
  readonly #projects = new Map<ProjectId, StoredProject>();
  readonly #resources = new Map<string, Uint8Array>();
  readonly #writeTails = new Map<ProjectId, Promise<void>>();

  async initialize(): Promise<void> {}

  async list(ownerUserId?: string): Promise<ProjectSummary[]> {
    return [...this.#projects.values()]
      .filter((project) => !ownerUserId || project.ownerUserId === ownerUserId)
      .map(({ document }) => summarizeProject(document))
      .toSorted((left, right) => right.updatedAt.localeCompare(left.updatedAt));
  }

  async create(document: ProjectDocument, ownerUserId?: string): Promise<ProjectDocument> {
    const normalized = normalizeProjectV2(document);
    if (this.#projects.has(normalized.projectId)) throw new Error('Project already exists.');
    this.#projects.set(normalized.projectId, {
      document: structuredClone(normalized),
      ownerUserId
    });
    return structuredClone(normalized);
  }

  async load(projectId: ProjectId): Promise<ProjectDocument> {
    const stored = this.#projects.get(projectId);
    if (!stored) throw new ProjectNotFoundError(projectId);
    return structuredClone(stored.document);
  }

  async append(
    projectId: ProjectId,
    expectedHead: number,
    pendingEvents: NewProjectEvent[],
    resources: readonly ProjectResourceBlob[] = []
  ): Promise<ProjectAppendResult> {
    return this.withWriteLock(projectId, async () => {
      const stored = this.#projects.get(projectId);
      if (!stored) throw new ProjectNotFoundError(projectId);
      const head = stored.document.events.at(-1)?.id ?? 0;
      if (head !== expectedHead) throw new ProjectConflictError();

      for (const resource of resources) this.storeResource(projectId, resource);
      const events = pendingEvents.map(
        (event, index): ProjectEvent => ({ ...event, id: head + index + 1 }) as ProjectEvent
      );
      const document = normalizeProjectV2({
        ...stored.document,
        events: [...stored.document.events, ...events]
      });
      stored.document = structuredClone(document);
      return { document: structuredClone(document), events: structuredClone(events) };
    });
  }

  async readResource(projectId: ProjectId, resourceId: string): Promise<Uint8Array> {
    if (!this.#projects.has(projectId)) throw new ProjectNotFoundError(projectId);
    const bytes = this.#resources.get(resourceKey(projectId, resourceId));
    if (!bytes) throw new ProjectResourceNotFoundError(resourceId);
    return Uint8Array.from(bytes);
  }

  async eventsAfter(projectId: ProjectId, after: number): Promise<ProjectEvent[]> {
    const document = await this.load(projectId);
    const head = document.events.at(-1)?.id ?? 0;
    if (after > head) throw new ProjectConflictError();
    return document.events.filter(({ id }) => id > after);
  }

  async deleteAll(): Promise<void> {
    this.#projects.clear();
    this.#resources.clear();
  }

  private storeResource(projectId: string, resource: ProjectResourceBlob): void {
    const digest = createHash('sha256').update(resource.bytes).digest('hex');
    if (resource.id !== `sha256-${resource.sha256}`) {
      throw new Error(`Resource ID ${resource.id} does not match its digest.`);
    }
    if (resource.byteLength !== resource.bytes.byteLength) {
      throw new Error(`Resource ${resource.id} has an unexpected byte length.`);
    }
    if (resource.sha256 !== digest) {
      throw new Error(`Resource ${resource.id} failed integrity verification.`);
    }
    const key = resourceKey(projectId, resource.id);
    const existing = this.#resources.get(key);
    if (existing && !Buffer.from(existing).equals(Buffer.from(resource.bytes))) {
      throw new Error(`Stored resource ${resource.id} does not match its content address.`);
    }
    this.#resources.set(key, Uint8Array.from(resource.bytes));
  }

  private async withWriteLock<T>(projectId: ProjectId, operation: () => Promise<T>): Promise<T> {
    const previous = this.#writeTails.get(projectId) ?? Promise.resolve();
    let release!: () => void;
    const tail = new Promise<void>((resolve) => (release = resolve));
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
}

function resourceKey(projectId: string, resourceId: string): string {
  return `${projectId}:${resourceId}`;
}
