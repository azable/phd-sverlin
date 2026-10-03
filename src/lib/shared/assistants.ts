/** Stable visualization-assistant identities derived from the mode catalogue. */

import * as v from 'valibot';

import type { VisualizationMode } from './presentations';
import { modeCatalog } from '$lib/modes/catalog';

/** Assistant implementations that may be recorded in a project Timeline. */
export const assistantIdSchema = v.picklist(
  Object.values(modeCatalog).map(({ assistantId }) => assistantId) as [
    (typeof modeCatalog)[keyof typeof modeCatalog]['assistantId'],
    ...(typeof modeCatalog)[keyof typeof modeCatalog]['assistantId'][]
  ]
);

/** Stable identifier for one configured visualization assistant. */
export type AssistantId = v.InferOutput<typeof assistantIdSchema>;

/** Return the mode owned by an assistant. */
export function assistantMode(id: AssistantId): VisualizationMode {
  const entry = Object.entries(modeCatalog).find(([, mode]) => mode.assistantId === id);
  if (!entry) throw new Error(`Unknown visualization assistant: ${id}`);
  return entry[0] as VisualizationMode;
}

/** Return the registered assistant implicit in a visualization mode. */
export function defaultAssistantId(mode: VisualizationMode): AssistantId {
  return modeCatalog[mode].assistantId;
}
