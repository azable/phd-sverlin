import OpenAI from 'openai';
import { env } from '$env/dynamic/private';

import type { ChatAdapter, ChatAdapterRequest, ChatAdapterResult } from './types';

const defaultMaxContextChars = 500_000;
const defaultRequestTimeoutMs = 180_000;

export class OpenAIConfigurationError extends Error {
  constructor() {
    super('OpenAI is not configured on the server.');
    this.name = 'OpenAIConfigurationError';
  }
}

export class ChatContextOverflowError extends Error {
  constructor() {
    super('The complete project history is too large for the configured chat context.');
    this.name = 'ChatContextOverflowError';
  }
}

export class InvalidChatbotResponseError extends Error {
  readonly providerResponse?: unknown;

  constructor(
    message = 'The chatbot returned an invalid structured response.',
    providerResponse?: unknown
  ) {
    super(message);
    this.name = 'InvalidChatbotResponseError';
    this.providerResponse = providerResponse;
  }
}

function readApiKey() {
  const apiKey = env.OPENAI_API_KEY?.trim();

  if (!apiKey) throw new OpenAIConfigurationError();

  return apiKey;
}

function readMaxContextChars() {
  const configured = Number.parseInt(env.CHATBOT_MAX_CONTEXT_CHARS ?? '', 10);

  return Number.isSafeInteger(configured) && configured > 0 ? configured : defaultMaxContextChars;
}

function readRequestTimeoutMs() {
  const configured = Number.parseInt(env.CHATBOT_REQUEST_TIMEOUT_MS ?? '', 10);
  return Number.isSafeInteger(configured) && configured > 0 ? configured : defaultRequestTimeoutMs;
}

function serializeContext(context: ChatAdapterRequest['context']) {
  const serialized = JSON.stringify(context);

  if (serialized.length > readMaxContextChars()) throw new ChatContextOverflowError();

  return serialized;
}

export function parseResult(outputText: string, providerResponse?: unknown): ChatAdapterResult {
  try {
    const parsed = JSON.parse(outputText) as {
      reply?: unknown;
      sourceArtifactContent?: unknown;
    };

    if (
      typeof parsed.reply !== 'string' ||
      !('sourceArtifactContent' in parsed) ||
      (parsed.sourceArtifactContent !== null && typeof parsed.sourceArtifactContent !== 'string')
    ) {
      throw invalidResponse(providerResponse);
    }

    return {
      reply: parsed.reply,
      sourceArtifactContent:
        typeof parsed.sourceArtifactContent === 'string' ? parsed.sourceArtifactContent : undefined
    };
  } catch (error) {
    if (error instanceof InvalidChatbotResponseError) throw error;
    throw invalidResponse(providerResponse);
  }
}

function invalidResponse(providerResponse?: unknown) {
  const response = providerResponse as
    | {
        status?: unknown;
        incomplete_details?: { reason?: unknown } | null;
        output?: unknown;
      }
    | undefined;
  if (response?.status === 'incomplete') {
    const reason = response.incomplete_details?.reason;
    return new InvalidChatbotResponseError(
      `The chatbot response was incomplete${typeof reason === 'string' ? ` (${reason})` : ''}.`,
      providerResponse
    );
  }
  if (containsRefusal(response?.output)) {
    return new InvalidChatbotResponseError(
      'The chatbot refused the request instead of returning structured output.',
      providerResponse
    );
  }
  return new InvalidChatbotResponseError(
    'The chatbot returned an invalid structured response.',
    providerResponse
  );
}

function containsRefusal(value: unknown): boolean {
  if (Array.isArray(value)) return value.some(containsRefusal);
  if (!value || typeof value !== 'object') return false;
  const record = value as Record<string, unknown>;
  return record.type === 'refusal' || Object.values(record).some(containsRefusal);
}

export async function generateOpenAIReply(request: ChatAdapterRequest): Promise<ChatAdapterResult> {
  const client = new OpenAI({
    apiKey: readApiKey(),
    maxRetries: 0,
    timeout: readRequestTimeoutMs()
  });
  const model = env.OPENAI_MODEL?.trim() || request.parameters.model;
  const context = serializeContext(request.context);
  const response = await client.responses.create({
    model,
    // Keep the server's immutable project Timeline as the source of truth.
    store: false,
    input: [
      {
        role: 'developer',
        content: `${request.initialPrompt}\n\nContext provided by this chat configuration:\n\n${context}`
      },
      ...request.messages
    ],
    max_output_tokens: request.parameters.maxOutputTokens,
    reasoning: request.parameters.reasoningEffort
      ? { effort: request.parameters.reasoningEffort }
      : undefined,
    temperature: request.parameters.temperature,
    text: {
      format: {
        type: 'json_schema',
        name: request.responseFormat.name,
        strict: request.responseFormat.strict ?? true,
        schema: request.responseFormat.schema
      }
    }
  });

  return {
    ...parseResult(response.output_text, response),
    providerResponse: response,
    generation: {
      model: response.model,
      responseId: response.id,
      ...(response.usage
        ? {
            usage: {
              inputTokens: response.usage.input_tokens,
              outputTokens: response.usage.output_tokens,
              totalTokens: response.usage.total_tokens
            }
          }
        : {})
    }
  };
}

export const openAIAdapter: ChatAdapter = {
  id: 'openai-responses',
  generateReply: generateOpenAIReply
};
