/** Visualization-rendered event contract. */

import * as v from 'valibot';

import { eventEnvelope, positiveSchema, recordedTextSchema } from './values';

/** Runtime schema for activating a compiled visualization. */
export const visualizationRenderedEventSchema = v.object({
  ...eventEnvelope,
  type: v.literal('visualization.rendered'),
  payload: v.object({
    seed: positiveSchema,
    source: recordedTextSchema,
    render: recordedTextSchema
  })
});
