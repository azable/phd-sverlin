/** A presentation's view failing as it drew a step in the participant's browser. */

import * as v from 'valibot';

import { presentationIdSchema } from '$lib/shared/presentations';

import { eventEnvelope, naturalSchema } from './values';

/** What the sandbox reported: the step being drawn, if known, and the error's message. */
export const runtimeFailureSchema = v.object({
  presentationId: presentationIdSchema,
  step: v.optional(naturalSchema),
  message: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(500))
});

export const visualizationRuntimeFailedEventSchema = v.object({
  ...eventEnvelope,
  type: v.literal('visualization.runtime-failed'),
  payload: runtimeFailureSchema
});
