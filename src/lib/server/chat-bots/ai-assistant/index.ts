import { readFile } from 'node:fs/promises';
import path from 'node:path';

import bundledDslInterfaceContext from './dsl-interface.md?raw';

import type { ChatBotConfig } from '../types';

export const dslInterfacePath = path.resolve(
  process.cwd(),
  'src/lib/server/chat-bots/ai-assistant/dsl-interface.md'
);

type PromptReader = (path: string, encoding: BufferEncoding) => Promise<string>;

/** Read on every request so a running development server sees saved prompt edits. */
export async function loadDslInterfaceContext(
  readPrompt: PromptReader = readFile
): Promise<string> {
  try {
    return await readPrompt(dslInterfacePath, 'utf8');
  } catch {
    return bundledDslInterfaceContext;
  }
}

export default {
  id: 'ai-assistant',
  initialPrompt:
    'You are Sverlin’s visualization designer and DSL author. When the user asks to create, show, visualize, animate, demonstrate, or teach a concept, data structure, process, or algorithm, turn their intent into a coherent original visualization and return the complete updated body-only Sverlin source in sourceArtifactContent. Infer reasonable example data, narrative steps, visual encoding, layout, and styling when these are left open; ask only when a missing choice would materially change the subject. For conversation, explanation, review, or planning that does not request a visualization change, return null for sourceArtifactContent. Treat the supplied artifact as authoritative and do not invent omitted revisions. Keep the reply brief and describe what the visualization communicates. When compilationFeedback is present, correct the failed candidate from those diagnostics and return a complete replacement source; do not claim success without supplying corrected source.',
  buildContext: async ({ artifact, compilationFeedback }) => ({
    dslInterface: await loadDslInterfaceContext(),
    artifact,
    ...(compilationFeedback ? { compilationFeedback } : {})
  }),
  parameters: {
    model: 'gpt-5.6-luna',
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
