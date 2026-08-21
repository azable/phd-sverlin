import { beforeEach, describe, expect, it, vi } from 'vitest';

const { generateOpenAIReply, OpenAIConfigurationError } = vi.hoisted(() => ({
  generateOpenAIReply: vi.fn(),
  OpenAIConfigurationError: class OpenAIConfigurationError extends Error {
    constructor() {
      super('OpenAI is not configured on the server.');
    }
  }
}));

vi.mock('$lib/server/chat-adapters/openai', () => ({
  generateOpenAIReply,
  OpenAIConfigurationError,
  openAIAdapter: {
    id: 'openai-responses',
    generateReply: generateOpenAIReply
  }
}));

vi.mock('$lib/server/openai-chat', () => ({ OpenAIConfigurationError }));
import { DELETE, GET, POST } from './+server';

function post(body: unknown) {
  return POST({
    request: new Request('http://localhost/api/chat', {
      method: 'POST',
      body: JSON.stringify(body),
      headers: { 'content-type': 'application/json' }
    })
  } as Parameters<typeof POST>[0]);
}

describe('chat API', () => {
  beforeEach(async () => {
    vi.clearAllMocks();
    generateOpenAIReply.mockResolvedValue({ reply: 'A helpful answer.' });
    await DELETE({} as Parameters<typeof DELETE>[0]);
  });

  it('returns and stores a generated reply', async () => {
    const response = await post({ message: '  hello there  ' });

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      messages: [
        { role: 'assistant', content: 'Hi! Ask me anything about this workspace.' },
        { role: 'user', content: 'hello there' },
        { role: 'assistant', content: 'A helpful answer.' }
      ],
      artifact: {
        artifactId: 'dsl-main',
        current: {
          id: 'dsl-main',
          path: 'Main.sverlin',
          language: 'sverlin'
        },
        headRevision: 0,
        streamVersion: 0,
        events: []
      }
    });
    expect(generateOpenAIReply).toHaveBeenCalledWith(
      expect.objectContaining({
        messages: [
          { role: 'assistant', content: 'Hi! Ask me anything about this workspace.' },
          { role: 'user', content: 'hello there' }
        ],
        initialPrompt: expect.stringContaining('body-only Sverlin source'),
        context: expect.objectContaining({ artifact: expect.any(Object) }),
        parameters: {
          model: 'gpt-5.6',
          reasoningEffort: 'medium',
          maxOutputTokens: 4096
        },
        responseFormat: expect.objectContaining({ name: 'chat_result', strict: true })
      })
    );

    const history = await GET({} as Parameters<typeof GET>[0]);
    await expect(history.json()).resolves.toMatchObject({
      messages: expect.arrayContaining([{ role: 'assistant', content: 'A helpful answer.' }])
    });
  });

  it.each([
    ['blank message', { message: '   ' }],
    ['missing message', {}],
    ['non-string message', { message: 42 }]
  ])('rejects a %s', async (_label, body) => {
    const response = await post(body);

    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error: '`message` must be a non-empty string.'
    });
  });

  it('rejects malformed JSON', async () => {
    const response = await POST({
      request: new Request('http://localhost/api/chat', {
        method: 'POST',
        body: '{',
        headers: { 'content-type': 'application/json' }
      })
    } as Parameters<typeof POST>[0]);

    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error: 'Request body must be valid JSON.'
    });
  });

  it('reports missing server configuration without saving the user message', async () => {
    generateOpenAIReply.mockRejectedValue(new OpenAIConfigurationError());

    const response = await post({ message: 'hello' });

    expect(response.status).toBe(503);
    await expect(response.json()).resolves.toEqual({
      error: 'OpenAI is not configured on the server.'
    });
    const history = await GET({} as Parameters<typeof GET>[0]);
    await expect(history.json()).resolves.toMatchObject({
      messages: [{ role: 'assistant', content: 'Hi! Ask me anything about this workspace.' }]
    });
  });

  it('sanitizes provider failures', async () => {
    generateOpenAIReply.mockRejectedValue(new Error('secret provider details'));

    const response = await post({ message: 'hello' });

    expect(response.status).toBe(502);
    await expect(response.json()).resolves.toEqual({
      error: 'The chat service is unavailable.'
    });
  });

  it('resets the current transcript', async () => {
    await post({ message: 'hello' });

    const response = await DELETE({} as Parameters<typeof DELETE>[0]);

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      messages: [{ role: 'assistant', content: 'Hi! Ask me anything about this workspace.' }],
      artifact: { headRevision: 0, streamVersion: 0, events: [] }
    });
  });

  it('tracks a generated source revision and patch', async () => {
    const source =
      'program :: Choreography ()\nprogram = return ()\n\nvisualization :: VisualizationBuilder ()\nvisualization = return ()\n';
    generateOpenAIReply.mockResolvedValue({
      reply: 'Updated the DSL.',
      sourceArtifactContent: source
    });

    const response = await post({ message: 'simplify the DSL' });

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      artifact: {
        current: { content: source },
        headRevision: 1,
        streamVersion: 1,
        events: [{ revision: 1, patch: [{ op: 'replace', path: '/content', value: source }] }]
      }
    });
  });

  it('passes the complete artifact history to the next chatbot turn', async () => {
    const before = await GET({} as Parameters<typeof GET>[0]);
    const beforeState = await before.json();
    const existingEvents = beforeState.artifact.events.length;

    for (let revision = 1; revision <= 6; revision += 1) {
      const source = `program :: Choreography ()\nprogram = return ()\n\nvisualization :: VisualizationBuilder ()\nvisualization = return ()\n-- revision ${revision}\n`;
      generateOpenAIReply.mockResolvedValueOnce({
        reply: `Revision ${revision}`,
        sourceArtifactContent: source
      });
      await post({ message: `apply revision ${revision}` });
    }

    generateOpenAIReply.mockResolvedValueOnce({ reply: 'History is available.' });
    await post({ message: 'summarize the history' });

    const historyRequest = generateOpenAIReply.mock.calls.at(-1)?.[0];
    expect(historyRequest.context.artifact.history).toHaveLength(existingEvents + 6);
    expect(historyRequest.context.artifact.history.at(-1).after.content).toContain('-- revision 6');

    const reset = await DELETE({} as Parameters<typeof DELETE>[0]);
    await expect(reset.json()).resolves.toMatchObject({
      artifact: {
        headRevision: existingEvents + 7,
        events: expect.arrayContaining([
          expect.objectContaining({
            revision: existingEvents + 7,
            source: expect.objectContaining({ reason: 'reset' })
          })
        ])
      }
    });
  });
});
