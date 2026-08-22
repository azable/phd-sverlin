/**
 * Browser-only visualization rendering types.
 *
 * @packageDocumentation
 */

export type * from '$lib/shared/visualization';

import type { RenderInstanceId, VisualElement } from '$lib/shared/visualization';

/** A visual element paired with its identity in the current scene snapshot. */
export type LiveElement = VisualElement & {
  instanceId: RenderInstanceId;
};
