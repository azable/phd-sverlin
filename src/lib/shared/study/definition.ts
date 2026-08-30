/** Pure, versioned research-study definitions and resolution helpers. */

import type {
  PresentationLayout,
  VisualizationMode,
  WorkspaceView
} from '$lib/shared/presentations';

export type StudyCondition = {
  renderer: VisualizationMode;
  workspace: {
    view: WorkspaceView;
    layout: PresentationLayout;
    artifactEditor: 'collapsible';
  };
  project: {
    templateId: string;
    artifactFormat?: 'html-frames-json';
  };
  durationSeconds: number;
};

export type StudyPhase =
  | {
      id: string;
      kind: 'instruction';
      title: string;
      paragraphs: string[];
      continueLabel: string;
    }
  | {
      id: string;
      kind: 'task';
      conditionSlot: string;
      instructions: { title: string; prompt: string };
    }
  | { id: string; kind: 'completion'; title: string; paragraphs: string[] };

export type StudyDefinition = {
  id: string;
  version: number;
  assignment: { strategy: 'balanced'; tieBreakOrder: string[] };
  conditions: Record<string, StudyCondition>;
  arms: Record<string, { slots: Record<string, string> }>;
  flow: StudyPhase[];
};

export type ResolvedStudyPhase =
  | Exclude<StudyPhase, { kind: 'task' }>
  | (Extract<StudyPhase, { kind: 'task' }> & {
      conditionId: string;
      condition: StudyCondition;
    });

/** Convert minutes to the seconds stored by server-authoritative task timers. */
export function minutes(value: number): number {
  if (!Number.isSafeInteger(value) || value <= 0) throw new Error('Minutes must be positive.');
  return value * 60;
}

/** Validate and freeze a study protocol before it is registered. */
export function defineStudy<const Definition extends StudyDefinition>(
  definition: Definition
): Readonly<Definition> {
  const phaseIds = definition.flow.map(({ id }) => id);
  if (new Set(phaseIds).size !== phaseIds.length)
    throw new Error('Study phase IDs must be unique.');
  if (!Number.isSafeInteger(definition.version) || definition.version <= 0) {
    throw new Error('Study versions must be positive integers.');
  }
  for (const [id, condition] of Object.entries(definition.conditions)) {
    if (!Number.isSafeInteger(condition.durationSeconds) || condition.durationSeconds <= 0) {
      throw new Error(`Study condition ${id} needs a positive duration.`);
    }
  }
  for (const armId of definition.assignment.tieBreakOrder) {
    if (!definition.arms[armId]) throw new Error(`Unknown study arm ${armId}.`);
  }
  for (const [armId, arm] of Object.entries(definition.arms)) {
    for (const phase of definition.flow) {
      if (phase.kind !== 'task') continue;
      const conditionId = arm.slots[phase.conditionSlot];
      if (!conditionId || !definition.conditions[conditionId]) {
        throw new Error(`Study arm ${armId} does not resolve slot ${phase.conditionSlot}.`);
      }
    }
  }
  return Object.freeze(definition);
}

/** Resolve one counterbalanced arm into the exact phase sequence a participant receives. */
export function resolveStudyArm(definition: StudyDefinition, armId: string): ResolvedStudyPhase[] {
  const arm = definition.arms[armId];
  if (!arm) throw new Error(`Unknown study arm ${armId}.`);
  return definition.flow.map((phase) => {
    if (phase.kind !== 'task') return phase;
    const conditionId = arm.slots[phase.conditionSlot];
    const condition = definition.conditions[conditionId];
    if (!condition) throw new Error(`Unknown study condition ${conditionId}.`);
    return { ...phase, conditionId, condition };
  });
}
