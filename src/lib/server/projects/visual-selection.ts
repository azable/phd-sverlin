/** Resolve a retained Sverlin presentation through the visual-selection boundary. */

import type { ProjectEventOf } from '$lib/shared/projects/events';
import type { VisualSelection } from '$lib/shared/projects/events/values';
import type { ProjectDocument } from '$lib/shared/projects/model';
import { decodeVisualization } from '$lib/shared/visualization';

type SelectionEvent = ProjectEventOf<'visualization.presented'>;

/** Validated selection plus the exact retained visualization it addresses. */
export type ResolvedProjectVisualSelection = {
  selection: VisualSelection;
  event: SelectionEvent;
  seed: number;
  sourceSha256: string;
  renderSha256: string;
  provenance?: Extract<
    ProjectEventOf<'visualization.presented'>['payload']['presentation'],
    { format: 'sverlin-ir-v1' }
  >['provenance'];
  targetDiagnostics?: Extract<
    ProjectEventOf<'visualization.presented'>['payload']['presentation'],
    { format: 'sverlin-ir-v1' }
  >['targetDiagnostics'];
  visualization: ReturnType<typeof decodeVisualization>;
  step: ReturnType<typeof decodeVisualization>['steps'][number];
};

/** Reject stale or malformed instance references before recording or prompting with them. */
export function resolveProjectVisualSelection(
  document: ProjectDocument,
  selection: VisualSelection
): ResolvedProjectVisualSelection {
  const event = document.events[selection.presentationEvent - 1];
  if (event?.type !== 'visualization.presented') {
    throw new Error('The visual selection references an unknown presentation.');
  }
  const presentation = event.payload.presentation;
  if (presentation.format !== 'sverlin-ir-v1') {
    throw new Error('Visual feedback is only available for Sverlin presentations.');
  }

  const visualization = decodeVisualization(presentation.render.text);
  const step = visualization.steps[selection.step];
  if (!step) throw new Error('The visual selection references an unknown visualization step.');
  const available = new Set(step.instances.map(({ id }) => id));
  const instances = [...new Set(selection.instances)];
  if (instances.some((id) => !available.has(id))) {
    throw new Error('The visual selection contains an unknown render instance.');
  }
  return {
    selection: { ...selection, instances },
    event,
    seed: presentation.seed,
    sourceSha256: presentation.source.sha256,
    renderSha256: presentation.render.sha256,
    ...(presentation.provenance ? { provenance: presentation.provenance } : {}),
    ...(presentation.targetDiagnostics
      ? { targetDiagnostics: presentation.targetDiagnostics }
      : {}),
    visualization,
    step
  };
}
