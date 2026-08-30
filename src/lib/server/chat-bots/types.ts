/**
 * Provider-independent chatbot configuration and execution contracts.
 *
 * @packageDocumentation
 */

import type { CompilerDiagnostic } from '$lib/shared/projects/events/values';
import * as v from 'valibot';

import { presentationIdSchema } from '$lib/shared/presentations';
import { textSchema } from '$lib/shared/projects/events/values';

/** User or assistant message retained as conversational context. */
export type ConversationMessage = {
  role: 'user' | 'assistant';
  content: string;
};

/** Model-authored reply segment before generated candidate slots have stable IDs. */
export const generatedMessageSegmentSchema = v.variant('type', [
  v.strictObject({ type: v.literal('markdown'), text: textSchema }),
  v.strictObject({ type: v.literal('presentation-ref'), presentationId: presentationIdSchema }),
  v.strictObject({ type: v.literal('candidate-ref'), slot: v.picklist([0, 1]) })
]);

export const generatedMessageContentSchema = v.pipe(
  v.array(generatedMessageSegmentSchema),
  v.minLength(1)
);

export type GeneratedMessageContent = v.InferOutput<typeof generatedMessageContentSchema>;

/** JSON Schema embedded in both assistant response contracts. */
export const generatedMessageContentJsonSchema = {
  type: 'array',
  minItems: 1,
  items: {
    oneOf: [
      {
        type: 'object',
        additionalProperties: false,
        properties: { type: { type: 'string', enum: ['markdown'] }, text: { type: 'string' } },
        required: ['type', 'text']
      },
      {
        type: 'object',
        additionalProperties: false,
        properties: {
          type: { type: 'string', enum: ['presentation-ref'] },
          presentationId: { type: 'string', format: 'uuid' }
        },
        required: ['type', 'presentationId']
      },
      {
        type: 'object',
        additionalProperties: false,
        properties: {
          type: { type: 'string', enum: ['candidate-ref'] },
          slot: { type: 'integer', enum: [0, 1] }
        },
        required: ['type', 'slot']
      }
    ]
  }
} as const;

/** Failed generated source and diagnostics supplied to one repair attempt. */
export type CompilationFeedback = {
  attempt: number;
  compilationEventId: number;
  failedSource: string;
  assistantReply: string;
  diagnostics: CompilerDiagnostic[];
};

/** Inputs from which a bot definition builds provider context. */
export type ChatContextInput<Project> = {
  messages: ConversationMessage[];
  project: Project;
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
export type SourceArtifactChatOutput = {
  reply: GeneratedMessageContent;
  candidateAction: 'none' | 'generate';
  sourceArtifactContent?: string;
};

export type ChatBotConfig<
  Project,
  Output extends { reply: GeneratedMessageContent } = SourceArtifactChatOutput
> = {
  id: string;
  participantIntroduction: string;
  initialPrompt: string;
  buildContext: (input: ChatContextInput<Project>) => ChatContext | Promise<ChatContext>;
  parameters: ChatBotParameters;
  responseFormat: ChatResponseFormat;
  parseOutput: (value: unknown) => Output;
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
export type ChatbotRequest<Project> = {
  messages: ConversationMessage[];
  project: Project;
  compilationFeedback?: CompilationFeedback;
};

/** Parsed chatbot output enriched with prompt and generation provenance. */
export type ChatbotResult<
  Output extends { reply: GeneratedMessageContent } = SourceArtifactChatOutput
> = Output & {
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
export interface Chatbot<
  Project,
  Output extends { reply: GeneratedMessageContent } = SourceArtifactChatOutput
> {
  /** Stable bot identifier recorded in project events. */
  readonly id: string;
  /** Static configuration used by this bot. */
  readonly config: ChatBotConfig<Project, Output>;
  /** Assemble a provider-neutral prompt from project inputs. */
  preparePrompt(request: ChatbotRequest<Project>): Promise<ChatbotPrompt>;
  /** Generate a response from an already prepared, recordable prompt. */
  generatePrepared(prompt: ChatbotPrompt): Promise<ChatbotResult<Output>>;
}
