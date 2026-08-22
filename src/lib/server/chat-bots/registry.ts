/**
 * Assembly and runtime selection of configured chatbots.
 *
 * @packageDocumentation
 */

import { env } from '$env/dynamic/private';

import { openAIAdapter } from '$lib/server/chat-adapters/openai';

import type { ChatAdapter } from '$lib/server/chat-adapters/types';
import type { ChatBotConfig, Chatbot, ChatbotRequest } from './types';
import aiAssistantBot from './ai-assistant';

/** Combine a bot definition with a provider adapter into an executable chatbot. */
export function createChatbot(config: ChatBotConfig, adapter: ChatAdapter): Chatbot {
  const preparePrompt = async (request: ChatbotRequest) => ({
    messages: request.messages,
    initialPrompt: config.initialPrompt,
    context: await config.buildContext(request),
    parameters: config.parameters,
    responseFormat: config.responseFormat
  });
  const generatePrepared = async (prompt: Awaited<ReturnType<typeof preparePrompt>>) => {
    const result = await adapter.generateReply(prompt);
    return {
      ...result,
      prompt,
      generation: {
        botId: config.id,
        adapterId: adapter.id,
        ...result.generation
      }
    };
  };
  return {
    id: config.id,
    config,
    preparePrompt,
    generatePrepared
  } satisfies Chatbot;
}

const configuredChatbots: Record<string, Chatbot> = {
  [aiAssistantBot.id]: createChatbot(aiAssistantBot, openAIAdapter)
};

/** Return the chatbot selected by server configuration. */
export function getChatbot(): Chatbot {
  const configured = env.CHATBOT_CONFIG?.trim() || aiAssistantBot.id;
  const chatbot = configuredChatbots[configured];

  if (!chatbot) {
    throw new Error(`Unknown chatbot configuration: ${configured}`);
  }

  return chatbot;
}
