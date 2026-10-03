import { describe, expect, it } from 'vitest';

import aiAssistant from './bot.server';

describe('single-component Svelte assistant', () => {
  it('uses the five-call Luna/Sol ladder with a bounded fallback', () => {
    expect(
      aiAssistant.attemptProfiles.map(({ purpose, parameters }) => [
        purpose,
        parameters.model,
        parameters.reasoningEffort
      ])
    ).toEqual([
      ['initial', 'gpt-5.6-luna', 'low'],
      ['repair', 'gpt-5.6-sol', 'medium'],
      ['repair', 'gpt-5.6-sol', 'high'],
      ['repair', 'gpt-5.6-sol', 'xhigh'],
      ['fallback', 'gpt-5.6-sol', 'xhigh']
    ]);
    expect(
      aiAssistant.attemptProfiles.every(({ parameters }) => parameters.maxOutputTokens === 12_000)
    ).toBe(true);
  });

  it('specifies the complete source and isolated step contract', () => {
    expect(aiAssistant.initialPrompt).toContain('complete, self-contained Svelte 5 component');
    expect(aiAssistant.initialPrompt).toContain('step and seed as props');
    expect(aiAssistant.initialPrompt).toContain('Do not use imports');
  });

  it('rejects empty source and reply text consistently with its provider schema', () => {
    expect(() =>
      aiAssistant.parseOutput({
        reply: [{ type: 'markdown', text: '' }],
        decision: { action: 'respond', sourceArtifactContent: null }
      })
    ).toThrow();
    expect(() =>
      aiAssistant.parseOutput({
        reply: [{ type: 'markdown', text: 'Update' }],
        decision: { action: 'revise', sourceArtifactContent: '   ' }
      })
    ).toThrow();
  });

  it('parses participant-facing fallback explanations', () => {
    expect(
      aiAssistant.parseOutput({
        reply: [{ type: 'markdown', text: 'Here is a simpler version.' }],
        decision: { action: 'revise', sourceArtifactContent: '<h1>Hello</h1>' },
        recovery: {
          struggledWith: 'the dense animated layout',
          simplified: 'the layout while preserving the subject'
        }
      })
    ).toMatchObject({
      recovery: {
        struggledWith: 'the dense animated layout',
        simplified: 'the layout while preserving the subject'
      }
    });
  });

  it('enforces the respond, resample, and revise source contract', () => {
    expect(aiAssistant.responseFormat.schema).toMatchObject({
      type: 'object',
      properties: {
        decision: {
          anyOf: [
            {
              properties: {
                action: { enum: ['revise'] },
                sourceArtifactContent: { type: 'string' }
              }
            },
            {
              properties: {
                action: { enum: ['respond', 'resample'] },
                sourceArtifactContent: { type: 'null' }
              }
            }
          ]
        }
      }
    });
    expect(() =>
      aiAssistant.parseOutput({
        reply: [{ type: 'markdown', text: 'I will change it.' }],
        decision: { action: 'respond', sourceArtifactContent: '<h1>Hello</h1>' },
        recovery: null
      })
    ).toThrow(/action/i);
    expect(() =>
      aiAssistant.parseOutput({
        reply: [{ type: 'markdown', text: 'I am updating it.' }],
        decision: { action: 'revise', sourceArtifactContent: null },
        recovery: null
      })
    ).toThrow(/action/i);
    expect(
      aiAssistant.parseOutput({
        reply: [{ type: 'markdown', text: 'I am preparing another pair.' }],
        decision: { action: 'resample', sourceArtifactContent: null },
        recovery: null
      })
    ).toMatchObject({ action: 'resample' });
  });

  it('rejects unsupported message content in assistant discussion', () => {
    expect(() =>
      aiAssistant.parseOutput({
        reply: [
          { type: 'unsupported-content' },
          { type: 'markdown', text: 'Do you prefer this presentation?' }
        ],
        decision: { action: 'respond', sourceArtifactContent: null },
        recovery: null
      })
    ).toThrow();
  });
});
