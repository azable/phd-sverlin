import { describe, expect, it } from 'vitest';

import { assistantIntroduction, getChatbot, getHtmlChatbot } from './registry';

describe('chatbot registry', () => {
  it('resolves only assistants compatible with the requested execution contract', () => {
    expect(getChatbot('sverlin-assistant').id).toBe('sverlin-assistant');
    expect(getHtmlChatbot('html-assistant').id).toBe('html-assistant');
    expect(() => getChatbot('html-assistant')).toThrow('Unknown Sverlin assistant');
    expect(() => getHtmlChatbot('sverlin-assistant')).toThrow('Unknown HTML assistant');
  });

  it('uses the resolved assistant identity for participant introductions', () => {
    expect(assistantIntroduction('sverlin-assistant').botId).toBe('sverlin-assistant');
    expect(assistantIntroduction('html-assistant').botId).toBe('html-assistant');
  });
});
