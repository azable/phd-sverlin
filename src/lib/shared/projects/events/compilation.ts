/** Compilation request and outcome event contracts. */

import * as v from 'valibot';

import {
  diagnosticSchema,
  eventEnvelope,
  integerSchema,
  naturalSchema,
  positiveSchema,
  recordedTextSchema,
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
    source: recordedTextSchema,
    sourceLabel: textSchema,
    seed: v.pipe(integerSchema, v.minValue(1)),
    attempt: v.optional(positiveSchema),
    compilationId: v.optional(v.pipe(v.string(), v.uuid())),
    batchIndex: v.optional(naturalSchema),
    batchSize: v.optional(positiveSchema)
  })
});

/** Runtime schema for a successful compilation. */
export const compilationSucceededEventSchema = v.object({
  ...eventEnvelope,
  type: v.literal('compilation.succeeded'),
  payload: v.object({
    durationMs: naturalSchema,
    compilationId: v.optional(v.pipe(v.string(), v.uuid())),
    seed: v.optional(positiveSchema),
    batchIndex: v.optional(naturalSchema),
    batchSize: v.optional(positiveSchema),
    render: recordedTextSchema
  })
});

/** Runtime schema for a failed compilation. */
export const compilationFailedEventSchema = v.object({
  ...eventEnvelope,
  type: v.literal('compilation.failed'),
  payload: v.object({
    durationMs: naturalSchema,
    compilationId: v.optional(v.pipe(v.string(), v.uuid())),
    seed: v.optional(positiveSchema),
    batchIndex: v.optional(naturalSchema),
    batchSize: v.optional(positiveSchema),
    failureKind: v.picklist(['source', 'infrastructure', 'cancelled']),
    diagnostics: v.array(diagnosticSchema),
    repairEligible: v.boolean(),
    error: v.optional(v.string())
  })
});
