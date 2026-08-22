import { randomUUID } from 'node:crypto';

import { projectAt, projectHead } from '$lib/projects/project';
import type {
  ArtifactChange,
  FeedbackAttachment,
  NewProjectEvent,
  ProjectCommandResult,
  ProjectDocument,
  SelectedVisualElement,
  VisualSelectionAttachment
} from '$lib/projects/types';
import { getChatbot } from '$lib/server/chat-bots/registry';
import type { CompilationFeedback } from '$lib/server/chat-bots/types';
import { formatDiagnosticSummary } from '$lib/server/compiler-diagnostics';
import type { LiveElement } from '$lib/visualization/types';

import { buildProjectPrompt } from './context';
import { runProjectCommand } from './command-lock';
import { readDslApiFingerprint, sourceSha256 } from './fingerprints';
import { projectRepository } from './repository';
import {
  activateCompiledRender,
  appendProjectEvents,
  compileProjectSource,
  draftEvent
} from './service';

export async function submitProjectFeedback(options: {
  projectId: string;
  expectedHeadEventId: string;
  text?: string;
  attachments?: FeedbackAttachment[];
  seed: number;
  correlationId?: string;
}): Promise<ProjectCommandResult> {
  return runProjectCommand(options.projectId, () => submitProjectFeedbackUnlocked(options));
}

async function submitProjectFeedbackUnlocked(options: {
  projectId: string;
  expectedHeadEventId: string;
  text?: string;
  attachments?: FeedbackAttachment[];
  seed: number;
  correlationId?: string;
}): Promise<ProjectCommandResult> {
  const before = await projectRepository.load(options.projectId);
  assertHead(before, options.expectedHeadEventId);
  const attachments = await validateAttachments(before, options.attachments ?? []);
  const text = options.text?.trim();
  if (!text && attachments.length === 0) throw new Error('Feedback cannot be empty.');

  const correlationId = options.correlationId ?? randomUUID();
  const feedback = draftEvent<'feedback.submitted'>({
    type: 'feedback.submitted',
    actor: { kind: 'user' },
    correlationId,
    payload: { ...(text ? { text } : {}), attachments }
  });
  let document = await appendProjectEvents(before, [feedback]);

  const first = await runGeneration({
    document,
    feedbackEventId: feedback.eventId,
    attempt: 1,
    correlationId
  });
  document = first.document;
  if (!first.ok) return finishMutation(before, document);
  if (first.result.sourceArtifactContent === undefined) {
    document = await appendAssistantResponse(
      document,
      feedback.eventId,
      first.generationEvent.eventId,
      first.result.reply,
      correlationId
    );
    return finishMutation(before, document);
  }

  const firstCompile = await compileCandidate({
    document,
    generationEvent: first.generationEvent,
    candidate: first.result.sourceArtifactContent,
    seed: options.seed,
    correlationId
  });
  document = firstCompile.document;
  if (firstCompile.recorded.result.ok) {
    document = await acceptCandidate({
      document,
      recorded: firstCompile.recorded,
      generationEvent: first.generationEvent,
      feedbackEventId: feedback.eventId,
      reply: first.result.reply,
      candidate: first.result.sourceArtifactContent,
      correlationId
    });
    return finishMutation(before, document);
  }

  const failedEvent = firstCompile.recorded.compileEvent;
  if (failedEvent.type !== 'compilation.failed' || !failedEvent.payload.repairEligible) {
    document = await appendSystemFailure(
      document,
      `The proposed source could not be compiled. ${formatDiagnosticSummary(firstCompile.recorded.result.diagnostics)}`,
      [failedEvent.eventId],
      correlationId
    );
    return finishMutation(before, document);
  }

  const repairFeedback: CompilationFeedback = {
    attempt: 1,
    compilationEventId: failedEvent.eventId,
    failedSource: first.result.sourceArtifactContent,
    assistantReply: first.result.reply,
    diagnostics: firstCompile.recorded.result.diagnostics
  };
  const repair = await runGeneration({
    document,
    feedbackEventId: feedback.eventId,
    attempt: 2,
    correlationId,
    repairOfCompilationEventId: failedEvent.eventId,
    compilationFeedback: repairFeedback
  });
  document = repair.document;
  if (!repair.ok) return finishMutation(before, document);
  if (repair.result.sourceArtifactContent === undefined) {
    document = await appendSystemFailure(
      document,
      'The repair attempt did not return corrected source. The accepted artifact is unchanged.',
      [repair.generationEvent.eventId],
      correlationId
    );
    return finishMutation(before, document);
  }

  const repairCompile = await compileCandidate({
    document,
    generationEvent: repair.generationEvent,
    candidate: repair.result.sourceArtifactContent,
    seed: options.seed,
    correlationId
  });
  document = repairCompile.document;
  if (!repairCompile.recorded.result.ok) {
    document = await appendSystemFailure(
      document,
      `The corrected source still failed compilation. The accepted artifact is unchanged. ${formatDiagnosticSummary(repairCompile.recorded.result.diagnostics)}`,
      [repairCompile.recorded.compileEvent.eventId],
      correlationId
    );
    return finishMutation(before, document);
  }

  document = await acceptCandidate({
    document,
    recorded: repairCompile.recorded,
    generationEvent: repair.generationEvent,
    feedbackEventId: feedback.eventId,
    reply: repair.result.reply,
    candidate: repair.result.sourceArtifactContent,
    correlationId
  });
  return finishMutation(before, document);
}

async function runGeneration(options: {
  document: ProjectDocument;
  feedbackEventId: string;
  attempt: 1 | 2;
  correlationId: string;
  repairOfCompilationEventId?: string;
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
    const document = await appendSystemFailure(
      options.document,
      safeErrorMessage(error),
      [options.feedbackEventId],
      options.correlationId
    );
    return { ok: false as const, document };
  }

  const promptJson = JSON.stringify(prompt);
  const promptRef = await projectRepository.putBlob(
    options.document.projectId,
    promptJson,
    'application/json'
  );
  const request = draftEvent<'ai.generation-requested'>({
    type: 'ai.generation-requested',
    actor: { kind: 'system' },
    correlationId: options.correlationId,
    causationEventId: options.repairOfCompilationEventId ?? options.feedbackEventId,
    payload: {
      attempt: options.attempt,
      purpose: options.attempt === 1 ? 'initial' : 'repair',
      feedbackEventId: options.feedbackEventId,
      ...(options.repairOfCompilationEventId
        ? { repairOfCompilationEventId: options.repairOfCompilationEventId }
        : {}),
      prompt: promptRef,
      promptSha256: promptRef.sha256,
      promptTemplateSha256: sourceSha256(prompt.initialPrompt),
      ...(await optionalDslFingerprint()),
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
    const candidateSource =
      result.sourceArtifactContent !== undefined
        ? await projectRepository.putBlob(
            document.projectId,
            result.sourceArtifactContent,
            'text/x-sverlin'
          )
        : undefined;
    const generationEvent = draftEvent<'ai.generation-succeeded'>({
      type: 'ai.generation-succeeded',
      actor: { kind: 'assistant', botId: result.generation.botId },
      correlationId: options.correlationId,
      causationEventId: request.eventId,
      payload: {
        requestEventId: request.eventId,
        attempt: options.attempt,
        adapterId: result.generation.adapterId,
        botId: result.generation.botId,
        requestedModel: prompt.parameters.model,
        ...(result.generation.model ? { model: result.generation.model } : {}),
        ...(result.generation.responseId ? { responseId: result.generation.responseId } : {}),
        durationMs: Math.round(performance.now() - startedAt),
        ...(result.generation.usage ? { usage: result.generation.usage } : {}),
        response,
        ...(candidateSource ? { candidateSource } : {}),
        reply: result.reply
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
      correlationId: options.correlationId,
      causationEventId: request.eventId,
      payload: {
        requestEventId: request.eventId,
        attempt: options.attempt,
        failureKind: generationFailureKind(error),
        durationMs: Math.round(performance.now() - startedAt),
        message: safeErrorMessage(error),
        details
      }
    });
    document = await appendProjectEvents(document, [failed]);
    document = await appendSystemFailure(
      document,
      failed.payload.message,
      [failed.eventId],
      options.correlationId
    );
    return { ok: false as const, document };
  }
}

async function compileCandidate(options: {
  document: ProjectDocument;
  generationEvent: Extract<NewProjectEvent, { type: 'ai.generation-succeeded' }>;
  candidate: string;
  seed: number;
  correlationId: string;
}) {
  const source =
    options.generationEvent.payload.candidateSource ??
    (await projectRepository.putBlob(
      options.document.projectId,
      options.candidate,
      'text/x-sverlin'
    ));
  const recorded = await compileProjectSource({
    document: options.document,
    sourceContent: options.candidate,
    source,
    sourceLabel: 'Main.sverlin',
    seed: options.seed,
    purpose: 'assistant-edit',
    input: 'assistant-candidate',
    correlationId: options.correlationId
  });
  return { document: recorded.document, recorded };
}

async function acceptCandidate(options: {
  document: ProjectDocument;
  recorded: Awaited<ReturnType<typeof compileProjectSource>>;
  generationEvent: Extract<NewProjectEvent, { type: 'ai.generation-succeeded' }>;
  feedbackEventId: string;
  reply: string;
  candidate: string;
  correlationId: string;
}) {
  const snapshot = projectAt(options.document);
  const current = snapshot.artifacts[snapshot.entryArtifactId];
  if (!current) throw new Error('The project has no entry artifact.');
  const content =
    options.generationEvent.payload.candidateSource ??
    (await projectRepository.putBlob(
      options.document.projectId,
      options.candidate,
      'text/x-sverlin'
    ));
  const change: ArtifactChange = {
    operation: 'upsert',
    artifact: { ...current, content, contentSha256: content.sha256 }
  };
  const artifactEvent = draftEvent<'artifact.version-created'>({
    type: 'artifact.version-created',
    actor: { kind: 'assistant', botId: options.generationEvent.payload.botId },
    correlationId: options.correlationId,
    causationEventId: options.generationEvent.eventId,
    payload: {
      origin: { kind: 'assistant-edit', generationEventId: options.generationEvent.eventId },
      changes: [change]
    }
  });
  let document = await appendProjectEvents(options.document, [artifactEvent]);
  document = await activateCompiledRender({ ...options.recorded, document });
  return appendAssistantResponse(
    document,
    options.feedbackEventId,
    options.generationEvent.eventId,
    options.reply,
    options.correlationId
  );
}

async function appendAssistantResponse(
  document: ProjectDocument,
  feedbackEventId: string,
  generationEventId: string,
  text: string,
  correlationId: string
) {
  const event = draftEvent<'assistant.responded'>({
    type: 'assistant.responded',
    actor: { kind: 'assistant', botId: 'ai-assistant' },
    correlationId,
    causationEventId: generationEventId,
    payload: { feedbackEventId, generationEventId, text }
  });
  return appendProjectEvents(document, [event]);
}

async function appendSystemFailure(
  document: ProjectDocument,
  message: string,
  relatedEventIds: string[],
  correlationId: string
) {
  const event = draftEvent<'system.notified'>({
    type: 'system.notified',
    actor: { kind: 'system' },
    correlationId,
    causationEventId: relatedEventIds.at(-1),
    payload: { severity: 'error', message, relatedEventIds }
  });
  return appendProjectEvents(document, [event]);
}

async function validateAttachments(
  document: ProjectDocument,
  attachments: FeedbackAttachment[]
): Promise<FeedbackAttachment[]> {
  const events = new Map(document.events.map((event) => [event.eventId, event]));
  return Promise.all(
    attachments.map(async (attachment) => {
      if (attachment.kind === 'timeline-reference') {
        for (const eventId of attachment.eventIds) {
          if (!events.has(eventId)) throw new Error(`Unknown referenced event ${eventId}.`);
        }
        return attachment;
      }

      const renderEvent = events.get(attachment.renderEventId);
      if (renderEvent?.type !== 'visualization.rendered') {
        throw new Error('The visual selection references an unknown render.');
      }
      const trace = JSON.parse(
        await projectRepository.readTextBlob(document.projectId, renderEvent.payload.render)
      );
      const step = trace.steps?.[attachment.step.index];
      if (!step) throw new Error('The visual selection references an unknown trace step.');
      const selectedIds = new Set(attachment.elements.map((element) => element.instanceId));
      const instances = step.instances.filter((instance: { id: number }) =>
        selectedIds.has(instance.id)
      );
      if (instances.length !== selectedIds.size) {
        throw new Error('The visual selection contains an unknown render instance.');
      }
      const elements = instances.map((instance: { id: number; elementId: number }) => {
        const element = trace.elements.find(
          (candidate: LiveElement) => candidate.id === instance.elementId
        );
        if (!element) throw new Error('The visual selection contains an unknown element.');
        return {
          elementId: element.id,
          instanceId: instance.id,
          role: element.role,
          ...(element.content ? { content: element.content } : {}),
          kind: element.kind,
          style: element.style,
          styleVariables: element.styleVariables
        } satisfies SelectedVisualElement;
      });
      return {
        ...attachment,
        step: { index: attachment.step.index, label: step.label },
        elements
      } satisfies VisualSelectionAttachment;
    })
  );
}

function finishMutation(before: ProjectDocument, document: ProjectDocument): ProjectCommandResult {
  return { document, appendedEvents: document.events.slice(before.events.length) };
}

async function optionalDslFingerprint() {
  const dslApiSha256 = await readDslApiFingerprint();
  return dslApiSha256 ? { dslApiSha256 } : {};
}

function assertHead(document: ProjectDocument, expectedHeadEventId: string) {
  if (projectHead(document).eventId !== expectedHeadEventId) {
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
      // Fall through to the readable error when a provider object is not serializable.
    }
  }
  return { value: summary, mediaType: 'text/plain' };
}
