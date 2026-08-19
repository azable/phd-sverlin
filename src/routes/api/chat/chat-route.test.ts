import { beforeEach, describe, expect, it, vi } from 'vitest';

const { generateChatReply, OpenAIConfigurationError } = vi.hoisted(() => ({
  generateChatReply: vi.fn(),
  OpenAIConfigurationError: class OpenAIConfigurationError extends Error {
    constructor() {
      super('OpenAI is not configured on the server.');
    }
  }
}));

vi.mock('$lib/server/openai-chat', () => ({ generateChatReply, OpenAIConfigurationError }));

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

describe('chat session API', () => {
  beforeEach(async () => {
    vi.clearAllMocks();
    generateChatReply.mockResolvedValue('A helpful answer.');
    await DELETE({} as Parameters<typeof DELETE>[0]);
  });

  it('returns and stores a generated reply for a session', async () => {
    const response = await post({ message: '  hello there  ' });

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({
      messages: [
        { role: 'assistant', content: 'Hi! Ask me anything about this workspace.' },
        { role: 'user', content: 'hello there' },
        { role: 'assistant', content: 'A helpful answer.' }
      ]
    });
    expect(generateChatReply).toHaveBeenCalledWith([
      { role: 'assistant', content: 'Hi! Ask me anything about this workspace.' },
      { role: 'user', content: 'hello there' }
    ]);

    const history = await GET({} as Parameters<typeof GET>[0]);
    await expect(history.json()).resolves.toEqual({
      messages: [
        { role: 'assistant', content: 'Hi! Ask me anything about this workspace.' },
        { role: 'user', content: 'hello there' },
        { role: 'assistant', content: 'A helpful answer.' }
      ]
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
    generateChatReply.mockRejectedValue(new OpenAIConfigurationError());

    const response = await post({ message: 'hello' });

    expect(response.status).toBe(503);
    await expect(response.json()).resolves.toEqual({
      error: 'OpenAI is not configured on the server.'
    });
    const history = await GET({} as Parameters<typeof GET>[0]);
    await expect(history.json()).resolves.toEqual({
      messages: [{ role: 'assistant', content: 'Hi! Ask me anything about this workspace.' }]
    });
  });

  it('sanitizes provider failures', async () => {
    generateChatReply.mockRejectedValue(new Error('secret provider details'));

    const response = await post({ message: 'hello' });

    expect(response.status).toBe(502);
    await expect(response.json()).resolves.toEqual({
      error: 'The chat service is unavailable.'
    });
  });

  it('resets the current session', async () => {
    await post({ message: 'hello' });

    const response = await DELETE({} as Parameters<typeof DELETE>[0]);

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({
      messages: [{ role: 'assistant', content: 'Hi! Ask me anything about this workspace.' }]
    });
    const history = await GET({} as Parameters<typeof GET>[0]);
    await expect(history.json()).resolves.toEqual({
      messages: [{ role: 'assistant', content: 'Hi! Ask me anything about this workspace.' }]
    });
  });
});
