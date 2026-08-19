import { json } from '@sveltejs/kit';

import type { RequestHandler } from './$types';

export const prerender = false;

type ChatResponse = { reply: string } | { error: string };

export const POST: RequestHandler = async ({ request }) => {
  let body: unknown;

  try {
    body = await request.json();
  } catch {
    return json({ error: 'Request body must be valid JSON.' } satisfies ChatResponse, {
      status: 400
    });
  }

  const message = readMessage(body);

  if (message === null) {
    return json({ error: '`message` must be a non-empty string.' } satisfies ChatResponse, {
      status: 400
    });
  }

  return json({ reply: `Echo: ${message}` } satisfies ChatResponse);
};

function readMessage(body: unknown): string | null {
  if (typeof body !== 'object' || body === null || !('message' in body)) return null;

  const message = body.message;

  if (typeof message !== 'string') return null;

  const trimmed = message.trim();

  return trimmed ? trimmed : null;
}
