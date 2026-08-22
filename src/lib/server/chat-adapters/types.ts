import type {
  ChatBotConfig,
  ChatContext,
  ChatBotParameters,
  ConversationMessage,
  ChatResponseFormat
} from '$lib/server/chat-bots/types';

export type ChatAdapterRequest = {
  messages: ConversationMessage[];
  initialPrompt: ChatBotConfig['initialPrompt'];
  context: ChatContext;
  parameters: ChatBotParameters;
  responseFormat: ChatResponseFormat;
};

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

export interface ChatAdapter {
  readonly id: string;
  generateReply(request: ChatAdapterRequest): Promise<ChatAdapterResult>;
}
