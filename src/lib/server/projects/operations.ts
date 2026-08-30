/** In-process asynchronous execution backed by durable Timeline lifecycle events. */

import type {
  NewProjectEvent,
  ProjectEvent,
  ProjectOperationKind
} from '$lib/shared/projects/events';
import type { ProjectCommand, ProjectCommandResult } from '$lib/shared/projects/model';
import { activeProjectOperation, projectOperation } from '$lib/shared/projects/operations';
import { sqlClient } from '$lib/server/db';

import { submitProjectFeedback } from './commands';
import { recordProjectPreference, saveHtmlProjectArtifact } from './presentations';
import { runWithProjectOperationSignal } from './operation-context';
import { recoveryEventsForInterruptedOperations } from './recovery';
import { projectRepository, type ProjectRepository } from './repository';
import {
  renameProject,
  replenishProjectPresentations,
  renderInitialProject,
  renderProject,
  restoreProjectArtifacts,
  updateProjectArtifact
} from './service';

export type InitialRenderCommand = { type: 'initial-render'; seed: number };
export type PresentationRefillCommand = { type: 'presentation-refill'; target: number };
export type ProjectOperationCommand =
  | ProjectCommand
  | InitialRenderCommand
  | PresentationRefillCommand;

export type AcceptedProjectOperation = {
  projectId: string;
  operationId: string;
  acceptedEventId: number;
};

type OperationLease = { release(): Promise<void> };
type OperationLock = { acquire(operationId: string): Promise<OperationLease | null> };
type ExecuteCommand = (options: {
  projectId: string;
  expectedHead: number;
  operationId: string;
  command: ProjectOperationCommand;
  signal: AbortSignal;
}) => Promise<ProjectCommandResult>;

/** Raised when this small deployment has reached its explicit work capacity. */
export class ProjectOperationCapacityError extends Error {
  constructor() {
    super(
      'The server is already processing the maximum number of project operations. Try again shortly.'
    );
    this.name = 'ProjectOperationCapacityError';
  }
}

/** Coordinates accepted Timeline operations with bounded process-owned execution. */
export class ProjectOperationExecutor {
  readonly #active = new Map<
    string,
    {
      projectId: string;
      kind: ProjectOperationKind;
      promise: Promise<void>;
      controller: AbortController;
    }
  >();
  #accepting = true;
  #recoveryTimer?: ReturnType<typeof setInterval>;

  constructor(
    private readonly repository: ProjectRepository = projectRepository,
    private readonly lock: OperationLock = postgresOperationLock,
    private readonly execute: ExecuteCommand = executeProjectCommand,
    private readonly capacity = 2
  ) {}

  /** Persist acceptance before returning, then execute without holding the HTTP request open. */
  async accept(options: {
    projectId: string;
    operationId: string;
    expectedHead: number;
    command: ProjectOperationCommand;
    actor?: 'user' | 'system';
  }): Promise<AcceptedProjectOperation> {
    if (!this.#accepting) {
      throw new ProjectOperationCapacityError();
    }
    const kind = commandKind(options.command);
    const expectedHead =
      kind === 'presentation-refill'
        ? options.expectedHead
        : await this.preemptRefill(options.projectId, options.expectedHead);
    if (kind !== 'presentation-refill' && this.#active.size >= this.capacity) {
      await this.preemptAnyRefill();
    }
    if (this.#active.size >= this.capacity) throw new ProjectOperationCapacityError();
    const reserved = new AbortController();
    let releaseReservation!: () => void;
    const reservation = new Promise<void>((resolve) => {
      releaseReservation = resolve;
    });
    this.#active.set(options.operationId, {
      projectId: options.projectId,
      kind,
      promise: reservation,
      controller: reserved
    });
    let lease: OperationLease | null = null;
    try {
      const document = await this.repository.load(options.projectId);
      if (activeProjectOperation(document)) {
        throw new Error('This project already has an active operation.');
      }
      lease = await this.lock.acquire(options.operationId);
      if (!lease) throw new Error('This operation is already running.');
      const accepted = await this.repository.append(options.projectId, expectedHead, [
        lifecycleEvent(
          'operation.accepted',
          options.operationId,
          kind,
          options.actor ?? (kind === 'presentation-refill' ? 'system' : 'user')
        )
      ]);
      const acceptedEventId = accepted.events[0].id;
      const promise = this.runAccepted(
        { ...options, expectedHead: acceptedEventId },
        reserved,
        lease
      );
      this.#active.set(options.operationId, {
        projectId: options.projectId,
        kind,
        promise,
        controller: reserved
      });
      void promise.finally(() => {
        releaseReservation();
        this.#active.delete(options.operationId);
      });
      return { projectId: options.projectId, operationId: options.operationId, acceptedEventId };
    } catch (cause) {
      releaseReservation();
      this.#active.delete(options.operationId);
      if (lease) await lease.release();
      throw cause;
    }
  }

  /** Mark operations abandoned by replaced processes as explicitly cancelled. */
  async recoverInterrupted(): Promise<number> {
    let recovered = 0;
    for (const summary of await this.repository.list()) {
      const document = await this.repository.load(summary.projectId);
      const active = activeProjectOperation(document);
      if (!active || this.#active.has(active.operationId)) continue;
      const lease = await this.lock.acquire(active.operationId);
      if (!lease) continue;
      try {
        const latest = await this.repository.load(summary.projectId);
        const current = projectOperation(latest, active.operationId);
        if (!current || current.status === 'completed' || current.status === 'failed') continue;
        const related = latest.events.filter(
          (event) => event.operationId === active.operationId && event.id > active.acceptedEventId
        );
        await this.repository.append(summary.projectId, latest.events.length, [
          ...recoveryEventsForInterruptedOperations(related),
          lifecycleFailure(
            active.operationId,
            active.kind,
            'cancelled',
            'The project operation was interrupted by a server restart. Retry the operation.'
          )
        ]);
        recovered += 1;
      } finally {
        await lease.release();
      }
    }
    return recovered;
  }

  /** Periodically catch overlap where a replacement starts before the old process exits. */
  startRecovery(intervalMs = 30_000): void {
    if (this.#recoveryTimer) return;
    this.#recoveryTimer = setInterval(() => {
      void this.recoverInterrupted().catch((cause) =>
        console.error('Interrupted project operation recovery failed.', cause)
      );
    }, intervalMs);
    this.#recoveryTimer.unref();
  }

  /** Stop admission, cancel active work, and wait up to the configured drain deadline. */
  async shutdown(timeoutMs: number): Promise<void> {
    this.#accepting = false;
    if (this.#recoveryTimer) clearInterval(this.#recoveryTimer);
    this.#recoveryTimer = undefined;
    for (const { controller } of this.#active.values()) controller.abort();
    const draining = Promise.allSettled([...this.#active.values()].map(({ promise }) => promise));
    await Promise.race([draining, delay(timeoutMs)]);
  }

  status(): { accepting: boolean; active: number; capacity: number } {
    return { accepting: this.#accepting, active: this.#active.size, capacity: this.capacity };
  }

  private async preemptRefill(projectId: string, expectedHead: number): Promise<number> {
    const refill = [...this.#active.entries()].find(
      ([, active]) => active.projectId === projectId && active.kind === 'presentation-refill'
    );
    if (!refill) return expectedHead;
    const [operationId, active] = refill;
    await this.cancelRefill(operationId, active);
    const document = await this.repository.load(projectId);
    if (expectedHead > document.events.length) {
      const conflict = new Error('The project changed before this operation was accepted.');
      conflict.name = 'ProjectConflictError';
      throw conflict;
    }
    const intervening = document.events.slice(expectedHead);
    if (intervening.some((event) => event.operationId !== operationId)) {
      const conflict = new Error('The project changed before this operation was accepted.');
      conflict.name = 'ProjectConflictError';
      throw conflict;
    }
    return document.events.length;
  }

  private async preemptAnyRefill(): Promise<void> {
    const refill = [...this.#active.entries()].find(
      ([, active]) => active.kind === 'presentation-refill'
    );
    if (refill) await this.cancelRefill(...refill);
  }

  private async cancelRefill(
    operationId: string,
    active: {
      promise: Promise<void>;
      controller: AbortController;
    }
  ): Promise<void> {
    active.controller.abort(new Error('Superseded by participant activity.'));
    await active.promise;
    this.#active.delete(operationId);
  }

  private async runAccepted(
    options: {
      projectId: string;
      operationId: string;
      expectedHead: number;
      command: ProjectOperationCommand;
    },
    controller: AbortController,
    lease: OperationLease
  ): Promise<void> {
    const kind = commandKind(options.command);
    try {
      const result = await runWithProjectOperationSignal(controller.signal, () =>
        this.execute({ ...options, signal: controller.signal })
      );
      const domainFailure = domainFailureFor(kind, result.appendedEvents);
      const document = await this.repository.load(options.projectId);
      await this.repository.append(options.projectId, document.events.length, [
        domainFailure
          ? lifecycleFailure(
              options.operationId,
              kind,
              'domain',
              domainFailureMessage(domainFailure)
            )
          : lifecycleEvent('operation.completed', options.operationId, kind)
      ]);
    } catch (cause) {
      await this.closeFailedOperation(
        options.projectId,
        options.operationId,
        kind,
        controller.signal.aborted ? 'cancelled' : 'infrastructure',
        controller.signal.aborted ? cancellationMessage(controller.signal) : messageFor(cause)
      );
    } finally {
      await lease.release();
    }
  }

  private async closeFailedOperation(
    projectId: string,
    operationId: string,
    kind: ProjectOperationKind,
    failureKind: 'infrastructure' | 'cancelled',
    message: string
  ): Promise<void> {
    try {
      const document = await this.repository.load(projectId);
      const operation = projectOperation(document, operationId);
      if (!operation || operation.status === 'completed' || operation.status === 'failed') return;
      const related = document.events.filter(
        (event) => event.operationId === operationId && event.id > operation.acceptedEventId
      );
      await this.repository.append(projectId, document.events.length, [
        ...recoveryEventsForInterruptedOperations(related),
        lifecycleFailure(operationId, kind, failureKind, message)
      ]);
    } catch (cause) {
      console.error(`Could not close failed project operation ${operationId}.`, cause);
    }
  }
}

const postgresOperationLock: OperationLock = {
  async acquire(operationId) {
    const connection = await sqlClient().reserve();
    let row: { acquired: boolean } | undefined;
    try {
      [row] = await connection<{ acquired: boolean }[]>`
        select pg_try_advisory_lock(hashtextextended(${operationId}, 0)) as acquired
      `;
    } catch (cause) {
      connection.release();
      throw cause;
    }
    if (!row?.acquired) {
      connection.release();
      return null;
    }
    return {
      async release() {
        await connection`
          select pg_advisory_unlock(hashtextextended(${operationId}, 0))
        `.catch(() => undefined);
        connection.release();
      }
    };
  }
};

const executorKey = Symbol.for('sverlin.project-operation-executor');
const executorGlobal = globalThis as typeof globalThis & {
  [executorKey]?: ProjectOperationExecutor;
};
export const projectOperationExecutor = (executorGlobal[executorKey] ??=
  new ProjectOperationExecutor());

/** Refuse export or deletion while a selected project's Timeline is still changing. */
export async function assertNoActiveProjectOperations(ownerUserId?: string): Promise<void> {
  for (const summary of await projectRepository.list(ownerUserId)) {
    if (activeProjectOperation(await projectRepository.load(summary.projectId))) {
      throw new Error(
        'A project operation is currently running. Wait for it to finish and try again.'
      );
    }
  }
}

/** Require every active project Timeline to have a terminal operation boundary. */
export function assertProjectOperationsIdle(): Promise<void> {
  return assertNoActiveProjectOperations();
}

async function executeProjectCommand(options: {
  projectId: string;
  expectedHead: number;
  operationId: string;
  command: ProjectOperationCommand;
  signal: AbortSignal;
}): Promise<ProjectCommandResult> {
  if (options.signal.aborted) throw options.signal.reason;
  const common = {
    projectId: options.projectId,
    expectedHead: options.expectedHead,
    operationId: options.operationId
  };
  switch (options.command.type) {
    case 'initial-render':
      return renderInitialProject({ ...common, seed: options.command.seed });
    case 'rename':
      return renameProject({ ...common, title: options.command.title });
    case 'feedback':
      return submitProjectFeedback({
        ...common,
        text: options.command.text,
        focus: options.command.focus,
        selection: options.command.selection,
        presentations: options.command.presentations,
        presentationCount: options.command.presentationCount
      });
    case 'render':
      return renderProject({ ...common, seed: options.command.seed });
    case 'presentation-refill':
      return replenishProjectPresentations({ ...common, target: options.command.target });
    case 'prefer':
      return recordProjectPreference({
        ...common,
        presentations: options.command.presentations,
        preferred: options.command.preferred,
        step: options.command.step
      });
    case 'save':
      return updateProjectArtifact({
        ...common,
        artifactId: options.command.artifactId,
        source: options.command.source,
        presentationCount: options.command.presentationCount
      });
    case 'save-html':
      return saveHtmlProjectArtifact({
        ...common,
        artifactId: options.command.artifactId,
        manifest: options.command.manifest
      });
    case 'restore':
      return restoreProjectArtifacts({
        ...common,
        from: options.command.from,
        seed: options.command.seed
      });
  }
}

function commandKind(command: ProjectOperationCommand): ProjectOperationKind {
  return command.type;
}

function lifecycleEvent<Type extends 'operation.accepted' | 'operation.completed'>(
  type: Type,
  operationId: string,
  kind: ProjectOperationKind,
  acceptedActor: 'user' | 'system' = 'user'
): NewProjectEvent<Type> {
  return {
    type,
    actor: type === 'operation.accepted' ? { kind: acceptedActor } : { kind: 'system' },
    operationId,
    createdAt: new Date().toISOString(),
    payload: { kind }
  } as NewProjectEvent<Type>;
}

function lifecycleFailure(
  operationId: string,
  kind: ProjectOperationKind,
  failureKind: 'domain' | 'infrastructure' | 'cancelled',
  message: string
): NewProjectEvent<'operation.failed'> {
  return {
    type: 'operation.failed',
    actor: { kind: 'system' },
    operationId,
    createdAt: new Date().toISOString(),
    payload: { kind, failureKind, message: message.slice(0, 4_000) || 'Project operation failed.' }
  };
}

function domainFailureFor(
  kind: ProjectOperationKind,
  events: readonly ProjectEvent[]
): ProjectEvent | undefined {
  if (kind === 'rename' || kind === 'prefer' || kind === 'save-html') return undefined;
  const outcome = events.findLast((event) => {
    if (kind === 'feedback') {
      return (
        event.type === 'assistant.responded' ||
        event.type === 'visualization.rendered' ||
        event.type === 'visualization.presented' ||
        event.type === 'ai.generation-failed' ||
        event.type === 'compilation.failed' ||
        (event.type === 'system.notified' && event.payload.severity === 'error')
      );
    }
    return (
      event.type === 'visualization.rendered' ||
      event.type === 'visualization.presented' ||
      event.type === 'compilation.failed'
    );
  });
  return outcome &&
    (outcome.type === 'ai.generation-failed' ||
      outcome.type === 'compilation.failed' ||
      (outcome.type === 'system.notified' && outcome.payload.severity === 'error'))
    ? outcome
    : undefined;
}

function domainFailureMessage(event: ProjectEvent): string {
  if (event.type === 'compilation.failed') {
    return event.payload.diagnostics[0]?.message ?? event.payload.error ?? 'Compilation failed.';
  }
  if (event.type === 'ai.generation-failed') return event.payload.message;
  if (event.type === 'system.notified') return event.payload.message;
  return 'Project operation failed.';
}

function messageFor(cause: unknown): string {
  return (cause instanceof Error ? cause.message : String(cause)).slice(0, 4_000);
}

function cancellationMessage(signal: AbortSignal): string {
  const reason = signal.reason;
  return reason instanceof Error && reason.name !== 'AbortError'
    ? reason.message
    : 'The project operation was cancelled while the server was shutting down. Retry the operation.';
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds).unref());
}
