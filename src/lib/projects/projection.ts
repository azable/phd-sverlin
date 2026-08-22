/**
 * Pure projections over an immutable project event document.
 *
 * @packageDocumentation
 */

import type { EventId, ProjectEvent, ProjectEventOf, ProjectEventType } from './events';
import type { ProjectDocument, ProjectSnapshot, ProjectSummary } from './model';

type SnapshotDraft = Omit<ProjectSnapshot, 'at'>;
type StateTransition<Type extends ProjectEventType> =
  | { changesState: false }
  | {
      changesState: true;
      apply: (state: SnapshotDraft, event: ProjectEventOf<Type>) => void;
    };
type StateTransitions = {
  [Type in ProjectEventType]: StateTransition<Type>;
};

const stateTransitions = {
  'project.created': {
    changesState: true,
    apply: (state, event) => {
      state.title = event.payload.title;
      state.entryArtifactId = event.payload.entryArtifactId;
    }
  },
  'project.renamed': {
    changesState: true,
    apply: (state, event) => {
      state.title = event.payload.title;
    }
  },
  'feedback.submitted': { changesState: false },
  'ai.generation-requested': { changesState: false },
  'ai.generation-succeeded': { changesState: false },
  'ai.generation-failed': { changesState: false },
  'compilation.requested': { changesState: false },
  'compilation.succeeded': { changesState: false },
  'compilation.failed': { changesState: false },
  'artifact.version-created': {
    changesState: true,
    apply: (state, event) => {
      state.activeRender = undefined;
      for (const change of event.payload.changes) {
        if (change.operation === 'delete') delete state.artifacts[change.artifactId];
        else state.artifacts[change.artifact.artifactId] = change.artifact;
      }
    }
  },
  'visualization.rendered': {
    changesState: true,
    apply: (state, event) => {
      state.activeRender = event;
    }
  },
  'assistant.responded': { changesState: false },
  'system.notified': { changesState: false }
} satisfies StateTransitions;

/** Return the final event in a valid project document. */
export function projectHead(document: ProjectDocument): ProjectEvent {
  return document.events.at(-1)!;
}

/** Return whether an event changes the projected project snapshot. */
export function projectEventChangesState(event: ProjectEvent): boolean {
  return stateTransitions[event.type].changesState;
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
    eventCount: document.events.length
  };
}

function applyProjectEvent(state: SnapshotDraft, event: ProjectEvent): void {
  const transition = stateTransitions[event.type];
  if (!transition.changesState) return;
  const apply = transition.apply as unknown as (draft: SnapshotDraft, value: ProjectEvent) => void;
  apply(state, event);
}
