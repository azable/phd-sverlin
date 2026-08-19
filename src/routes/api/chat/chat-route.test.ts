import { describe, expect, it } from 'vitest';

import { POST } from './+server';

describe('POST /api/chat', () => {
  it('echoes a trimmed message', async () => {
    const response = await POST({
      request: new Request('http://localhost/api/chat', {
        method: 'POST',
        body: JSON.stringify({ message: '  hello there  ' }),
        headers: { 'content-type': 'application/json' }
      })
    } as Parameters<typeof POST>[0]);

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({ reply: 'Echo: hello there' });
  });

  it.each([
    ['blank message', { message: '   ' }],
    ['missing message', {}],
    ['non-string message', { message: 42 }]
  ])('rejects a %s', async (_label, body) => {
    const response = await POST({
      request: new Request('http://localhost/api/chat', {
        method: 'POST',
        body: JSON.stringify(body),
        headers: { 'content-type': 'application/json' }
      })
    } as Parameters<typeof POST>[0]);

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
});
