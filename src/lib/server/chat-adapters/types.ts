import type {
  ChatBotConfig,
  ChatContext,
  ChatBotParameters,
  ChatResponseFormat
} from '$lib/server/chat-bots/types';
import type { ChatMessage } from '$lib/chat/types';

export type ChatAdapterRequest = {
  messages: ChatMessage[];
  initialPrompt: ChatBotConfig['initialPrompt'];
  context: ChatContext;
  parameters: ChatBotParameters;
  responseFormat: ChatResponseFormat;
};

export type ChatAdapterResult = {
  reply: string;
  sourceArtifactContent?: string;
};

export interface ChatAdapter {
  readonly id: string;
  generateReply(request: ChatAdapterRequest): Promise<ChatAdapterResult>;
}
