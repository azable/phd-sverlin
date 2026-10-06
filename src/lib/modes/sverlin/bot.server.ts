/** Primary single-component Svelte visualization assistant. */

import {
  generatedMessageContentSchema,
  parseRecoveryExplanation,
  recoveryExplanationJsonSchema,
  retainedMessageContentJsonSchema,
  type ChatBotConfig
} from '$lib/server/chat-bots/types';
import { visualizationAttemptProfiles } from '$lib/server/chat-bots/attempt-profiles';
import { visualizationParticipantIntake } from '$lib/server/chat-bots/participant-intake';
import * as v from 'valibot';
import type { AiProjectContext } from '$lib/server/chat-bots/project-context';

import assistant from './assistant.md?raw';
import guide from './README.md?raw';

/** Prompt text from a Markdown file: its HTML comments are notes for maintainers. */
const promptText = (markdown: string) => markdown.replace(/<!--[\s\S]*?-->\s*/gu, '').trim();
const instructions = promptText(assistant);
export const languageGuide = promptText(guide);

/** Primary visualization-authoring chatbot definition. */
export default {
  id: 'sverlin-assistant',
  participantIntake: visualizationParticipantIntake,
  initialPrompt: [instructions, languageGuide].join('\n\n'),
  buildContext: ({ project, attempt, buildFeedback }) => ({
    project,
    attemptContext: attempt,
    ...(buildFeedback ? { buildFeedback } : {})
  }),
  attemptProfiles: visualizationAttemptProfiles(12000),
  responseFormat: {
    name: 'chat_result',
    strict: true,
    schema: {
      type: 'object',
      additionalProperties: false,
      properties: {
        reply: retainedMessageContentJsonSchema,
        decision: {
          anyOf: [
            {
              type: 'object',
              additionalProperties: false,
              properties: {
                action: { type: 'string', enum: ['revise'] },
                sourceArtifactContent: { type: 'string', minLength: 1, pattern: '\\S' }
              },
              required: ['action', 'sourceArtifactContent']
            },
            {
              type: 'object',
              additionalProperties: false,
              properties: {
                action: { type: 'string', enum: ['respond', 'resample'] },
                sourceArtifactContent: { type: 'null' }
              },
              required: ['action', 'sourceArtifactContent']
            }
          ]
        },
        recovery: recoveryExplanationJsonSchema
      },
      required: ['reply', 'decision', 'recovery']
    }
  },
  parseOutput(value) {
    const output = value as {
      reply?: unknown;
      decision?: {
        action?: unknown;
        sourceArtifactContent?: unknown;
      };
      recovery?: unknown;
    };
    const decision = output?.decision;
    if (
      !decision ||
      (decision.action !== 'respond' &&
        decision?.action !== 'resample' &&
        decision?.action !== 'revise') ||
      !('sourceArtifactContent' in decision) ||
      (decision.sourceArtifactContent !== null &&
        (typeof decision.sourceArtifactContent !== 'string' ||
          !decision.sourceArtifactContent.trim()))
    ) {
      throw new Error('The chatbot returned an invalid structured response.');
    }
    const hasSource = typeof decision.sourceArtifactContent === 'string';
    if ((decision.action === 'revise') !== hasSource) {
      throw new Error('The chatbot action did not match its source artifact content.');
    }
    const recovery = parseRecoveryExplanation(output.recovery);
    const reply = v.parse(generatedMessageContentSchema, output.reply);
    if (decision.action === 'revise') {
      return {
        reply,
        action: 'revise',
        sourceArtifactContent: decision.sourceArtifactContent as string,
        ...(recovery ? { recovery } : {})
      };
    }
    return { reply, action: decision.action, ...(recovery ? { recovery } : {}) };
  }
} satisfies ChatBotConfig<AiProjectContext>;
