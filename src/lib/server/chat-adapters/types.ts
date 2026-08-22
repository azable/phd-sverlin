/**
 * Provider-neutral interfaces implemented by chat API adapters.
 *
 * @packageDocumentation
 */

import type {
  ChatContext,
  ChatBotParameters,
  ConversationMessage,
  ChatResponseFormat
} from '$lib/server/chat-bots/types';

/** Fully prepared request accepted by a provider adapter. */
export type ChatAdapterRequest = {
  messages: ConversationMessage[];
  initialPrompt: string;
  context: ChatContext;
  parameters: ChatBotParameters;
  responseFormat: ChatResponseFormat;
};

/** Provider-neutral result returned after structured response parsing. */
export type ChatAdapterResult = {
  reply: string;
  sourceArtifactContent?: string;
  providerResponse?: unknown;
  generation?: {
    model?: string;
    responseId?: string;
    usage?: Record<string, number>;
  };
};

/** Adapter capable of generating one structured chatbot response. */
export interface ChatAdapter {
  /** Stable adapter identifier recorded in project history. */
  readonly id: string;
  /** Submit a prepared request and normalize the provider response. */
  generateReply(request: ChatAdapterRequest): Promise<ChatAdapterResult>;
}
