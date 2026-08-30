import { describe, expect, it } from 'vitest';

import { pilotStudyV1 } from './pilot-v1';
import { projectStudyFlow, type StudyRunSnapshot } from './projection';

const baseRun: StudyRunSnapshot = {
  id: 'run-one',
  mode: 'participant',
  studyId: pilotStudyV1.id,
  studyVersion: pilotStudyV1.version,
  armId: 'sverlin-first',
  currentPhaseIndex: 0,
  startPhaseIndex: 0
};

describe('complete study flow projection', () => {
  it('shows every configured phase as unfilled before the participant starts', () => {
    const flow = projectStudyFlow(pilotStudyV1, baseRun, []);
    expect(flow.status).toBe('not-started');
    expect(flow.phases).toHaveLength(pilotStudyV1.flow.length);
    expect(flow.phases.every(({ status }) => status === 'pending')).toBe(true);
  });

  it('derives active and deadline-ready task states from sparse records', () => {
    const startedAt = '2026-08-30T12:00:00.000Z';
    const deadlineAt = '2026-08-30T12:15:00.000Z';
    const run = { ...baseRun, currentPhaseIndex: 1, startedAt };
    const phases = [
      {
        phaseId: 'welcome',
        sequenceIndex: 0,
        status: 'completed' as const,
        endedAt: startedAt,
        endReason: 'continued' as const
      },
      {
        phaseId: 'task-one',
        sequenceIndex: 1,
        status: 'active' as const,
        startedAt,
        deadlineAt,
        projectId: 'project-one'
      }
    ];
    expect(
      projectStudyFlow(pilotStudyV1, run, phases, Date.parse(deadlineAt) - 1).phases[1]?.status
    ).toBe('active');
    expect(
      projectStudyFlow(pilotStudyV1, run, phases, Date.parse(deadlineAt)).phases[1]?.status
    ).toBe('ready-to-continue');
  });

  it('fills a completed flow and keeps isolated preview phases outside scope', () => {
    const completed = projectStudyFlow(
      pilotStudyV1,
      {
        ...baseRun,
        currentPhaseIndex: pilotStudyV1.flow.length - 1,
        startedAt: '2026-08-30T12:00:00.000Z',
        completedAt: '2026-08-30T12:30:00.000Z'
      },
      []
    );
    expect(completed.status).toBe('completed');
    expect(completed.phases.every(({ status }) => status === 'completed')).toBe(true);

    const isolated = projectStudyFlow(
      pilotStudyV1,
      {
        ...baseRun,
        mode: 'preview',
        currentPhaseIndex: 2,
        startPhaseIndex: 2,
        stopAfterPhaseIndex: 2,
        startedAt: '2026-08-30T12:00:00.000Z'
      },
      []
    );
    expect(isolated.phases.map(({ status }) => status)).toEqual([
      'out-of-scope',
      'out-of-scope',
      'active',
      'out-of-scope',
      'out-of-scope'
    ]);
  });
});
