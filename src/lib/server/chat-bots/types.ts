import type { ArtifactContext } from '$lib/artifacts/types';
import type { ChatMessage } from '$lib/chat/types';
import type { CompilerDiagnostic } from '$lib/visualization/types';

export type CompilationFeedback = {
  attempt: number;
  failureRecordId: string;
  failedSource: string;
  assistantReply: string;
  diagnostics: CompilerDiagnostic[];
};

export type ChatContextInput = {
  messages: ChatMessage[];
  artifact: ArtifactContext;
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
  messages: ChatMessage[];
  context: ChatContext;
  parameters: ChatBotParameters;
  responseFormat: ChatResponseFormat;
};

export type ChatbotRequest = {
  messages: ChatMessage[];
  artifact: ArtifactContext;
  compilationFeedback?: CompilationFeedback;
};

export type ChatbotResult = {
  reply: string;
  sourceArtifactContent?: string;
  prompt: ChatbotPrompt;
  generation: {
    botId: string;
    adapterId: string;
    model?: string;
    responseId?: string;
  };
};

export type { ChatAdapter, ChatAdapterResult } from '$lib/server/chat-adapters/types';

export interface Chatbot {
  readonly id: string;
  readonly config: ChatBotConfig;
  generateReply(request: ChatbotRequest): Promise<ChatbotResult>;
}
