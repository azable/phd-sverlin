/**
 * AI-assisted feedback command orchestration for projects.
 *
 * @packageDocumentation
 */

import type { EventId, NewProjectEvent } from '$lib/projects/events';
import type { ArtifactChange, VisualSelection } from '$lib/projects/events/values';
import type { ProjectCommandResult, ProjectDocument } from '$lib/projects/model';
import { projectHead, projectSnapshotAt } from '$lib/projects/projection';
import { getChatbot } from '$lib/server/chat-bots/registry';
import type { CompilationFeedback } from '$lib/server/chat-bots/types';
import { formatDiagnosticSummary } from '$lib/server/compiler-diagnostics';
import { decodeVisualization } from '$lib/visualization/types';

import { buildProjectPrompt } from './prompt-context';
import { runProjectCommand } from './command-lock';
import { readDslRevision, sourceSha256 } from './fingerprints';
import { projectRepository } from './repository';
import {
  activateCompiledRender,
  appendProjectEvents,
  compileProjectSource,
  draftEvent,
  type RecordedCompilation
} from './service';

/** Record user feedback, run AI generation, and accept at most one compiled candidate. */
export function submitProjectFeedback(options: {
  projectId: string;
  expectedHead: EventId;
  text?: string;
  focus: EventId[];
  selection?: VisualSelection;
  seed: number;
  operationId: string;
}): Promise<ProjectCommandResult> {
  return runProjectCommand(options.projectId, () => submitProjectFeedbackUnlocked(options));
}

async function submitProjectFeedbackUnlocked(options: {
  projectId: string;
  expectedHead: EventId;
  text?: string;
  focus: EventId[];
  selection?: VisualSelection;
  seed: number;
  operationId: string;
}): Promise<ProjectCommandResult> {
  const before = await projectRepository.load(options.projectId);
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
  let document = await appendProjectEvents(before, [feedback]);

  const first = await runGeneration({ document, attempt: 1, operationId: options.operationId });
  document = first.document;
  if (!first.ok) return finishMutation(before, document);
  if (first.result.sourceArtifactContent === undefined) {
    document = await appendAssistantResponse(document, first.result.reply, options.operationId);
    return finishMutation(before, document);
  }

  const firstCompile = await compileCandidate({
    document,
    generationEvent: first.generationEvent,
    candidate: first.result.sourceArtifactContent,
    seed: options.seed,
    operationId: options.operationId,
    attempt: 1
  });
  document = firstCompile.document;
  if (firstCompile.recorded.result.ok) {
    document = await acceptCandidate({
      document,
      recorded: firstCompile.recorded,
      generationEvent: first.generationEvent,
      reply: first.result.reply,
      candidate: first.result.sourceArtifactContent,
      operationId: options.operationId
    });
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
      options.operationId
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
  const repair = await runGeneration({
    document,
    attempt: 2,
    operationId: options.operationId,
    compilationFeedback: repairFeedback
  });
  document = repair.document;
  if (!repair.ok) return finishMutation(before, document);
  if (repair.result.sourceArtifactContent === undefined) {
    document = await appendSystemFailure(
      document,
      'The repair attempt did not return corrected source. The accepted artifact is unchanged.',
      options.operationId
    );
    return finishMutation(before, document);
  }

  const repairCompile = await compileCandidate({
    document,
    generationEvent: repair.generationEvent,
    candidate: repair.result.sourceArtifactContent,
    seed: options.seed,
    operationId: options.operationId,
    attempt: 2
  });
  document = repairCompile.document;
  if (!repairCompile.recorded.result.ok) {
    document = await appendSystemFailure(
      document,
      `The corrected source still failed compilation. The accepted artifact is unchanged. ${formatDiagnosticSummary(repairCompile.recorded.result.diagnostics)}`,
      options.operationId
    );
    return finishMutation(before, document);
  }

  document = await acceptCandidate({
    document,
    recorded: repairCompile.recorded,
    generationEvent: repair.generationEvent,
    reply: repair.result.reply,
    candidate: repair.result.sourceArtifactContent,
    operationId: options.operationId
  });
  return finishMutation(before, document);
}

async function runGeneration(options: {
  document: ProjectDocument;
  attempt: 1 | 2;
  operationId: string;
  compilationFeedback?: CompilationFeedback;
}) {
  const chatbot = getChatbot();
  const input = await buildProjectPrompt(options.document);
  let prompt;
  try {
    prompt = await chatbot.preparePrompt({
      messages: input.messages,
      project: input.project,
      ...(options.compilationFeedback ? { compilationFeedback: options.compilationFeedback } : {})
    });
  } catch (error) {
    return {
      ok: false as const,
      document: await appendSystemFailure(
        options.document,
        safeErrorMessage(error),
        options.operationId
      )
    };
  }

  const promptRef = await projectRepository.putBlob(
    options.document.projectId,
    JSON.stringify(prompt),
    'application/json'
  );
  const dslRevision = await readDslRevision();
  const request = draftEvent<'ai.generation-requested'>({
    type: 'ai.generation-requested',
    actor: { kind: 'system' },
    operationId: options.operationId,
    payload: {
      attempt: options.attempt,
      purpose: options.attempt === 1 ? 'initial' : 'repair',
      prompt: promptRef,
      promptTemplateSha256: sourceSha256(prompt.initialPrompt),
      ...(dslRevision ? { dslRevision } : {}),
      requestedModel: prompt.parameters.model,
      parameters: { ...prompt.parameters }
    }
  });
  let document = await appendProjectEvents(options.document, [request]);
  const startedAt = performance.now();

  try {
    const result = await chatbot.generatePrepared(prompt);
    const response = await projectRepository.putBlob(
      document.projectId,
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
    document = await appendProjectEvents(document, [generationEvent]);
    return { ok: true as const, document, result, generationEvent };
  } catch (error) {
    const errorDetails = generationErrorDetails(error);
    const details = await projectRepository.putBlob(
      document.projectId,
      errorDetails.value,
      errorDetails.mediaType
    );
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
    document = await appendProjectEvents(document, [failed]);
    document = await appendSystemFailure(document, failed.payload.message, options.operationId);
    return { ok: false as const, document };
  }
}

async function compileCandidate(options: {
  document: ProjectDocument;
  generationEvent: NewProjectEvent<'ai.generation-succeeded'>;
  candidate: string;
  seed: number;
  operationId: string;
  attempt: 1 | 2;
}) {
  const source = await projectRepository.putBlob(
    options.document.projectId,
    options.candidate,
    'text/x-sverlin'
  );
  const recorded = await compileProjectSource({
    document: options.document,
    sourceContent: options.candidate,
    source,
    sourceLabel: 'Main.sverlin',
    seed: options.seed,
    purpose: 'assistant-edit',
    input: 'assistant-candidate',
    operationId: options.operationId,
    attempt: options.attempt
  });
  return { document: recorded.document, recorded };
}

async function acceptCandidate(options: {
  document: ProjectDocument;
  recorded: RecordedCompilation;
  generationEvent: NewProjectEvent<'ai.generation-succeeded'>;
  reply: string;
  candidate: string;
  operationId: string;
}) {
  const snapshot = projectSnapshotAt(options.document);
  const current = snapshot.artifacts[snapshot.entryArtifactId];
  if (!current) throw new Error('The project has no entry artifact.');
  const content = await projectRepository.putBlob(
    options.document.projectId,
    options.candidate,
    'text/x-sverlin'
  );
  const change: ArtifactChange = {
    operation: 'upsert',
    artifact: { ...current, content }
  };
  let document = await appendProjectEvents(options.document, [
    draftEvent({
      type: 'artifact.version-created',
      actor: options.generationEvent.actor,
      operationId: options.operationId,
      payload: { origin: { kind: 'assistant-edit' }, changes: [change] }
    })
  ]);
  document = await activateCompiledRender({ ...options.recorded, document });
  return appendAssistantResponse(document, options.reply, options.operationId);
}

function appendAssistantResponse(document: ProjectDocument, text: string, operationId: string) {
  return appendProjectEvents(document, [
    draftEvent({
      type: 'assistant.responded',
      actor: { kind: 'assistant', botId: 'ai-assistant' },
      operationId,
      payload: { text }
    })
  ]);
}

function appendSystemFailure(document: ProjectDocument, message: string, operationId: string) {
  return appendProjectEvents(document, [
    draftEvent({
      type: 'system.notified',
      actor: { kind: 'system' },
      operationId,
      payload: { severity: 'error', message }
    })
  ]);
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
  const visualization = decodeVisualization(
    await projectRepository.readTextBlob(document.projectId, renderEvent.payload.render)
  );
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
