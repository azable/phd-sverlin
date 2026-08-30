/** In-process asynchronous execution backed by durable Timeline lifecycle events. */

import { randomUUID } from 'node:crypto';

import type {
  NewProjectEvent,
  ProjectEvent,
  ProjectOperationKind
} from '$lib/shared/projects/events';
import type { ProjectCommand, ProjectCommandResult } from '$lib/shared/projects/model';
import {
  activeProjectOperation,
  pendingAssistantTurnRequests,
  projectOperation
} from '$lib/shared/projects/operations';
import { projectSnapshotAt } from '$lib/shared/projects/projection';
import { sqlClient } from '$lib/server/db';

import {
  queueProjectFeedback,
  queueProjectPreference,
  runQueuedSverlinAssistantTurn,
  submitProjectFeedback
} from './commands';
import { saveHtmlProjectArtifact } from './presentations';
import { runProjectCommand } from './command-lock';
import { projectOperationDeadlineError, runWithProjectOperationSignal } from './operation-context';
import { recoveryEventsForInterruptedOperations } from './recovery';
import { ProjectConflictError, projectRepository, type ProjectRepository } from './repository';
import {
  renameProject,
  advanceProjectPresentations,
  replenishProjectPresentations,
  renderInitialProject,
  renderProject,
  restoreProjectArtifacts,
  updateProjectArtifact
} from './service';

export type InitialRenderCommand = { type: 'initial-render'; seed: number };
export type PresentationRefillCommand = { type: 'presentation-refill'; target: number };
export type AssistantTurnCommand = { type: 'assistant-turn'; requestEventIds: number[] };
export type ProjectOperationCommand =
  | ProjectCommand
  | InitialRenderCommand
  | PresentationRefillCommand
  | AssistantTurnCommand;

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
  deadlineAt?: number;
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
  readonly #assistantProjects = new Set<string>();
  #assistantDrain?: Promise<void>;

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
    deadlineAt?: string;
  }): Promise<AcceptedProjectOperation> {
    if (!this.#accepting) {
      throw new ProjectOperationCapacityError();
    }
    const deadlineAt = parseDeadline(options.deadlineAt);
    const kind = commandKind(options.command);
    const initial = await this.repository.load(options.projectId);
    if (
      (options.command.type === 'feedback' && projectSnapshotAt(initial).renderer === 'sverlin') ||
      options.command.type === 'prefer'
    ) {
      return this.acceptInteraction({
        ...options,
        kind: options.command.type,
        command: options.command,
        deadlineAt
      });
    }
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
      lease = await this.lock.acquire(options.operationId);
      if (!lease) throw new Error('This operation is already running.');
      const acceptedEvent = lifecycleEvent(
        'operation.accepted',
        options.operationId,
        kind,
        options.actor ?? (kind === 'presentation-refill' ? 'system' : 'user')
      );
      const accepted = await this.appendAccepted(
        options.projectId,
        expectedHead,
        acceptedEvent,
        kind === 'assistant-turn'
      );
      const acceptedEventId = accepted.events[0].id;
      const promise = this.runAccepted(
        {
          projectId: options.projectId,
          operationId: options.operationId,
          command: options.command,
          expectedHead: acceptedEventId,
          ...(deadlineAt === undefined ? {} : { deadlineAt })
        },
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
        const projectId = this.#active.get(options.operationId)?.projectId;
        this.#active.delete(options.operationId);
        if (projectId) this.queueAssistantProject(projectId);
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
      this.queueAssistantProject(summary.projectId);
    }
    await this.discoverQueuedAssistantTurns();
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
    this.#assistantProjects.clear();
    if (this.#recoveryTimer) clearInterval(this.#recoveryTimer);
    this.#recoveryTimer = undefined;
    for (const { controller } of this.#active.values()) controller.abort();
    const draining = Promise.allSettled([...this.#active.values()].map(({ promise }) => promise));
    await Promise.race([draining, delay(timeoutMs)]);
  }

  status(): { accepting: boolean; active: number; capacity: number } {
    return { accepting: this.#accepting, active: this.#active.size, capacity: this.capacity };
  }

  private async acceptInteraction(options: {
    projectId: string;
    operationId: string;
    expectedHead: number;
    command: Extract<ProjectOperationCommand, { type: 'feedback' | 'prefer' }>;
    actor?: 'user' | 'system';
    deadlineAt?: number;
    kind: 'feedback' | 'prefer';
  }): Promise<AcceptedProjectOperation> {
    await this.preemptRefill(options.projectId, options.expectedHead).catch(async (cause) => {
      if (!(cause instanceof Error) || cause.name !== 'ProjectConflictError') throw cause;
      const latest = await this.repository.load(options.projectId);
      if (options.expectedHead > latest.events.length) throw cause;
      return latest.events.length;
    });
    const lease = await this.lock.acquire(options.operationId);
    if (!lease) throw new Error('This operation is already running.');
    try {
      const accepted = await runProjectCommand(options.projectId, async () => {
        const document = await this.repository.load(options.projectId);
        const active = activeProjectOperation(document);
        if (active && active.kind !== 'assistant-turn') {
          throw new Error('This project already has an active operation.');
        }
        if (options.expectedHead > document.events.length) {
          const conflict = new Error('The project changed before this operation was accepted.');
          conflict.name = 'ProjectConflictError';
          throw conflict;
        }
        return this.repository.append(options.projectId, document.events.length, [
          lifecycleEvent(
            'operation.accepted',
            options.operationId,
            options.kind,
            options.actor ?? 'user'
          )
        ]);
      });
      const acceptedEventId = accepted.events[0].id;
      const controller = new AbortController();
      const deadlineTimer =
        options.deadlineAt === undefined
          ? undefined
          : setTimeout(
              () => controller.abort(projectOperationDeadlineError()),
              Math.max(0, options.deadlineAt - Date.now())
            );
      deadlineTimer?.unref();
      try {
        await runWithProjectOperationSignal(
          controller.signal,
          () =>
            this.execute({
              projectId: options.projectId,
              operationId: options.operationId,
              expectedHead: acceptedEventId,
              command: options.command,
              signal: controller.signal,
              ...(options.deadlineAt === undefined ? {} : { deadlineAt: options.deadlineAt })
            }),
          options.deadlineAt
        );
        await this.appendCurrent(options.projectId, [
          lifecycleEvent('operation.completed', options.operationId, options.kind)
        ]);
      } catch (cause) {
        await this.closeFailedOperation(
          options.projectId,
          options.operationId,
          options.kind,
          controller.signal.aborted ? 'cancelled' : 'infrastructure',
          controller.signal.aborted ? cancellationMessage(controller.signal) : messageFor(cause)
        );
      } finally {
        if (deadlineTimer) clearTimeout(deadlineTimer);
      }
      this.queueAssistantProject(options.projectId);
      return { projectId: options.projectId, operationId: options.operationId, acceptedEventId };
    } finally {
      await lease.release();
    }
  }

  private queueAssistantProject(projectId: string): void {
    if (!this.#accepting) return;
    this.#assistantProjects.add(projectId);
    if (!this.#assistantDrain) {
      this.#assistantDrain = this.drainAssistantTurns().finally(() => {
        this.#assistantDrain = undefined;
        if (
          this.#accepting &&
          this.#assistantProjects.size > 0 &&
          this.#active.size < this.capacity
        ) {
          const next = this.#assistantProjects.values().next().value as string;
          queueMicrotask(() => this.queueAssistantProject(next));
        }
      });
    }
  }

  private async drainAssistantTurns(): Promise<void> {
    while (this.#accepting && this.#active.size < this.capacity) {
      const projectId = this.#assistantProjects.values().next().value as string | undefined;
      if (!projectId) return;
      this.#assistantProjects.delete(projectId);
      const document = await this.repository.load(projectId);
      if (activeProjectOperation(document)) continue;
      const requests = pendingAssistantTurnRequests(document);
      if (requests.length === 0) continue;
      const deadlineAt = requests
        .map((event) => event.payload.deadlineAt)
        .filter((value): value is string => value !== undefined)
        .toSorted()[0];
      try {
        await this.accept({
          projectId,
          operationId: randomUUID(),
          expectedHead: document.events.length,
          command: { type: 'assistant-turn', requestEventIds: requests.map(({ id }) => id) },
          actor: 'system',
          ...(deadlineAt ? { deadlineAt } : {})
        });
      } catch (cause) {
        if (cause instanceof ProjectOperationCapacityError) {
          this.#assistantProjects.add(projectId);
          return;
        }
        console.error(`Could not start queued assistant turn for ${projectId}.`, cause);
      }
    }
  }

  private async discoverQueuedAssistantTurns(): Promise<void> {
    for (const summary of await this.repository.list()) {
      if (pendingAssistantTurnRequests(await this.repository.load(summary.projectId)).length > 0) {
        this.queueAssistantProject(summary.projectId);
      }
    }
  }

  private appendCurrent(projectId: string, events: NewProjectEvent[]) {
    return runProjectCommand(projectId, async () => {
      const document = await this.repository.load(projectId);
      return this.repository.append(projectId, document.events.length, events);
    });
  }

  private appendAccepted(
    projectId: string,
    expectedHead: number,
    event: NewProjectEvent<'operation.accepted'>,
    mayRebase: boolean
  ) {
    return runProjectCommand(projectId, async () => {
      const document = await this.repository.load(projectId);
      if (activeProjectOperation(document)) {
        throw new Error('This project already has an active operation.');
      }
      if (!mayRebase && document.events.length !== expectedHead) {
        throw new ProjectConflictError();
      }
      return this.repository.append(projectId, document.events.length, [event]);
    });
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
      deadlineAt?: number;
    },
    controller: AbortController,
    lease: OperationLease
  ): Promise<void> {
    const kind = commandKind(options.command);
    const deadlineAt = options.deadlineAt;
    const deadlineTimer =
      deadlineAt !== undefined
        ? setTimeout(
            () => controller.abort(projectOperationDeadlineError()),
            Math.max(0, deadlineAt - Date.now())
          )
        : undefined;
    deadlineTimer?.unref();
    try {
      const result = await runWithProjectOperationSignal(
        controller.signal,
        () => this.execute({ ...options, signal: controller.signal }),
        deadlineAt
      );
      const terminalFailure = terminalFailureFor(kind, result.appendedEvents);
      await this.appendCurrent(options.projectId, [
        terminalFailure
          ? lifecycleFailure(
              options.operationId,
              kind,
              terminalFailure.failureKind,
              terminalFailure.message
            )
          : lifecycleEvent('operation.completed', options.operationId, kind)
      ]);
    } catch (cause) {
      const cancelled =
        controller.signal.aborted ||
        (cause instanceof Error && cause.name === 'StudyPhaseDeadlineError');
      await this.closeFailedOperation(
        options.projectId,
        options.operationId,
        kind,
        cancelled ? 'cancelled' : 'infrastructure',
        controller.signal.aborted ? cancellationMessage(controller.signal) : messageFor(cause)
      );
    } finally {
      if (deadlineTimer) clearTimeout(deadlineTimer);
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
      await runProjectCommand(projectId, async () => {
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
      });
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
    const document = await projectRepository.load(summary.projectId);
    if (activeProjectOperation(document) || pendingAssistantTurnRequests(document).length > 0) {
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
  deadlineAt?: number;
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
      return projectSnapshotAt(await projectRepository.load(options.projectId)).renderer ===
        'sverlin'
        ? queueProjectFeedback({
            ...common,
            content: options.command.content,
            focus: options.command.focus,
            presentationCount: options.command.presentationCount,
            ...(options.deadlineAt === undefined
              ? {}
              : { deadlineAt: new Date(options.deadlineAt).toISOString() })
          })
        : submitProjectFeedback({
            ...common,
            content: options.command.content,
            focus: options.command.focus,
            presentationCount: options.command.presentationCount
          });
    case 'advance-presentations':
      return advanceProjectPresentations({
        ...common,
        presentations: options.command.presentations
      });
    case 'render':
      return renderProject({ ...common, seed: options.command.seed });
    case 'presentation-refill':
      return replenishProjectPresentations({ ...common, target: options.command.target });
    case 'prefer':
      return queueProjectPreference({
        ...common,
        presentations: options.command.presentations,
        preferred: options.command.preferred,
        step: options.command.step,
        visualSelections: options.command.visualSelections,
        ...(options.deadlineAt === undefined
          ? {}
          : { deadlineAt: new Date(options.deadlineAt).toISOString() })
      });
    case 'assistant-turn': {
      const command = options.command;
      await runProjectCommand(options.projectId, async () => {
        const document = await projectRepository.load(options.projectId);
        const requests = command.requestEventIds.map((id) => document.events[id - 1]);
        if (requests.some((event) => event?.type !== 'assistant.turn-requested')) {
          throw new Error('The assistant operation references an unknown queued request.');
        }
        const interactionEventIds = requests.map((event) =>
          event?.type === 'assistant.turn-requested' ? event.payload.interactionEventId : 0
        );
        await projectRepository.append(options.projectId, document.events.length, [
          {
            type: 'assistant.turn-started',
            actor: { kind: 'system' },
            operationId: options.operationId,
            createdAt: new Date().toISOString(),
            payload: { requestEventIds: command.requestEventIds, interactionEventIds }
          }
        ]);
      });
      return runQueuedSverlinAssistantTurn(common);
    }
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

function terminalFailureFor(
  kind: ProjectOperationKind,
  events: readonly ProjectEvent[]
): { failureKind: 'domain' | 'infrastructure' | 'cancelled'; message: string } | undefined {
  if (kind === 'rename' || kind === 'save-html' || kind === 'advance-presentations')
    return undefined;
  const outcome = events.findLast((event) => {
    if (kind === 'feedback' || kind === 'prefer' || kind === 'assistant-turn') {
      return (
        event.type === 'assistant.responded' ||
        event.type === 'visualization.presented' ||
        event.type === 'ai.generation-failed' ||
        event.type === 'compilation.failed' ||
        (event.type === 'system.notified' && event.payload.severity === 'error')
      );
    }
    return event.type === 'visualization.presented' || event.type === 'compilation.failed';
  });
  if (!outcome) return undefined;
  const noticeMessage =
    outcome.type === 'system.notified' && outcome.payload.severity === 'error'
      ? outcome.payload.message
      : undefined;
  const failure =
    outcome.type === 'system.notified'
      ? (events.findLast(
          (event) => event.type === 'ai.generation-failed' || event.type === 'compilation.failed'
        ) ?? outcome)
      : outcome;
  if (failure.type === 'ai.generation-failed') {
    return {
      failureKind: failure.payload.failureKind === 'cancelled' ? 'cancelled' : 'infrastructure',
      message: noticeMessage ?? failure.payload.message
    };
  }
  if (failure.type === 'compilation.failed') {
    return {
      failureKind:
        failure.payload.failureKind === 'source'
          ? 'domain'
          : failure.payload.failureKind === 'cancelled'
            ? 'cancelled'
            : 'infrastructure',
      message:
        noticeMessage ??
        failure.payload.diagnostics[0]?.message ??
        failure.payload.error ??
        'Compilation failed.'
    };
  }
  if (failure.type === 'system.notified' && failure.payload.severity === 'error') {
    return { failureKind: 'domain', message: failure.payload.message };
  }
  return undefined;
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

function parseDeadline(value?: string): number | undefined {
  if (!value) return undefined;
  const deadline = Date.parse(value);
  if (!Number.isFinite(deadline)) throw new Error('The project operation deadline is invalid.');
  return deadline;
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds).unref());
}
