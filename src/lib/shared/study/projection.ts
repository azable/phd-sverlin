/** Pure projections of durable study execution onto the complete registered flow. */

import { resolveStudyArm, type ResolvedStudyPhase, type StudyDefinition } from './definition';

export type StudyRunMode = 'participant' | 'preview';
export type StudyProgressStatus = 'not-started' | 'in-progress' | 'completed';
export type StudyPhaseStatus =
  | 'pending'
  | 'active'
  | 'ready-to-continue'
  | 'completed'
  | 'out-of-scope';
export type StudyPhaseEndReason =
  | 'continued'
  | 'deadline'
  | 'participant-early'
  | 'admin-forced'
  | 'flow-complete';

export type StudyRunSnapshot = {
  id: string;
  mode: StudyRunMode;
  studyId: string;
  studyVersion: number;
  armId: string;
  currentPhaseIndex: number;
  startPhaseIndex: number;
  stopAfterPhaseIndex?: number;
  startedAt?: string;
  completedAt?: string;
};

export type StudyPhaseRunSnapshot = {
  phaseId: string;
  sequenceIndex: number;
  projectId?: string;
  status: 'active' | 'completed';
  startedAt?: string;
  deadlineAt?: string;
  endedAt?: string;
  endReason?: StudyPhaseEndReason;
};

export type StudyFlowPhase = {
  sequenceIndex: number;
  phase: ResolvedStudyPhase;
  status: StudyPhaseStatus;
  projectId?: string;
  startedAt?: string;
  deadlineAt?: string;
  endedAt?: string;
  endReason?: StudyPhaseEndReason;
};

export type StudyFlow = {
  runId: string;
  mode: StudyRunMode;
  studyId: string;
  studyVersion: number;
  studyName: string;
  armId: string;
  status: StudyProgressStatus;
  currentPhaseIndex: number;
  startedAt?: string;
  completedAt?: string;
  phases: StudyFlowPhase[];
};

/** Combine immutable protocol data and sparse execution records into every configured phase. */
export function projectStudyFlow(
  definition: StudyDefinition,
  run: StudyRunSnapshot,
  phaseRuns: readonly StudyPhaseRunSnapshot[],
  now = Date.now()
): StudyFlow {
  if (definition.id !== run.studyId || definition.version !== run.studyVersion) {
    throw new Error('The study run does not match the supplied protocol.');
  }
  const resolved = resolveStudyArm(definition, run.armId);
  const byPhase = new Map(phaseRuns.map((phaseRun) => [phaseRun.phaseId, phaseRun]));
  const stopAfter = run.stopAfterPhaseIndex ?? resolved.length - 1;
  const status: StudyProgressStatus = run.completedAt
    ? 'completed'
    : run.startedAt
      ? 'in-progress'
      : 'not-started';

  return {
    runId: run.id,
    mode: run.mode,
    studyId: run.studyId,
    studyVersion: run.studyVersion,
    studyName: definition.name,
    armId: run.armId,
    status,
    currentPhaseIndex: run.currentPhaseIndex,
    ...(run.startedAt ? { startedAt: run.startedAt } : {}),
    ...(run.completedAt ? { completedAt: run.completedAt } : {}),
    phases: resolved.map((phase, sequenceIndex) => {
      const phaseRun = byPhase.get(phase.id);
      return {
        sequenceIndex,
        phase,
        status: phaseStatus({ run, phaseRun, sequenceIndex, stopAfter, now }),
        ...(phaseRun?.projectId ? { projectId: phaseRun.projectId } : {}),
        ...(phaseRun?.startedAt ? { startedAt: phaseRun.startedAt } : {}),
        ...(phaseRun?.deadlineAt ? { deadlineAt: phaseRun.deadlineAt } : {}),
        ...(phaseRun?.endedAt ? { endedAt: phaseRun.endedAt } : {}),
        ...(phaseRun?.endReason ? { endReason: phaseRun.endReason } : {})
      };
    })
  };
}

function phaseStatus(options: {
  run: StudyRunSnapshot;
  phaseRun?: StudyPhaseRunSnapshot;
  sequenceIndex: number;
  stopAfter: number;
  now: number;
}): StudyPhaseStatus {
  const { run, phaseRun, sequenceIndex, stopAfter, now } = options;
  if (sequenceIndex < run.startPhaseIndex || sequenceIndex > stopAfter) return 'out-of-scope';
  if (!run.startedAt) return 'pending';
  if (phaseRun?.status === 'completed' || sequenceIndex < run.currentPhaseIndex) return 'completed';
  if (sequenceIndex > run.currentPhaseIndex) return 'pending';
  if (run.completedAt) return 'completed';
  if (phaseRun?.deadlineAt && Date.parse(phaseRun.deadlineAt) <= now) {
    return 'ready-to-continue';
  }
  return 'active';
}
