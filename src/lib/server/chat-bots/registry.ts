/**
 * Assembly and runtime selection of configured chatbots.
 *
 * @packageDocumentation
 */

import { e2eChatAdapter, e2eChatAdapterEnabled } from '$lib/server/chat-adapters/e2e';
import { openAIAdapter } from '$lib/server/chat-adapters/openai';
import { assistantMode, type AssistantId } from '$lib/shared/assistants';

import type { ChatAdapter } from '$lib/server/chat-adapters/types';
import { InvalidChatbotResponseError } from '$lib/server/chat-adapters/types';
import type { AiProjectContext } from './sverlin-assistant/project-context';
import type { ChatBotConfig, Chatbot, ChatbotRequest, GeneratedMessageContent } from './types';
import sverlinAssistantBot from './sverlin-assistant';
import htmlAssistantBot, { type HtmlAssistantOutput } from './html-assistant';

/** Combine a bot definition with a provider adapter into an executable chatbot. */
export function createChatbot<Project, Output extends { reply: GeneratedMessageContent }>(
  config: ChatBotConfig<Project, Output>,
  adapter: ChatAdapter
): Chatbot<Project, Output> {
  const preparePrompt = async (request: ChatbotRequest<Project>) => {
    const profile = config.attemptProfiles[request.attempt - 1];
    if (!Number.isSafeInteger(request.attempt) || request.attempt < 1 || !profile) {
      throw new Error(`Chatbot attempt ${request.attempt} is outside the configured ladder.`);
    }
    const attempt = { number: request.attempt, purpose: profile.purpose };
    return {
      messages: request.messages,
      initialPrompt: config.initialPrompt,
      context: await config.buildContext({ ...request, attempt }),
      attempt,
      parameters: profile.parameters,
      responseFormat: config.responseFormat
    };
  };
  const generatePrepared = async (
    prompt: Awaited<ReturnType<typeof preparePrompt>>,
    options?: { signal?: AbortSignal }
  ) => {
    const result = await adapter.generateReply({ ...prompt, signal: options?.signal });
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
    generatePrepared,
    requestTimeoutMs: () => adapter.requestTimeoutMs?.() ?? 0
  } satisfies Chatbot<Project, Output>;
}

const configuredAdapter = e2eChatAdapterEnabled() ? e2eChatAdapter : openAIAdapter;
const sverlinChatbot = createChatbot(sverlinAssistantBot, configuredAdapter);
const configuredChatbots: Partial<Record<AssistantId, Chatbot<AiProjectContext>>> = {
  [sverlinAssistantBot.id]: sverlinChatbot
};

const htmlChatbot: Chatbot<AiProjectContext, HtmlAssistantOutput> = createChatbot(
  htmlAssistantBot,
  configuredAdapter
);

/** Return the Sverlin-source assistant recorded by a project. */
export function getChatbot(assistantId: AssistantId): Chatbot<AiProjectContext> {
  const chatbot =
    assistantMode(assistantId) === 'sverlin' ? configuredChatbots[assistantId] : undefined;

  if (!chatbot) {
    throw new Error(`Unknown Sverlin assistant: ${assistantId}`);
  }

  return chatbot;
}

/** Return the HTML assistant recorded by a project. */
export function getHtmlChatbot(
  assistantId: AssistantId
): Chatbot<AiProjectContext, HtmlAssistantOutput> {
  if (assistantId !== htmlAssistantBot.id || assistantMode(assistantId) !== 'html') {
    throw new Error(`Unknown HTML assistant: ${assistantId}`);
  }
  return htmlChatbot;
}

/** Return participant-facing identity and guidance owned by the mode's recorded assistant. */
export function assistantIntroduction(assistantId: AssistantId): {
  botId: string;
  text: string;
} {
  const config = assistantId === 'html-assistant' ? htmlAssistantBot : sverlinAssistantBot;
  return { botId: config.id, text: config.participantIntroduction };
}
