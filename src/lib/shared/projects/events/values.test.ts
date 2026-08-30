import { describe, expect, it } from 'vitest';
import * as v from 'valibot';

import { visualSelectionSchema } from './values';

describe('visualSelectionSchema', () => {
  it('accepts the zero-based render instance IDs produced by the compiler', () => {
    expect(
      v.parse(visualSelectionSchema, {
        render: 1,
        step: 0,
        instances: [0]
      })
    ).toEqual({ render: 1, step: 0, instances: [0] });
  });

  it('accepts current presentation-event selections without changing legacy data', () => {
    expect(
      v.parse(visualSelectionSchema, {
        presentationEvent: 4,
        step: 1,
        instances: [0, 2]
      })
    ).toEqual({ presentationEvent: 4, step: 1, instances: [0, 2] });
  });

  it('rejects negative render instance IDs', () => {
    expect(() =>
      v.parse(visualSelectionSchema, {
        render: 1,
        step: 0,
        instances: [-1]
      })
    ).toThrow();
  });
});
