import { describe, expect, it, vi } from 'vitest';

import { dslInterfacePath, loadDslInterfaceContext } from '.';

describe('AI assistant DSL interface', () => {
  it('reads the guide again for every request', async () => {
    const readPrompt = vi
      .fn()
      .mockResolvedValueOnce('first revision')
      .mockResolvedValueOnce('second revision');

    await expect(loadDslInterfaceContext(readPrompt)).resolves.toBe('first revision');
    await expect(loadDslInterfaceContext(readPrompt)).resolves.toBe('second revision');
    expect(readPrompt).toHaveBeenNthCalledWith(1, dslInterfacePath, 'utf8');
    expect(readPrompt).toHaveBeenNthCalledWith(2, dslInterfacePath, 'utf8');
  });
});
