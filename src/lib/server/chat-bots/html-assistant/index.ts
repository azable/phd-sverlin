/** Direct static-HTML visualization authoring configuration. */

import * as v from 'valibot';

import { htmlFramesManifestSchema, type HtmlFramesManifest } from '$lib/shared/presentations';

import type { AiProjectContext } from '../sverlin-assistant/project-context';
import {
  generatedMessageContentJsonSchema,
  generatedMessageContentSchema,
  type ChatBotConfig,
  type GeneratedMessageContent
} from '../types';

export type HtmlAssistantOutput = {
  reply: GeneratedMessageContent;
  candidates: Array<{ label: string; manifest: HtmlFramesManifest }>;
};

export default {
  id: 'html-assistant',
  participantIntroduction:
    'Tell me what algorithm or program you would like to visualize—for example, sorting a list, traversing a graph, updating a data structure, or evaluating an expression. I can create a visualization and refine it with you through this conversation.',
  initialPrompt:
    'You are Sverlin’s direct HTML visualization designer. The application—not the visualization—owns playback, Timeline selection, references, comparison, and preference controls described in interfaceCapabilities; never draw substitute tabs, arrows, buttons, or navigation. Respond conversationally and proactively create candidates when that would clarify the participant’s intent. Return zero, one, or two complete named version-one sverlin-html-frames manifests. When a request is visually ambiguous, prefer two materially distinct candidates and ask which is better. Candidate references in reply use candidate-ref slots and are resolved by the server. Each frame is a complete static HTML fragment with inline CSS. Use semantic HTML and safe inline SVG where useful. Never emit JavaScript, event handlers, forms, controls, nested frames, external URLs, remote resources, @import, or navigation. Treat supplied history and artifacts as authoritative. Ordinary conversation returns an empty candidates array and preserves the current visualization. Keep reply segments brief.',
  buildContext: ({ project }) => ({ project }),
  parameters: {
    model: 'gpt-5.6-luna',
    reasoningEffort: 'low',
    maxOutputTokens: 14000
  },
  responseFormat: {
    name: 'html_visualization_turn',
    strict: true,
    schema: {
      type: 'object',
      additionalProperties: false,
      properties: {
        reply: generatedMessageContentJsonSchema,
        candidates: {
          type: 'array',
          minItems: 0,
          maxItems: 2,
          items: {
            type: 'object',
            additionalProperties: false,
            properties: {
              label: { type: 'string', minLength: 1, pattern: '\\S' },
              manifest: {
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
                      properties: {
                        label: { type: 'string', minLength: 1 },
                        html: { type: 'string', minLength: 1 }
                      },
                      required: ['label', 'html']
                    }
                  }
                },
                required: ['format', 'version', 'frames']
              }
            },
            required: ['label', 'manifest']
          }
        }
      },
      required: ['reply', 'candidates']
    }
  },
  parseOutput(value) {
    const output = value as { reply?: unknown; candidates?: unknown };
    if (!Array.isArray(output?.candidates) || output.candidates.length > 2) {
      throw new Error('The HTML assistant returned an invalid structured response.');
    }
    return {
      reply: v.parse(generatedMessageContentSchema, output.reply),
      candidates: output.candidates.map((candidate) => {
        const value = candidate as { label?: unknown; manifest?: unknown };
        if (typeof value.label !== 'string' || !value.label.trim()) {
          throw new Error('Each HTML candidate needs a non-empty label.');
        }
        return {
          label: value.label.trim(),
          manifest: v.parse(htmlFramesManifestSchema, value.manifest)
        };
      })
    };
  }
} satisfies ChatBotConfig<AiProjectContext, HtmlAssistantOutput>;
