import { eventLabel, projectAt } from '$lib/projects/project';
import type {
  FeedbackAttachment,
  FeedbackSubmittedEvent,
  ProjectDocument,
  ProjectEvent
} from '$lib/projects/types';
import type { ConversationMessage } from '$lib/server/chat-bots/types';

import { projectRepository } from './repository';

export async function buildProjectPrompt(document: ProjectDocument) {
  const snapshot = projectAt(document);
  const artifacts = await Promise.all(
    Object.values(snapshot.artifacts).map(async (artifact) => ({
      artifactId: artifact.artifactId,
      path: artifact.path,
      language: artifact.language,
      content: await projectRepository.readTextBlob(document.projectId, artifact.content),
      sha256: artifact.contentSha256
    }))
  );
  const timeline = document.events.map(promptEvent);
  const feedback = [...document.events]
    .reverse()
    .find((event): event is FeedbackSubmittedEvent => event.type === 'feedback.submitted');
  const resolvedReferences = feedback
    ? await resolveReferences(document, feedback.payload.attachments)
    : [];

  return {
    messages: conversationMessages(document.events),
    project: {
      projectId: document.projectId,
      title: snapshot.title,
      headEventId: document.events.at(-1)!.eventId,
      currentWorkspace: {
        entryArtifactId: snapshot.entryArtifactId,
        artifacts
      },
      activeRender: snapshot.activeRender
        ? {
            eventId: snapshot.activeRender.eventId,
            seed: snapshot.activeRender.payload.seed,
            sourceSha256: snapshot.activeRender.payload.sourceSha256,
            renderSha256: snapshot.activeRender.payload.renderSha256
          }
        : undefined,
      timeline,
      resolvedReferences
    }
  };
}

function conversationMessages(events: ProjectEvent[]): ConversationMessage[] {
  return events.flatMap<ConversationMessage>((event) => {
    switch (event.type) {
      case 'feedback.submitted':
        return [
          {
            role: 'user',
            content: feedbackMessage(event)
          }
        ];
      case 'assistant.responded':
        return [{ role: 'assistant', content: event.payload.text }];
      default:
        return [];
    }
  });
}

function feedbackMessage(event: FeedbackSubmittedEvent) {
  const attachmentSummary = event.payload.attachments
    .map((attachment) => {
      if (attachment.kind === 'timeline-reference') {
        return `${attachment.relationship} Timeline events: ${attachment.eventIds.join(', ')}`;
      }
      return `${attachment.judgement} visual selection at step ${attachment.step.index} (${attachment.step.label}): ${attachment.elements
        .map((element) => `${element.role}${element.content ? ` “${element.content}”` : ''}`)
        .join(', ')}`;
    })
    .join('\n');
  return [event.payload.text, attachmentSummary].filter(Boolean).join('\n\n');
}

function promptEvent(event: ProjectEvent) {
  const base = {
    eventId: event.eventId,
    type: event.type,
    actor: event.actor,
    createdAt: event.createdAt,
    correlationId: event.correlationId,
    label: eventLabel(event)
  };

  switch (event.type) {
    case 'project.created':
    case 'project.renamed':
    case 'feedback.submitted':
    case 'assistant.responded':
    case 'system.notified':
      return { ...base, payload: event.payload };
    case 'ai.generation-requested':
      return {
        ...base,
        payload: {
          attempt: event.payload.attempt,
          purpose: event.payload.purpose,
          requestedModel: event.payload.requestedModel,
          promptSha256: event.payload.promptSha256,
          repairOfCompilationEventId: event.payload.repairOfCompilationEventId
        }
      };
    case 'ai.generation-succeeded':
      return {
        ...base,
        payload: {
          attempt: event.payload.attempt,
          model: event.payload.model,
          durationMs: event.payload.durationMs,
          candidateSha256: event.payload.candidateSource?.sha256,
          reply: event.payload.reply
        }
      };
    case 'ai.generation-failed':
      return { ...base, payload: event.payload };
    case 'compilation.failed':
      return {
        ...base,
        payload: {
          failureKind: event.payload.failureKind,
          diagnostics: event.payload.diagnostics,
          repairEligible: event.payload.repairEligible,
          error: event.payload.error
        }
      };
    case 'compilation.succeeded':
      return {
        ...base,
        payload: {
          durationMs: event.payload.durationMs,
          diagnostics: event.payload.diagnostics,
          renderSha256: event.payload.renderSha256
        }
      };
    case 'artifact.version-created':
      return {
        ...base,
        payload: {
          origin: event.payload.origin,
          changes: event.payload.changes.map((change) =>
            change.operation === 'delete'
              ? change
              : {
                  operation: change.operation,
                  artifactId: change.artifact.artifactId,
                  path: change.artifact.path,
                  sha256: change.artifact.contentSha256
                }
          )
        }
      };
    case 'visualization.render-requested':
      return {
        ...base,
        payload: {
          purpose: event.payload.purpose,
          seed: event.payload.seed,
          sourceSha256: event.payload.sourceSha256,
          input: event.payload.input
        }
      };
    case 'compilation.requested':
      return {
        ...base,
        payload: {
          seed: event.payload.seed,
          sourceSha256: event.payload.sourceSha256
        }
      };
    case 'visualization.rendered':
      return {
        ...base,
        payload: {
          seed: event.payload.seed,
          sourceSha256: event.payload.sourceSha256,
          renderSha256: event.payload.renderSha256
        }
      };
  }
}

async function resolveReferences(document: ProjectDocument, attachments: FeedbackAttachment[]) {
  const eventIds = new Set(
    attachments.flatMap((attachment) =>
      attachment.kind === 'timeline-reference' ? attachment.eventIds : [attachment.sourceEventId]
    )
  );
  return Promise.all(
    [...eventIds].map(async (eventId) => {
      const snapshot = projectAt(document, eventId);
      const artifacts = await Promise.all(
        Object.values(snapshot.artifacts).map(async (artifact) => ({
          artifactId: artifact.artifactId,
          path: artifact.path,
          content: await projectRepository.readTextBlob(document.projectId, artifact.content),
          sha256: artifact.contentSha256
        }))
      );
      return {
        eventId,
        title: snapshot.title,
        artifacts,
        activeRender: snapshot.activeRender
          ? {
              eventId: snapshot.activeRender.eventId,
              seed: snapshot.activeRender.payload.seed
            }
          : undefined
      };
    })
  );
}
