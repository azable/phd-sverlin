/**
 * Pure projections over an immutable project event document.
 *
 * @packageDocumentation
 */

import type { EventId, ProjectEvent, ProjectEventOf, ProjectEventType } from './events';
import type { ProjectDocument, ProjectSnapshot, ProjectSummary } from './model';
import { defaultAssistantId } from '$lib/shared/assistants';
import { defaultProjectCreation, projectCreationRenderer } from './creation';

type SnapshotDraft = Omit<ProjectSnapshot, 'at'>;
type StateTransition<Type extends ProjectEventType> =
  | ((state: SnapshotDraft, event: ProjectEventOf<Type>) => void)
  | null;
type StateTransitions = {
  [Type in ProjectEventType]: StateTransition<Type>;
};

const stateTransitions = {
  'project.created': (state, event) => {
    state.title = event.payload.title;
    state.entryArtifactId = event.payload.entryArtifactId;
    state.assistantId = event.payload.assistantId;
    state.creation = event.payload.creation;
    state.renderer = projectCreationRenderer(state.creation);
  },
  'project.renamed': (state, event) => {
    state.title = event.payload.title;
  },
  'operation.accepted': null,
  'operation.completed': null,
  'operation.failed': null,
  'feedback.submitted': null,
  'assistant.turn-requested': null,
  'assistant.turn-started': null,
  'visualization.candidates-advanced': null,
  'ai.generation-requested': null,
  'ai.generation-succeeded': null,
  'ai.generation-failed': null,
  'compilation.requested': null,
  'compilation.succeeded': null,
  'compilation.failed': null,
  'artifact.version-created': (state, event) => {
    state.activePresentationSet = undefined;
    for (const change of event.payload.changes) {
      if (change.operation === 'delete') delete state.artifacts[change.artifactId];
      else state.artifacts[change.artifact.artifactId] = change.artifact;
    }
  },
  'visualization.presented': (state, event) => {
    const current = state.activePresentationSet;
    state.activePresentationSet =
      current?.displaySetId === event.payload.displaySetId
        ? {
            displaySetId: current.displaySetId,
            presentations: [
              ...current.presentations.filter((value) => value.payload.slot !== event.payload.slot),
              event
            ].toSorted((left, right) => left.payload.slot - right.payload.slot)
          }
        : { displaySetId: event.payload.displaySetId, presentations: [event] };
  },
  'visualization.preference-recorded': null,
  'assistant.responded': null,
  'system.notified': null
} satisfies StateTransitions;

/** Return the final event in a valid project document. */
export function projectHead(document: ProjectDocument): ProjectEvent {
  return document.events.at(-1)!;
}

/** Reconstruct project state at a stable event position. */
export function projectSnapshotAt(
  document: ProjectDocument,
  at: EventId = projectHead(document).id
): ProjectSnapshot {
  if (at < 1 || at > document.events.length) throw new Error(`Unknown project event ${at}.`);

  const state: SnapshotDraft = {
    title: '',
    entryArtifactId: '',
    assistantId: defaultAssistantId('sverlin'),
    creation: defaultProjectCreation,
    renderer: 'sverlin',
    artifacts: {}
  };
  for (const event of document.events.slice(0, at)) applyProjectEvent(state, event);

  return { at, ...state };
}

/** Build the list-view summary for a project document. */
export function summarizeProject(document: ProjectDocument): ProjectSummary {
  const snapshot = projectSnapshotAt(document);
  return {
    projectId: document.projectId,
    title: snapshot.title,
    updatedAt: projectHead(document).createdAt,
    eventCount: document.events.length,
    templateId: snapshot.creation.templateId,
    renderer: snapshot.renderer
  };
}

function applyProjectEvent(state: SnapshotDraft, event: ProjectEvent): void {
  const transition = stateTransitions[event.type];
  if (!transition) return;
  const apply = transition as (draft: SnapshotDraft, value: ProjectEvent) => void;
  apply(state, event);
}
