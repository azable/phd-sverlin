/** Free-form HTML/JS visualization assistant; never used by the static-HTML study condition. */

import * as v from 'valibot';

import type { AiProjectContext } from '$lib/server/chat-bots/project-context';
import { visualizationAttemptProfiles } from '$lib/server/chat-bots/attempt-profiles';
import { visualizationParticipantIntake } from '$lib/server/chat-bots/participant-intake';
import {
  generatedMessageContentJsonSchema,
  generatedMessageContentSchema,
  parseRecoveryExplanation,
  recoveryExplanationJsonSchema,
  type ChatBotConfig,
  type GeneratedMessageContent,
  type RecoveryExplanation
} from '$lib/server/chat-bots/types';

import { htmlJsSourceSchema, type HtmlJsSource } from './compile.server';

export type HtmlJsAssistantOutput = {
  reply: GeneratedMessageContent;
  candidates: Array<{ label: string; manifest: HtmlJsSource }>;
  recovery?: RecoveryExplanation;
};

export default {
  id: 'html-js-assistant',
  participantIntake: visualizationParticipantIntake,
  initialPrompt: [
    'You are a free-form HTML and JavaScript visualization designer.',
    'Return zero, one, or two complete candidates. Each candidate has a format html-js-v1 manifest containing self-contained HTML and separately authored JavaScript. The application owns playback and comparison controls; do not recreate them.',
    'Use semantic HTML, inline CSS and SVG, and local browser behavior. Do not include external resources, imports, frames, forms, navigation or network calls. Never include a script tag in html; put JavaScript only in javascript.',
    'Treat the latest project artifact and user interaction as authoritative. Candidate references use candidate-ref segments; conversation without a change returns an empty candidates array.',
    'If a candidate fails validation, return a corrected complete candidate. On fallback simplify the design and explain what proved difficult and was reduced in recovery; otherwise set recovery to null.'
  ].join(' '),
  buildContext: ({ project, attempt }) => ({ project, attemptContext: attempt }),
  attemptProfiles: visualizationAttemptProfiles(14000),
  responseFormat: {
    name: 'html_js_visualization_turn',
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
              label: { type: 'string', minLength: 1 },
              manifest: {
                type: 'object',
                additionalProperties: false,
                properties: {
                  format: { type: 'string', enum: ['html-js-v1'] },
                  html: { type: 'string', minLength: 1 },
                  javascript: { type: 'string' }
                },
                required: ['format', 'html', 'javascript']
              }
            },
            required: ['label', 'manifest']
          }
        },
        recovery: recoveryExplanationJsonSchema
      },
      required: ['reply', 'candidates', 'recovery']
    }
  },
  parseOutput(value) {
    const output = value as { reply?: unknown; candidates?: unknown; recovery?: unknown };
    if (!Array.isArray(output?.candidates) || output.candidates.length > 2) {
      throw new Error('The HTML/JS assistant returned an invalid structured response.');
    }
    const recovery = parseRecoveryExplanation(output.recovery);
    return {
      reply: v.parse(generatedMessageContentSchema, output.reply),
      candidates: output.candidates.map((candidate) => {
        const entry = candidate as { label?: unknown; manifest?: unknown };
        if (typeof entry.label !== 'string' || !entry.label.trim())
          throw new Error('Each candidate needs a label.');
        return { label: entry.label.trim(), manifest: v.parse(htmlJsSourceSchema, entry.manifest) };
      }),
      ...(recovery ? { recovery } : {})
    };
  }
} satisfies ChatBotConfig<AiProjectContext, HtmlJsAssistantOutput>;
