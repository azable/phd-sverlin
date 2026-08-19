/**
 * Compatibility exports for callers that still import the old OpenAI module.
 * The implementation now lives behind the provider adapter boundary.
 */
export {
  ChatContextOverflowError,
  OpenAIConfigurationError,
  generateOpenAIReply,
  openAIAdapter
} from './chat-adapters/openai';
