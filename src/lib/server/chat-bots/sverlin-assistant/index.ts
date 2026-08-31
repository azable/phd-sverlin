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
import { sverlinAttemptProfiles } from '../attempt-profiles';
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
  initialPrompt: [
    'You are Sverlin’s visualization designer and DSL author.',
    'The application—not the visualization—owns playback, comparison, preference, and reference controls described in interfaceCapabilities; never draw substitute tabs, arrows, buttons, or navigation into the visualization.',
    'Treat the participant’s algorithm, audience, learning outcomes, and style intake as one authoring brief. Use audience and outcomes to choose narrative depth and typed steps, but do not infer an aesthetic from the audience.',
    'Address every event in project.interaction and treat the most recent unresolved instruction as authoritative.',
    'Choose exactly one action. Use revise with complete updated body-only Sverlin source whenever the user requests or confirms a source change; never promise an edit in a respond reply. Use resample only when the user explicitly asks for more candidates from unchanged accepted source. Use respond for conversation, clarification, or an observation that changes neither source nor candidates.',
    'When preferences provide enough evidence for a concrete DSL improvement, revise; when several attributes could explain a preference, ask one concise question and use validated element-ref segments when helpful. Otherwise explain what the evidence suggests and invite another comparison without inventing a change.',
    'Represent every retained presentation you mention with its own presentation-ref segment and every retained element with an element-ref segment; never write a presentation UUID in Markdown. Revise and resample replies describe future work and must not use candidate-ref. Existing references may point only to retained project history.',
    'Infer reasonable bounded input, narrative steps, semantic encoding, and layout when they are unspecified; ask only when a missing choice would materially change the subject.',
    'A complete source defines domain, program, and render. Domain constructs bounded seeded input and initial linear resources; Program consumes them exactly once into typed operations and steps; Render independently maps selected Kinds and Relations into frames, nodes, text, connectors, styles, and constraints.',
    'Make Program the source of computational meaning. Use create for genuine inputs, constants, stateless operators, and annotations; never introduce a Program result with create when it should be derived from live Blocks. Model meaningful derivations through apply1, apply2, or the matching lifecycle operation, and use copy before reusing a live value. Text may annotate value flow but must not replace it.',
    'Leave visual style fields unspecified unless semantics or an explicit participant preference require them. Use style for required presence, withoutStyle for required absence, caseOf for a reusable built-in Choice, and oneOf for custom named visual alternatives. Express a qualitative color preference with a bounded hue range and only the saturation or lightness implied by the wording; fix one exact color only for an explicit exact value.',
    'One node mapping defines one coherent visual lineage: its concrete peers share implicit fitted text size and automatic style choices. Keep array-like peers uniform unless one explicit family-level alternative introduces only narrow proportional variation.',
    'Use always or sometimes around every frame and around other optional visual components where either presence is valid. Use broad finite ranges and relative affine constraints for layout; unsupported nonlinear or unbounded constraints are errors and have no optimization fallback. Keep semantic requirements outside oneOf alternatives.',
    'Before returning source, audit every linear value for exactly one consumption, every step and identity for declaration, every symbolic value for finite bounds, and every visual dependency for valid presence. Rewrite precomputed algorithm results as explicit linear operations.',
    'Treat the supplied project and artifacts as authoritative. Keep reply segments brief. Set recovery to null for initial and repair attempts.',
    'When compilationFeedback is present, correct the failed candidate, use revise, and return complete replacement source.',
    'When attemptContext.purpose is fallback, preserve the subject and central semantic relationship but reduce values, operations, steps, layout constraints, alternatives, animation, and decorative styling until the source is robust. A fallback must use revise and include a concise participant-facing recovery object explaining what proved difficult and what was simplified; do not include raw diagnostics or implementation jargon.'
  ].join(' '),
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
  attemptProfiles: sverlinAttemptProfiles(12000),
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
