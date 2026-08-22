/**
 * Projection of immutable project history into provider-neutral chatbot context.
 *
 * @packageDocumentation
 */

import {
  matchProjectEvent,
  type EventId,
  type ProjectEvent,
  type ProjectEventCases,
  type ProjectEventOf,
  type ProjectEventType
} from '$lib/projects/events';
import type { VisualSelection } from '$lib/projects/events/values';
import type { ProjectDocument, ProjectSnapshot } from '$lib/projects/model';
import { projectHead, projectSnapshotAt } from '$lib/projects/projection';
import type { ChatContextInput, ConversationMessage } from '$lib/server/chat-bots/types';
import { decodeVisualization } from '$lib/visualization/types';

import { projectRepository } from './repository';

/** AI-facing summary of one immutable project event. */
export type PromptTimelineEvent = {
  id: EventId;
  type: ProjectEventType;
  actor: ProjectEvent['actor'];
  createdAt: string;
  operationId: string;
  payload: Record<string, unknown>;
};

type PromptRenderSummary = {
  id: EventId;
  seed: number;
  sourceSha256: string;
  renderSha256: string;
};

const promptEventCases = {
  'project.created': retainedPromptEvent,
  'project.renamed': retainedPromptEvent,
  'feedback.submitted': retainedPromptEvent,
  'ai.generation-requested': (event) =>
    promptEventWith(event, {
      attempt: event.payload.attempt,
      purpose: event.payload.purpose,
      requestedModel: event.payload.requestedModel,
      promptSha256: event.payload.prompt.sha256,
      promptTemplateSha256: event.payload.promptTemplateSha256,
      dslRevision: event.payload.dslRevision
    }),
  'ai.generation-succeeded': (event) =>
    promptEventWith(event, {
      attempt: event.payload.attempt,
      model: event.payload.model ?? event.payload.requestedModel,
      durationMs: event.payload.durationMs,
      responseSha256: event.payload.response.sha256
    }),
  'ai.generation-failed': retainedPromptEvent,
  'compilation.requested': (event) =>
    promptEventWith(event, {
      purpose: event.payload.purpose,
      input: event.payload.input,
      sourceLabel: event.payload.sourceLabel,
      sourceSha256: event.payload.source.sha256,
      seed: event.payload.seed,
      attempt: event.payload.attempt,
      dslRevision: event.payload.dslRevision
    }),
  'compilation.succeeded': (event) =>
    promptEventWith(event, {
      durationMs: event.payload.durationMs,
      renderSha256: event.payload.render.sha256
    }),
  'compilation.failed': retainedPromptEvent,
  'artifact.version-created': (event) =>
    promptEventWith(event, {
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
    }),
  'visualization.rendered': (event) => promptEventWith(event, renderSummary(event)),
  'assistant.responded': retainedPromptEvent,
  'system.notified': retainedPromptEvent
} satisfies ProjectEventCases<PromptTimelineEvent>;

const conversationCases = {
  'project.created': () => [],
  'project.renamed': () => [],
  'feedback.submitted': (event) => [{ role: 'user', content: feedbackMessage(event) }],
  'ai.generation-requested': () => [],
  'ai.generation-succeeded': () => [],
  'ai.generation-failed': () => [],
  'compilation.requested': () => [],
  'compilation.succeeded': () => [],
  'compilation.failed': () => [],
  'artifact.version-created': () => [],
  'visualization.rendered': () => [],
  'assistant.responded': (event) => [{ role: 'assistant', content: event.payload.text } as const],
  'system.notified': () => []
} satisfies ProjectEventCases<ConversationMessage[]>;

/** Project one event into the compact semantic Timeline supplied to the AI. */
export function projectPromptEvent(event: ProjectEvent): PromptTimelineEvent {
  return matchProjectEvent(event, promptEventCases);
}

/** Project event history into the user/assistant messages supplied to the AI. */
export function projectConversationMessages(
  events: readonly ProjectEvent[]
): ConversationMessage[] {
  return events.flatMap((event) =>
    matchProjectEvent<ConversationMessage[]>(event, conversationCases)
  );
}

/** Build the conversation and complete project context supplied to a chatbot. */
export async function buildProjectPrompt(document: ProjectDocument): Promise<ChatContextInput> {
  const snapshot = projectSnapshotAt(document);
  const feedback = document.events.findLast(
    (event): event is ProjectEventOf<'feedback.submitted'> => event.type === 'feedback.submitted'
  );

  return {
    messages: projectConversationMessages(document.events),
    project: {
      projectId: document.projectId,
      title: snapshot.title,
      headEventId: projectHead(document).id,
      currentWorkspace: {
        entryArtifactId: snapshot.entryArtifactId,
        artifacts: await hydrateArtifacts(document, snapshot)
      },
      activeRender: snapshot.activeRender ? renderSummary(snapshot.activeRender) : undefined,
      timeline: document.events.map(projectPromptEvent),
      focus: feedback ? await resolveFocus(document, feedback) : undefined
    }
  };
}

function retainedPromptEvent(event: ProjectEvent): PromptTimelineEvent {
  return promptEventWith(event, event.payload);
}

function promptEventWith(
  event: ProjectEvent,
  payload: Record<string, unknown>
): PromptTimelineEvent {
  return {
    id: event.id,
    type: event.type,
    actor: event.actor,
    createdAt: event.createdAt,
    operationId: event.operationId,
    payload
  };
}

function feedbackMessage(event: ProjectEventOf<'feedback.submitted'>): string {
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

async function resolveFocus(
  document: ProjectDocument,
  feedback: ProjectEventOf<'feedback.submitted'>
) {
  const events = await Promise.all(
    feedback.payload.focus.map(async (id) => {
      const snapshot = projectSnapshotAt(document, id);
      return {
        event: projectPromptEvent(document.events[id - 1]),
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

async function hydrateArtifacts(document: ProjectDocument, snapshot: ProjectSnapshot) {
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

function renderSummary(event: ProjectEventOf<'visualization.rendered'>): PromptRenderSummary {
  return {
    id: event.id,
    seed: event.payload.seed,
    sourceSha256: event.payload.source.sha256,
    renderSha256: event.payload.render.sha256
  };
}
