import { describe, expect, it } from 'vitest';

import { presentationDisplayId } from '$lib/client/visualization/presentation-history';

import { referenceChipLabel, singletonReferenceSegments } from './reference-labels';

const presentationId = '12345678-1234-4123-8123-123456789ac1';

describe('visualization reference labels', () => {
  it('expands a retained selection into ordered, de-duplicated singleton references', () => {
    expect(
      singletonReferenceSegments({
        type: 'element-ref',
        presentationId,
        presentationEvent: 4,
        step: 2,
        instances: [7, 2, 7]
      })
    ).toEqual([
      {
        type: 'element-ref',
        presentationId,
        presentationEvent: 4,
        step: 2,
        instances: [7]
      },
      {
        type: 'element-ref',
        presentationId,
        presentationEvent: 4,
        step: 2,
        instances: [2]
      }
    ]);
  });

  it('labels an exact element with its candidate, human step, and render instance ID', () => {
    expect(
      referenceChipLabel({
        type: 'element-ref',
        presentationId,
        presentationEvent: 4,
        step: 2,
        instances: [7]
      })
    ).toBe(`${presentationDisplayId(presentationId)} / S3 / E7`);
  });
});
