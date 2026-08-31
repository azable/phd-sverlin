/** Isolated ingestion for best-effort participant workspace observations. */

import { and, eq, sql } from 'drizzle-orm';

import type { ParticipantPrincipal } from '$lib/server/auth';
import { database } from '$lib/server/db';
import * as schema from '$lib/server/db/schema';
import type {
  StudyInteractionBatchInput,
  StudyInteractionCapturePolicy
} from '$lib/shared/study/interactions';
import { studyDefinition } from '$lib/shared/study/registry';

// Normal clients flush every five seconds; thirty batches leave headroom for reconnect drains.
const batchRateWindowMs = 60_000;
const batchRateLimit = 30;
// Client and server clocks may differ slightly without admitting post-deadline collection.
const clientClockToleranceMs = 5_000;

type RateWindow = { startedAt: number; count: number };
const rateWindows = new Map<string, RateWindow>();

export type StudyInteractionIngestionResult = {
  acceptedThrough: number;
  serverReceivedAt: string;
};

export class StudyInteractionIngestionError extends Error {
  constructor(
    message: string,
    readonly status: 400 | 403 | 409 | 410 | 429 = 400
  ) {
    super(message);
    this.name = 'StudyInteractionIngestionError';
  }
}

/** Process-local guard supplementing strict body and batch limits. */
export function consumeStudyInteractionBatchAllowance(userId: string, now = Date.now()): boolean {
  const current = rateWindows.get(userId);
  if (!current || now - current.startedAt >= batchRateWindowMs) {
    rateWindows.set(userId, { startedAt: now, count: 1 });
    pruneRateWindows(now);
    return true;
  }
  if (current.count >= batchRateLimit) return false;
  current.count += 1;
  return true;
}

/** Clear process-local rate state in deterministic tests. */
export function resetStudyInteractionRateLimits(): void {
  rateWindows.clear();
}

/** Accept one contiguous idempotent batch without touching project events or locks. */
export async function ingestStudyInteractions(
  principal: ParticipantPrincipal,
  batch: StudyInteractionBatchInput,
  now = new Date()
): Promise<StudyInteractionIngestionResult> {
  assertContiguousBatch(batch);
  const result = await database().transaction(async (transaction) => {
    let [stored] = await transaction
      .select()
      .from(schema.projectInteractionSessions)
      .where(eq(schema.projectInteractionSessions.id, batch.session.id))
      .limit(1);

    if (!stored) {
      const association = await projectAssociation(transaction, batch.session.projectId);
      const policy = association
        ? studyDefinition(association.studyId, association.studyVersion).interactionCapture
        : undefined;
      if (
        !association ||
        association.projectDeletedAt ||
        association.mode !== 'participant' ||
        association.ownerUserId !== principal.user.id ||
        !association.deadlineAt ||
        !policy
      ) {
        throw new StudyInteractionIngestionError(
          'Interaction recording is unavailable for this study phase.',
          403
        );
      }
      const captureEnd = association.endedAt ?? association.deadlineAt;
      if (now.getTime() > captureEnd.getTime() + policy.lateDeliverySeconds * 1_000) {
        throw new StudyInteractionIngestionError(
          'The interaction delivery window has closed.',
          410
        );
      }
      const clientStartedAt = new Date(batch.session.clientStartedAt);
      if (!sameCapturePolicy(batch.session.capture, policy)) {
        throw new StudyInteractionIngestionError(
          'The interaction capture policy has changed.',
          409
        );
      }
      if (
        !association.startedAt ||
        clientStartedAt.getTime() < association.startedAt.getTime() - clientClockToleranceMs ||
        clientStartedAt.getTime() > captureEnd.getTime() + clientClockToleranceMs
      ) {
        throw new StudyInteractionIngestionError(
          'The interaction session falls outside the study phase.',
          410
        );
      }
      assertWithinCaptureWindow(clientStartedAt, captureEnd, batch.events);
      await transaction
        .insert(schema.projectInteractionSessions)
        .values({
          id: batch.session.id,
          projectId: batch.session.projectId,
          schemaVersion: batch.session.schemaVersion,
          clientStartedAt: new Date(batch.session.clientStartedAt),
          clientTimeOrigin: batch.session.timeOrigin,
          initialViewport: batch.session.initialViewport,
          applicationVersion: batch.session.applicationVersion,
          buildSha: batch.session.buildSha,
          capture: batch.session.capture
        })
        .onConflictDoNothing({ target: schema.projectInteractionSessions.id });
    }

    await transaction.execute(
      sql`select id from project_interaction_session where id = ${batch.session.id} for update`
    );
    [stored] = await transaction
      .select()
      .from(schema.projectInteractionSessions)
      .where(eq(schema.projectInteractionSessions.id, batch.session.id))
      .limit(1);
    if (!stored) {
      throw new StudyInteractionIngestionError(
        'The interaction session could not be created.',
        409
      );
    }

    const association = await projectAssociation(transaction, stored.projectId);
    if (
      !association ||
      association.projectDeletedAt ||
      association.mode !== 'participant' ||
      association.ownerUserId !== principal.user.id ||
      stored.projectId !== batch.session.projectId ||
      stored.schemaVersion !== batch.session.schemaVersion ||
      !sameCapturePolicy(stored.capture, batch.session.capture)
    ) {
      throw new StudyInteractionIngestionError('Interaction session access was rejected.', 403);
    }

    const captureEnd = association.endedAt ?? association.deadlineAt;
    if (!captureEnd) {
      throw new StudyInteractionIngestionError('The study phase has no capture boundary.', 409);
    }
    const deliveryEndsAt = captureEnd.getTime() + stored.capture.lateDeliverySeconds * 1_000;
    if (now.getTime() > deliveryEndsAt) {
      throw new StudyInteractionIngestionError('The interaction delivery window has closed.', 410);
    }

    const pending = batch.events.filter(({ sequence }) => sequence > stored.acceptedThrough);
    if (!pending.length) {
      return { acceptedThrough: stored.acceptedThrough, serverReceivedAt: now.toISOString() };
    }
    if (pending[0]?.sequence !== stored.acceptedThrough + 1) {
      throw new StudyInteractionIngestionError(
        `Interaction sequence ${stored.acceptedThrough + 1} is required next.`,
        409
      );
    }
    assertWithinCaptureWindow(stored.clientStartedAt, captureEnd, pending);
    if (pending.some((event) => event.projectHead > association.projectHead)) {
      throw new StudyInteractionIngestionError(
        'An interaction references a future project Timeline head.',
        409
      );
    }

    await transaction.insert(schema.projectInteractionEvents).values(
      pending.map((event) => ({
        sessionId: stored.id,
        sequence: event.sequence,
        kind: event.kind,
        elapsedMs: event.elapsedMs,
        clientOccurredAt: new Date(event.clientOccurredAt),
        projectHead: event.projectHead,
        payload: event.payload,
        receivedAt: now
      }))
    );
    const acceptedThrough = pending.at(-1)!.sequence;
    await transaction
      .update(schema.projectInteractionSessions)
      .set({ acceptedThrough, updatedAt: now })
      .where(eq(schema.projectInteractionSessions.id, stored.id));
    return { acceptedThrough, serverReceivedAt: now.toISOString() };
  });
  return result;
}

function assertContiguousBatch(batch: StudyInteractionBatchInput): void {
  for (let index = 1; index < batch.events.length; index += 1) {
    if (batch.events[index]!.sequence !== batch.events[index - 1]!.sequence + 1) {
      throw new StudyInteractionIngestionError('Interaction batches must be contiguous.', 409);
    }
  }
}

function assertWithinCaptureWindow(
  clientStartedAt: Date,
  captureEnd: Date,
  events: StudyInteractionBatchInput['events']
): void {
  const maximumElapsed =
    Math.max(0, captureEnd.getTime() - clientStartedAt.getTime()) + clientClockToleranceMs;
  const earliest = clientStartedAt.getTime() - clientClockToleranceMs;
  const latest = captureEnd.getTime() + clientClockToleranceMs;
  for (const event of events) {
    const occurredAt = new Date(event.clientOccurredAt).getTime();
    if (event.elapsedMs > maximumElapsed || occurredAt < earliest || occurredAt > latest) {
      throw new StudyInteractionIngestionError(
        'An interaction falls outside the study phase capture window.',
        410
      );
    }
  }
}

async function projectAssociation(
  transaction: Parameters<Parameters<ReturnType<typeof database>['transaction']>[0]>[0],
  projectId: string
) {
  const [row] = await transaction
    .select({
      mode: schema.studyRuns.mode,
      ownerUserId: schema.studyRuns.ownerUserId,
      studyId: schema.studyRuns.studyId,
      studyVersion: schema.studyRuns.studyVersion,
      deadlineAt: schema.studyPhaseRuns.deadlineAt,
      startedAt: schema.studyPhaseRuns.startedAt,
      endedAt: schema.studyPhaseRuns.endedAt,
      projectHead: schema.projects.head,
      projectDeletedAt: schema.projects.deletedAt
    })
    .from(schema.studyPhaseRuns)
    .innerJoin(schema.studyRuns, eq(schema.studyRuns.id, schema.studyPhaseRuns.runId))
    .innerJoin(schema.projects, eq(schema.projects.id, schema.studyPhaseRuns.projectId))
    .where(
      and(eq(schema.studyPhaseRuns.projectId, projectId), eq(schema.studyPhaseRuns.kind, 'task'))
    )
    .limit(1);
  return row;
}

function sameCapturePolicy(
  left: StudyInteractionCapturePolicy,
  right: StudyInteractionCapturePolicy
): boolean {
  const keys: Array<keyof StudyInteractionCapturePolicy> = [
    'schemaVersion',
    'cursorSampleIntervalMs',
    'cursorChunkDurationMs',
    'flushIntervalMs',
    'flushRecordThreshold',
    'flushByteThreshold',
    'checkpointIntervalMs',
    'draftSnapshotIntervalMs',
    'outboxByteLimit',
    'lateDeliverySeconds'
  ];
  return keys.every((key) => left[key] === right[key]);
}

function pruneRateWindows(now: number): void {
  if (rateWindows.size < 1_000) return;
  for (const [userId, window] of rateWindows) {
    if (now - window.startedAt >= batchRateWindowMs) rateWindows.delete(userId);
  }
}
