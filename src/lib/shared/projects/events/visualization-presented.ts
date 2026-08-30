/** Renderer-neutral visualization presentation and preference event contracts. */

import * as v from 'valibot';

import { presentationIdSchema, renderablePresentationSchema } from '$lib/shared/presentations';

import { eventEnvelope, naturalSchema, visualSelectionSchema } from './values';

/** Runtime schema for one visualization becoming visible in a display set. */
export const visualizationPresentedEventSchema = v.object({
  ...eventEnvelope,
  type: v.literal('visualization.presented'),
  payload: v.object({
    displaySetId: v.pipe(v.string(), v.uuid()),
    slot: v.picklist([0, 1]),
    presentation: renderablePresentationSchema
  })
});

/** Runtime schema for a preference between two compatible presentations. */
export const visualizationPreferenceRecordedEventSchema = v.object({
  ...eventEnvelope,
  type: v.literal('visualization.preference-recorded'),
  payload: v.object({
    displaySetId: v.optional(v.pipe(v.string(), v.uuid())),
    presentations: v.tuple([presentationIdSchema, presentationIdSchema]),
    preferred: presentationIdSchema,
    step: naturalSchema,
    visualSelections: v.optional(v.pipe(v.array(visualSelectionSchema), v.maxLength(2)))
  })
});
