/**
 * AI-assisted feedback command orchestration for projects.
 *
 * @packageDocumentation
 */

import type { EventId, NewProjectEvent } from '$lib/shared/projects/events';
import type { ArtifactChange, VisualSelection } from '$lib/shared/projects/events/values';
import type { ProjectCommandResult, ProjectDocument } from '$lib/shared/projects/model';
import { projectHead, projectSnapshotAt } from '$lib/shared/projects/projection';
import { decodeVisualization } from '$lib/shared/visualization';
import { getChatbot } from '$lib/server/chat-bots/registry';
import {
  projectAiContext,
  projectConversationMessages,
  type AiContextSelection
} from '$lib/server/chat-bots/ai-assistant/project-context';
import type { CompilationFeedback } from '$lib/server/chat-bots/types';
import { formatDiagnosticSummary } from '$lib/server/compiler';

import { runProjectCommand } from './command-lock';
import { readDslRevision, recordText, sourceSha256 } from './fingerprints';
import { projectRepository } from './repository';
import {
  activateCompiledRender,
  appendProjectEvents,
  compileProjectSource,
  defaultProjectServiceDependencies,
  draftEvent,
  type ProjectServiceDependencies,
  type RecordedCompilation
} from './service';

/** Replaceable AI and persistence boundaries used by command unit tests. */
export type ProjectCommandDependencies = {
  repository: typeof projectRepository;
  projectService: ProjectServiceDependencies;
  getChatbot: typeof getChatbot;
  readDslRevision: typeof readDslRevision;
};

export const defaultProjectCommandDependencies: ProjectCommandDependencies = {
  repository: projectRepository,
  projectService: defaultProjectServiceDependencies,
  getChatbot,
  readDslRevision
};

/** Record user feedback, run AI generation, and accept at most one compiled candidate. */
export function submitProjectFeedback(
  options: {
    projectId: string;
    expectedHead: EventId;
    text?: string;
    focus: EventId[];
    selection?: VisualSelection;
    seed: number;
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
    seed: number;
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
  const text = options.text?.trim();
  if (!text && focus.length === 0 && !selection) throw new Error('Feedback cannot be empty.');

  const feedback = draftEvent<'feedback.submitted'>({
    type: 'feedback.submitted',
    actor: { kind: 'user' },
    operationId: options.operationId,
    payload: { ...(text ? { text } : {}), focus, ...(selection ? { selection } : {}) }
  });
  let document = await appendProjectEvents(before, [feedback], [], dependencies.projectService);
  const contextSelection: AiContextSelection = {
    eventIds: focus,
    ...(selection ? { visualSelection: selection } : {})
  };

  const first = await runGeneration(
    {
      document,
      attempt: 1,
      operationId: options.operationId,
      contextSelection
    },
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

  const firstCompile = await compileCandidate(
    {
      document,
      generationEvent: first.generationEvent,
      candidate: first.result.sourceArtifactContent,
      seed: options.seed,
      operationId: options.operationId,
      attempt: 1
    },
    dependencies
  );
  document = firstCompile.document;
  if (firstCompile.recorded.result.ok) {
    document = await acceptCandidate(
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

  const failed = firstCompile.recorded;
  if (failed.result.ok) throw new Error('A successful compilation was not activated.');
  if (
    failed.compileEvent.type !== 'compilation.failed' ||
    !failed.compileEvent.payload.repairEligible
  ) {
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
    compilationEventId: projectHead(document).id,
    failedSource: first.result.sourceArtifactContent,
    assistantReply: first.result.reply,
    diagnostics: failed.result.diagnostics
  };
  const repair = await runGeneration(
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

  const repairCompile = await compileCandidate(
    {
      document,
      generationEvent: repair.generationEvent,
      candidate: repair.result.sourceArtifactContent,
      seed: options.seed,
      operationId: options.operationId,
      attempt: 2
    },
    dependencies
  );
  document = repairCompile.document;
  if (!repairCompile.recorded.result.ok) {
    document = await appendSystemFailure(
      document,
      `The corrected source still failed compilation. The accepted artifact is unchanged. ${formatDiagnosticSummary(repairCompile.recorded.result.diagnostics)}`,
      options.operationId,
      dependencies
    );
    return finishMutation(before, document);
  }

  document = await acceptCandidate(
    {
      document,
      recorded: repairCompile.recorded,
      generationEvent: repair.generationEvent,
      reply: repair.result.reply,
      candidate: repair.result.sourceArtifactContent,
      operationId: options.operationId
    },
    dependencies
  );
  return finishMutation(before, document);
}

async function runGeneration(
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

  const promptRecord = recordText(JSON.stringify(prompt), 'application/json');
  const dslRevision = await dependencies.readDslRevision();
  const request = draftEvent<'ai.generation-requested'>({
    type: 'ai.generation-requested',
    actor: { kind: 'system' },
    operationId: options.operationId,
    payload: {
      attempt: options.attempt,
      purpose: options.attempt === 1 ? 'initial' : 'repair',
      prompt: promptRecord,
      promptTemplateSha256: sourceSha256(prompt.initialPrompt),
      ...(dslRevision ? { dslRevision } : {}),
      requestedModel: prompt.parameters.model,
      parameters: { ...prompt.parameters }
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
    const result = await chatbot.generatePrepared(prompt);
    const response = recordText(
      JSON.stringify(
        result.providerResponse ?? {
          reply: result.reply,
          sourceArtifactContent: result.sourceArtifactContent ?? null,
          generation: result.generation
        }
      ),
      'application/json'
    );
    const generationEvent = draftEvent<'ai.generation-succeeded'>({
      type: 'ai.generation-succeeded',
      actor: { kind: 'assistant', botId: result.generation.botId },
      operationId: options.operationId,
      payload: {
        attempt: options.attempt,
        adapterId: result.generation.adapterId,
        requestedModel: prompt.parameters.model,
        ...(result.generation.model ? { model: result.generation.model } : {}),
        ...(result.generation.responseId ? { responseId: result.generation.responseId } : {}),
        durationMs: Math.round(performance.now() - startedAt),
        ...(result.generation.usage ? { usage: result.generation.usage } : {}),
        response
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
    const errorDetails = generationErrorDetails(error);
    const details = recordText(errorDetails.value, errorDetails.mediaType);
    const failed = draftEvent<'ai.generation-failed'>({
      type: 'ai.generation-failed',
      actor: { kind: 'system' },
      operationId: options.operationId,
      payload: {
        attempt: options.attempt,
        failureKind: generationFailureKind(error),
        durationMs: Math.round(performance.now() - startedAt),
        message: safeErrorMessage(error),
        details
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

async function compileCandidate(
  options: {
    document: ProjectDocument;
    generationEvent: NewProjectEvent<'ai.generation-succeeded'>;
    candidate: string;
    seed: number;
    operationId: string;
    attempt: 1 | 2;
  },
  dependencies: ProjectCommandDependencies
) {
  const source = recordText(options.candidate, 'text/x-sverlin');
  const recorded = await compileProjectSource(
    {
      document: options.document,
      sourceContent: options.candidate,
      source,
      sourceLabel: 'Main.sverlin',
      seed: options.seed,
      purpose: 'assistant-edit',
      input: 'assistant-candidate',
      operationId: options.operationId,
      attempt: options.attempt
    },
    dependencies.projectService
  );
  return { document: recorded.document, recorded };
}

async function acceptCandidate(
  options: {
    document: ProjectDocument;
    recorded: RecordedCompilation;
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
  const content = recordText(options.candidate, 'text/x-sverlin');
  const change: ArtifactChange = {
    operation: 'upsert',
    artifact: { ...current, content }
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
  document = await activateCompiledRender(
    { ...options.recorded, document },
    dependencies.projectService
  );
  return appendAssistantResponse(
    document,
    options.reply,
    assistantBotId(options.generationEvent),
    options.operationId,
    dependencies
  );
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
  if (error instanceof Error && error.name === 'APITimeoutError') {
    return 'The AI request timed out.';
  }
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
