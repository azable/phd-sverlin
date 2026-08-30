/**
 * Pure projections over an immutable project event document.
 *
 * @packageDocumentation
 */

import type { EventId, ProjectEvent, ProjectEventOf, ProjectEventType } from './events';
import type { ProjectDocument, ProjectSnapshot, ProjectSummary } from './model';
import { defaultProjectCreation, normalizeRecordedProjectCreation } from './creation';

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
    state.creation = normalizeRecordedProjectCreation(event.payload.creation);
  },
  'project.renamed': (state, event) => {
    state.title = event.payload.title;
  },
  'operation.accepted': null,
  'operation.completed': null,
  'operation.failed': null,
  'feedback.submitted': null,
  'ai.generation-requested': null,
  'ai.generation-succeeded': null,
  'ai.generation-failed': null,
  'compilation.requested': null,
  'compilation.succeeded': null,
  'compilation.failed': null,
  'artifact.version-created': (state, event) => {
    state.activeRender = undefined;
    for (const change of event.payload.changes) {
      if (change.operation === 'delete') delete state.artifacts[change.artifactId];
      else state.artifacts[change.artifact.artifactId] = change.artifact;
    }
  },
  'visualization.rendered': (state, event) => {
    state.activeRender = event;
  },
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
    creation: defaultProjectCreation,
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
    templateId: snapshot.creation.templateId
  };
}

function applyProjectEvent(state: SnapshotDraft, event: ProjectEvent): void {
  const transition = stateTransitions[event.type];
  if (!transition) return;
  const apply = transition as (draft: SnapshotDraft, value: ProjectEvent) => void;
  apply(state, event);
}
