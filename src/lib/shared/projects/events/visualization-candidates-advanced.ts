/** Explicit consumption boundary for ahead-of-time visualization candidates. */

import * as v from 'valibot';

import { presentationIdSchema } from '$lib/shared/presentations';

import { eventEnvelope } from './values';

export const visualizationCandidatesAdvancedEventSchema = v.object({
  ...eventEnvelope,
  type: v.literal('visualization.candidates-advanced'),
  payload: v.object({
    presentations: v.pipe(v.array(presentationIdSchema), v.minLength(1), v.maxLength(2)),
    reason: v.picklist(['next', 'agent-request'])
  })
});
