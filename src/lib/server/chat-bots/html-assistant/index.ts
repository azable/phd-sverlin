/** Direct static-HTML visualization authoring configuration. */

import * as v from 'valibot';

import { htmlFramesManifestSchema, type HtmlFramesManifest } from '$lib/shared/presentations';

import type { AiProjectContext } from '../sverlin-assistant/project-context';
import {
  generatedMessageContentJsonSchema,
  generatedMessageContentSchema,
  parseRecoveryExplanation,
  recoveryExplanationJsonSchema,
  type ChatBotConfig,
  type GeneratedMessageContent,
  type RecoveryExplanation
} from '../types';
import { visualizationAttemptProfiles } from '../attempt-profiles';
import { visualizationParticipantIntake } from '../participant-intake';

export type HtmlAssistantOutput = {
  reply: GeneratedMessageContent;
  candidates: Array<{ label: string; manifest: HtmlFramesManifest }>;
  recovery?: RecoveryExplanation;
};

export default {
  id: 'html-assistant',
  participantIntake: visualizationParticipantIntake,
  initialPrompt:
    'You are Sverlin’s direct HTML visualization designer. The application—not the visualization—owns playback, Timeline selection, references, comparison, and preference controls described in interfaceCapabilities; never draw substitute tabs, arrows, buttons, or navigation. Treat the participant’s algorithm, audience, learning-outcome, and style intake answers as the authoring brief. Do not infer a visual style from the audience alone. When the participant asks to be given options, return exactly two materially distinct candidates. Otherwise make neutral, necessary design decisions where the participant left details open. Respond conversationally and proactively create candidates when that would clarify the participant’s intent. Return zero, one, or two complete named version-one sverlin-html-frames manifests. When a request is visually ambiguous, prefer two materially distinct candidates and ask which is better. Candidate references in reply use candidate-ref slots and are resolved by the server. Each frame is a complete static HTML fragment with inline CSS. Use semantic HTML and safe inline SVG where useful. Never emit JavaScript, event handlers, forms, controls, nested frames, external URLs, remote resources, @import, or navigation. Treat supplied history and artifacts as authoritative. Ordinary conversation returns an empty candidates array and preserves the current visualization. Keep reply segments brief. Set recovery to null for initial and repair attempts. When attemptContext.purpose is repair, correct the unsafe or invalid candidate described by the latest correction message. When attemptContext.purpose is fallback, preserve the subject and central semantic relationship but reduce elements, frames, layout complexity, alternatives, animation, SVG detail, and decorative styling until the manifest is robust. A fallback must return at least one complete candidate and a recovery object that explains in concise participant-facing language what proved difficult and what was simplified; do not include raw diagnostics or implementation jargon.',
  buildContext: ({ project, attempt }) => ({ project, attemptContext: attempt }),
  attemptProfiles: visualizationAttemptProfiles(14000),
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
        },
        recovery: recoveryExplanationJsonSchema
      },
      required: ['reply', 'candidates', 'recovery']
    }
  },
  parseOutput(value) {
    const output = value as { reply?: unknown; candidates?: unknown; recovery?: unknown };
    if (!Array.isArray(output?.candidates) || output.candidates.length > 2) {
      throw new Error('The HTML assistant returned an invalid structured response.');
    }
    const recovery = parseRecoveryExplanation(output.recovery);
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
      }),
      ...(recovery ? { recovery } : {})
    };
  }
} satisfies ChatBotConfig<AiProjectContext, HtmlAssistantOutput>;
