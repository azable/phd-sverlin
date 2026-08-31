import { describe, expect, it } from 'vitest';

import { plainMessageText, structureKnownPresentationReferences } from './message-content';

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

describe('known presentation references', () => {
  it('promotes a known UUID, including Markdown code ticks, without changing unknown UUIDs', () => {
    const unknown = '22345678-1234-4234-8234-123456789ac2';
    expect(
      structureKnownPresentationReferences(
        [
          {
            type: 'markdown',
            text: `Prefer \`${presentationId}\` over ${unknown}.`
          }
        ],
        [presentationId]
      )
    ).toEqual([
      { type: 'markdown', text: 'Prefer ' },
      { type: 'presentation-ref', presentationId },
      { type: 'markdown', text: ` over ${unknown}.` }
    ]);
  });
});
