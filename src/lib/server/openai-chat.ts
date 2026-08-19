import OpenAI from 'openai';
import { env } from '$env/dynamic/private';

import type { ChatMessage } from './chat-sessions';

const defaultModel = 'gpt-5.6';

export class OpenAIConfigurationError extends Error {
  constructor() {
    super('OpenAI is not configured on the server.');
    this.name = 'OpenAIConfigurationError';
  }
}

function readApiKey() {
  const apiKey = env.OPENAI_API_KEY?.trim();

  if (!apiKey) throw new OpenAIConfigurationError();

  return apiKey;
}

export async function generateChatReply(messages: ChatMessage[]): Promise<string> {
  const client = new OpenAI({ apiKey: readApiKey() });
  const model = env.OPENAI_MODEL?.trim() || defaultModel;
  const response = await client.responses.create({ model, input: messages });

  return response.output_text;
}
