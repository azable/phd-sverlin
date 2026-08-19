import type { ArtifactContext } from '$lib/artifacts/types';
import type { ChatMessage } from '$lib/chat/types';

export type ChatContextInput = {
  messages: ChatMessage[];
  artifact: ArtifactContext;
};

/** Provider-neutral context assembled by a chat bot definition. */
export type ChatContext = Record<string, unknown>;

export type ChatBotParameters = {
  model: string;
  maxOutputTokens?: number;
  reasoningEffort?: 'none' | 'low' | 'medium' | 'high' | 'xhigh' | 'max';
  temperature?: number;
};

export type ChatResponseFormat = {
  name: string;
  schema: Record<string, unknown>;
  strict?: boolean;
};

export type ChatBotConfig = {
  id: string;
  initialPrompt: string;
  buildContext: (input: ChatContextInput) => ChatContext;
  parameters: ChatBotParameters;
  responseFormat: ChatResponseFormat;
};

export type ChatbotRequest = {
  messages: ChatMessage[];
  artifact: ArtifactContext;
};

export type ChatbotResult = {
  reply: string;
  sourceArtifactContent?: string;
};

export type { ChatAdapter, ChatAdapterResult } from '$lib/server/chat-adapters/types';

export interface Chatbot {
  readonly id: string;
  readonly config: ChatBotConfig;
  generateReply(request: ChatbotRequest): Promise<ChatbotResult>;
}
