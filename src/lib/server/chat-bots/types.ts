import type { CompilerDiagnostic } from '$lib/visualization/types';

export type ConversationMessage = {
  role: 'user' | 'assistant';
  content: string;
};

export type CompilationFeedback = {
  attempt: number;
  compilationEventId: string;
  failedSource: string;
  assistantReply: string;
  diagnostics: CompilerDiagnostic[];
};

export type ChatContextInput = {
  messages: ConversationMessage[];
  project: Record<string, unknown>;
  compilationFeedback?: CompilationFeedback;
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
  buildContext: (input: ChatContextInput) => ChatContext | Promise<ChatContext>;
  parameters: ChatBotParameters;
  responseFormat: ChatResponseFormat;
};

export type ChatbotPrompt = {
  initialPrompt: string;
  messages: ConversationMessage[];
  context: ChatContext;
  parameters: ChatBotParameters;
  responseFormat: ChatResponseFormat;
};

export type ChatbotRequest = {
  messages: ConversationMessage[];
  project: Record<string, unknown>;
  compilationFeedback?: CompilationFeedback;
};

export type ChatbotResult = {
  reply: string;
  sourceArtifactContent?: string;
  providerResponse?: unknown;
  prompt: ChatbotPrompt;
  generation: {
    botId: string;
    adapterId: string;
    model?: string;
    responseId?: string;
    usage?: Record<string, number>;
  };
};

export type { ChatAdapter, ChatAdapterResult } from '$lib/server/chat-adapters/types';

export interface Chatbot {
  readonly id: string;
  readonly config: ChatBotConfig;
  preparePrompt(request: ChatbotRequest): Promise<ChatbotPrompt>;
  generatePrepared(prompt: ChatbotPrompt): Promise<ChatbotResult>;
}
