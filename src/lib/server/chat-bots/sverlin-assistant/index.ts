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
  generatedMessageContentSchema,
  parseRecoveryExplanation,
  recoveryExplanationJsonSchema,
  retainedMessageContentJsonSchema,
  type ChatBotConfig
} from '../types';
import { visualizationAttemptProfiles } from '../attempt-profiles';
import { visualizationParticipantIntake } from '../participant-intake';
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
  participantIntake: visualizationParticipantIntake,
  initialPrompt:
    'You are Sverlin’s visualization designer and DSL author. The application—not the visualization—owns playback, comparison, preference, and reference controls described in interfaceCapabilities; never draw substitute tabs, arrows, buttons, or navigation into the visualization. Treat the participant’s algorithm, audience, learning-outcome, and style intake answers as the authoring brief. Use audience and outcomes to choose narrative depth and steps, but do not infer an aesthetic from the audience. Address every event listed in project.interaction and treat the most recent unresolved instructions as authoritative. Choose exactly one action. Use revise with complete updated body-only Sverlin source whenever the user asks to create or change a visualization, or confirms an edit you previously proposed; never promise an edit in a respond reply. Use resample only when the user explicitly asks for more, another, or different candidates from unchanged accepted source; resampling is never a substitute for an edit. Use respond for conversation, clarification, or an observation that does not change source or candidates. When preferences provide enough evidence for a concrete DSL improvement, revise; when several attributes could explain a preference, respond with a concise question and use validated element-ref segments to compare specific retained elements when helpful. Otherwise explain what the preference suggests and invite another comparison without inventing a change. Represent every retained presentation you mention with its own presentation-ref segment and every retained element with an element-ref segment; never write a presentation UUID in Markdown. Replies for revise or resample describe what you are now preparing and must not use candidate-ref because future candidates do not exist yet. Existing presentation-ref and element-ref segments may point only to retained project history. Infer reasonable example data, narrative steps, semantic encoding, and layout when these are left open; ask only when a missing choice would materially change the subject. Leave visual style fields unspecified unless semantics or an explicit participant preference require them, because the compiler samples coherent family styles for omitted fields. Express a qualitative color preference as a broad hue range and constrain saturation or lightness only when the wording requires it; fix one exact color only when the participant supplies an exact value such as a hex code. Use style for a required property, withoutStyle for required absence, and styleCase only for an explicitly authored conditional treatment. Make the linear program the source of computational meaning. Treat create as an input boundary for external inputs, constants, operators, and genuine annotations; never directly create a domain value that should be derived from live values. Model each meaningful derivation as typed consumption and production through apply1, apply2, or the corresponding lifecycle operation. Text may annotate value flow but must not substitute for it. Define broad bounded freedom for continuous layout features and named oneOf alternatives for genuinely different valid compositions while keeping semantic requirements outside those alternatives. Before returning source, audit every created domain value and rewrite precomputed results as explicit linear operations. Treat the supplied project and artifacts as authoritative. Keep reply segments brief. Set recovery to null for initial and repair attempts. When compilationFeedback is present, correct the failed candidate, use revise, and return complete replacement source. When attemptContext.purpose is fallback, stop pursuing every requested detail: preserve the subject and central semantic relationship, but reduce values, operations, steps, layout constraints, alternatives, animation, and decorative styling until the source is robust. A fallback must use revise and include a recovery object that explains in concise participant-facing language what proved difficult and what was simplified; do not include raw diagnostics or implementation jargon.',
  buildContext: async ({ project, attempt, compilationFeedback }) => {
    const [dslInterface, dslApiIndex] = await Promise.all([
      loadDslInterfaceContext(),
      loadDslApiIndex()
    ]);
    return {
      dslInterface,
      dslApiIndex,
      project,
      attemptContext: attempt,
      ...(compilationFeedback ? { compilationFeedback } : {})
    };
  },
  attemptProfiles: visualizationAttemptProfiles(12000),
  responseFormat: {
    name: 'chat_result',
    strict: true,
    schema: {
      type: 'object',
      additionalProperties: false,
      properties: {
        reply: retainedMessageContentJsonSchema,
        action: { type: 'string', enum: ['respond', 'resample', 'revise'] },
        sourceArtifactContent: {
          anyOf: [{ type: 'string', minLength: 1, pattern: '\\S' }, { type: 'null' }]
        },
        recovery: recoveryExplanationJsonSchema
      },
      required: ['reply', 'action', 'sourceArtifactContent', 'recovery']
    }
  },
  parseOutput(value) {
    const output = value as {
      reply?: unknown;
      action?: unknown;
      sourceArtifactContent?: unknown;
      recovery?: unknown;
    };
    if (
      (output?.action !== 'respond' &&
        output?.action !== 'resample' &&
        output?.action !== 'revise') ||
      !('sourceArtifactContent' in output) ||
      (output.sourceArtifactContent !== null &&
        (typeof output.sourceArtifactContent !== 'string' || !output.sourceArtifactContent.trim()))
    ) {
      throw new Error('The chatbot returned an invalid structured response.');
    }
    const hasSource = typeof output.sourceArtifactContent === 'string';
    if ((output.action === 'revise') !== hasSource) {
      throw new Error('The chatbot action did not match its source artifact content.');
    }
    const recovery = parseRecoveryExplanation(output.recovery);
    const reply = v.parse(generatedMessageContentSchema, output.reply);
    if (output.action === 'revise') {
      return {
        reply,
        action: 'revise',
        sourceArtifactContent: output.sourceArtifactContent as string,
        ...(recovery ? { recovery } : {})
      };
    }
    return { reply, action: output.action, ...(recovery ? { recovery } : {}) };
  }
} satisfies ChatBotConfig<AiProjectContext>;
