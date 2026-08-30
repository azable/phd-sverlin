/**
 * Primary AI assistant configuration and dynamically reloadable DSL authoring context.
 *
 * @packageDocumentation
 */

import { readFile } from 'node:fs/promises';
import path from 'node:path';

import bundledDslApiIndex from './dsl-api-index.md?raw';
import bundledDslInterfaceContext from './dsl-interface.md?raw';

import type { ChatBotConfig } from '../types';
import type { AiProjectContext } from './project-context';

/** Workspace path read on each development request for live prompt updates. */
export const dslInterfacePath = path.resolve(
  process.cwd(),
  'src/lib/server/chat-bots/sverlin-assistant/dsl-interface.md'
);

/** Generated API index path read on each development request for live updates. */
export const dslApiIndexPath = path.resolve(
  process.cwd(),
  'src/lib/server/chat-bots/sverlin-assistant/dsl-api-index.md'
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

/** Read the source-derived API index, falling back to its bundled build copy. */
export async function loadDslApiIndex(readPrompt: PromptReader = readFile): Promise<string> {
  try {
    return await readPrompt(dslApiIndexPath, 'utf8');
  } catch {
    return bundledDslApiIndex;
  }
}

/** Primary visualization-authoring chatbot definition. */
export default {
  id: 'sverlin-assistant',
  initialPrompt:
    'You are Sverlin’s visualization designer and DSL author. When the user asks to create, show, visualize, animate, demonstrate, or teach a concept, data structure, process, or algorithm, turn their intent into a coherent original visualization and return the complete updated body-only Sverlin source in sourceArtifactContent. Infer reasonable example data, narrative steps, semantic encoding, and layout when these are left open; ask only when a missing choice would materially change the subject. Leave visual style fields unspecified unless the user or the visualization’s semantics require them, because the compiler samples coherent family styles for omitted fields. Use style for a required property, withoutStyle for required absence, and styleCase only for an explicitly authored conditional treatment. Make the linear program the source of computational meaning. Treat create as an input boundary for external inputs, constants, operators, and genuine annotations; never directly create a domain value that should be derived from live values. Model each meaningful derivation as typed consumption and production through apply1, apply2, or the corresponding lifecycle operation. Text may annotate that value flow but must not substitute for it. Define broad bounded freedom for continuous layout features and use named oneOf alternatives for genuinely different valid compositions; keep semantic requirements outside those alternatives so every sampled branch preserves meaning. Before returning source, audit every created domain value and rewrite any precomputed result as an explicit linear operation. For conversation, explanation, review, or planning that does not request a visualization change, return null for sourceArtifactContent. Treat the supplied project and its current artifacts as authoritative and do not invent omitted events. Keep the reply brief and describe what the visualization communicates. When compilationFeedback is present, correct the failed candidate from those diagnostics and return a complete replacement source; do not claim success without supplying corrected source.',
  buildContext: async ({ project, compilationFeedback }) => {
    const [dslInterface, dslApiIndex] = await Promise.all([
      loadDslInterfaceContext(),
      loadDslApiIndex()
    ]);
    return {
      dslInterface,
      dslApiIndex,
      project,
      ...(compilationFeedback ? { compilationFeedback } : {})
    };
  },
  parameters: {
    model: 'gpt-5.6-luna',
    reasoningEffort: 'low',
    maxOutputTokens: 12000
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
  },
  parseOutput(value) {
    const output = value as { reply?: unknown; sourceArtifactContent?: unknown };
    if (
      typeof output?.reply !== 'string' ||
      !('sourceArtifactContent' in output) ||
      (output.sourceArtifactContent !== null && typeof output.sourceArtifactContent !== 'string')
    ) {
      throw new Error('The chatbot returned an invalid structured response.');
    }
    return {
      reply: output.reply,
      ...(typeof output.sourceArtifactContent === 'string'
        ? { sourceArtifactContent: output.sourceArtifactContent }
        : {})
    };
  }
} satisfies ChatBotConfig<AiProjectContext>;
