/** AI-assisted feedback orchestration for Sverlin and direct-HTML projects. */

import { randomUUID } from 'node:crypto';

import type { EventId, NewProjectEvent } from '$lib/shared/projects/events';
import type {
  ArtifactChange,
  DslRevision,
  VisualSelection
} from '$lib/shared/projects/events/values';
import type { ProjectCommandResult, ProjectDocument } from '$lib/shared/projects/model';
import type { HtmlFramesPresentation, HtmlFramesManifest } from '$lib/shared/presentations';
import { legacyPresentationId } from '$lib/shared/presentations';
import { projectHead, projectSnapshotAt } from '$lib/shared/projects/projection';
import { decodeVisualization } from '$lib/shared/visualization';
import { getChatbot, getHtmlChatbot } from '$lib/server/chat-bots/registry';
import {
  projectAiContext,
  projectConversationMessages,
  type AiContextSelection
} from '$lib/server/chat-bots/sverlin-assistant/project-context';
import type {
  ChatbotPrompt,
  ChatbotResult,
  CompilationFeedback
} from '$lib/server/chat-bots/types';
import { formatDiagnosticSummary } from '$lib/server/compiler';
import { createHtmlPresentation } from '$lib/server/visualization-modes';

import { runProjectCommand } from './command-lock';
import { readDslRevision, recordText, sourceSha256 } from './fingerprints';
import { projectRepository } from './repository';
import {
  activateCompiledPresentations,
  appendProjectEvents,
  compileProjectSourceBatch,
  defaultProjectServiceDependencies,
  draftEvent,
  freshPresentationSeeds,
  type ProjectServiceDependencies,
  type RecordedCompilation,
  type RecordedCompilationBatch
} from './service';

/** Replaceable AI and persistence boundaries used by command unit tests. */
export type ProjectCommandDependencies = {
  repository: typeof projectRepository;
  projectService: ProjectServiceDependencies;
  getChatbot: typeof getChatbot;
  getHtmlChatbot: typeof getHtmlChatbot;
  readDslRevision: typeof readDslRevision;
};

export const defaultProjectCommandDependencies: ProjectCommandDependencies = {
  repository: projectRepository,
  projectService: defaultProjectServiceDependencies,
  getChatbot,
  getHtmlChatbot,
  readDslRevision
};

/** Record user feedback and produce the mode's next visualization response. */
export function submitProjectFeedback(
  options: {
    projectId: string;
    expectedHead: EventId;
    text?: string;
    focus: EventId[];
    selection?: VisualSelection;
    presentations?: string[];
    presentationCount: 1 | 2;
    operationId: string;
  },
  dependencies: ProjectCommandDependencies = defaultProjectCommandDependencies
): Promise<ProjectCommandResult> {
  return runProjectCommand(options.projectId, () =>
    submitProjectFeedbackUnlocked(options, dependencies)
  );
}

async function submitProjectFeedbackUnlocked(
  options: {
    projectId: string;
    expectedHead: EventId;
    text?: string;
    focus: EventId[];
    selection?: VisualSelection;
    presentations?: string[];
    presentationCount: 1 | 2;
    operationId: string;
  },
  dependencies: ProjectCommandDependencies
): Promise<ProjectCommandResult> {
  const before = await dependencies.repository.load(options.projectId);
  assertHead(before, options.expectedHead);
  const focus = validateFocus(before, options.focus);
  const selection = options.selection
    ? await validateSelection(before, options.selection)
    : undefined;
  const presentations = validatePresentations(before, options.presentations ?? []);
  const text = options.text?.trim();
  if (!text && focus.length === 0 && !selection) throw new Error('Feedback cannot be empty.');

  let document = await appendProjectEvents(
    before,
    [
      draftEvent({
        type: 'feedback.submitted',
        actor: { kind: 'user' },
        operationId: options.operationId,
        payload: {
          ...(text ? { text } : {}),
          focus,
          ...(selection ? { selection } : {}),
          ...(presentations.length ? { presentations } : {})
        }
      })
    ],
    [],
    dependencies.projectService
  );
  if (projectSnapshotAt(document).renderer === 'html') {
    document = await submitHtmlFeedback(
      document,
      options.operationId,
      {
        eventIds: focus,
        presentationIds: presentations,
        ...(selection ? { visualSelection: selection } : {})
      },
      dependencies
    );
    return finishMutation(before, document);
  }

  const contextSelection: AiContextSelection = {
    eventIds: focus,
    presentationIds: presentations,
    ...(selection ? { visualSelection: selection } : {})
  };
  const first = await runSverlinGeneration(
    { document, attempt: 1, operationId: options.operationId, contextSelection },
    dependencies
  );
  document = first.document;
  if (!first.ok) return finishMutation(before, document);
  if (first.result.sourceArtifactContent === undefined) {
    document = await appendAssistantResponse(
      document,
      first.result.reply,
      assistantBotId(first.generationEvent),
      options.operationId,
      dependencies
    );
    return finishMutation(before, document);
  }

  const seeds = freshPresentationSeeds(options.presentationCount);
  const firstCompile = await compileCandidateBatch(
    {
      document,
      candidate: first.result.sourceArtifactContent,
      seeds,
      operationId: options.operationId,
      attempt: 1
    },
    dependencies
  );
  document = firstCompile.document;
  if (batchSucceeded(firstCompile.recorded)) {
    document = await acceptSverlinCandidate(
      {
        document,
        recorded: firstCompile.recorded,
        generationEvent: first.generationEvent,
        reply: first.result.reply,
        candidate: first.result.sourceArtifactContent,
        operationId: options.operationId
      },
      dependencies
    );
    return finishMutation(before, document);
  }

  const failed = firstFailure(firstCompile.recorded);
  if (!failed || failed.compileEvent.type !== 'compilation.failed') {
    throw new Error('A failed compilation batch had no failure event.');
  }
  if (!failed.compileEvent.payload.repairEligible) {
    document = await appendSystemFailure(
      document,
      `The proposed source could not be compiled. ${formatDiagnosticSummary(failed.result.diagnostics)}`,
      options.operationId,
      dependencies
    );
    return finishMutation(before, document);
  }

  const repairFeedback: CompilationFeedback = {
    attempt: 1,
    compilationEventId:
      document.events.findLast(
        (event) => event.operationId === options.operationId && event.type === 'compilation.failed'
      )?.id ?? projectHead(document).id,
    failedSource: first.result.sourceArtifactContent,
    assistantReply: first.result.reply,
    diagnostics: failed.result.diagnostics
  };
  const repair = await runSverlinGeneration(
    {
      document,
      attempt: 2,
      operationId: options.operationId,
      contextSelection,
      compilationFeedback: repairFeedback
    },
    dependencies
  );
  document = repair.document;
  if (!repair.ok) return finishMutation(before, document);
  if (repair.result.sourceArtifactContent === undefined) {
    document = await appendSystemFailure(
      document,
      'The repair attempt did not return corrected source. The accepted artifact is unchanged.',
      options.operationId,
      dependencies
    );
    return finishMutation(before, document);
  }

  const repaired = await compileCandidateBatch(
    {
      document,
      candidate: repair.result.sourceArtifactContent,
      seeds,
      operationId: options.operationId,
      attempt: 2
    },
    dependencies
  );
  document = repaired.document;
  const repairFailure = firstFailure(repaired.recorded);
  if (repairFailure) {
    document = await appendSystemFailure(
      document,
      `The corrected source still failed compilation. The accepted artifact is unchanged. ${formatDiagnosticSummary(repairFailure.result.diagnostics)}`,
      options.operationId,
      dependencies
    );
    return finishMutation(before, document);
  }

  document = await acceptSverlinCandidate(
    {
      document,
      recorded: repaired.recorded,
      generationEvent: repair.generationEvent,
      reply: repair.result.reply,
      candidate: repair.result.sourceArtifactContent,
      operationId: options.operationId
    },
    dependencies
  );
  return finishMutation(before, document);
}

async function submitHtmlFeedback(
  document: ProjectDocument,
  operationId: string,
  contextSelection: AiContextSelection,
  dependencies: ProjectCommandDependencies
): Promise<ProjectDocument> {
  const first = await runHtmlGeneration(
    { document, attempt: 1, operationId, contextSelection },
    dependencies
  );
  document = first.document;
  if (!first.ok) return document;
  if (!first.result.manifest) {
    return appendAssistantResponse(
      document,
      first.result.reply,
      assistantBotId(first.generationEvent),
      operationId,
      dependencies
    );
  }

  let accepted: AcceptedHtmlTurn;
  try {
    accepted = {
      presentation: createHtmlPresentation(first.result.manifest, projectHead(document).id),
      reply: first.result.reply,
      generationEvent: first.generationEvent
    };
  } catch (cause) {
    const repair = await runHtmlGeneration(
      {
        document,
        attempt: 2,
        operationId,
        contextSelection,
        correction: htmlCorrection(first.result.manifest, cause)
      },
      dependencies
    );
    document = repair.document;
    if (!repair.ok) return document;
    if (!repair.result.manifest) {
      return appendSystemFailure(
        document,
        'The HTML correction did not return a visualization. The accepted artifact is unchanged.',
        operationId,
        dependencies
      );
    }
    try {
      accepted = {
        presentation: createHtmlPresentation(repair.result.manifest, projectHead(document).id),
        reply: repair.result.reply,
        generationEvent: repair.generationEvent
      };
    } catch (repairCause) {
      return appendSystemFailure(
        document,
        `The corrected HTML visualization was still unsafe or invalid. ${errorMessage(repairCause)}`,
        operationId,
        dependencies
      );
    }
  }
  return acceptHtmlTurn(document, accepted, operationId, dependencies);
}

type AcceptedHtmlTurn = {
  presentation: HtmlFramesPresentation;
  reply: string;
  generationEvent: NewProjectEvent<'ai.generation-succeeded'>;
};

async function acceptHtmlTurn(
  document: ProjectDocument,
  accepted: AcceptedHtmlTurn,
  operationId: string,
  dependencies: ProjectCommandDependencies
): Promise<ProjectDocument> {
  const snapshot = projectSnapshotAt(document);
  const current = snapshot.artifacts[snapshot.entryArtifactId];
  if (!current) throw new Error('The project has no entry artifact.');
  document = await appendProjectEvents(
    document,
    [
      draftEvent({
        type: 'artifact.version-created',
        actor: accepted.generationEvent.actor,
        operationId,
        payload: {
          origin: { kind: 'assistant-edit' },
          changes: [
            {
              operation: 'upsert',
              artifact: { ...current, language: 'json', content: accepted.presentation.authored }
            }
          ]
        }
      }),
      draftEvent({
        type: 'visualization.presented',
        actor: accepted.generationEvent.actor,
        operationId,
        payload: {
          displaySetId: randomUUID(),
          slot: 0,
          presentation: accepted.presentation
        }
      })
    ],
    [],
    dependencies.projectService
  );
  return appendAssistantResponse(
    document,
    accepted.reply,
    assistantBotId(accepted.generationEvent),
    operationId,
    dependencies
  );
}

async function runSverlinGeneration(
  options: {
    document: ProjectDocument;
    attempt: 1 | 2;
    operationId: string;
    contextSelection: AiContextSelection;
    compilationFeedback?: CompilationFeedback;
  },
  dependencies: ProjectCommandDependencies
) {
  const chatbot = dependencies.getChatbot();
  let prompt;
  try {
    prompt = await chatbot.preparePrompt({
      messages: projectConversationMessages(options.document.events),
      project: projectAiContext(options.document, options.contextSelection),
      ...(options.compilationFeedback ? { compilationFeedback: options.compilationFeedback } : {})
    });
  } catch (error) {
    return generationPreparationFailure(options, error, dependencies);
  }
  return runPreparedGeneration(
    {
      document: options.document,
      attempt: options.attempt,
      operationId: options.operationId,
      prompt,
      dslRevision: await dependencies.readDslRevision(),
      generate: () => chatbot.generatePrepared(prompt),
      fallbackResponse: (result) => ({
        reply: result.reply,
        sourceArtifactContent: result.sourceArtifactContent ?? null,
        generation: result.generation
      })
    },
    dependencies
  );
}

async function runHtmlGeneration(
  options: {
    document: ProjectDocument;
    attempt: 1 | 2;
    operationId: string;
    contextSelection: AiContextSelection;
    correction?: string;
  },
  dependencies: ProjectCommandDependencies
) {
  const chatbot = dependencies.getHtmlChatbot();
  let prompt;
  try {
    prompt = await chatbot.preparePrompt({
      messages: [
        ...projectConversationMessages(options.document.events),
        ...(options.correction ? [{ role: 'user' as const, content: options.correction }] : [])
      ],
      project: projectAiContext(options.document, options.contextSelection)
    });
  } catch (error) {
    return generationPreparationFailure(options, error, dependencies);
  }
  return runPreparedGeneration(
    {
      document: options.document,
      attempt: options.attempt,
      operationId: options.operationId,
      prompt,
      generate: () => chatbot.generatePrepared(prompt),
      fallbackResponse: (result) => ({
        reply: result.reply,
        manifest: result.manifest ?? null,
        generation: result.generation
      })
    },
    dependencies
  );
}

async function generationPreparationFailure(
  options: { document: ProjectDocument; operationId: string },
  error: unknown,
  dependencies: ProjectCommandDependencies
) {
  return {
    ok: false as const,
    document: await appendSystemFailure(
      options.document,
      safeErrorMessage(error),
      options.operationId,
      dependencies
    )
  };
}

async function runPreparedGeneration<Output extends { reply: string }>(
  options: {
    document: ProjectDocument;
    attempt: 1 | 2;
    operationId: string;
    prompt: ChatbotPrompt;
    dslRevision?: DslRevision;
    generate: () => Promise<ChatbotResult<Output>>;
    fallbackResponse: (result: ChatbotResult<Output>) => unknown;
  },
  dependencies: ProjectCommandDependencies
) {
  const request = draftEvent<'ai.generation-requested'>({
    type: 'ai.generation-requested',
    actor: { kind: 'system' },
    operationId: options.operationId,
    payload: {
      attempt: options.attempt,
      purpose: options.attempt === 1 ? 'initial' : 'repair',
      prompt: recordText(JSON.stringify(options.prompt), 'application/json'),
      promptTemplateSha256: sourceSha256(options.prompt.initialPrompt),
      ...(options.dslRevision ? { dslRevision: options.dslRevision } : {}),
      requestedModel: options.prompt.parameters.model,
      parameters: { ...options.prompt.parameters }
    }
  });
  let document = await appendProjectEvents(
    options.document,
    [request],
    [],
    dependencies.projectService
  );
  const startedAt = performance.now();
  try {
    const result = await options.generate();
    const generationEvent = draftEvent<'ai.generation-succeeded'>({
      type: 'ai.generation-succeeded',
      actor: { kind: 'assistant', botId: result.generation.botId },
      operationId: options.operationId,
      payload: {
        attempt: options.attempt,
        adapterId: result.generation.adapterId,
        requestedModel: options.prompt.parameters.model,
        ...(result.generation.model ? { model: result.generation.model } : {}),
        ...(result.generation.responseId ? { responseId: result.generation.responseId } : {}),
        durationMs: Math.round(performance.now() - startedAt),
        ...(result.generation.usage ? { usage: result.generation.usage } : {}),
        response: recordText(
          JSON.stringify(result.providerResponse ?? options.fallbackResponse(result)),
          'application/json'
        )
      }
    });
    document = await appendProjectEvents(
      document,
      [generationEvent],
      [],
      dependencies.projectService
    );
    return { ok: true as const, document, result, generationEvent };
  } catch (error) {
    const details = generationErrorDetails(error);
    const failed = draftEvent<'ai.generation-failed'>({
      type: 'ai.generation-failed',
      actor: { kind: 'system' },
      operationId: options.operationId,
      payload: {
        attempt: options.attempt,
        failureKind: generationFailureKind(error),
        durationMs: Math.round(performance.now() - startedAt),
        message: safeErrorMessage(error),
        details: recordText(details.value, details.mediaType)
      }
    });
    document = await appendProjectEvents(document, [failed], [], dependencies.projectService);
    document = await appendSystemFailure(
      document,
      failed.payload.message,
      options.operationId,
      dependencies
    );
    return { ok: false as const, document };
  }
}

async function compileCandidateBatch(
  options: {
    document: ProjectDocument;
    candidate: string;
    seeds: readonly number[];
    operationId: string;
    attempt: 1 | 2;
  },
  dependencies: ProjectCommandDependencies
) {
  const source = recordText(options.candidate, 'text/x-sverlin');
  const recorded = await compileProjectSourceBatch(
    {
      document: options.document,
      sourceContent: options.candidate,
      source,
      sourceLabel: 'Main.sverlin',
      seeds: options.seeds,
      purpose: 'assistant-edit',
      input: 'assistant-candidate',
      operationId: options.operationId,
      attempt: options.attempt
    },
    dependencies.projectService
  );
  return { document: recorded.document, recorded };
}

async function acceptSverlinCandidate(
  options: {
    document: ProjectDocument;
    recorded: RecordedCompilationBatch;
    generationEvent: NewProjectEvent<'ai.generation-succeeded'>;
    reply: string;
    candidate: string;
    operationId: string;
  },
  dependencies: ProjectCommandDependencies
) {
  const snapshot = projectSnapshotAt(options.document);
  const current = snapshot.artifacts[snapshot.entryArtifactId];
  if (!current) throw new Error('The project has no entry artifact.');
  const change: ArtifactChange = {
    operation: 'upsert',
    artifact: { ...current, content: recordText(options.candidate, 'text/x-sverlin') }
  };
  let document = await appendProjectEvents(
    options.document,
    [
      draftEvent({
        type: 'artifact.version-created',
        actor: options.generationEvent.actor,
        operationId: options.operationId,
        payload: { origin: { kind: 'assistant-edit' }, changes: [change] }
      })
    ],
    [],
    dependencies.projectService
  );
  document = await activateCompiledPresentations(
    { ...options.recorded, document },
    dependencies.projectService,
    options.generationEvent.actor
  );
  return appendAssistantResponse(
    document,
    options.reply,
    assistantBotId(options.generationEvent),
    options.operationId,
    dependencies
  );
}

function batchSucceeded(batch: RecordedCompilationBatch): boolean {
  return batch.compilations.length > 0 && batch.compilations.every(({ result }) => result.ok);
}

function firstFailure(
  batch: RecordedCompilationBatch
): Extract<RecordedCompilation, { result: { ok: false } }> | undefined {
  return batch.compilations.find(({ result }) => !result.ok) as
    | Extract<RecordedCompilation, { result: { ok: false } }>
    | undefined;
}

function appendAssistantResponse(
  document: ProjectDocument,
  text: string,
  botId: string,
  operationId: string,
  dependencies: ProjectCommandDependencies
) {
  return appendProjectEvents(
    document,
    [
      draftEvent({
        type: 'assistant.responded',
        actor: { kind: 'assistant', botId },
        operationId,
        payload: { text }
      })
    ],
    [],
    dependencies.projectService
  );
}

function assistantBotId(event: NewProjectEvent<'ai.generation-succeeded'>): string {
  if (event.actor.kind !== 'assistant') {
    throw new Error('A successful AI generation must have an assistant actor.');
  }
  return event.actor.botId;
}

function appendSystemFailure(
  document: ProjectDocument,
  message: string,
  operationId: string,
  dependencies: ProjectCommandDependencies
) {
  return appendProjectEvents(
    document,
    [
      draftEvent({
        type: 'system.notified',
        actor: { kind: 'system' },
        operationId,
        payload: { severity: 'error', message }
      })
    ],
    [],
    dependencies.projectService
  );
}

function validateFocus(document: ProjectDocument, focus: EventId[]) {
  const unique = [...new Set(focus)];
  for (const id of unique) {
    if (document.events[id - 1]?.id !== id) throw new Error(`Unknown focused event ${id}.`);
  }
  return unique;
}

function validatePresentations(document: ProjectDocument, presentationIds: string[]): string[] {
  const unique = [...new Set(presentationIds)];
  if (unique.length > 2) throw new Error('Feedback can reference at most two presentations.');
  const available = new Set(
    document.events.flatMap((event) => {
      if (event.type === 'visualization.presented') {
        return [event.payload.presentation.presentationId];
      }
      return event.type === 'visualization.rendered' ? [legacyPresentationId(event.id)] : [];
    })
  );
  for (const id of unique) {
    if (!available.has(id)) throw new Error(`Unknown selected presentation ${id}.`);
  }
  return unique;
}

async function validateSelection(
  document: ProjectDocument,
  selection: VisualSelection
): Promise<VisualSelection> {
  const renderEvent = document.events[selection.render - 1];
  if (renderEvent?.type !== 'visualization.rendered') {
    throw new Error('The visual selection references an unknown render.');
  }
  const visualization = decodeVisualization(renderEvent.payload.render.text);
  const step = visualization.steps[selection.step];
  if (!step) throw new Error('The visual selection references an unknown visualization step.');
  const available = new Set(step.instances.map(({ id }) => id));
  const instances = [...new Set(selection.instances)];
  if (instances.some((id) => !available.has(id))) {
    throw new Error('The visual selection contains an unknown render instance.');
  }
  return { ...selection, instances };
}

function finishMutation(before: ProjectDocument, document: ProjectDocument): ProjectCommandResult {
  return { document, appendedEvents: document.events.slice(before.events.length) };
}

function assertHead(document: ProjectDocument, expectedHead: EventId) {
  if (projectHead(document).id !== expectedHead) {
    const error = new Error('The project changed before this operation completed.');
    error.name = 'ProjectConflictError';
    throw error;
  }
}

function htmlCorrection(manifest: HtmlFramesManifest, cause: unknown): string {
  return `The previous manifest failed static safety validation: ${errorMessage(cause)}. Return one complete corrected manifest. Previous manifest: ${JSON.stringify(manifest)}`;
}

function generationFailureKind(error: unknown) {
  if (error instanceof Error && error.name === 'OpenAIConfigurationError') return 'configuration';
  if (error instanceof Error && error.name === 'APITimeoutError') return 'timeout';
  if (error instanceof Error && error.name === 'AbortError') return 'cancelled';
  if (error instanceof Error && error.name === 'InvalidChatbotResponseError') {
    return 'invalid-response';
  }
  return 'provider';
}

function safeErrorMessage(error: unknown) {
  if (error instanceof Error && error.name === 'OpenAIConfigurationError') return error.message;
  if (error instanceof Error && error.name === 'ChatContextOverflowError') return error.message;
  if (error instanceof Error && error.name === 'APITimeoutError')
    return 'The AI request timed out.';
  if (error instanceof Error && error.name === 'InvalidChatbotResponseError') return error.message;
  return 'The AI service could not complete this request.';
}

function generationErrorDetails(error: unknown) {
  const summary = error instanceof Error ? (error.stack ?? error.message) : String(error);
  if (
    error instanceof Error &&
    'providerResponse' in error &&
    error.providerResponse !== undefined
  ) {
    try {
      return {
        value: JSON.stringify({ error: summary, providerResponse: error.providerResponse }),
        mediaType: 'application/json'
      };
    } catch {
      // Use the readable error if a provider object is not serializable.
    }
  }
  return { value: summary, mediaType: 'text/plain' };
}

function errorMessage(cause: unknown): string {
  return cause instanceof Error ? cause.message : String(cause);
}
