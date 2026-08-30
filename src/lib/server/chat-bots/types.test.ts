import { describe, expect, it } from 'vitest';

import { generatedMessageContentJsonSchema } from './types';

describe('generated message provider schema', () => {
  it('uses structured-output-compatible unions and mirrors non-empty text validation', () => {
    expect(generatedMessageContentJsonSchema.items).toHaveProperty('anyOf');
    expect(generatedMessageContentJsonSchema.items).not.toHaveProperty('oneOf');
    expect(generatedMessageContentJsonSchema.items.anyOf[0]).toMatchObject({
      properties: { text: { type: 'string', minLength: 1 } }
    });
  });
});
