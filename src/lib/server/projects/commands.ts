/** AI-assisted feedback orchestration for Sverlin and direct-HTML projects. */

import { randomUUID } from 'node:crypto';

import { InvalidChatbotResponseError } from '$lib/server/chat-adapters/types';
import type { EventId, NewProjectEvent } from '$lib/shared/projects/events';
import { markdownMessage, type MessageContent } from '$lib/shared/projects/events/message-content';
import type {
  ArtifactChange,
  DslRevision,
  VisualSelection
} from '$lib/shared/projects/events/values';
import type { ProjectCommandResult, ProjectDocument } from '$lib/shared/projects/model';
import { presentationBufferState } from '$lib/shared/projects/presentation-buffer';
import type {
  HtmlFramesPresentation,
  HtmlFramesManifest,
  RenderablePresentation
} from '$lib/shared/presentations';
import { projectHead, projectSnapshotAt } from '$lib/shared/projects/projection';
import { assistantTurnClaim, projectOperation } from '$lib/shared/projects/operations';
import { getChatbot, getHtmlChatbot } from '$lib/server/chat-bots/registry';
import type { HtmlAssistantOutput } from '$lib/server/chat-bots/html-assistant';
import {
  projectAiContext,
  projectConversationMessages,
  type AiContextSelection,
  type AiProjectContext
} from '$lib/server/chat-bots/sverlin-assistant/project-context';
import type {
  Chatbot,
  ChatbotPrompt,
  ChatbotResult,
  CompilationFeedback,
  GeneratedMessageContent,
  RecoveryExplanation,
  SourceArtifactChatOutput
} from '$lib/server/chat-bots/types';
import { formatDiagnosticSummary } from '$lib/server/compiler';
import { createHtmlPresentation } from '$lib/server/visualization-modes';

import { runProjectCommand } from './command-lock';
import { readDslRevision, recordText, sourceSha256 } from './fingerprints';
import { appendProjectPreference } from './presentations';
import {
  assertCurrentProjectOperationActive,
  currentProjectOperationDeadline,
  currentProjectOperationSignal
} from './operation-context';
import { projectRepository, type ProjectRepository } from './repository';
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
import { resolveProjectVisualSelection } from './visual-selection';

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

/** Validate and durably queue participant feedback without waiting for the assistant. */
export function queueProjectFeedback(
  options: {
    projectId: string;
    operationId: string;
    content: MessageContent;
    focus: EventId[];
    presentationCount: 1 | 2;
    deadlineAt?: string;
  },
  dependencies: ProjectCommandDependencies = defaultProjectCommandDependencies
): Promise<ProjectCommandResult> {
  return runProjectCommand(options.projectId, async () => {
    assertCurrentProjectOperationActive();
    const before = await dependencies.repository.load(options.projectId);
    assertAcceptedInteraction(before, options.operationId, 'feedback');
    const focus = validateFocus(before, options.focus);
    const content = await validateMessageContent(before, options.content);
    const interactionEventId = projectHead(before).id + 1;
    const document = await appendProjectEvents(
      before,
      [
        draftEvent({
          type: 'feedback.submitted',
          actor: { kind: 'user' },
          operationId: options.operationId,
          payload: { content, focus, presentationCount: options.presentationCount }
        }),
        draftEvent({
          type: 'assistant.turn-requested',
          actor: { kind: 'system' },
          operationId: options.operationId,
          payload: {
            interactionEventId,
            presentationCount: options.presentationCount,
            ...(options.deadlineAt ? { deadlineAt: options.deadlineAt } : {})
          }
        })
      ],
      [],
      dependencies.projectService
    );
    return finishMutation(before, document);
  });
}

/** Validate and durably queue one comparison preference without waiting for the assistant. */
export function queueProjectPreference(
  options: {
    projectId: string;
    operationId: string;
    presentations: [string, string];
    preferred: string;
    step: number;
    visualSelections: VisualSelection[];
    deadlineAt?: string;
  },
  dependencies: ProjectCommandDependencies = defaultProjectCommandDependencies
): Promise<ProjectCommandResult> {
  return runProjectCommand(options.projectId, async () => {
    assertCurrentProjectOperationActive();
    const before = await dependencies.repository.load(options.projectId);
    assertAcceptedInteraction(before, options.operationId, 'prefer');
    let document = await appendProjectPreference(before, options, dependencies.projectService);
    const preference = document.events.findLast(
      (event) =>
        event.operationId === options.operationId &&
        event.type === 'visualization.preference-recorded'
    );
    if (preference?.type !== 'visualization.preference-recorded') {
      throw new Error('The recorded preference event could not be resolved.');
    }
    document = await appendProjectEvents(
      document,
      [
        draftEvent({
          type: 'assistant.turn-requested',
          actor: { kind: 'system' },
          operationId: options.operationId,
          payload: {
            interactionEventId: preference.id,
            presentationCount: 2,
            ...(options.deadlineAt ? { deadlineAt: options.deadlineAt } : {})
          }
        })
      ],
      [],
      dependencies.projectService
    );
    return finishMutation(before, document);
  });
}

/** Process one durable claim while allowing new participant interactions to append concurrently. */
export async function runQueuedSverlinAssistantTurn(
  options: { projectId: string; operationId: string },
  dependencies: ProjectCommandDependencies = defaultProjectCommandDependencies
): Promise<ProjectCommandResult> {
  const before = await dependencies.repository.load(options.projectId);
  const claim = assistantTurnClaim(before, options.operationId);
  if (!claim) throw new Error('The assistant operation has no durable turn claim.');
  const requests = claim.payload.requestEventIds.map((id) => before.events[id - 1]);
  if (requests.some((event) => event?.type !== 'assistant.turn-requested')) {
    throw new Error('The assistant turn claim references an unknown request.');
  }
  const interactions = claim.payload.interactionEventIds.map((id) => before.events[id - 1]);
  if (
    interactions.some(
      (event) =>
        event?.type !== 'feedback.submitted' && event?.type !== 'visualization.preference-recorded'
    )
  ) {
    throw new Error('The assistant turn claim references an unknown interaction.');
  }
  const feedback = interactions.filter(
    (event): event is Extract<(typeof interactions)[number], { type: 'feedback.submitted' }> =>
      event?.type === 'feedback.submitted'
  );
  const preferences = interactions.filter(
    (
      event
    ): event is Extract<
      (typeof interactions)[number],
      { type: 'visualization.preference-recorded' }
    > => event?.type === 'visualization.preference-recorded'
  );
  const content = feedback.flatMap((event) => event.payload.content);
  const contextSelection: AiContextSelection = {
    eventIds: [...new Set(feedback.flatMap((event) => event.payload.focus))],
    presentationIds: [
      ...new Set([
        ...referencedPresentations(content),
        ...preferences.flatMap((event) => event.payload.presentations)
      ])
    ],
    visualSelections: deduplicateVisualSelections([
      ...referencedVisualSelections(content),
      ...preferences.flatMap((event) => event.payload.visualSelections ?? [])
    ]),
    interactionEventIds: claim.payload.interactionEventIds
  };
  const presentationCount = Math.max(
    ...requests.map((event) =>
      event?.type === 'assistant.turn-requested' ? event.payload.presentationCount : 1
    )
  ) as 1 | 2;
  const concurrentDependencies = rebasingDependencies(dependencies);
  const document = await runSverlinAssistantTurn(
    before,
    options.operationId,
    contextSelection,
    presentationCount,
    concurrentDependencies,
    claim.payload.interactionEventIds
  );
  return {
    document,
    appendedEvents: document.events.filter(
      (event) => event.id > projectHead(before).id && event.operationId === options.operationId
    )
  };
}

/** Record user feedback and produce the mode's next visualization response. */
export function submitProjectFeedback(
  options: {
    projectId: string;
    expectedHead: EventId;
    content: MessageContent;
    focus: EventId[];
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
    content: MessageContent;
    focus: EventId[];
    presentationCount: 1 | 2;
    operationId: string;
  },
  dependencies: ProjectCommandDependencies
): Promise<ProjectCommandResult> {
  const before = await dependencies.repository.load(options.projectId);
  assertHead(before, options.expectedHead);
  const focus = validateFocus(before, options.focus);
  const content = await validateMessageContent(before, options.content);
  const presentations = referencedPresentations(content);
  const visualSelections = referencedVisualSelections(content);

  let document = await appendProjectEvents(
    before,
    [
      draftEvent({
        type: 'feedback.submitted',
        actor: { kind: 'user' },
        operationId: options.operationId,
        payload: { content, focus }
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
        visualSelections
      },
      dependencies
    );
    return finishMutation(before, document);
  }

  const contextSelection: AiContextSelection = {
    eventIds: focus,
    presentationIds: presentations,
    visualSelections
  };
  document = await runSverlinAssistantTurn(
    document,
    options.operationId,
    contextSelection,
    options.presentationCount,
    dependencies
  );
  return finishMutation(before, document);
}

/** Record a pairwise preference and let the Sverlin assistant decide whether to adapt source. */
export function submitProjectPreference(
  options: {
    projectId: string;
    expectedHead: EventId;
    presentations: [string, string];
    preferred: string;
    step: number;
    visualSelections: VisualSelection[];
    operationId: string;
  },
  dependencies: ProjectCommandDependencies = defaultProjectCommandDependencies
): Promise<ProjectCommandResult> {
  return runProjectCommand(options.projectId, async () => {
    const before = await dependencies.repository.load(options.projectId);
    assertHead(before, options.expectedHead);
    let document = await appendProjectPreference(before, options, dependencies.projectService);
    const preference = document.events.findLast(
      (event) =>
        event.operationId === options.operationId &&
        event.type === 'visualization.preference-recorded'
    );
    if (preference?.type !== 'visualization.preference-recorded') {
      throw new Error('The recorded preference event could not be resolved.');
    }
    document = await runSverlinAssistantTurn(
      document,
      options.operationId,
      {
        eventIds: [],
        presentationIds: options.presentations,
        visualSelections: preference.payload.visualSelections ?? [],
        interactionEventIds: [preference.id]
      },
      2,
      dependencies
    );
    return finishMutation(before, document);
  });
}

async function runSverlinAssistantTurn(
  document: ProjectDocument,
  operationId: string,
  contextSelection: AiContextSelection,
  presentationCount: 1 | 2,
  dependencies: ProjectCommandDependencies,
  inReplyTo: readonly EventId[] = []
): Promise<ProjectDocument> {
  const chatbot = dependencies.getChatbot(projectSnapshotAt(document).assistantId);
  let seeds: readonly number[] | undefined;
  const failureSummaries: string[] = [];
  let compilationFeedback: CompilationFeedback | undefined;

  return runAttemptLadder(
    document,
    operationId,
    chatbot,
    dependencies,
    async (current, attempt) => {
      const generation = await runSverlinGeneration(
        {
          chatbot,
          document: current,
          attempt,
          operationId,
          contextSelection,
          presentationCount,
          ...(compilationFeedback ? { compilationFeedback } : {})
        },
        dependencies
      );
      current = generation.document;
      if (!generation.ok) return { document: current, done: true };

      if (attempt === 1) {
        current = await appendAssistantResponse(
          current,
          resolveAssistantContent(current, generation.result.reply, []),
          assistantBotId(generation.generationEvent),
          operationId,
          dependencies,
          inReplyTo
        );
      }

      const candidate = generation.result.sourceArtifactContent;
      if (candidate === undefined) {
        if (attempt === 1) {
          const advanced =
            generation.result.action === 'resample'
              ? await advanceCandidatesForAgent(
                  current,
                  presentationCount,
                  operationId,
                  dependencies
                )
              : { document: current, presentations: [] };
          current = advanced.document;
          return { document: advanced.document, done: true };
        }
        failureSummaries.push(`Attempt ${attempt} did not return corrected source.`);
        if (!compilationFeedback || attempt === chatbot.config.attemptProfiles.length) {
          return {
            document: await appendExhaustedSverlinFailure(
              current,
              operationId,
              failureSummaries.at(-1),
              dependencies
            ),
            done: true
          };
        }
        compilationFeedback = {
          ...compilationFeedback,
          attempt,
          assistantReply: generatedReplyText(generation.result.reply),
          priorFailureSummaries: [...failureSummaries]
        };
        return { document: current, done: false };
      }

      seeds ??= freshPresentationSeeds(presentationCount);
      const compiled = await compileCandidateBatch(
        { document: current, candidate, seeds, operationId, attempt },
        dependencies
      );
      current = compiled.document;
      if (batchSucceeded(compiled.recorded)) {
        assertCurrentProjectOperationActive();
        return {
          document: await acceptSverlinCandidate(
            {
              document: current,
              recorded: compiled.recorded,
              generationEvent: generation.generationEvent,
              candidate,
              operationId,
              recovery: generation.result.recovery,
              recoveryReply: generation.result.reply,
              inReplyTo
            },
            dependencies
          ),
          done: true
        };
      }

      const failed = firstFailure(compiled.recorded);
      if (!failed || failed.compileEvent.type !== 'compilation.failed') {
        throw new Error('A failed compilation batch had no failure event.');
      }
      const summary = formatDiagnosticSummary(failed.result.diagnostics);
      failureSummaries.push(`Attempt ${attempt}: ${summary}`);
      if (!failed.compileEvent.payload.repairEligible) {
        return {
          document: await appendSystemFailure(
            current,
            `The proposed visualization could not be checked safely, so I kept the last working visualization. The remaining difficulty was: ${plainFailureSummary(participantDiagnostic(failed.result.diagnostics))}`,
            operationId,
            dependencies
          ),
          done: true
        };
      }
      if (attempt === chatbot.config.attemptProfiles.length) {
        return {
          document: await appendExhaustedSverlinFailure(
            current,
            operationId,
            participantDiagnostic(failed.result.diagnostics),
            dependencies
          ),
          done: true
        };
      }
      compilationFeedback = {
        attempt,
        compilationEventId:
          current.events.findLast(
            (event) => event.operationId === operationId && event.type === 'compilation.failed'
          )?.id ?? projectHead(current).id,
        failedSource: candidate,
        assistantReply: generatedReplyText(generation.result.reply),
        diagnostics: failed.result.diagnostics,
        priorFailureSummaries: [...failureSummaries]
      };
      return { document: current, done: false };
    }
  );
}

async function submitHtmlFeedback(
  document: ProjectDocument,
  operationId: string,
  contextSelection: AiContextSelection,
  dependencies: ProjectCommandDependencies
): Promise<ProjectDocument> {
  const chatbot = dependencies.getHtmlChatbot(projectSnapshotAt(document).assistantId);
  const failureSummaries: string[] = [];
  let correction: string | undefined;

  return runAttemptLadder(
    document,
    operationId,
    chatbot,
    dependencies,
    async (current, attempt) => {
      const generation = await runHtmlGeneration(
        {
          chatbot,
          document: current,
          attempt,
          operationId,
          contextSelection,
          ...(correction ? { correction } : {})
        },
        dependencies
      );
      current = generation.document;
      if (!generation.ok) return { document: current, done: true };
      if (generation.result.candidates.length === 0) {
        if (attempt === 1) {
          return {
            document: await appendAssistantResponse(
              current,
              resolveAssistantContent(current, generation.result.reply, []),
              assistantBotId(generation.generationEvent),
              operationId,
              dependencies
            ),
            done: true
          };
        }
        const summary = `Attempt ${attempt} did not return a visualization candidate.`;
        failureSummaries.push(summary);
        if (attempt === chatbot.config.attemptProfiles.length) {
          return {
            document: await appendExhaustedHtmlFailure(
              current,
              operationId,
              'the generated HTML still did not pass the visualization safety checks',
              dependencies
            ),
            done: true
          };
        }
        correction = htmlCorrection([], summary, failureSummaries);
        return { document: current, done: false };
      }

      let accepted: AcceptedHtmlTurn;
      try {
        accepted = {
          presentations: generation.result.candidates.map(({ manifest }) =>
            createHtmlPresentation(manifest, projectHead(current).id)
          ),
          reply: replyWithRecovery(generation.result.reply, generation.result.recovery),
          generationEvent: generation.generationEvent
        };
      } catch (cause) {
        const summary = errorMessage(cause);
        failureSummaries.push(`Attempt ${attempt}: ${summary}`);
        if (attempt === chatbot.config.attemptProfiles.length) {
          return {
            document: await appendExhaustedHtmlFailure(
              current,
              operationId,
              'the generated HTML still did not pass the visualization safety checks',
              dependencies
            ),
            done: true
          };
        }
        correction = htmlCorrection(generation.result.candidates, cause, failureSummaries);
        return { document: current, done: false };
      }
      assertCurrentProjectOperationActive();
      return {
        document: await acceptHtmlTurn(current, accepted, operationId, dependencies),
        done: true
      };
    }
  );
}

type AcceptedHtmlTurn = {
  presentations: HtmlFramesPresentation[];
  reply: GeneratedMessageContent;
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
  const first = accepted.presentations[0];
  if (!first) throw new Error('An accepted HTML turn needs at least one presentation.');
  const displaySetId = randomUUID();
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
              artifact: { ...current, language: 'json', content: first.authored }
            }
          ]
        }
      }),
      ...accepted.presentations.map((presentation, slot) =>
        draftEvent({
          type: 'visualization.presented',
          actor: accepted.generationEvent.actor,
          operationId,
          payload: { displaySetId, slot: slot as 0 | 1, presentation }
        })
      )
    ],
    [],
    dependencies.projectService
  );
  return appendAssistantResponse(
    document,
    resolveAssistantContent(document, accepted.reply, accepted.presentations),
    assistantBotId(accepted.generationEvent),
    operationId,
    dependencies
  );
}

async function runSverlinGeneration(
  options: {
    chatbot: Chatbot<AiProjectContext, SourceArtifactChatOutput>;
    document: ProjectDocument;
    attempt: number;
    operationId: string;
    contextSelection: AiContextSelection;
    presentationCount: 1 | 2;
    compilationFeedback?: CompilationFeedback;
  },
  dependencies: ProjectCommandDependencies
) {
  let prompt;
  try {
    prompt = await options.chatbot.preparePrompt({
      messages: projectConversationMessages(options.document.events),
      project: projectAiContext(options.document, options.contextSelection),
      attempt: options.attempt,
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
      generate: () =>
        options.chatbot.generatePrepared(prompt, { signal: currentProjectOperationSignal() }),
      validateResult: (result) => {
        validateRecoveryExplanation(prompt, result.recovery, result.providerResponse);
        if (
          options.contextSelection.interactionEventIds?.some(
            (id) => options.document.events[id - 1]?.type === 'visualization.preference-recorded'
          ) &&
          result.sourceArtifactContent === undefined &&
          result.action === 'resample'
        ) {
          throw new InvalidChatbotResponseError(
            'A deferred preference adaptation cannot advance candidates itself.',
            result.providerResponse
          );
        }
        validateGeneratedReply(options.document, result.reply, 0, result.providerResponse);
      },
      fallbackResponse: (result) => ({
        reply: result.reply,
        action: result.action,
        sourceArtifactContent: result.sourceArtifactContent ?? null,
        recovery: result.recovery ?? null,
        generation: result.generation
      })
    },
    dependencies
  );
}

async function runHtmlGeneration(
  options: {
    chatbot: Chatbot<AiProjectContext, HtmlAssistantOutput>;
    document: ProjectDocument;
    attempt: number;
    operationId: string;
    contextSelection: AiContextSelection;
    correction?: string;
  },
  dependencies: ProjectCommandDependencies
) {
  let prompt;
  try {
    prompt = await options.chatbot.preparePrompt({
      messages: [
        ...projectConversationMessages(options.document.events),
        ...(options.correction ? [{ role: 'user' as const, content: options.correction }] : [])
      ],
      project: projectAiContext(options.document, options.contextSelection),
      attempt: options.attempt
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
      generate: () =>
        options.chatbot.generatePrepared(prompt, { signal: currentProjectOperationSignal() }),
      validateResult: (result) => {
        validateGeneratedReply(
          options.document,
          result.reply,
          result.candidates.length,
          result.providerResponse
        );
        validateRecoveryExplanation(prompt, result.recovery, result.providerResponse);
      },
      fallbackResponse: (result) => ({
        reply: result.reply,
        candidates: result.candidates,
        recovery: result.recovery ?? null,
        generation: result.generation
      })
    },
    dependencies
  );
}

async function generationPreparationFailure(
  options: { document: ProjectDocument; operationId: string; attempt: number },
  error: unknown,
  dependencies: ProjectCommandDependencies
) {
  const details = generationErrorDetails(error);
  const failed = draftEvent<'ai.generation-failed'>({
    type: 'ai.generation-failed',
    actor: { kind: 'system' },
    operationId: options.operationId,
    payload: {
      attempt: options.attempt,
      failureKind: generationFailureKind(error),
      durationMs: 0,
      message: safeErrorMessage(error),
      details: recordText(details.value, details.mediaType)
    }
  });
  const document = await appendProjectEvents(
    options.document,
    [failed],
    [],
    dependencies.projectService
  );
  return {
    ok: false as const,
    document: await appendSystemFailure(
      document,
      failed.payload.message,
      options.operationId,
      dependencies
    )
  };
}

async function runPreparedGeneration<Output extends { reply: GeneratedMessageContent }>(
  options: {
    document: ProjectDocument;
    attempt: number;
    operationId: string;
    prompt: ChatbotPrompt;
    dslRevision?: DslRevision;
    generate: () => Promise<ChatbotResult<Output>>;
    validateResult: (result: ChatbotResult<Output>) => void;
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
      purpose: options.prompt.attempt.purpose,
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
    options.validateResult(result);
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
    attempt: number;
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
    candidate: string;
    operationId: string;
    recovery?: RecoveryExplanation;
    recoveryReply: GeneratedMessageContent;
    inReplyTo: readonly EventId[];
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
  if (!options.recovery) return document;
  return appendAssistantResponse(
    document,
    resolveAssistantContent(
      document,
      replyWithRecovery(options.recoveryReply, options.recovery),
      []
    ),
    assistantBotId(options.generationEvent),
    options.operationId,
    dependencies,
    options.inReplyTo
  );
}

async function advanceCandidatesForAgent(
  document: ProjectDocument,
  presentationCount: 1 | 2,
  operationId: string,
  dependencies: ProjectCommandDependencies
): Promise<{ document: ProjectDocument; presentations: RenderablePresentation[] }> {
  const current = presentationBufferState(document, 0).available.slice(0, presentationCount);
  let available = presentationBufferState(document, 0).available;
  const remaining = available.slice(current.length);
  if (remaining.length < presentationCount) {
    const snapshot = projectSnapshotAt(document);
    const artifact = snapshot.artifacts[snapshot.entryArtifactId];
    if (!artifact || snapshot.renderer !== 'sverlin') {
      throw new Error('Only Sverlin projects can generate buffered candidates from source.');
    }
    const recorded = await compileProjectSourceBatch(
      {
        document,
        sourceContent: artifact.content.text,
        source: artifact.content,
        sourceLabel: artifact.path,
        seeds: freshPresentationSeeds((presentationCount - remaining.length) as 1 | 2),
        purpose: 'seed-change',
        input: 'committed-artifact',
        operationId
      },
      dependencies.projectService
    );
    document = recorded.document;
    if (!batchSucceeded(recorded)) {
      throw new Error('The next visualization candidates could not be compiled.');
    }
    document = await activateCompiledPresentations(recorded, dependencies.projectService);
    available = presentationBufferState(document, 0).available;
  }
  if (current.length > 0) {
    document = await appendProjectEvents(
      document,
      [
        draftEvent({
          type: 'visualization.candidates-advanced',
          actor: { kind: 'system' },
          operationId,
          payload: {
            presentations: current.map(({ presentationId }) => presentationId),
            reason: 'agent-request'
          }
        })
      ],
      [],
      dependencies.projectService
    );
    available = presentationBufferState(document, 0).available;
  }
  const ids = new Set(
    available.slice(0, presentationCount).map(({ presentationId }) => presentationId)
  );
  return {
    document,
    presentations: document.events.flatMap((event) =>
      event.type === 'visualization.presented' && ids.has(event.payload.presentation.presentationId)
        ? [event.payload.presentation]
        : []
    )
  };
}

function resolveAssistantContent(
  document: ProjectDocument,
  reply: GeneratedMessageContent,
  candidates: readonly RenderablePresentation[]
): MessageContent {
  const content: MessageContent = reply.map((segment) => {
    if (segment.type === 'markdown') return segment;
    if (segment.type === 'presentation-ref') return segment;
    if (segment.type === 'element-ref') return segment;
    const presentation = candidates[segment.slot];
    if (!presentation) {
      throw new Error(`The assistant referenced unavailable candidate slot ${segment.slot}.`);
    }
    return { type: 'presentation-ref', presentationId: presentation.presentationId };
  });
  validatePresentations(document, referencedPresentations(content));
  return content;
}

function validateGeneratedReply(
  document: ProjectDocument,
  reply: GeneratedMessageContent,
  candidateCount: number,
  providerResponse?: unknown
): void {
  try {
    validatePresentations(
      document,
      reply.flatMap((segment) =>
        segment.type === 'presentation-ref' ? [segment.presentationId] : []
      )
    );
    for (const segment of reply) {
      if (segment.type === 'element-ref') {
        const resolved = resolveProjectVisualSelection(document, {
          presentationEvent: segment.presentationEvent,
          step: segment.step,
          instances: segment.instances
        });
        if (resolved.event.payload.presentation.presentationId !== segment.presentationId) {
          throw new Error('The assistant element reference does not match its presentation.');
        }
      }
      if (segment.type === 'candidate-ref' && segment.slot >= candidateCount) {
        throw new Error(`The assistant referenced unavailable candidate slot ${segment.slot}.`);
      }
    }
  } catch (cause) {
    throw new InvalidChatbotResponseError(
      cause instanceof Error ? cause.message : 'The chatbot returned invalid references.',
      providerResponse
    );
  }
}

function validateRecoveryExplanation(
  prompt: ChatbotPrompt,
  recovery: RecoveryExplanation | undefined,
  providerResponse?: unknown
): void {
  if (prompt.attempt.purpose === 'fallback' && !recovery) {
    throw new InvalidChatbotResponseError(
      'The fallback response did not explain what was simplified.',
      providerResponse
    );
  }
  if (prompt.attempt.purpose !== 'fallback' && recovery) {
    throw new InvalidChatbotResponseError(
      'A non-fallback response unexpectedly included a recovery explanation.',
      providerResponse
    );
  }
}

function generatedReplyText(reply: GeneratedMessageContent): string {
  return reply
    .map((segment) => {
      if (segment.type === 'markdown') return segment.text;
      if (segment.type === 'presentation-ref') return `[Presentation ${segment.presentationId}]`;
      if (segment.type === 'element-ref') {
        return `[Elements ${segment.instances.join(', ')} in presentation ${segment.presentationId}, step ${segment.step + 1}]`;
      }
      return `[Candidate ${segment.slot + 1}]`;
    })
    .join(' ');
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
  content: string | MessageContent,
  botId: string,
  operationId: string,
  dependencies: ProjectCommandDependencies,
  inReplyTo: readonly EventId[] = []
) {
  return appendProjectEvents(
    document,
    [
      draftEvent({
        type: 'assistant.responded',
        actor: { kind: 'assistant', botId },
        operationId,
        payload: {
          content: typeof content === 'string' ? markdownMessage(content) : content,
          ...(inReplyTo.length > 0 ? { inReplyTo: [...inReplyTo] } : {})
        }
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

function appendAttemptDeadlineFailure(
  document: ProjectDocument,
  operationId: string,
  dependencies: ProjectCommandDependencies
) {
  return appendSystemFailure(
    document,
    'This visualization needed another attempt, but there was not enough time left in the study phase to complete it safely. I kept the last working visualization.',
    operationId,
    dependencies
  );
}

function appendExhaustedSverlinFailure(
  document: ProjectDocument,
  operationId: string,
  finalDifficulty: string | undefined,
  dependencies: ProjectCommandDependencies
) {
  return appendSystemFailure(
    document,
    `I could not make the requested visualization compile after several repairs and a simpler fallback, so I kept the last working visualization.${finalDifficulty ? ` The remaining difficulty was: ${plainFailureSummary(finalDifficulty)}` : ''}`,
    operationId,
    dependencies
  );
}

function appendExhaustedHtmlFailure(
  document: ProjectDocument,
  operationId: string,
  finalDifficulty: string,
  dependencies: ProjectCommandDependencies
) {
  return appendSystemFailure(
    document,
    `I could not make the requested visualization pass the safety checks after several repairs and a simpler fallback, so I kept the last working visualization. The remaining difficulty was: ${plainFailureSummary(finalDifficulty)}`,
    operationId,
    dependencies
  );
}

async function runAttemptLadder(
  document: ProjectDocument,
  operationId: string,
  chatbot: {
    config: { attemptProfiles: readonly unknown[] };
    requestTimeoutMs(): number;
  },
  dependencies: ProjectCommandDependencies,
  runAttempt: (
    document: ProjectDocument,
    attempt: number
  ) => Promise<{ document: ProjectDocument; done: boolean }>
): Promise<ProjectDocument> {
  for (let attempt = 1; attempt <= chatbot.config.attemptProfiles.length; attempt += 1) {
    if (attempt > 1 && !hasTimeForAnotherAttempt(chatbot)) {
      return appendAttemptDeadlineFailure(document, operationId, dependencies);
    }
    const result = await runAttempt(document, attempt);
    document = result.document;
    if (result.done) return document;
  }
  throw new Error('The configured attempt ladder ended without a terminal result.');
}

function hasTimeForAnotherAttempt(chatbot: { requestTimeoutMs(): number }): boolean {
  const deadline = currentProjectOperationDeadline();
  return deadline === undefined || deadline - Date.now() >= chatbot.requestTimeoutMs();
}

function replyWithRecovery(
  reply: GeneratedMessageContent,
  recovery?: RecoveryExplanation
): GeneratedMessageContent {
  if (!recovery) return reply;
  return [
    {
      type: 'markdown',
      text: `I ran into a difficulty: ${plainFailureSummary(recovery.struggledWith)} To produce a working visualization, I simplified ${plainFailureSummary(recovery.simplified)}`
    },
    ...reply
  ];
}

function participantDiagnostic(diagnostics: readonly { message: string }[]): string {
  return diagnostics.length > 0
    ? 'the generated program still did not satisfy the visualization language checks'
    : 'the visualization compiler could not validate the generated program';
}

function plainFailureSummary(value: string): string {
  const text = value.replace(/\s+/g, ' ').trim().slice(0, 500);
  if (!text) return 'an unspecified validation problem.';
  return /[.!?]$/.test(text) ? text : `${text}.`;
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
    document.events.flatMap((event) =>
      event.type === 'visualization.presented' ? [event.payload.presentation.presentationId] : []
    )
  );
  for (const id of unique) {
    if (!available.has(id)) throw new Error(`Unknown selected presentation ${id}.`);
  }
  return unique;
}

async function validateMessageContent(
  document: ProjectDocument,
  content: MessageContent
): Promise<MessageContent> {
  const presentations = validatePresentations(document, referencedPresentations(content));
  const known = new Set(presentations);
  for (const segment of content) {
    if (segment.type === 'markdown') continue;
    if (!known.has(segment.presentationId)) {
      throw new Error(`Unknown referenced presentation ${segment.presentationId}.`);
    }
    if (segment.type === 'element-ref') {
      const resolved = await validateSelection(document, {
        presentationEvent: segment.presentationEvent,
        step: segment.step,
        instances: segment.instances
      });
      const event = document.events[resolved.presentationEvent - 1];
      if (
        event?.type !== 'visualization.presented' ||
        event.payload.presentation.presentationId !== segment.presentationId
      ) {
        throw new Error('The element reference does not match its presentation.');
      }
    }
  }
  return content;
}

function referencedPresentations(content: MessageContent): string[] {
  return [
    ...new Set(
      content.flatMap((segment) => (segment.type === 'markdown' ? [] : [segment.presentationId]))
    )
  ];
}

function referencedVisualSelections(content: MessageContent): VisualSelection[] {
  const selections = new Map<string, VisualSelection>();
  for (const segment of content) {
    if (segment.type !== 'element-ref') continue;
    const selection = {
      presentationEvent: segment.presentationEvent,
      step: segment.step,
      instances: segment.instances
    } satisfies VisualSelection;
    selections.set(
      `${selection.presentationEvent}:${selection.step}:${selection.instances.join(',')}`,
      selection
    );
  }
  return [...selections.values()];
}

async function validateSelection(
  document: ProjectDocument,
  selection: VisualSelection
): Promise<VisualSelection> {
  return resolveProjectVisualSelection(document, selection).selection;
}

function finishMutation(before: ProjectDocument, document: ProjectDocument): ProjectCommandResult {
  return { document, appendedEvents: document.events.slice(before.events.length) };
}

function assertAcceptedInteraction(
  document: ProjectDocument,
  operationId: string,
  kind: 'feedback' | 'prefer'
): void {
  const operation = projectOperation(document, operationId);
  if (
    !operation ||
    operation.kind !== kind ||
    operation.status === 'completed' ||
    operation.status === 'failed'
  ) {
    throw new Error(`The ${kind} operation is not active.`);
  }
}

function deduplicateVisualSelections(selections: readonly VisualSelection[]): VisualSelection[] {
  const unique = new Map<string, VisualSelection>();
  for (const selection of selections) {
    unique.set(
      `${selection.presentationEvent}:${selection.step}:${selection.instances.join(',')}`,
      selection
    );
  }
  return [...unique.values()];
}

function rebasingDependencies(
  dependencies: ProjectCommandDependencies
): ProjectCommandDependencies {
  const repository = rebasingRepository(dependencies.repository);
  return {
    ...dependencies,
    repository,
    projectService: { ...dependencies.projectService, repository }
  };
}

function rebasingRepository(repository: ProjectRepository): ProjectRepository {
  return {
    initialize: () => repository.initialize(),
    create: (document, ownerUserId) => repository.create(document, ownerUserId),
    list: (ownerUserId) => repository.list(ownerUserId),
    load: (projectId) => repository.load(projectId),
    readResource: (projectId, resourceId) => repository.readResource(projectId, resourceId),
    eventsAfter: (projectId, after) => repository.eventsAfter(projectId, after),
    deleteAll: () => repository.deleteAll(),
    append: (projectId, _expectedHead, events, resources) =>
      runProjectCommand(projectId, async () => {
        const current = await repository.load(projectId);
        return repository.append(projectId, projectHead(current).id, events, resources);
      })
  };
}

function assertHead(document: ProjectDocument, expectedHead: EventId) {
  if (projectHead(document).id !== expectedHead) {
    const error = new Error('The project changed before this operation completed.');
    error.name = 'ProjectConflictError';
    throw error;
  }
}

function htmlCorrection(
  candidates: Array<{ label: string; manifest: HtmlFramesManifest }>,
  cause: unknown,
  failureSummaries: readonly string[]
): string {
  return `The previous candidate batch failed static safety validation: ${errorMessage(cause)}. Return one complete corrected batch of up to two candidates. Previous candidates: ${JSON.stringify(candidates)}. Failure history: ${JSON.stringify(failureSummaries.map((summary) => summary.slice(0, 2_000)))}`;
}

function generationFailureKind(error: unknown) {
  if (error instanceof Error && error.name === 'OpenAIConfigurationError') return 'configuration';
  if (
    error instanceof Error &&
    (error.name === 'APITimeoutError' || error.name === 'APIConnectionTimeoutError')
  )
    return 'timeout';
  if (
    error instanceof Error &&
    (error.name === 'AbortError' ||
      error.name === 'APIUserAbortError' ||
      error.name === 'StudyPhaseDeadlineError')
  )
    return 'cancelled';
  if (error instanceof Error && error.name === 'InvalidChatbotResponseError') {
    return 'invalid-response';
  }
  return 'provider';
}

function safeErrorMessage(error: unknown) {
  if (error instanceof Error && error.name === 'OpenAIConfigurationError') return error.message;
  if (error instanceof Error && error.name === 'ChatContextOverflowError') return error.message;
  if (
    error instanceof Error &&
    (error.name === 'APITimeoutError' || error.name === 'APIConnectionTimeoutError')
  )
    return 'The AI request timed out.';
  if (
    error instanceof Error &&
    (error.name === 'AbortError' ||
      error.name === 'APIUserAbortError' ||
      error.name === 'StudyPhaseDeadlineError')
  ) {
    const reason = currentProjectOperationSignal()?.reason;
    return reason instanceof Error
      ? reason.message
      : 'The AI request was cancelled before it could finish.';
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

function errorMessage(cause: unknown): string {
  return cause instanceof Error ? cause.message : String(cause);
}
