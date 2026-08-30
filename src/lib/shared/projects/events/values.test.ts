import { describe, expect, it } from 'vitest';
import * as v from 'valibot';

import { visualSelectionSchema } from './values';

describe('visualSelectionSchema', () => {
  it('accepts zero-based instance IDs for an exact presentation event', () => {
    expect(
      v.parse(visualSelectionSchema, {
        presentationEvent: 1,
        step: 0,
        instances: [0]
      })
    ).toEqual({ presentationEvent: 1, step: 0, instances: [0] });
  });

  it('accepts current presentation-event selections', () => {
    expect(
      v.parse(visualSelectionSchema, {
        presentationEvent: 4,
        step: 1,
        instances: [0, 2]
      })
    ).toEqual({ presentationEvent: 4, step: 1, instances: [0, 2] });
  });

  it('rejects the former render key and negative instance IDs', () => {
    expect(() =>
      v.parse(visualSelectionSchema, {
        render: 1,
        step: 0,
        instances: [0]
      })
    ).toThrow();
    expect(() =>
      v.parse(visualSelectionSchema, {
        presentationEvent: 1,
        step: 0,
        instances: [-1]
      })
    ).toThrow();
  });
});
