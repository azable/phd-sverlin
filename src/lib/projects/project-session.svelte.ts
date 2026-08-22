import { goto } from '$app/navigation';
import { resolve } from '$app/paths';

import {
  normalizeProjectEventV1,
  type EventId,
  type ProjectCommandInput,
  type ProjectConnectionState,
  type ProjectEvent,
  type ProjectView
} from './types';

export type PendingProjectCommand = {
  type: ProjectCommandInput['type'];
  operationId: string;
  startedAfter: EventId;
};

const projectionEvents = new Set<ProjectEvent['type']>([
  'project.renamed',
  'artifact.version-created',
  'visualization.rendered'
]);

export class ProjectSession {
  view = $state<ProjectView | null>(null);
  cursor = $state<EventId | null>(null);
  pending = $state<PendingProjectCommand | null>(null);
  connection = $state<ProjectConnectionState>('connecting');
  error = $state<string | null>(null);
  focusedEvents = $state<EventId[]>([]);

  #projectId: string;
  #source?: EventSource;
  #request?: AbortController;
  #loadVersion = 0;

  constructor(projectId: string) {
    this.#projectId = projectId;
  }

  get ready() {
    return this.view !== null;
  }

  get document() {
    if (!this.view) throw new Error('The project has not loaded.');
    return this.view.document;
  }

  get snapshot() {
    if (!this.view) throw new Error('The project has not loaded.');
    return this.view.snapshot;
  }

  get visualization() {
    return this.view?.visualization;
  }

  get projects() {
    return this.view?.projects ?? [];
  }

  get events() {
    return this.view?.document.events ?? [];
  }

  get head() {
    return this.events.length;
  }

  get atHead() {
    return this.cursor === null || this.cursor === this.head;
  }

  get pendingEvent() {
    const pending = this.pending;
    if (!pending) return undefined;
    return this.events.findLast(
      (event) => event.id > pending.startedAfter && event.operationId === pending.operationId
    );
  }

  async open(at?: EventId) {
    const version = ++this.#loadVersion;
    this.disconnect();
    this.#request?.abort();
    const request = new AbortController();
    this.#request = request;
    this.connection = 'connecting';
    const query = at ? `?at=${at}` : '';

    try {
      const response = await fetch(`/api/projects/${encodeURIComponent(this.#projectId)}${query}`, {
        cache: 'no-store',
        signal: request.signal
      });
      if (!response.ok) throw new Error(await responseError(response));
      const view = (await response.json()) as ProjectView;
      if (version !== this.#loadVersion) return;
      this.view = view;
      this.cursor = at && at !== view.document.events.length ? at : null;
      this.connect();
    } catch (cause) {
      if (request.signal.aborted || version !== this.#loadVersion) return;
      this.error = cause instanceof Error ? cause.message : 'The project could not be loaded.';
      this.connection = 'reconnecting';
    }
  }

  dispose() {
    this.#loadVersion += 1;
    this.#request?.abort();
    this.disconnect();
  }

  toggleFocus(id: EventId) {
    this.focusedEvents = this.focusedEvents.includes(id)
      ? this.focusedEvents.filter((focused) => focused !== id)
      : [...this.focusedEvents, id].toSorted((left, right) => left - right);
  }

  removeFocus(id: EventId) {
    this.focusedEvents = this.focusedEvents.filter((focused) => focused !== id);
  }

  async createProject() {
    if (this.pending) return;
    const response = await fetch('/api/projects', { method: 'POST' });
    if (!response.ok) {
      this.error = await responseError(response);
      return;
    }
    const { projectId } = (await response.json()) as { projectId: string };
    await goto(resolve('/projects/[projectId]', { projectId }));
  }

  async runCommand(input: ProjectCommandInput) {
    if (this.pending || !this.view) return false;
    const operationId = crypto.randomUUID();
    this.pending = { type: input.type, operationId, startedAfter: this.head };
    this.error = null;

    try {
      const response = await fetch(`/api/projects/${encodeURIComponent(this.#projectId)}`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ ...input, operationId, expectedHead: this.head })
      });
      if (!response.ok) throw new Error(await responseError(response));
      await goto(resolve('/projects/[projectId]', { projectId: this.#projectId }), {
        replaceState: this.cursor !== null
      });
      await this.open();
      return true;
    } catch (cause) {
      this.error = cause instanceof Error ? cause.message : 'The project operation failed.';
      await this.open(this.cursor ?? undefined);
      return false;
    } finally {
      this.pending = null;
    }
  }

  private connect() {
    if (!this.view) return;
    const source = new EventSource(
      `/api/projects/${encodeURIComponent(this.#projectId)}/events?after=${this.head}`
    );
    this.#source = source;

    source.addEventListener('project-event', (message) => {
      try {
        this.ingest(normalizeProjectEventV1(JSON.parse((message as MessageEvent<string>).data)));
      } catch {
        void this.recover();
      }
    });
    source.addEventListener('ready', () => (this.connection = 'open'));
    source.addEventListener('error', () => (this.connection = 'reconnecting'));
  }

  private disconnect() {
    this.#source?.close();
    this.#source = undefined;
  }

  private ingest(event: ProjectEvent) {
    if (!this.view) return;
    const existing = this.view.document.events[event.id - 1];
    if (existing) {
      if (existing.operationId !== event.operationId || existing.type !== event.type) {
        void this.recover();
      }
      return;
    }
    if (event.id !== this.head + 1) return void this.recover();
    this.view.document.events.push(event);
    if (
      this.atHead &&
      projectionEvents.has(event.type) &&
      event.operationId !== this.pending?.operationId
    ) {
      void this.open();
    }
  }

  private async recover() {
    this.connection = 'reconnecting';
    await this.open(this.cursor ?? undefined);
  }
}

async function responseError(response: Response) {
  try {
    const value = (await response.json()) as { error?: unknown };
    if (typeof value.error === 'string') return value.error;
  } catch {
    // Fall back to the status below.
  }
  return `Project request failed (${response.status}).`;
}
