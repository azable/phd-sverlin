import { env } from '$env/dynamic/private';

import { generateOpenAIReply } from '$lib/server/openai-chat';

import type { Chatbot } from './types';

const openAIChatbot: Chatbot = {
  id: 'openai-default',
  generateReply: generateOpenAIReply
};

export function getChatbot(): Chatbot {
  const configured = env.CHATBOT_CONFIG?.trim() || openAIChatbot.id;

  if (configured !== openAIChatbot.id) {
    throw new Error(`Unknown chatbot configuration: ${configured}`);
  }

  return openAIChatbot;
}
