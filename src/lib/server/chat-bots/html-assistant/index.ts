/** Direct static-HTML visualization authoring configuration. */

import * as v from 'valibot';

import { htmlFramesManifestSchema, type HtmlFramesManifest } from '$lib/shared/presentations';

import type { AiProjectContext } from '../sverlin-assistant/project-context';
import type { ChatBotConfig } from '../types';

export type HtmlAssistantOutput = {
  reply: string;
  manifest?: HtmlFramesManifest;
};

export default {
  id: 'html-assistant',
  participantIntroduction:
    'Tell me what algorithm or program you would like to visualize—for example, sorting a list, traversing a graph, updating a data structure, or evaluating an expression. I can create a visualization and refine it with you through this conversation.',
  initialPrompt:
    'You are Sverlin’s direct HTML visualization designer. Respond to the user as a conversational design assistant. When their request changes or creates the visualization, return one complete version-one sverlin-html-frames manifest; otherwise return null for manifest. Each frame is a complete static HTML fragment with its own inline CSS. Use semantic HTML and safe inline SVG where useful. Never emit JavaScript, event handlers, forms, controls, nested frames, external URLs, remote resources, @import, or navigation. Treat the supplied project history and current artifact as authoritative. Keep the reply brief.',
  buildContext: ({ project }) => ({ project }),
  parameters: {
    model: 'gpt-5.6-luna',
    reasoningEffort: 'low',
    // One static manifest needs materially less output than the former four-candidate batch.
    maxOutputTokens: 8000
  },
  responseFormat: {
    name: 'html_visualization_turn',
    strict: true,
    schema: {
      type: 'object',
      additionalProperties: false,
      properties: {
        reply: { type: 'string' },
        manifest: {
          anyOf: [
            { type: 'null' },
            {
              type: 'object',
              additionalProperties: false,
              properties: {
                format: { type: 'string', enum: ['sverlin-html-frames'] },
                version: { type: 'integer', enum: [1] },
                frames: {
                  type: 'array',
                  minItems: 1,
                  items: {
                    type: 'object',
                    additionalProperties: false,
                    properties: { label: { type: 'string' }, html: { type: 'string' } },
                    required: ['label', 'html']
                  }
                }
              },
              required: ['format', 'version', 'frames']
            }
          ]
        }
      },
      required: ['reply', 'manifest']
    }
  },
  parseOutput(value) {
    const output = value as { reply?: unknown; manifest?: unknown };
    if (
      typeof output?.reply !== 'string' ||
      !('manifest' in output) ||
      (output.manifest !== null && typeof output.manifest !== 'object')
    ) {
      throw new Error('The HTML assistant returned an invalid structured response.');
    }
    return {
      reply: output.reply,
      ...(output.manifest === null
        ? {}
        : { manifest: v.parse(htmlFramesManifestSchema, output.manifest) })
    };
  }
} satisfies ChatBotConfig<AiProjectContext, HtmlAssistantOutput>;
