import type { ChatBotConfig } from '../types';

export default {
  id: 'ai-assistant',
  initialPrompt:
    'Answer the user. If they request a DSL change, return the complete updated compile/app/DSL/Main.hs source in sourceArtifactContent; otherwise return null for that field. Treat the artifact context as authoritative and do not invent omitted revisions.',
  buildContext: ({ artifact }) => ({
    artifact
  }),
  parameters: {
    model: 'gpt-5.6',
    reasoningEffort: 'medium',
    maxOutputTokens: 4096
  },
  responseFormat: {
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
} satisfies ChatBotConfig;
