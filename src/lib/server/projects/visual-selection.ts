/** Resolve legacy renders and current presentations through one visual-selection boundary. */

import type { ProjectEventOf } from '$lib/shared/projects/events';
import type { VisualSelection } from '$lib/shared/projects/events/values';
import type { ProjectDocument } from '$lib/shared/projects/model';
import { decodeVisualization } from '$lib/shared/visualization';

type SelectionEvent =
  | ProjectEventOf<'visualization.rendered'>
  | ProjectEventOf<'visualization.presented'>;

/** Validated selection plus the exact retained visualization it addresses. */
export type ResolvedProjectVisualSelection = {
  selection: VisualSelection;
  event: SelectionEvent;
  seed: number;
  sourceSha256: string;
  renderSha256: string;
  provenance?: ProjectEventOf<'visualization.rendered'>['payload']['provenance'];
  targetDiagnostics?: ProjectEventOf<'visualization.rendered'>['payload']['targetDiagnostics'];
  visualization: ReturnType<typeof decodeVisualization>;
  step: ReturnType<typeof decodeVisualization>['steps'][number];
};

/** Reject stale or malformed instance references before recording or prompting with them. */
export function resolveProjectVisualSelection(
  document: ProjectDocument,
  selection: VisualSelection
): ResolvedProjectVisualSelection {
  const eventId = 'presentationEvent' in selection ? selection.presentationEvent : selection.render;
  const event = document.events[eventId - 1];
  let render;
  let seed: number;
  let sourceSha256: string;
  let renderSha256: string;
  let provenance;
  let targetDiagnostics;
  if (event?.type === 'visualization.rendered' && 'render' in selection) {
    render = event.payload.render;
    seed = event.payload.seed;
    sourceSha256 = event.payload.source.sha256;
    renderSha256 = event.payload.render.sha256;
    provenance = event.payload.provenance;
    targetDiagnostics = event.payload.targetDiagnostics;
  } else if (event?.type === 'visualization.presented' && 'presentationEvent' in selection) {
    const presentation = event.payload.presentation;
    if (presentation.format !== 'sverlin-ir-v1') {
      throw new Error('Visual feedback is only available for Sverlin presentations.');
    }
    render = presentation.render;
    seed = presentation.seed;
    sourceSha256 = presentation.source.sha256;
    renderSha256 = presentation.render.sha256;
    provenance = presentation.provenance;
    targetDiagnostics = presentation.targetDiagnostics;
  } else {
    throw new Error('The visual selection references an unknown presentation.');
  }

  const visualization = decodeVisualization(render.text);
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
    seed,
    sourceSha256,
    renderSha256,
    ...(provenance ? { provenance } : {}),
    ...(targetDiagnostics ? { targetDiagnostics } : {}),
    visualization,
    step
  };
}
