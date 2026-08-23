import { describe, expect, it, vi } from 'vitest';

import aiAssistant, { dslInterfacePath, loadDslInterfaceContext } from '.';

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

  it('makes linear value flow the source of computational meaning', async () => {
    expect(aiAssistant.initialPrompt).toContain(
      'never directly create a domain value that should be derived from live values'
    );
    const guide = await loadDslInterfaceContext();
    expect(guide).toContain('`create` is the ingress boundary');
    expect(guide).toContain('Apply2 pendingResult <- apply2 addition leftInput rightInput');
    expect(guide).toContain(
      'Treat an explicitly requested border as one composite visual property'
    );
  });

  it('delegates unspecified presentation to conditional family profiles', async () => {
    expect(aiAssistant.initialPrompt).toContain(
      'Leave visual style fields unspecified unless the user or the visualization’s semantics require them'
    );
    const guide = await loadDslInterfaceContext();
    expect(guide).toContain('`style @Field value` is a hard authoring requirement');
    expect(guide).toContain('`withoutStyle @Field` is also hard');
    expect(guide).toContain('Use `styleCase` only when the requested design itself needs');
    expect(guide).toContain('one exact managed font face and one text occupancy target');
    expect(guide).toContain('Do not make a numeric list');
  });
});
