/** Compilation request and outcome event contracts. */

import * as v from 'valibot';

import {
  blobRefSchema,
  diagnosticSchema,
  dslRevisionSchema,
  eventEnvelope,
  integerSchema,
  naturalSchema,
  renderPurposeSchema,
  textSchema
} from './values';

/** Runtime schema for a compilation request. */
export const compilationRequestedEventSchema = v.object({
  ...eventEnvelope,
  type: v.literal('compilation.requested'),
  payload: v.object({
    purpose: renderPurposeSchema,
    input: v.picklist(['committed-artifact', 'assistant-candidate']),
    source: blobRefSchema,
    sourceLabel: textSchema,
    seed: v.pipe(integerSchema, v.minValue(1)),
    attempt: v.optional(v.picklist([1, 2])),
    dslRevision: v.optional(dslRevisionSchema)
  })
});

/** Runtime schema for a successful compilation. */
export const compilationSucceededEventSchema = v.object({
  ...eventEnvelope,
  type: v.literal('compilation.succeeded'),
  payload: v.object({
    durationMs: naturalSchema,
    stdout: blobRefSchema,
    stderr: blobRefSchema,
    render: blobRefSchema
  })
});

/** Runtime schema for a failed compilation. */
export const compilationFailedEventSchema = v.object({
  ...eventEnvelope,
  type: v.literal('compilation.failed'),
  payload: v.object({
    durationMs: naturalSchema,
    exitCode: v.nullable(integerSchema),
    failureKind: v.picklist([
      'source',
      'pipeline',
      'infrastructure',
      'timeout',
      'invalid-output',
      'cancelled'
    ]),
    diagnostics: v.array(diagnosticSchema),
    stdout: blobRefSchema,
    stderr: blobRefSchema,
    timedOut: v.boolean(),
    repairEligible: v.boolean(),
    error: v.optional(v.string())
  })
});
