/** User-feedback event contract. */

import * as v from 'valibot';

import { eventEnvelope, positiveSchema, visualSelectionSchema } from './values';

/** Runtime schema for user feedback and its optional visual focus. */
export const feedbackSubmittedEventSchema = v.object({
  ...eventEnvelope,
  type: v.literal('feedback.submitted'),
  payload: v.object({
    text: v.optional(v.string()),
    focus: v.array(positiveSchema),
    selection: v.optional(visualSelectionSchema)
  })
});
