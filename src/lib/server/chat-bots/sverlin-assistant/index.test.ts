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
    expect(index).toContain(
      '`fitText` — Type: `fitText :: ContentValue -> VisualizationBuilder ()`'
    );

    const context = await aiAssistant.buildContext({
      messages: [],
      project: {} as never,
      attempt: { number: 1, purpose: 'initial' }
    });
    expect(context.dslApiIndex).toBe(index);
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
      'Leave visual style fields unspecified unless semantics require them'
    );
    const guide = await loadDslInterfaceContext();
    expect(guide).toContain('`style @Field value` is a hard authoring requirement');
    expect(guide).toContain('`withoutStyle @Field` is also hard');
    expect(guide).toContain('Use `styleCase` only when the requested design itself needs');
    expect(guide).toContain('one exact managed font face and one text occupancy target');
    expect(guide).toContain('Do not make a numeric list');
  });

  it('rejects empty source and reply text consistently with its provider schema', () => {
    expect(() =>
      aiAssistant.parseOutput({
        reply: [{ type: 'markdown', text: '' }],
        candidateAction: 'none',
        sourceArtifactContent: null
      })
    ).toThrow();
    expect(() =>
      aiAssistant.parseOutput({
        reply: [{ type: 'markdown', text: 'Update' }],
        candidateAction: 'generate',
        sourceArtifactContent: '   '
      })
    ).toThrow();
  });

  it('parses participant-facing fallback explanations', () => {
    expect(
      aiAssistant.parseOutput({
        reply: [{ type: 'markdown', text: 'Here is a simpler version.' }],
        candidateAction: 'none',
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
});
