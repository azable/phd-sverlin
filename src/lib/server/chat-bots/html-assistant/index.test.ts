import { describe, expect, it } from 'vitest';

import htmlAssistant from '.';

const manifest = {
  format: 'sverlin-html-frames',
  version: 1,
  frames: [{ label: 'Overview', html: '<main>Safe</main>' }]
};

describe('HTML assistant contract', () => {
  it('accepts zero to two labelled candidates per conversational turn', () => {
    expect(
      htmlAssistant.parseOutput({
        reply: [{ type: 'markdown', text: 'No change' }],
        candidates: []
      })
    ).toEqual({
      reply: [{ type: 'markdown', text: 'No change' }],
      candidates: []
    });
    expect(
      htmlAssistant.parseOutput({
        reply: [{ type: 'candidate-ref', slot: 0 }],
        candidates: [
          { label: 'First', manifest },
          { label: 'Second', manifest }
        ]
      })
    ).toEqual({
      reply: [{ type: 'candidate-ref', slot: 0 }],
      candidates: [
        { label: 'First', manifest },
        { label: 'Second', manifest }
      ]
    });
  });

  it('rejects the former string reply and unlabelled candidate shape', () => {
    expect(() =>
      htmlAssistant.parseOutput({ reply: 'Batch', candidates: [manifest, manifest] })
    ).toThrow();
    expect(() =>
      htmlAssistant.parseOutput({
        reply: [{ type: 'markdown', text: 'Batch' }],
        candidates: [{ label: ' ', manifest }]
      })
    ).toThrow();
    expect(() =>
      htmlAssistant.parseOutput({
        reply: [{ type: 'markdown', text: 'Batch' }],
        candidates: [
          { label: 'Candidate', manifest: { ...manifest, frames: [{ label: '', html: '' }] } }
        ]
      })
    ).toThrow();
  });

  it('parses participant-facing fallback explanations', () => {
    expect(
      htmlAssistant.parseOutput({
        reply: [{ type: 'markdown', text: 'Here is a simpler version.' }],
        candidates: [{ label: 'Candidate', manifest }],
        recovery: {
          struggledWith: 'the interactive behavior',
          simplified: 'the interaction into static frames'
        }
      })
    ).toMatchObject({
      recovery: {
        struggledWith: 'the interactive behavior',
        simplified: 'the interaction into static frames'
      }
    });
  });
});
