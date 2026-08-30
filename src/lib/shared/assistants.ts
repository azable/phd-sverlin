/** Stable visualization-assistant identities and their renderer compatibility. */

import * as v from 'valibot';

import type { VisualizationMode } from './presentations';

/** Assistant implementations that may be recorded in a project Timeline. */
export const assistantIdSchema = v.picklist(['sverlin-assistant', 'html-assistant']);

/** Stable identifier for one configured visualization assistant. */
export type AssistantId = v.InferOutput<typeof assistantIdSchema>;

const modes = {
  'sverlin-assistant': 'sverlin',
  'html-assistant': 'html'
} as const satisfies Record<AssistantId, VisualizationMode>;

/** Return the renderer contract implemented by an assistant. */
export function assistantMode(id: AssistantId): VisualizationMode {
  return modes[id];
}

/** Return the registered assistant implicit in a visualization mode. */
export function defaultAssistantId(mode: VisualizationMode): AssistantId {
  return mode === 'html' ? 'html-assistant' : 'sverlin-assistant';
}
