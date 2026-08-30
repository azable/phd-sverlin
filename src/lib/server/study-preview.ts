/** Admin-only projections for previewing one task condition without enrolling a participant. */

import type { PresentationLayout, VisualizationMode } from '$lib/shared/presentations';
import type { StudyDefinition } from '$lib/shared/study/definition';
import { activeStudyDefinition } from '$lib/shared/study/registry';

export type StudyPreviewOption = {
  key: string;
  name: string;
  label: string;
  studyId: string;
  studyVersion: number;
  phaseId: string;
  conditionId: string;
  title: string;
  prompt: string;
  renderer: VisualizationMode;
  layout: PresentationLayout;
  templateId: string;
  durationSeconds: number;
  presentationCount: 1 | 2;
};

export type AdminPreviewTask = {
  context: 'admin-preview';
  previewKey: string;
  phaseId: string;
  title: string;
  prompt: string;
  deadlineAt: string;
  expired: boolean;
  layout: PresentationLayout;
};

/** Enumerate one preview choice per condition using the protocol's first task instructions. */
export function studyPreviewOptions(
  definition: StudyDefinition = activeStudyDefinition
): StudyPreviewOption[] {
  const phase = definition.flow.find((candidate) => candidate.kind === 'task');
  if (!phase || phase.kind !== 'task')
    throw new Error('The study protocol has no task to preview.');

  return Object.entries(definition.conditions).map(([conditionId, condition]) => {
    const name = condition.renderer === 'html' ? 'HTML' : 'Sverlin';
    return {
      key: `${definition.id}@${definition.version}:${phase.id}:${conditionId}`,
      name,
      label: `${name} · ${layoutLabel(condition.workspace.layout)} · ${durationLabel(
        condition.durationSeconds
      )}`,
      studyId: definition.id,
      studyVersion: definition.version,
      phaseId: phase.id,
      conditionId,
      title: phase.instructions.title,
      prompt: phase.instructions.prompt,
      renderer: condition.renderer,
      layout: condition.workspace.layout,
      templateId: condition.project.templateId,
      durationSeconds: condition.durationSeconds,
      presentationCount: condition.workspace.layout === 'comparison' ? 2 : 1
    };
  });
}

/** Resolve a browser-supplied key against generated registered choices. */
export function studyPreviewOption(key: string): StudyPreviewOption {
  const option = studyPreviewOptions().find((candidate) => candidate.key === key);
  if (!option) throw new InvalidStudyPreviewError('Unknown study preview option.');
  return option;
}

/** Derive the timed workspace state from a server-issued preview start timestamp. */
export function adminPreviewTask(
  key: string,
  startedAtValue: string,
  now = Date.now()
): AdminPreviewTask {
  const option = studyPreviewOption(key);
  const startedAt = Number(startedAtValue);
  if (!Number.isSafeInteger(startedAt) || startedAt <= 0 || startedAt > now + 1_000) {
    throw new InvalidStudyPreviewError('Invalid study preview start time.');
  }
  const deadlineAt = startedAt + option.durationSeconds * 1_000;
  return {
    context: 'admin-preview',
    previewKey: option.key,
    phaseId: option.phaseId,
    title: option.title,
    prompt: option.prompt,
    deadlineAt: new Date(deadlineAt).toISOString(),
    expired: deadlineAt <= now,
    layout: option.layout
  };
}

/** Build the canonical admin preview URL without persisting transient timer state. */
export function studyPreviewProjectUrl(
  projectId: string,
  previewKey: string,
  startedAt: number
): string {
  const parameters = new URLSearchParams({
    studyPreview: previewKey,
    previewStartedAt: String(startedAt)
  });
  return `/projects/${encodeURIComponent(projectId)}?${parameters}`;
}

export class InvalidStudyPreviewError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'InvalidStudyPreviewError';
  }
}

function layoutLabel(layout: PresentationLayout): string {
  return layout === 'comparison' ? 'Comparison' : 'Single render';
}

function durationLabel(seconds: number): string {
  return seconds % 60 === 0 ? `${seconds / 60} min` : `${seconds} sec`;
}
