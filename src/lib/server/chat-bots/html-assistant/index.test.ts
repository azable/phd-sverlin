import { describe, expect, it } from 'vitest';

import htmlAssistant from '.';

const manifest = {
  format: 'sverlin-html-frames',
  version: 1,
  frames: [{ label: 'Overview', html: '<main>Safe</main>' }]
};

describe('HTML assistant contract', () => {
  it('accepts one optional manifest per conversational turn', () => {
    expect(htmlAssistant.parseOutput({ reply: 'No change', manifest: null })).toEqual({
      reply: 'No change'
    });
    expect(htmlAssistant.parseOutput({ reply: 'Updated', manifest })).toEqual({
      reply: 'Updated',
      manifest
    });
  });

  it('rejects the former candidate-array response shape', () => {
    expect(() =>
      htmlAssistant.parseOutput({ reply: 'Batch', candidates: [manifest, manifest] })
    ).toThrow('invalid structured response');
  });
});
