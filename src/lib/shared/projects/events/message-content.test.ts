import { describe, expect, it } from 'vitest';

import { plainMessageText } from './message-content';

const presentationId = '12345678-1234-4123-8123-123456789ac1';

describe('plain message text', () => {
  it('identifies every referenced render instance separately', () => {
    expect(
      plainMessageText([
        { type: 'markdown', text: 'Compare' },
        {
          type: 'element-ref',
          presentationId,
          presentationEvent: 4,
          step: 2,
          instances: [7, 2]
        }
      ])
    ).toBe(
      `Compare [Element E7 in presentation ${presentationId}, step 3] [Element E2 in presentation ${presentationId}, step 3]`
    );
  });
});
