/** Durable project-command transport backed by pg-boss and PostgreSQL. */

import { and, asc, eq, gt } from 'drizzle-orm';
import { PgBoss, type Job, type JobWithMetadata } from 'pg-boss';

import type { NewProjectEvent, ProjectEvent } from '$lib/shared/projects/events';
import {
  parseProjectCommand,
  type ProjectCommand,
  type ProjectCommandResult
} from '$lib/shared/projects/model';
import { database } from '$lib/server/db';
import { projectEvents } from '$lib/server/db/schema';

import { submitProjectFeedback } from './commands';
import { projectRepository } from './repository';
import { recoveryEventsForInterruptedOperations } from './recovery';
import {
  renameProject,
  renderInitialProject,
  renderProject,
  restoreProjectArtifacts,
  updateProjectArtifact
} from './service';

const queueName = 'project-command';
const producerBossKey = Symbol.for('sverlin.pg-boss.producer');
const workerBossKey = Symbol.for('sverlin.pg-boss.worker');

export type InitialRenderCommand = { type: 'initial-render'; seed: number };
export type QueuedProjectCommand = ProjectCommand | InitialRenderCommand;

type ProjectJobData = {
  projectId: string;
  ownerUserId: string;
  operationId: string;
  expectedHead: number;
  command: QueuedProjectCommand;
};

type ProjectJobOutput = { status: 'succeeded' } | { status: 'failed'; error: string };

type SharedBosses = typeof globalThis & {
  [producerBossKey]?: Promise<PgBoss>;
  [workerBossKey]?: Promise<PgBoss>;
};

export type ProjectJobView = {
  id: string;
  projectId: string;
  operationId: string;
  status: 'queued' | 'running' | 'succeeded' | 'failed' | 'cancelled';
  error: string | null;
  createdAt: Date;
  startedAt: Date | null;
  finishedAt: Date | null;
};

/** Enqueue one idempotent command, using its operation UUID as the durable job ID. */
export async function createProjectJob(
  data: ProjectJobData
): Promise<{ id: string; status: string }> {
  const boss = await projectJobBoss(false);
  const id = await boss.send(queueName, data, {
    id: data.operationId,
    group: { id: data.ownerUserId }
  });
  if (id) return { id, status: 'queued' };

  const existing = await findProjectJob(boss, data.operationId);
  if (!existing) throw new Error('The project job could not be created.');
  return { id: existing.id, status: projectJobStatus(existing) };
}

/** Register the project command handler. Run this only in the Railway worker service. */
export async function startProjectJobWorker(): Promise<PgBoss> {
  const boss = await projectJobBoss(true);
  await boss.work<ProjectJobData, ProjectJobOutput>(
    queueName,
    {
      localConcurrency: 1,
      groupConcurrency: 1,
      pollingIntervalSeconds: 2,
      notifyPollingIntervalSeconds: 30,
      heartbeatRefreshSeconds: Math.max(5, Math.floor(jobHeartbeatSeconds() / 2))
    },
    async (jobs) => executeProjectJob(jobs[0])
  );
  return boss;
}

/** Read a job only when visible to its owner (or to the administrator). */
export async function readProjectJob(
  jobId: string,
  ownerUserId?: string
): Promise<ProjectJobView | null> {
  const job = await findProjectJob(await projectJobBoss(false), jobId);
  if (!job || (ownerUserId && job.data.ownerUserId !== ownerUserId)) return null;
  const output = projectJobOutput(job.output);
  return {
    id: job.id,
    projectId: job.data.projectId,
    operationId: job.data.operationId,
    status: projectJobStatus(job),
    error: output?.status === 'failed' ? output.error : transportError(job),
    createdAt: job.createdOn,
    startedAt: job.startedOn ?? null,
    finishedAt: job.completedOn
  };
}

/** Identify only command-specific terminal events, not merely any committed append. */
export function projectOperationHasCompleted(
  command: QueuedProjectCommand,
  events: readonly ProjectEvent[]
): boolean {
  const eventTypes = new Set(events.map(({ type }) => type));
  switch (command.type) {
    case 'rename':
      return eventTypes.has('project.renamed');
    case 'initial-render':
    case 'render':
    case 'save':
    case 'restore':
      return eventTypes.has('compilation.failed') || eventTypes.has('visualization.rendered');
    case 'feedback':
      return eventTypes.has('assistant.responded') || eventTypes.has('system.notified');
  }
}

export function projectJobExpirationSeconds(): number {
  return positiveInteger(process.env.SVERLIN_JOB_EXPIRE_SECONDS, 1_800, 60);
}

async function executeProjectJob(job: Job<ProjectJobData>): Promise<ProjectJobOutput> {
  const { projectId, expectedHead, operationId, command } = job.data;
  try {
    await executeProjectCommand(projectId, expectedHead, operationId, command);
    return { status: 'succeeded' };
  } catch (cause) {
    // A retry may observe a command that committed before its worker stopped.
    // Partial lifecycle appends are closed explicitly in the Timeline.
    const committed = await database()
      .select({ event: projectEvents.event })
      .from(projectEvents)
      .where(
        and(
          eq(projectEvents.projectId, projectId),
          eq(projectEvents.operationId, operationId),
          gt(projectEvents.eventId, expectedHead)
        )
      )
      .orderBy(asc(projectEvents.eventId));
    const events = committed.map(({ event }) => event);
    if (projectOperationWasInterrupted(events)) {
      return {
        status: 'failed',
        error: 'The project operation was interrupted before it completed.'
      };
    }
    if (projectOperationHasCompleted(command, events)) return { status: 'succeeded' };

    await recordInterruptedProjectOperation(projectId, operationId, events);
    return { status: 'failed', error: messageFor(cause) };
  }
}

/** Detect the explicit cancellation markers written by interrupted-operation recovery. */
export function projectOperationWasInterrupted(events: readonly ProjectEvent[]): boolean {
  return events.some(
    (event) =>
      (event.type === 'compilation.failed' && event.payload.failureKind === 'cancelled') ||
      (event.type === 'ai.generation-failed' && event.payload.failureKind === 'cancelled') ||
      (event.type === 'system.notified' &&
        event.payload.message === 'The project operation was interrupted before it completed.')
  );
}

async function recordInterruptedProjectOperation(
  projectId: string,
  operationId: string,
  events: ProjectEvent[]
): Promise<void> {
  if (events.length === 0) return;
  const document = await projectRepository.load(projectId);
  const message = 'The project operation was interrupted before it completed.';
  const notice: NewProjectEvent<'system.notified'> = {
    type: 'system.notified',
    actor: { kind: 'system' },
    operationId,
    createdAt: new Date().toISOString(),
    payload: { severity: 'error', message }
  };
  await projectRepository.append(projectId, document.events.at(-1)?.id ?? 0, [
    ...recoveryEventsForInterruptedOperations(events),
    notice
  ]);
}

async function executeProjectCommand(
  projectId: string,
  expectedHead: number,
  operationId: string,
  rawCommand: unknown
): Promise<ProjectCommandResult> {
  if (isInitialRender(rawCommand)) {
    return renderInitialProject({ projectId, expectedHead, operationId, seed: rawCommand.seed });
  }
  const command = parseProjectCommand(rawCommand);
  const common = { projectId, expectedHead, operationId };
  switch (command.type) {
    case 'rename':
      return renameProject({ ...common, title: command.title });
    case 'feedback':
      return submitProjectFeedback({
        ...common,
        text: command.text,
        focus: command.focus,
        selection: command.selection,
        seed: command.seed
      });
    case 'render':
      return renderProject({ ...common, seed: command.seed });
    case 'save':
      return updateProjectArtifact({
        ...common,
        artifactId: command.artifactId,
        source: command.source,
        seed: command.seed
      });
    case 'restore':
      return restoreProjectArtifacts({ ...common, from: command.from, seed: command.seed });
  }
}

async function projectJobBoss(worker: boolean): Promise<PgBoss> {
  const shared = globalThis as SharedBosses;
  const key = worker ? workerBossKey : producerBossKey;
  const existing = shared[key];
  if (existing) return existing;

  const starting = startBoss(worker).catch((cause) => {
    delete shared[key];
    throw cause;
  });
  shared[key] = starting;
  return starting;
}

async function startBoss(worker: boolean): Promise<PgBoss> {
  const connectionString = process.env.DATABASE_URL?.trim();
  if (!connectionString) throw new Error('DATABASE_URL is required for project jobs.');
  const boss = new PgBoss({
    connectionString,
    application_name: worker ? 'sverlin-project-worker' : 'sverlin-web-jobs',
    max: 3,
    schedule: false,
    useListenNotify: worker
  });
  boss.on('error', (cause) => console.error('Project queue error.', cause));
  boss.on('warning', (warning) => console.warn('Project queue warning.', warning));
  await boss.start();
  await boss.createQueue(queueName, queueOptions());
  await boss.updateQueue(queueName, queueOptions());
  return boss;
}

function queueOptions() {
  return {
    retryLimit: 1,
    retryDelay: 5,
    retryBackoff: true,
    retryDelayMax: 30,
    expireInSeconds: projectJobExpirationSeconds(),
    heartbeatSeconds: jobHeartbeatSeconds(),
    retentionSeconds: 14 * 24 * 60 * 60,
    deleteAfterSeconds: 7 * 24 * 60 * 60,
    notify: true
  } as const;
}

function jobHeartbeatSeconds(): number {
  return Math.min(
    positiveInteger(process.env.SVERLIN_JOB_HEARTBEAT_SECONDS, 60, 10),
    Math.max(10, projectJobExpirationSeconds() - 1)
  );
}

async function findProjectJob(
  boss: PgBoss,
  id: string
): Promise<JobWithMetadata<ProjectJobData> | null> {
  return (await boss.findJobs<ProjectJobData>(queueName, { id }))[0] ?? null;
}

function projectJobStatus(job: JobWithMetadata<ProjectJobData>): ProjectJobView['status'] {
  if (job.state === 'created' || job.state === 'retry') return 'queued';
  if (job.state === 'active') return 'running';
  if (job.state === 'cancelled') return 'cancelled';
  if (job.state === 'failed') return 'failed';
  return projectJobOutput(job.output)?.status === 'failed' ? 'failed' : 'succeeded';
}

function projectJobOutput(value: object): ProjectJobOutput | null {
  if (!value || typeof value !== 'object' || !('status' in value)) return null;
  if (value.status === 'succeeded') return { status: 'succeeded' };
  if (value.status === 'failed' && 'error' in value && typeof value.error === 'string') {
    return { status: 'failed', error: value.error };
  }
  return null;
}

function transportError(job: JobWithMetadata<ProjectJobData>): string | null {
  if (job.state !== 'failed') return null;
  if ('message' in job.output && typeof job.output.message === 'string') {
    return job.output.message.slice(0, 4_000);
  }
  return 'The project worker could not complete this job.';
}

function isInitialRender(value: unknown): value is InitialRenderCommand {
  return (
    !!value &&
    typeof value === 'object' &&
    'type' in value &&
    value.type === 'initial-render' &&
    'seed' in value &&
    Number.isSafeInteger(value.seed) &&
    Number(value.seed) > 0
  );
}

function messageFor(cause: unknown): string {
  const message = cause instanceof Error ? cause.message : String(cause);
  return message.slice(0, 4_000);
}

function positiveInteger(raw: string | undefined, fallback: number, minimum: number): number {
  const value = Number(raw);
  return Number.isSafeInteger(value) && value >= minimum ? value : fallback;
}
