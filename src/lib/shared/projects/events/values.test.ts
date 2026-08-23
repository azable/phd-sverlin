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
