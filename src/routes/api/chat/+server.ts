import { json } from '@sveltejs/kit';

import { clearChatState, getChatState } from '$lib/server/chat-sessions';
import { InvalidSourceArtifactError, sendChatMessage } from '$lib/server/chat-service';
import { OpenAIConfigurationError } from '$lib/server/openai-chat';

import type { RequestHandler } from './$types';

export const prerender = false;

export const GET: RequestHandler = async () => json(getChatState());

export const POST: RequestHandler = async ({ request }) => {
  let body: unknown;

  try {
    body = await request.json();
  } catch {
    return json({ error: 'Request body must be valid JSON.' }, { status: 400 });
  }

  const message = readMessage(body);

  if (message === null) {
    return json({ error: '`message` must be a non-empty string.' }, { status: 400 });
  }

  try {
    return json(await sendChatMessage(message));
  } catch (error) {
    return providerError(error);
  }
};

export const DELETE: RequestHandler = async () => {
  await clearChatState();
  return json(getChatState());
};

function providerError(error: unknown) {
  if (error instanceof OpenAIConfigurationError) {
    return json({ error: error.message }, { status: 503 });
  }

  if (error instanceof InvalidSourceArtifactError) {
    return json({ error: error.message }, { status: 502 });
  }

  if (error instanceof Error && error.name === 'ChatContextOverflowError') {
    return json({ error: error.message }, { status: 413 });
  }

  console.error('Chat request failed.', error);
  return json({ error: 'The chat service is unavailable.' }, { status: 502 });
}

function readMessage(body: unknown): string | null {
  if (typeof body !== 'object' || body === null || !('message' in body)) return null;

  const message = body.message;

  if (typeof message !== 'string') return null;

  const trimmed = message.trim();

  return trimmed ? trimmed : null;
}
