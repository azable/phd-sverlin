/** Client-facing labels and singleton expansion for retained visualization references. */

import { presentationDisplayId } from '$lib/client/visualization/presentation-history';
import type { MessageContentSegment } from '$lib/shared/projects/events/message-content';

export type ReferenceSegment = Exclude<MessageContentSegment, { type: 'markdown' }>;

/** Expand a reference into the individually actionable chips shown to participants. */
export function singletonReferenceSegments(reference: ReferenceSegment): ReferenceSegment[] {
  return [reference];
}

/** Return the compact, participant-facing label for one reference chip. */
export function referenceChipLabel(reference: ReferenceSegment): string {
  const presentation = presentationDisplayId(reference.presentationId);
  if (reference.type === 'presentation-ref') return presentation;
  return `${presentation} / S${reference.step + 1} / ${reference.element.label}`;
}
