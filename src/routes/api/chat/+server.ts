import { json } from '@sveltejs/kit';

import {
  clearChatMessages,
  getChatMessages,
  saveChatMessages,
  type ChatMessage
} from '$lib/server/chat-sessions';
import { generateChatReply, OpenAIConfigurationError } from '$lib/server/openai-chat';

import type { RequestHandler } from './$types';

export const prerender = false;

type ChatResponse = { messages: ChatMessage[] } | { error: string };

export const GET: RequestHandler = async () => {
  return json({ messages: getChatMessages() } satisfies ChatResponse);
};

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

  const nextMessages: ChatMessage[] = [...getChatMessages(), { role: 'user', content: message }];

  try {
    const reply = await generateChatReply(nextMessages);
    const messages: ChatMessage[] = [...nextMessages, { role: 'assistant', content: reply }];

    saveChatMessages(messages);

    return json({ messages } satisfies ChatResponse);
  } catch (error) {
    if (error instanceof OpenAIConfigurationError) {
      return json({ error: error.message } satisfies ChatResponse, { status: 503 });
    }

    console.error('OpenAI chat request failed.', error);
    return json({ error: 'The chat service is unavailable.' } satisfies ChatResponse, {
      status: 502
    });
  }
};

export const DELETE: RequestHandler = async () => {
  clearChatMessages();

  return json({ messages: getChatMessages() } satisfies ChatResponse);
};

function readMessage(body: unknown): string | null {
  if (typeof body !== 'object' || body === null || !('message' in body)) return null;

  const message = body.message;

  if (typeof message !== 'string') return null;

  const trimmed = message.trim();

  return trimmed ? trimmed : null;
}
