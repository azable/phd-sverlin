import OpenAI from 'openai';
import { env } from '$env/dynamic/private';

import type { ChatAdapter, ChatAdapterRequest, ChatAdapterResult } from './types';

const defaultMaxContextChars = 500_000;

export class OpenAIConfigurationError extends Error {
  constructor() {
    super('OpenAI is not configured on the server.');
    this.name = 'OpenAIConfigurationError';
  }
}

export class ChatContextOverflowError extends Error {
  constructor() {
    super('The complete artifact history is too large for the configured chat context.');
    this.name = 'ChatContextOverflowError';
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

function serializeContext(context: ChatAdapterRequest['context']) {
  const serialized = JSON.stringify(context);

  if (serialized.length > readMaxContextChars()) throw new ChatContextOverflowError();

  return serialized;
}

function parseResult(outputText: string): ChatAdapterResult {
  try {
    const parsed = JSON.parse(outputText) as {
      reply?: unknown;
      sourceArtifactContent?: unknown;
    };

    if (typeof parsed.reply !== 'string') throw new Error('Invalid chatbot response.');

    return {
      reply: parsed.reply,
      sourceArtifactContent:
        typeof parsed.sourceArtifactContent === 'string' ? parsed.sourceArtifactContent : undefined
    };
  } catch {
    return { reply: outputText };
  }
}

export async function generateOpenAIReply(request: ChatAdapterRequest): Promise<ChatAdapterResult> {
  const client = new OpenAI({ apiKey: readApiKey() });
  const model = env.OPENAI_MODEL?.trim() || request.parameters.model;
  const context = serializeContext(request.context);
  const response = await client.responses.create({
    model,
    // Keep the server's artifact/chat audit trail as the source of truth.
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
    ...parseResult(response.output_text),
    generation: {
      model: response.model,
      responseId: response.id
    }
  };
}

export const openAIAdapter: ChatAdapter = {
  id: 'openai-responses',
  generateReply: generateOpenAIReply
};
