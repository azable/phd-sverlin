/**
 * Assembly and runtime selection of configured chatbots.
 *
 * @packageDocumentation
 */

import { openAIAdapter } from '$lib/server/chat-adapters/openai';

import type { ChatAdapter } from '$lib/server/chat-adapters/types';
import { InvalidChatbotResponseError } from '$lib/server/chat-adapters/types';
import type { AiProjectContext } from './sverlin-assistant/project-context';
import type { ChatBotConfig, Chatbot, ChatbotRequest } from './types';
import sverlinAssistantBot from './sverlin-assistant';
import htmlAssistantBot, { type HtmlAssistantOutput } from './html-assistant';
import type { VisualizationMode } from '$lib/shared/presentations';

/** Combine a bot definition with a provider adapter into an executable chatbot. */
export function createChatbot<Project, Output extends { reply: string }>(
  config: ChatBotConfig<Project, Output>,
  adapter: ChatAdapter
): Chatbot<Project, Output> {
  const preparePrompt = async (request: ChatbotRequest<Project>) => ({
    messages: request.messages,
    initialPrompt: config.initialPrompt,
    context: await config.buildContext(request),
    parameters: config.parameters,
    responseFormat: config.responseFormat
  });
  const generatePrepared = async (prompt: Awaited<ReturnType<typeof preparePrompt>>) => {
    const result = await adapter.generateReply(prompt);
    let output: Output;
    try {
      output = config.parseOutput(result.output);
    } catch (cause) {
      throw new InvalidChatbotResponseError(
        cause instanceof Error ? cause.message : 'The chatbot returned an invalid response.',
        result.providerResponse
      );
    }
    return {
      ...output,
      providerResponse: result.providerResponse,
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
  } satisfies Chatbot<Project, Output>;
}

const sverlinChatbot = createChatbot(sverlinAssistantBot, openAIAdapter);
const configuredChatbots: Record<string, Chatbot<AiProjectContext>> = {
  [sverlinAssistantBot.id]: sverlinChatbot,
  // Keep existing ignored deployment/local environments working during the rename.
  'ai-assistant': sverlinChatbot
};

const htmlChatbot: Chatbot<AiProjectContext, HtmlAssistantOutput> = createChatbot(
  htmlAssistantBot,
  openAIAdapter
);

/** Return the chatbot selected by server configuration. */
export function getChatbot(): Chatbot<AiProjectContext> {
  const configured = process.env.CHATBOT_CONFIG?.trim() || sverlinAssistantBot.id;
  const chatbot = configuredChatbots[configured];

  if (!chatbot) {
    throw new Error(`Unknown chatbot configuration: ${configured}`);
  }

  return chatbot;
}

/** Return the direct-HTML visualization authoring bot. */
export function getHtmlChatbot(): Chatbot<AiProjectContext, HtmlAssistantOutput> {
  return htmlChatbot;
}

/** Return participant-facing identity and guidance owned by the selected assistant. */
export function assistantIntroduction(mode: VisualizationMode): {
  botId: string;
  text: string;
} {
  const config = mode === 'html' ? htmlAssistantBot : sverlinAssistantBot;
  return { botId: config.id, text: config.participantIntroduction };
}
