/** Structured user-facing message content retained in project Timelines. */

import * as v from 'valibot';

import { presentationIdSchema } from '$lib/shared/presentations';
import type { RenderInstanceId } from '$lib/shared/visualization';

import { naturalSchema, positiveSchema, textSchema } from './values';

export const markdownMessageSegmentSchema = v.strictObject({
  type: v.literal('markdown'),
  text: textSchema
});

export const presentationReferenceSegmentSchema = v.strictObject({
  type: v.literal('presentation-ref'),
  presentationId: presentationIdSchema
});

export const elementReferenceSegmentSchema = v.strictObject({
  type: v.literal('element-ref'),
  presentationId: presentationIdSchema,
  presentationEvent: positiveSchema,
  step: naturalSchema,
  instances: v.pipe(v.array(naturalSchema), v.minLength(1))
});

/** Runtime schema for one Markdown or exact visualization reference segment. */
export const messageContentSegmentSchema = v.variant('type', [
  markdownMessageSegmentSchema,
  presentationReferenceSegmentSchema,
  elementReferenceSegmentSchema
]);

/** Runtime schema for a non-empty structured message. */
export const messageContentSchema = v.pipe(v.array(messageContentSegmentSchema), v.minLength(1));

export type MessageContentSegment =
  v.InferOutput<typeof messageContentSegmentSchema> extends infer Segment
    ? Segment extends { instances: number[] }
      ? Omit<Segment, 'instances'> & { instances: RenderInstanceId[] }
      : Segment
    : never;
export type MessageContent = MessageContentSegment[];

/** Construct the canonical representation of a text-only Markdown message. */
export function markdownMessage(text: string): MessageContent {
  const value = text.trim();
  if (!value) throw new Error('Message text cannot be empty.');
  return [{ type: 'markdown', text: value }];
}

/** Flatten structured content for compact logs and model-provider text channels. */
export function plainMessageText(content: MessageContent): string {
  return content
    .flatMap((segment) => {
      if (segment.type === 'markdown') return [segment.text];
      if (segment.type === 'presentation-ref') {
        return [`[Presentation ${segment.presentationId}]`];
      }
      return segment.instances.map(
        (instance) =>
          `[Element E${instance} in presentation ${segment.presentationId}, step ${segment.step + 1}]`
      );
    })
    .join(' ')
    .trim();
}
