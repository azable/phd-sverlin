import { describe, expect, it } from 'vitest';

import { presentationDisplayId } from '$lib/client/visualization/presentation-history';
import { referenceChipLabel, singletonReferenceSegments } from './reference-labels';

describe('presentation reference labels', () => {
  it('labels an element chip with its presentation, step, and element', () => {
    const reference = {
      type: 'element-ref' as const,
      presentationId: '12345678-1234-4123-8123-123456789ac1',
      step: 2,
      element: { id: '62:7#2', label: 'Int 8' }
    };
    expect(referenceChipLabel(reference)).toBe(
      `${presentationDisplayId(reference.presentationId)} / S3 / Int 8`
    );
  });

  it('retains one actionable chip with a stable participant-facing label', () => {
    const reference = {
      type: 'presentation-ref' as const,
      presentationId: '12345678-1234-4123-8123-123456789ac1'
    };
    expect(singletonReferenceSegments(reference)).toEqual([reference]);
    expect(referenceChipLabel(reference)).toBe(presentationDisplayId(reference.presentationId));
  });
});
