/** Durable, retry-safe orchestration for centrally registered participant studies. */

import { createHash, randomUUID } from 'node:crypto';

import { and, count, eq, sql } from 'drizzle-orm';

import type { ParticipantPrincipal } from '$lib/server/auth';
import { database, sqlClient } from '$lib/server/db';
import * as schema from '$lib/server/db/schema';
import { projectRepository, ProjectNotFoundError } from '$lib/server/projects/repository';
import { createProject, renderProjectPresentations } from '$lib/server/projects/service';
import { projectSnapshotAt } from '$lib/shared/projects/projection';
import { resolveStudyArm, type ResolvedStudyPhase } from '$lib/shared/study/definition';
import { activeStudyDefinition, studyDefinition } from '$lib/shared/study/registry';

export type ParticipantStudyState = {
  studyId: string;
  studyVersion: number;
  armId: string;
  phaseIndex: number;
  phase: ResolvedStudyPhase;
  projectId?: string;
  startedAt?: string;
  deadlineAt?: string;
  expired: boolean;
};

/** Assign a newly provisioned participant to the currently smaller counterbalance arm. */
export async function enrollParticipant(userId: string): Promise<void> {
  const definition = activeStudyDefinition;
  await database().transaction(async (transaction) => {
    await transaction.execute(
      sql`select pg_advisory_xact_lock(hashtextextended(${definition.id}, ${definition.version}))`
    );
    const totals = await transaction
      .select({ armId: schema.studyEnrollments.armId, total: count() })
      .from(schema.studyEnrollments)
      .where(
        and(
          eq(schema.studyEnrollments.studyId, definition.id),
          eq(schema.studyEnrollments.studyVersion, definition.version)
        )
      )
      .groupBy(schema.studyEnrollments.armId);
    const byArm = new Map(totals.map(({ armId, total }) => [armId, total]));
    const armId = definition.assignment.tieBreakOrder.reduce((selected, candidate) =>
      (byArm.get(candidate) ?? 0) < (byArm.get(selected) ?? 0) ? candidate : selected
    );
    await transaction
      .insert(schema.studyEnrollments)
      .values({
        userId,
        studyId: definition.id,
        studyVersion: definition.version,
        armId
      })
      .onConflictDoNothing();
  });
}

/** Return the participant's current phase using the exact protocol version they enrolled in. */
export async function participantStudyState(userId: string): Promise<ParticipantStudyState> {
  await enrollParticipant(userId);
  return loadParticipantStudyState(userId);
}

/** Complete the current screen without exposing a half-created or untimed task project. */
export function continueParticipantStudy(userId: string): Promise<ParticipantStudyState> {
  return withParticipantStudyLock(userId, async () => {
    let state = await participantStudyState(userId);
    if (state.phase.kind === 'completion') return state;
    // A repeated submission after a successful task transition is harmless.
    if (state.phase.kind === 'task' && !state.expired) return state;

    const enrollment = await loadEnrollment(userId);
    const definition = studyDefinition(enrollment.studyId, enrollment.studyVersion);
    const phases = resolveStudyArm(definition, enrollment.armId);
    const nextIndex = enrollment.currentPhaseIndex + 1;
    const nextPhase = phases[nextIndex];
    if (!nextPhase) throw new Error('The study protocol has no next phase.');

    const projectId =
      nextPhase.kind === 'task'
        ? await ensureTaskProject({
            userId,
            studyId: enrollment.studyId,
            studyVersion: enrollment.studyVersion,
            phase: nextPhase
          })
        : undefined;
    const transitionedAt = new Date();

    await database().transaction(async (transaction) => {
      if (state.phase.kind === 'task') {
        await transaction
          .update(schema.studyPhaseRuns)
          .set({ status: 'completed', endedAt: transitionedAt })
          .where(
            and(
              eq(schema.studyPhaseRuns.userId, userId),
              eq(schema.studyPhaseRuns.phaseId, state.phase.id)
            )
          );
      } else {
        await transaction
          .insert(schema.studyPhaseRuns)
          .values({
            userId,
            phaseId: state.phase.id,
            sequenceIndex: state.phaseIndex,
            kind: state.phase.kind,
            status: 'completed',
            endedAt: transitionedAt
          })
          .onConflictDoNothing();
      }

      if (nextPhase.kind === 'task' && projectId) {
        const deadlineAt = new Date(
          transitionedAt.getTime() + nextPhase.condition.durationSeconds * 1_000
        );
        await transaction
          .insert(schema.studyPhaseRuns)
          .values({
            userId,
            phaseId: nextPhase.id,
            sequenceIndex: nextIndex,
            kind: 'task',
            conditionId: nextPhase.conditionId,
            renderer: nextPhase.condition.renderer,
            layout: nextPhase.condition.workspace.layout,
            view: nextPhase.condition.workspace.view,
            projectId,
            status: 'active',
            startedAt: transitionedAt,
            deadlineAt
          })
          .onConflictDoNothing();
      }

      await transaction
        .update(schema.studyEnrollments)
        .set({
          currentPhaseIndex: nextIndex,
          ...(nextPhase.kind === 'completion' ? { completedAt: transitionedAt } : {})
        })
        .where(
          and(
            eq(schema.studyEnrollments.userId, userId),
            eq(schema.studyEnrollments.currentPhaseIndex, enrollment.currentPhaseIndex)
          )
        );
    });

    state = await loadParticipantStudyState(userId);
    return state;
  });
}

/** Enforce that participant mutations target only their live task project. */
export async function assertParticipantStudyMutation(
  principal: ParticipantPrincipal,
  projectId: string
): Promise<void> {
  const state = await participantStudyState(principal.user.id);
  if (
    state.phase.kind !== 'task' ||
    state.projectId !== projectId ||
    state.expired ||
    !state.deadlineAt
  ) {
    throw new Error('This study phase is read-only.');
  }
}

async function loadParticipantStudyState(userId: string): Promise<ParticipantStudyState> {
  const enrollment = await loadEnrollment(userId);
  const definition = studyDefinition(enrollment.studyId, enrollment.studyVersion);
  const phases = resolveStudyArm(definition, enrollment.armId);
  const phase = phases[enrollment.currentPhaseIndex] ?? phases.at(-1);
  if (!phase) throw new Error('The enrolled study has no phases.');
  const [run] = await database()
    .select()
    .from(schema.studyPhaseRuns)
    .where(
      and(eq(schema.studyPhaseRuns.userId, userId), eq(schema.studyPhaseRuns.phaseId, phase.id))
    )
    .limit(1);
  return {
    studyId: enrollment.studyId,
    studyVersion: enrollment.studyVersion,
    armId: enrollment.armId,
    phaseIndex: enrollment.currentPhaseIndex,
    phase,
    ...(run?.projectId ? { projectId: run.projectId } : {}),
    ...(run?.startedAt ? { startedAt: run.startedAt.toISOString() } : {}),
    ...(run?.deadlineAt ? { deadlineAt: run.deadlineAt.toISOString() } : {}),
    expired: !!run?.deadlineAt && run.deadlineAt.getTime() <= Date.now()
  };
}

async function loadEnrollment(userId: string) {
  const [enrollment] = await database()
    .select()
    .from(schema.studyEnrollments)
    .where(eq(schema.studyEnrollments.userId, userId))
    .limit(1);
  if (!enrollment) throw new Error('The participant could not be enrolled in the study.');
  return enrollment;
}

async function ensureTaskProject(options: {
  userId: string;
  studyId: string;
  studyVersion: number;
  phase: Extract<ResolvedStudyPhase, { kind: 'task' }>;
}): Promise<string> {
  const projectId = studyTaskProjectId(
    options.studyId,
    options.studyVersion,
    options.userId,
    options.phase.id
  );
  const presentationCount = options.phase.condition.workspace.layout === 'comparison' ? 2 : 1;
  let document;
  try {
    document = await projectRepository.load(projectId);
  } catch (cause) {
    if (!(cause instanceof ProjectNotFoundError)) throw cause;
    document = await createProject({
      projectId,
      ownerUserId: options.userId,
      operationId: randomUUID(),
      creation: {
        templateId: options.phase.condition.project.templateId,
        renderer: options.phase.condition.renderer
      },
      presentationCount
    });
    if (!hasReadyPresentation(document, presentationCount)) {
      throw new Error('The task visualization could not be prepared. Retry to continue.');
    }
    return projectId;
  }

  if (!hasReadyPresentation(document, presentationCount)) {
    const rendered = await renderProjectPresentations({
      projectId,
      expectedHead: document.events.length,
      presentationCount,
      operationId: randomUUID()
    });
    document = rendered.document;
  }
  if (!hasReadyPresentation(document, presentationCount)) {
    throw new Error('The task visualization could not be prepared. Retry to continue.');
  }
  return projectId;
}

function hasReadyPresentation(
  document: Awaited<ReturnType<typeof projectRepository.load>>,
  count: 1 | 2
) {
  const active = projectSnapshotAt(document).activePresentationSet;
  return active?.presentations.length === count;
}

/** Stable task-project identity used to resume preparation after interrupted requests. */
export function studyTaskProjectId(
  studyId: string,
  studyVersion: number,
  userId: string,
  phaseId: string
): string {
  const identity = `${studyId}:${studyVersion}:${userId}:${phaseId}`;
  return `study-${createHash('sha256').update(identity).digest('hex').slice(0, 48)}`;
}

async function withParticipantStudyLock<Result>(
  userId: string,
  operation: () => Promise<Result>
): Promise<Result> {
  const connection = await sqlClient().reserve();
  try {
    await connection`select pg_advisory_lock(hashtextextended(${`study:${userId}`}, 1))`;
    return await operation();
  } finally {
    await connection`
      select pg_advisory_unlock(hashtextextended(${`study:${userId}`}, 1))
    `.catch(() => undefined);
    connection.release();
  }
}
