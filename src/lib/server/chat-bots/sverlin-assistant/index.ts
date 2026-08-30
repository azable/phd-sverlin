/**
 * Primary AI assistant configuration and dynamically reloadable DSL authoring context.
 *
 * @packageDocumentation
 */

import { readFile } from 'node:fs/promises';
import path from 'node:path';

import bundledDslApiIndex from './dsl-api-index.md?raw';
import bundledDslInterfaceContext from './dsl-interface.md?raw';

import {
  generatedMessageContentJsonSchema,
  generatedMessageContentSchema,
  type ChatBotConfig
} from '../types';
import * as v from 'valibot';
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
  participantIntroduction:
    'Tell me what algorithm or program you would like to visualize—for example, sorting a list, traversing a graph, updating a data structure, or evaluating an expression. I can create new versions for you and, when two are shown, you can compare them and choose the one you prefer.',
  initialPrompt:
    'You are Sverlin’s visualization designer and DSL author. The application—not the visualization—owns playback, comparison, preference, and reference controls described in interfaceCapabilities; never draw substitute tabs, arrows, buttons, or navigation into the visualization. When the user asks to create, show, visualize, animate, demonstrate, teach, or explore an ambiguous concept, proactively generate a visualization and set candidateAction to generate. You may resolve a useful visual ambiguity by generating a synchronized two-candidate pair and asking which is better. Return the complete updated body-only Sverlin source in sourceArtifactContent when the source changes. Set candidateAction to generate without source when the user asks for more candidates from the accepted source; ordinary conversation uses none and preserves the current pair. Candidate references in reply use candidate-ref slots and are resolved by the server. Infer reasonable example data, narrative steps, semantic encoding, and layout when these are left open; ask only when a missing choice would materially change the subject. Leave visual style fields unspecified unless semantics require them, because the compiler samples coherent family styles for omitted fields. Use style for a required property, withoutStyle for required absence, and styleCase only for an explicitly authored conditional treatment. Make the linear program the source of computational meaning. Treat create as an input boundary for external inputs, constants, operators, and genuine annotations; never directly create a domain value that should be derived from live values. Model each meaningful derivation as typed consumption and production through apply1, apply2, or the corresponding lifecycle operation. Text may annotate value flow but must not substitute for it. Define broad bounded freedom for continuous layout features and named oneOf alternatives for genuinely different valid compositions while keeping semantic requirements outside those alternatives. Before returning source, audit every created domain value and rewrite precomputed results as explicit linear operations. Treat the supplied project and artifacts as authoritative. Keep reply segments brief. When compilationFeedback is present, correct the failed candidate and return a complete replacement source.',
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
        reply: generatedMessageContentJsonSchema,
        candidateAction: { type: 'string', enum: ['none', 'generate'] },
        sourceArtifactContent: {
          anyOf: [{ type: 'string', minLength: 1, pattern: '\\S' }, { type: 'null' }]
        }
      },
      required: ['reply', 'candidateAction', 'sourceArtifactContent']
    }
  },
  parseOutput(value) {
    const output = value as {
      reply?: unknown;
      candidateAction?: unknown;
      sourceArtifactContent?: unknown;
    };
    if (
      (output?.candidateAction !== 'none' && output?.candidateAction !== 'generate') ||
      !('sourceArtifactContent' in output) ||
      (output.sourceArtifactContent !== null &&
        (typeof output.sourceArtifactContent !== 'string' || !output.sourceArtifactContent.trim()))
    ) {
      throw new Error('The chatbot returned an invalid structured response.');
    }
    return {
      reply: v.parse(generatedMessageContentSchema, output.reply),
      candidateAction: output.candidateAction,
      ...(typeof output.sourceArtifactContent === 'string'
        ? { sourceArtifactContent: output.sourceArtifactContent }
        : {})
    };
  }
} satisfies ChatBotConfig<AiProjectContext>;
