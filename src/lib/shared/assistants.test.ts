import { describe, expect, it } from 'vitest';

import { assistantMode, defaultAssistantId } from './assistants';

describe('visualization assistants', () => {
  it('derives one renderer-compatible assistant from each mode', () => {
    expect(defaultAssistantId('sverlin')).toBe('sverlin-assistant');
    expect(defaultAssistantId('html')).toBe('html-assistant');
    expect(assistantMode('sverlin-assistant')).toBe('sverlin');
    expect(assistantMode('html-assistant')).toBe('html');
  });
});
