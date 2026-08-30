/** User-visible lifecycle boundaries for asynchronous project operations. */

import * as v from 'valibot';

import { eventEnvelope, textSchema } from './values';

/** Stable project operation kinds understood outside the execution mechanism. */
export const projectOperationKindSchema = v.picklist([
  'initial-render',
  'rename',
  'feedback',
  'render',
  'presentation-refill',
  'prefer',
  'save',
  'save-html',
  'restore'
]);

const operationPayloadSchema = v.object({ kind: projectOperationKindSchema });

/** Runtime schema for a command accepted for asynchronous execution. */
export const operationAcceptedEventSchema = v.object({
  ...eventEnvelope,
  type: v.literal('operation.accepted'),
  payload: operationPayloadSchema
});

/** Runtime schema for an operation that reached its successful domain outcome. */
export const operationCompletedEventSchema = v.object({
  ...eventEnvelope,
  type: v.literal('operation.completed'),
  payload: operationPayloadSchema
});

/** Runtime schema for an operation that reached an unsuccessful terminal outcome. */
export const operationFailedEventSchema = v.object({
  ...eventEnvelope,
  type: v.literal('operation.failed'),
  payload: v.object({
    kind: projectOperationKindSchema,
    failureKind: v.picklist(['domain', 'infrastructure', 'cancelled']),
    message: textSchema
  })
});

/** A stable operation category represented in project history. */
export type ProjectOperationKind = v.InferOutput<typeof projectOperationKindSchema>;
