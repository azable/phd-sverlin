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

/** Ephemeral renderer evidence kept separate from immutable compiler findings. */
export type TextRuntimeObservation = {
  code: 'text.metric-mismatch';
  instanceId: RenderInstanceId;
  elementId: number;
  lineIndex: number;
  fontResourceId: string;
  expectedAdvance: number;
  measuredAdvance: number;
  difference: number;
};
