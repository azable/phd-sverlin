import OpenAI from 'openai';
import { env } from '$env/dynamic/private';

import type { Chatbot, ChatbotRequest, ChatbotResult } from './chatbot/types';

const defaultModel = 'gpt-5.6';
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

function serializeArtifactContext(request: ChatbotRequest) {
  const serialized = JSON.stringify(request.artifact);

  if (serialized.length > readMaxContextChars()) throw new ChatContextOverflowError();

  return serialized;
}

export async function generateOpenAIReply(request: ChatbotRequest): Promise<ChatbotResult> {
  const client = new OpenAI({ apiKey: readApiKey() });
  const model = env.OPENAI_MODEL?.trim() || defaultModel;
  const artifactContext = serializeArtifactContext(request);
  const response = await client.responses.create({
    model,
    // Keep the server's artifact/chat audit trail as the source of truth.
    store: false,
    input: [
      {
        role: 'developer',
        content: `Answer the user. If they request a DSL change, return the complete updated compile/app/DSL/Main.hs source in sourceArtifactContent; otherwise return null for that field. The artifact context below contains the current source and the complete ordered revision history. Treat its event stream as authoritative; no revisions have been omitted.\n\nArtifact context:\n\n${artifactContext}`
      },
      ...request.messages
    ],
    text: {
      format: {
        type: 'json_schema',
        name: 'chat_result',
        strict: true,
        schema: {
          type: 'object',
          additionalProperties: false,
          properties: {
            reply: { type: 'string' },
            sourceArtifactContent: {
              anyOf: [{ type: 'string' }, { type: 'null' }]
            }
          },
          required: ['reply', 'sourceArtifactContent']
        }
      }
    }
  });

  try {
    const parsed = JSON.parse(response.output_text) as {
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
    return { reply: response.output_text };
  }
}

export const openAIChatbot: Chatbot = {
  id: 'openai-default',
  generateReply: generateOpenAIReply
};
