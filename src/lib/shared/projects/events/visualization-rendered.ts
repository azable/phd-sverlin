/** Visualization-rendered event contract. */

import * as v from 'valibot';

import {
  compilationResourceSchema,
  compilationProvenanceSchema,
  eventEnvelope,
  positiveSchema,
  recordedTextSchema,
  targetDiagnosticSchema
} from './values';

/** Runtime schema for activating a compiled visualization. */
export const visualizationRenderedEventSchema = v.object({
  ...eventEnvelope,
  type: v.literal('visualization.rendered'),
  payload: v.object({
    seed: positiveSchema,
    source: recordedTextSchema,
    render: recordedTextSchema,
    resources: v.optional(v.array(compilationResourceSchema)),
    provenance: v.optional(compilationProvenanceSchema),
    targetDiagnostics: v.optional(v.array(targetDiagnosticSchema))
  })
});
