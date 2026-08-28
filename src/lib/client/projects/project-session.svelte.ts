/**
 * Browser-side project state, commands, history navigation, and live event sync.
 *
 * @packageDocumentation
 */

import { goto } from '$app/navigation';
import { resolve } from '$app/paths';

import { unlockedMaintenanceStatus, type MaintenanceStatus } from '$lib/shared/maintenance';
import {
  normalizeProjectEventV1,
  type EventId,
  type ProjectEvent
} from '$lib/shared/projects/events';
import {
  normalizeProjectResourceV1,
  type ProjectCommandInput,
  type ProjectId,
  type ProjectResource,
  type ProjectSnapshot,
  type ProjectSummary
} from '$lib/shared/projects/model';
import { defaultProjectCreation, type ProjectCreation } from '$lib/shared/projects/creation';
import { projectSnapshotAt, summarizeProject } from '$lib/shared/projects/projection';
import { decodeVisualization, type Visualization } from '$lib/shared/visualization';

/** Browser-visible state of the project's durable event polling connection. */
export type ProjectConnectionState = 'connecting' | 'open' | 'reconnecting';

/** Metadata for the project command currently awaiting completion. */
export type PendingProjectCommand = {
  type: ProjectCommandInput['type'];
  operationId: string;
  startedAfter: EventId;
};

/**
 * Owns one project's reactive browser session. The complete document is the
 * only synchronized state; snapshots and visualizations are local projections.
 */
export class ProjectSession {
  /** Command currently running for this project. */
  pending = $state.raw<PendingProjectCommand | null>(null);
  /** Whether a new template-backed project is currently being created. */
  creating = $state(false);
  /** Current state of the live event connection. */
  connection = $state<ProjectConnectionState>('connecting');
  /** Last user-facing session error. */
  error = $state<string | null>(null);
  /** Timeline events explicitly selected as feedback context. */
  focusedEvents = $state.raw<EventId[]>([]);
  /** Whether the server has temporarily disabled project mutations. */
  maintenance = $state.raw<MaintenanceStatus>(unlockedMaintenanceStatus);

  #resource = $state.raw<ProjectResource | null>(null);
  #selectedAt = $state<EventId | undefined>(undefined);
  #eventTimer?: ReturnType<typeof setInterval>;
  #request?: AbortController;
  #commandRequest?: AbortController;
  #maintenanceTimer?: ReturnType<typeof setInterval>;
  #loadVersion = 0;

  constructor(readonly projectId: ProjectId) {}

  /** Complete project resource most recently received from the server. */
  get resource(): ProjectResource | null {
    return this.#resource;
  }

  /** Project state reconstructed at the selected event position. */
  get snapshot(): ProjectSnapshot {
    if (!this.#resource) throw new Error('The project has not loaded.');
    return projectSnapshotAt(this.#resource.document, this.#selectedAt);
  }

  /** Visualization decoded from the render active at the selected position. */
  get visualization(): Visualization | undefined {
    const render = this.#resource ? this.snapshot.activeRender : undefined;
    return render ? decodeVisualization(render.payload.render.text) : undefined;
  }

  /** Available projects ordered by the server. */
  get projects(): ProjectSummary[] {
    return this.#resource?.projects ?? [];
  }

  /** Immutable events in the loaded project document. */
  get events(): ProjectEvent[] {
    return this.#resource?.document.events ?? [];
  }

  /** Stable event ID at the project head, or zero before loading. */
  get head(): number {
    return this.events.length;
  }

  /** Whether the session is viewing the current project state. */
  get atHead(): boolean {
    return this.#resource !== null && this.#selectedAt === undefined;
  }

  /** Whether create, edit, feedback, and render commands are currently blocked. */
  get maintenanceLocked(): boolean {
    return this.maintenance.locked;
  }

  /** Most recent streamed event belonging to the pending command. */
  get pendingEvent(): ProjectEvent | undefined {
    const pending = this.pending;
    if (!pending) return undefined;
    return this.events.findLast(
      (event) => event.id > pending.startedAfter && event.operationId === pending.operationId
    );
  }

  /** Select a historical event locally; omitting it follows the live head. */
  select(at?: EventId): void {
    if (at !== undefined && this.#resource && at > this.head) {
      this.error = `Unknown project event ${at}.`;
      this.#selectedAt = undefined;
      return;
    }
    this.#selectedAt = at;
  }

  /** Load the complete project resource once and start live synchronization. */
  async open(): Promise<void> {
    const version = ++this.#loadVersion;
    this.disconnect();
    this.#request?.abort();
    const request = new AbortController();
    this.#request = request;
    this.connection = 'connecting';
    await this.refreshMaintenance();
    if (version !== this.#loadVersion) return;
    this.startMaintenancePolling();

    try {
      const response = await fetch(`/api/projects/${encodeURIComponent(this.projectId)}`, {
        cache: 'no-store',
        signal: request.signal
      });
      if (!response.ok) throw new Error(await responseError(response));
      const resource = parseProjectResource(await response.json());
      if (version !== this.#loadVersion) return;
      this.#resource = resource;
      this.select(this.#selectedAt);
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
    this.#commandRequest?.abort();
    this.disconnect();
    if (this.#maintenanceTimer) clearInterval(this.#maintenanceTimer);
    this.#maintenanceTimer = undefined;
  }

  /** Refresh the server-owned read-only state without disturbing project loading. */
  async refreshMaintenance(): Promise<void> {
    try {
      const response = await fetch('/api/maintenance', { cache: 'no-store' });
      if (!response.ok) return;
      const value = (await response.json()) as Partial<MaintenanceStatus>;
      if (value.locked === false) this.maintenance = { locked: false };
      else if (value.locked === true && typeof value.lockedAt === 'string') {
        this.maintenance = {
          locked: true,
          lockedAt: value.lockedAt,
          ...(typeof value.reason === 'string' ? { reason: value.reason } : {})
        };
      }
    } catch {
      // The server remains authoritative; retain the most recent known state.
    }
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
  async createProject(
    creation: ProjectCreation = defaultProjectCreation,
    devMode = false
  ): Promise<boolean> {
    if (this.pending || this.creating || this.maintenanceLocked) return false;
    this.creating = true;
    this.error = null;

    try {
      const response = await fetch('/api/projects', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(creation)
      });
      if (!response.ok) {
        if (response.status === 423) await this.refreshMaintenance();
        throw new Error(await responseError(response));
      }
      const { projectId, jobId } = (await response.json()) as {
        projectId: string;
        jobId?: string;
      };
      const path = resolve('/projects/[projectId]', { projectId });
      const parameters = [
        devMode ? 'dev=1' : null,
        jobId ? `job=${encodeURIComponent(jobId)}` : null
      ]
        .filter(Boolean)
        .join('&');
      // The route is resolved above; the optional query controls browser-only detail.
      // eslint-disable-next-line svelte/no-navigation-without-resolve
      await goto(parameters ? `${path}?${parameters}` : path);
      return true;
    } catch (cause) {
      this.error = cause instanceof Error ? cause.message : 'Project creation failed.';
      return false;
    } finally {
      this.creating = false;
    }
  }

  /** Submit a command and install the server's authoritative complete resource. */
  async runCommand(input: ProjectCommandInput): Promise<boolean> {
    if (this.pending || !this.#resource || !this.atHead || this.maintenanceLocked) return false;
    const operationId = crypto.randomUUID();
    const request = new AbortController();
    this.#commandRequest?.abort();
    this.#commandRequest = request;
    this.pending = { type: input.type, operationId, startedAfter: this.head };
    this.error = null;

    try {
      const response = await fetch(`/api/projects/${encodeURIComponent(this.projectId)}`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ ...input, operationId, expectedHead: this.head }),
        signal: request.signal
      });
      if (!response.ok) {
        if (response.status === 423) await this.refreshMaintenance();
        throw new Error(await responseError(response));
      }
      if (response.status === 202) {
        const accepted = (await response.json()) as { jobId: string };
        await this.waitForJob(accepted.jobId, request.signal);
        await this.reloadResource(request.signal);
      } else {
        this.#resource = parseProjectResource(await response.json());
      }
      return true;
    } catch (cause) {
      if (request.signal.aborted) return false;
      this.error = cause instanceof Error ? cause.message : 'The project operation failed.';
      await this.open();
      return false;
    } finally {
      if (this.#commandRequest === request) {
        this.#commandRequest = undefined;
        this.pending = null;
      }
    }
  }

  /** Resume the initial job carried by a newly created project URL. */
  async resumeJob(jobId: string): Promise<void> {
    if (this.pending || !this.#resource) return;
    const request = new AbortController();
    this.#commandRequest?.abort();
    this.#commandRequest = request;
    try {
      const job = await this.readJob(jobId, request.signal);
      if (job.projectId !== this.projectId) {
        throw new Error('The project job does not match this project.');
      }
      this.pending = {
        type: 'render',
        operationId: job.operationId,
        startedAfter: this.head
      };
      if (job.status !== 'succeeded') {
        if (job.status === 'failed' || job.status === 'cancelled') {
          throw new Error(job.error || 'Initial project compilation failed.');
        }
        await this.waitForJob(jobId, request.signal);
      }
      await this.reloadResource(request.signal);
    } catch (cause) {
      if (!request.signal.aborted) {
        this.error = cause instanceof Error ? cause.message : 'Initial project compilation failed.';
      }
    } finally {
      if (this.#commandRequest === request) {
        this.#commandRequest = undefined;
        this.pending = null;
      }
    }
  }

  private connect(): void {
    if (!this.#resource) return;
    this.connection = 'open';
    this.#eventTimer = setInterval(() => void this.pollEvents(), 1_000);
  }

  private startMaintenancePolling(): void {
    if (this.#maintenanceTimer) return;
    this.#maintenanceTimer = setInterval(() => void this.refreshMaintenance(), 2_000);
  }

  private disconnect(): void {
    if (this.#eventTimer) clearInterval(this.#eventTimer);
    this.#eventTimer = undefined;
  }

  private async pollEvents(): Promise<void> {
    if (!this.#resource) return;
    try {
      const response = await fetch(
        `/api/projects/${encodeURIComponent(this.projectId)}/events?after=${this.head}`,
        { cache: 'no-store' }
      );
      if (!response.ok) throw new Error(await responseError(response));
      const value = (await response.json()) as { events?: unknown[] };
      for (const event of value.events ?? []) this.ingest(normalizeProjectEventV1(event));
      this.connection = 'open';
    } catch {
      this.connection = 'reconnecting';
    }
  }

  private async waitForJob(jobId: string, signal: AbortSignal): Promise<void> {
    for (;;) {
      const job = await this.readJob(jobId, signal);
      if (job.status === 'succeeded') return;
      if (job.status === 'failed' || job.status === 'cancelled') {
        throw new Error(job.error || 'The project operation failed.');
      }
      await delay(1_000, signal);
    }
  }

  private async readJob(jobId: string, signal: AbortSignal): Promise<ProjectJobState> {
    const response = await fetch(`/api/jobs/${encodeURIComponent(jobId)}`, {
      cache: 'no-store',
      signal
    });
    if (!response.ok) throw new Error(await responseError(response));
    return (await response.json()) as ProjectJobState;
  }

  private async reloadResource(signal: AbortSignal): Promise<void> {
    const response = await fetch(`/api/projects/${encodeURIComponent(this.projectId)}`, {
      cache: 'no-store',
      signal
    });
    if (!response.ok) throw new Error(await responseError(response));
    this.#resource = parseProjectResource(await response.json());
  }

  private ingest(event: ProjectEvent): void {
    if (!this.#resource) return;
    const existing = this.#resource.document.events[event.id - 1];
    if (existing) {
      if (existing.operationId !== event.operationId || existing.type !== event.type) {
        void this.recover();
      }
      return;
    }
    if (event.id !== this.head + 1) return void this.recover();

    const document = {
      ...this.#resource.document,
      events: [...this.#resource.document.events, event]
    };
    const summary = summarizeProject(document);
    this.#resource = {
      document,
      projects: this.#resource.projects
        .map((project) => (project.projectId === this.projectId ? summary : project))
        .toSorted((left, right) => right.updatedAt.localeCompare(left.updatedAt))
    };
  }

  private async recover(): Promise<void> {
    this.connection = 'reconnecting';
    await this.open();
  }
}

function parseProjectResource(value: unknown): ProjectResource {
  return normalizeProjectResourceV1(value);
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

type ProjectJobState = {
  projectId: string;
  operationId: string;
  status: string;
  error?: string | null;
};

function delay(milliseconds: number, signal: AbortSignal): Promise<void> {
  return new Promise((resolveDelay, reject) => {
    if (signal.aborted) {
      reject(signal.reason);
      return;
    }
    const onAbort = () => {
      clearTimeout(timeout);
      reject(signal.reason);
    };
    const timeout = setTimeout(() => {
      signal.removeEventListener('abort', onAbort);
      resolveDelay();
    }, milliseconds);
    signal.addEventListener('abort', onAbort, { once: true });
  });
}
