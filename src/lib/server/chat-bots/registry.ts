import { env } from '$env/dynamic/private';

import { openAIAdapter } from '$lib/server/chat-adapters/openai';

import type { ChatAdapter } from '$lib/server/chat-adapters/types';
import type { ChatBotConfig, Chatbot, ChatbotRequest, ChatbotResult } from './types';
import aiAssistantBot from './ai-assistant';

export function createChatbot(config: ChatBotConfig, adapter: ChatAdapter): Chatbot {
  return {
    id: config.id,
    config,
    generateReply: async (request: ChatbotRequest): Promise<ChatbotResult> => {
      const result = await adapter.generateReply({
        messages: request.messages,
        initialPrompt: config.initialPrompt,
        context: config.buildContext(request),
        parameters: config.parameters,
        responseFormat: config.responseFormat
      });

      return {
        ...result,
        generation: {
          botId: config.id,
          adapterId: adapter.id,
          ...result.generation
        }
      };
    }
  };
}

const configuredChatbots: Record<string, Chatbot> = {
  [aiAssistantBot.id]: createChatbot(aiAssistantBot, openAIAdapter)
};

export function getChatbot(): Chatbot {
  const configured = env.CHATBOT_CONFIG?.trim() || aiAssistantBot.id;
  const chatbot = configuredChatbots[configured];

  if (!chatbot) {
    throw new Error(`Unknown chatbot configuration: ${configured}`);
  }

  return chatbot;
}
