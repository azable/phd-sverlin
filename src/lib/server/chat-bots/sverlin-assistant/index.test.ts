import { describe, expect, it, vi } from 'vitest';

import aiAssistant, {
  dslApiIndexPath,
  dslInterfacePath,
  loadDslApiIndex,
  loadDslInterfaceContext
} from '.';

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

  it('reads the source-derived API index again for every request', async () => {
    const readPrompt = vi
      .fn()
      .mockResolvedValueOnce('first API revision')
      .mockResolvedValueOnce('second API revision');

    await expect(loadDslApiIndex(readPrompt)).resolves.toBe('first API revision');
    await expect(loadDslApiIndex(readPrompt)).resolves.toBe('second API revision');
    expect(readPrompt).toHaveBeenNthCalledWith(1, dslApiIndexPath, 'utf8');
    expect(readPrompt).toHaveBeenNthCalledWith(2, dslApiIndexPath, 'utf8');
  });

  it('supplies the complete documented facade index to the model', async () => {
    const index = await loadDslApiIndex();
    expect(index).toContain('# Public Sverlin DSL API index');
    expect(index).toContain('`node` —');
    expect(index).toContain('`fitText` — Type: `fitText :: ContentValue -> Render ()`');
    expect(index).toContain('`Traceable` — Type: `class Traceable tag where; type Payload tag`');
    expect(index).not.toContain('NodeBinding');
    expect(index).not.toContain('ChoiceDomain');

    const context = await aiAssistant.buildContext({
      messages: [],
      project: {} as never,
      attempt: { number: 1, purpose: 'initial' }
    });
    expect(context.dslApiIndex).toBe(index);
  });

  it('makes linear value flow the source of computational meaning', async () => {
    expect(aiAssistant.initialPrompt).toContain(
      'never introduce a Program result with create when it should be derived from live Blocks'
    );
    const guide = await loadDslInterfaceContext();
    expect(guide).toContain('Do not precompute algorithm results outside Program');
    expect(guide).toContain('`copy` is the only way to reuse a live semantic value');
    expect(guide).toContain('A requested border needs a positive `StrokeWidth`');
  });

  it('keeps unspecified presentation open and uses explicit finite choices', async () => {
    expect(aiAssistant.initialPrompt).toContain(
      'Leave visual style fields unspecified unless semantics or an explicit participant preference require them'
    );
    const guide = await loadDslInterfaceContext();
    expect(guide).toContain('`style @Field value` requires one field');
    expect(guide).toContain('`withoutStyle @Field` removes an inherited field');
    expect(guide).toContain('`oneOf name first rest` creates one fresh authored choice');
    expect(guide).toContain('`fontChoice (fontKind Monospace)`');
    expect(guide).toContain('not to guess an aesthetic');
  });

  it('lets preference evidence drive or defer a proactive source adaptation', () => {
    expect(aiAssistant.initialPrompt).toContain('When preferences provide enough evidence');
    expect(aiAssistant.initialPrompt).toContain('when several attributes could explain');
    expect(aiAssistant.initialPrompt).toContain('without inventing a change');
  });

  it('rejects empty source and reply text consistently with its provider schema', () => {
    expect(() =>
      aiAssistant.parseOutput({
        reply: [{ type: 'markdown', text: '' }],
        action: 'respond',
        sourceArtifactContent: null
      })
    ).toThrow();
    expect(() =>
      aiAssistant.parseOutput({
        reply: [{ type: 'markdown', text: 'Update' }],
        action: 'revise',
        sourceArtifactContent: '   '
      })
    ).toThrow();
  });

  it('parses participant-facing fallback explanations', () => {
    expect(
      aiAssistant.parseOutput({
        reply: [{ type: 'markdown', text: 'Here is a simpler version.' }],
        action: 'revise',
        sourceArtifactContent: 'main = pure ()',
        recovery: {
          struggledWith: 'the dense animated layout',
          simplified: 'the layout while preserving the value flow'
        }
      })
    ).toMatchObject({
      recovery: {
        struggledWith: 'the dense animated layout',
        simplified: 'the layout while preserving the value flow'
      }
    });
  });

  it('enforces the respond, resample, and revise source contract', () => {
    expect(() =>
      aiAssistant.parseOutput({
        reply: [{ type: 'markdown', text: 'I will change it.' }],
        action: 'respond',
        sourceArtifactContent: 'main = pure ()',
        recovery: null
      })
    ).toThrow(/action/i);
    expect(() =>
      aiAssistant.parseOutput({
        reply: [{ type: 'markdown', text: 'I am updating it.' }],
        action: 'revise',
        sourceArtifactContent: null,
        recovery: null
      })
    ).toThrow(/action/i);
    expect(
      aiAssistant.parseOutput({
        reply: [{ type: 'markdown', text: 'I am preparing another pair.' }],
        action: 'resample',
        sourceArtifactContent: null,
        recovery: null
      })
    ).toMatchObject({ action: 'resample' });
  });

  it('accepts exact retained-element references in assistant discussion', () => {
    expect(
      aiAssistant.parseOutput({
        reply: [
          {
            type: 'element-ref',
            presentationId: '12345678-1234-4123-8123-123456789abc',
            presentationEvent: 4,
            step: 1,
            instances: [2]
          },
          { type: 'markdown', text: 'Do you prefer this element?' }
        ],
        action: 'respond',
        sourceArtifactContent: null,
        recovery: null
      })
    ).toMatchObject({ action: 'respond' });
  });
});
