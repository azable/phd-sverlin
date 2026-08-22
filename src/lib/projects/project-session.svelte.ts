/**
 * Browser-side project state, command submission, and live event synchronization.
 *
 * @packageDocumentation
 */

import { goto } from '$app/navigation';
import { resolve } from '$app/paths';

import { normalizeProjectEventV1, type EventId, type ProjectEvent } from './events';
import type {
  ProjectCommandInput,
  ProjectConnectionState,
  ProjectId,
  ProjectSummary,
  ProjectView
} from './model';
import { projectEventChangesState } from './projection';

/** Metadata for the project command currently awaiting completion. */
export type PendingProjectCommand = {
  type: ProjectCommandInput['type'];
  operationId: string;
  startedAfter: EventId;
};

/**
 * Owns one project's reactive browser session, including historical navigation,
 * command state, and the server-sent event connection.
 */
export class ProjectSession {
  /** Command currently running for this project. */
  pending = $state.raw<PendingProjectCommand | null>(null);
  /** Current state of the live event connection. */
  connection = $state<ProjectConnectionState>('connecting');
  /** Last user-facing session error. */
  error = $state<string | null>(null);
  /** Timeline events explicitly selected as feedback context. */
  focusedEvents = $state.raw<EventId[]>([]);

  #view = $state.raw<ProjectView | null>(null);
  #source?: EventSource;
  #request?: AbortController;
  #loadVersion = 0;

  constructor(readonly projectId: ProjectId) {}

  /** Latest hydrated project view returned by the server. */
  get view(): ProjectView | null {
    return this.#view;
  }

  /** Project state reconstructed at the active cursor. */
  get snapshot(): ProjectView['snapshot'] {
    if (!this.view) throw new Error('The project has not loaded.');
    return this.view.snapshot;
  }

  /** Visualization active at the current project cursor. */
  get visualization(): ProjectView['visualization'] {
    return this.view?.visualization;
  }

  /** Available projects ordered by the server. */
  get projects(): ProjectSummary[] {
    return this.view?.projects ?? [];
  }

  /** Immutable events in the loaded project document. */
  get events(): ProjectEvent[] {
    return this.view?.document.events ?? [];
  }

  /** Stable event ID at the project head, or zero before loading. */
  get head(): number {
    return this.events.length;
  }

  /** Whether the session is viewing the current project state. */
  get atHead(): boolean {
    return this.view !== null && this.view.snapshot.at === this.head;
  }

  /** Most recent streamed event belonging to the pending command. */
  get pendingEvent(): ProjectEvent | undefined {
    const pending = this.pending;
    if (!pending) return undefined;
    return this.events.findLast(
      (event) => event.id > pending.startedAfter && event.operationId === pending.operationId
    );
  }

  /** Load a project view, optionally reconstructed at a historical event. */
  async open(at?: EventId): Promise<void> {
    const version = ++this.#loadVersion;
    this.disconnect();
    this.#request?.abort();
    const request = new AbortController();
    this.#request = request;
    this.connection = 'connecting';
    const query = at ? `?at=${at}` : '';

    try {
      const response = await fetch(`/api/projects/${encodeURIComponent(this.projectId)}${query}`, {
        cache: 'no-store',
        signal: request.signal
      });
      if (!response.ok) throw new Error(await responseError(response));
      const view = (await response.json()) as ProjectView;
      if (version !== this.#loadVersion) return;
      this.#view = view;
      this.connect();
    } catch (cause) {
      if (request.signal.aborted || version !== this.#loadVersion) return;
      this.error = cause instanceof Error ? cause.message : 'The project could not be loaded.';
      this.connection = 'reconnecting';
    }
  }

  /** Stop requests and live updates owned by this session. */
  dispose(): void {
    this.#loadVersion += 1;
    this.#request?.abort();
    this.disconnect();
  }

  /** Toggle an event's inclusion in future feedback context. */
  toggleFocus(id: EventId): void {
    this.focusedEvents = this.focusedEvents.includes(id)
      ? this.focusedEvents.filter((focused) => focused !== id)
      : [...this.focusedEvents, id].toSorted((left, right) => left - right);
  }

  /** Remove an event from future feedback context. */
  removeFocus(id: EventId): void {
    this.focusedEvents = this.focusedEvents.filter((focused) => focused !== id);
  }

  /** Create a new project and navigate to it. */
  async createProject(): Promise<void> {
    if (this.pending) return;
    const response = await fetch('/api/projects', { method: 'POST' });
    if (!response.ok) {
      this.error = await responseError(response);
      return;
    }
    const { projectId } = (await response.json()) as { projectId: string };
    await goto(resolve('/projects/[projectId]', { projectId }));
  }

  /** Submit a project command and install its authoritative resulting view. */
  async runCommand(input: ProjectCommandInput): Promise<boolean> {
    if (this.pending || !this.view || !this.atHead) return false;
    const operationId = crypto.randomUUID();
    this.pending = { type: input.type, operationId, startedAfter: this.head };
    this.error = null;

    try {
      const response = await fetch(`/api/projects/${encodeURIComponent(this.projectId)}`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ ...input, operationId, expectedHead: this.head })
      });
      if (!response.ok) throw new Error(await responseError(response));
      this.#view = (await response.json()) as ProjectView;
      return true;
    } catch (cause) {
      this.error = cause instanceof Error ? cause.message : 'The project operation failed.';
      await this.open();
      return false;
    } finally {
      this.pending = null;
    }
  }

  private connect(): void {
    if (!this.view) return;
    const source = new EventSource(
      `/api/projects/${encodeURIComponent(this.projectId)}/events?after=${this.head}`
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

  private disconnect(): void {
    this.#source?.close();
    this.#source = undefined;
  }

  private ingest(event: ProjectEvent): void {
    if (!this.view) return;
    const existing = this.view.document.events[event.id - 1];
    if (existing) {
      if (existing.operationId !== event.operationId || existing.type !== event.type) {
        void this.recover();
      }
      return;
    }
    if (event.id !== this.head + 1) return void this.recover();
    const wasAtHead = this.atHead;
    this.#view = {
      ...this.view,
      document: {
        ...this.view.document,
        events: [...this.view.document.events, event]
      },
      snapshot: wasAtHead ? { ...this.view.snapshot, at: event.id } : this.view.snapshot
    };
    if (
      wasAtHead &&
      projectEventChangesState(event) &&
      event.operationId !== this.pending?.operationId
    ) {
      void this.open();
    }
  }

  private async recover(): Promise<void> {
    this.connection = 'reconnecting';
    await this.open(this.atHead ? undefined : this.snapshot.at);
  }
}

async function responseError(response: Response): Promise<string> {
  try {
    const value = (await response.json()) as { error?: unknown };
    if (typeof value.error === 'string') return value.error;
  } catch {
    // Fall back to the status below.
  }
  return `Project request failed (${response.status}).`;
}
