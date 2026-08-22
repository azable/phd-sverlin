import { projectAt, projectHead } from '$lib/projects/project';
import type {
  FeedbackSubmittedEvent,
  ProjectDocument,
  ProjectEvent,
  VisualSelection
} from '$lib/projects/types';
import type { ConversationMessage } from '$lib/server/chat-bots/types';
import { decodeVisualization } from '$lib/visualization/types';

import { projectRepository } from './repository';

export async function buildProjectPrompt(document: ProjectDocument) {
  const snapshot = projectAt(document);
  const feedback = document.events.findLast(
    (event): event is FeedbackSubmittedEvent => event.type === 'feedback.submitted'
  );

  return {
    messages: conversationMessages(document.events),
    project: {
      projectId: document.projectId,
      title: snapshot.title,
      headEventId: projectHead(document).id,
      currentWorkspace: {
        entryArtifactId: snapshot.entryArtifactId,
        artifacts: await hydrateArtifacts(document, snapshot)
      },
      activeRender: snapshot.activeRender ? renderSummary(snapshot.activeRender) : undefined,
      timeline: document.events.map(promptEvent),
      focus: feedback ? await resolveFocus(document, feedback) : undefined
    }
  };
}

function conversationMessages(events: ProjectEvent[]): ConversationMessage[] {
  return events.flatMap<ConversationMessage>((event) => {
    if (event.type === 'feedback.submitted') {
      return [{ role: 'user', content: feedbackMessage(event) }];
    }
    if (event.type === 'assistant.responded') {
      return [{ role: 'assistant', content: event.payload.text }];
    }
    return [];
  });
}

function feedbackMessage(event: FeedbackSubmittedEvent) {
  const details = [event.payload.text];
  if (event.payload.focus.length > 0) {
    details.push(`Focused timeline events: ${event.payload.focus.join(', ')}`);
  }
  if (event.payload.selection) {
    const selection = event.payload.selection;
    details.push(
      `${selection.judgement} visual selection in render ${selection.render}, step ${selection.step}: instances ${selection.instances.join(', ')}`
    );
  }
  return details.filter(Boolean).join('\n\n');
}

function promptEvent(event: ProjectEvent) {
  const base = {
    id: event.id,
    type: event.type,
    actor: event.actor,
    createdAt: event.createdAt,
    operationId: event.operationId
  };

  switch (event.type) {
    case 'project.created':
    case 'project.renamed':
    case 'feedback.submitted':
    case 'assistant.responded':
    case 'system.notified':
    case 'ai.generation-failed':
    case 'compilation.failed':
      return { ...base, payload: event.payload };
    case 'ai.generation-requested':
      return {
        ...base,
        payload: {
          attempt: event.payload.attempt,
          purpose: event.payload.purpose,
          requestedModel: event.payload.requestedModel,
          promptSha256: event.payload.prompt.sha256,
          promptTemplateSha256: event.payload.promptTemplateSha256,
          dslRevision: event.payload.dslRevision
        }
      };
    case 'ai.generation-succeeded':
      return {
        ...base,
        payload: {
          attempt: event.payload.attempt,
          model: event.payload.model ?? event.payload.requestedModel,
          durationMs: event.payload.durationMs,
          responseSha256: event.payload.response.sha256
        }
      };
    case 'compilation.requested':
      return {
        ...base,
        payload: {
          purpose: event.payload.purpose,
          input: event.payload.input,
          sourceLabel: event.payload.sourceLabel,
          sourceSha256: event.payload.source.sha256,
          seed: event.payload.seed,
          attempt: event.payload.attempt,
          dslRevision: event.payload.dslRevision
        }
      };
    case 'compilation.succeeded':
      return {
        ...base,
        payload: {
          durationMs: event.payload.durationMs,
          renderSha256: event.payload.render.sha256
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
                  sha256: change.artifact.content.sha256
                }
          )
        }
      };
    case 'visualization.rendered':
      return { ...base, payload: renderSummary(event) };
  }
}

async function resolveFocus(document: ProjectDocument, feedback: FeedbackSubmittedEvent) {
  const events = await Promise.all(
    feedback.payload.focus.map(async (id) => {
      const snapshot = projectAt(document, id);
      return {
        event: promptEvent(document.events[id - 1]),
        workspace: {
          entryArtifactId: snapshot.entryArtifactId,
          artifacts: await hydrateArtifacts(document, snapshot)
        },
        activeRender: snapshot.activeRender ? renderSummary(snapshot.activeRender) : undefined
      };
    })
  );
  const selection = feedback.payload.selection
    ? await resolveSelection(document, feedback.payload.selection)
    : undefined;
  return { events, selection };
}

async function resolveSelection(document: ProjectDocument, selection: VisualSelection) {
  const render = document.events[selection.render - 1];
  if (render?.type !== 'visualization.rendered') return undefined;
  const visualization = decodeVisualization(
    await projectRepository.readTextBlob(document.projectId, render.payload.render)
  );
  const step = visualization.steps[selection.step];
  if (!step) return undefined;
  const selected = new Set(selection.instances);
  const elements = step.instances.flatMap((instance) => {
    if (!selected.has(instance.id)) return [];
    const element = visualization.elements.find(({ id }) => id === instance.elementId);
    return element ? [{ instanceId: instance.id, ...element }] : [];
  });
  return {
    ...selection,
    stepLabel: step.label,
    render: renderSummary(render),
    elements
  };
}

async function hydrateArtifacts(document: ProjectDocument, snapshot: ReturnType<typeof projectAt>) {
  return Promise.all(
    Object.values(snapshot.artifacts).map(async (artifact) => ({
      artifactId: artifact.artifactId,
      path: artifact.path,
      language: artifact.language,
      source: await projectRepository.readTextBlob(document.projectId, artifact.content),
      sha256: artifact.content.sha256
    }))
  );
}

function renderSummary(event: Extract<ProjectEvent, { type: 'visualization.rendered' }>) {
  return {
    id: event.id,
    seed: event.payload.seed,
    sourceSha256: event.payload.source.sha256,
    renderSha256: event.payload.render.sha256
  };
}
