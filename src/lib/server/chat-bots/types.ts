/**
 * Provider-independent chatbot configuration and execution contracts.
 *
 * @packageDocumentation
 */

import type { CompilerDiagnostic } from '$lib/visualization/types';

/** User or assistant message retained as conversational context. */
export type ConversationMessage = {
  role: 'user' | 'assistant';
  content: string;
};

/** Failed generated source and diagnostics supplied to one repair attempt. */
export type CompilationFeedback = {
  attempt: number;
  compilationEventId: number;
  failedSource: string;
  assistantReply: string;
  diagnostics: CompilerDiagnostic[];
};

/** Inputs from which a bot definition builds provider context. */
export type ChatContextInput = {
  messages: ConversationMessage[];
  project: Record<string, unknown>;
  compilationFeedback?: CompilationFeedback;
};

/** Provider-neutral context assembled by a chat bot definition. */
export type ChatContext = Record<string, unknown>;

/** Model and sampling parameters selected by a chatbot definition. */
export type ChatBotParameters = {
  model: string;
  maxOutputTokens?: number;
  reasoningEffort?: 'none' | 'low' | 'medium' | 'high' | 'xhigh' | 'max';
  temperature?: number;
};

/** JSON Schema response contract requested from a provider. */
export type ChatResponseFormat = {
  name: string;
  schema: Record<string, unknown>;
  strict?: boolean;
};

/** Static behavior and context builder for one chatbot. */
export type ChatBotConfig = {
  id: string;
  initialPrompt: string;
  buildContext: (input: ChatContextInput) => ChatContext | Promise<ChatContext>;
  parameters: ChatBotParameters;
  responseFormat: ChatResponseFormat;
};

/** Complete provider-neutral prompt prepared for an adapter. */
export type ChatbotPrompt = {
  initialPrompt: string;
  messages: ConversationMessage[];
  context: ChatContext;
  parameters: ChatBotParameters;
  responseFormat: ChatResponseFormat;
};

/** Project conversation inputs accepted by a configured chatbot. */
export type ChatbotRequest = {
  messages: ConversationMessage[];
  project: Record<string, unknown>;
  compilationFeedback?: CompilationFeedback;
};

/** Parsed chatbot output enriched with prompt and generation provenance. */
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

/** Adapter contracts re-exported for chatbot consumers. */
export type { ChatAdapter, ChatAdapterResult } from '$lib/server/chat-adapters/types';

/** Executable chatbot assembled from a bot configuration and provider adapter. */
export interface Chatbot {
  /** Stable bot identifier recorded in project events. */
  readonly id: string;
  /** Static configuration used by this bot. */
  readonly config: ChatBotConfig;
  /** Assemble a provider-neutral prompt from project inputs. */
  preparePrompt(request: ChatbotRequest): Promise<ChatbotPrompt>;
  /** Generate a response from an already prepared, recordable prompt. */
  generatePrepared(prompt: ChatbotPrompt): Promise<ChatbotResult>;
}
