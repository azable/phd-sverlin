/** Role-specific project projections used at the browser boundary. */

import type { ProjectEvent } from '$lib/shared/projects/events';
import type {
  ProjectDocument,
  ProjectSummary,
  WorkspaceResource,
  WorkspaceTimelineEntry
} from '$lib/shared/projects/model';
import type { PresentationLayout, WorkspaceView } from '$lib/shared/presentations';
import { activeProjectOperation } from '$lib/shared/projects/operations';
import { projectHead, projectSnapshotAt } from '$lib/shared/projects/projection';

/** Project a complete retained document into the minimum browser-facing workspace shape. */
export function projectWorkspace(options: {
  document: ProjectDocument;
  projects: ProjectSummary[];
  view: WorkspaceView;
  layout: PresentationLayout;
  readOnly?: boolean;
  study?: WorkspaceResource['study'];
  at?: number;
}): WorkspaceResource {
  const snapshot = projectSnapshotAt(options.document, options.at);
  const operation = activeProjectOperation(options.document);
  return {
    schemaVersion: 1,
    projectId: options.document.projectId,
    head: projectHead(options.document).id,
    view: options.view,
    layout: options.layout,
    readOnly: options.readOnly ?? options.at !== undefined,
    snapshot: options.view === 'developer' ? snapshot : redactSnapshot(snapshot),
    timeline:
      options.view === 'developer'
        ? options.document.events.map(developerEntry)
        : participantTimeline(options.document.events),
    projects: options.projects,
    ...(operation
      ? { activeOperation: { operationId: operation.operationId, kind: operation.kind } }
      : {}),
    ...(options.study ? { study: options.study } : {})
  };
}

function participantTimeline(events: readonly ProjectEvent[]): WorkspaceTimelineEntry[] {
  const entries: WorkspaceTimelineEntry[] = [];
  const byOperation = Map.groupBy(events, ({ operationId }) => operationId);
  for (const [operationId, related] of byOperation) {
    const feedback = related.find(({ type }) => type === 'feedback.submitted');
    const response = related.findLast(({ type }) => type === 'assistant.responded');
    if (feedback?.type === 'feedback.submitted') {
      entries.push({
        id: `operation-${operationId}`,
        operationId,
        kind: response ? 'assistant' : 'user',
        title: response ? 'Assistant response' : 'Request',
        detail: [
          feedback.payload.text,
          response?.type === 'assistant.responded' ? response.payload.text : undefined
        ]
          .filter(Boolean)
          .join('\n\n'),
        sourceEventIds: related.map(({ id }) => id)
      });
    }
    for (const event of related) {
      if (event.type === 'visualization.rendered' || event.type === 'visualization.presented') {
        entries.push({
          id: `presentation-${event.id}`,
          operationId,
          kind: 'presentation',
          title: 'Visualization updated',
          sourceEventIds: [event.id]
        });
      } else if (event.type === 'visualization.preference-recorded') {
        entries.push({
          id: `preference-${event.id}`,
          operationId,
          kind: 'action',
          title: 'Preference recorded',
          sourceEventIds: [event.id]
        });
      } else if (event.type === 'operation.failed') {
        entries.push({
          id: `failure-${event.id}`,
          operationId,
          kind: 'error',
          title: 'Operation failed',
          detail: event.payload.message,
          sourceEventIds: [event.id]
        });
      }
    }
  }
  return entries.toSorted(
    (left, right) => Math.min(...left.sourceEventIds) - Math.min(...right.sourceEventIds)
  );
}

function developerEntry(event: ProjectEvent): WorkspaceTimelineEntry {
  return {
    id: `event-${event.id}`,
    operationId: event.operationId,
    kind: 'developer',
    title: event.type,
    sourceEventIds: [event.id],
    rawEvent: event
  };
}

function redactSnapshot(snapshot: ReturnType<typeof projectSnapshotAt>) {
  const clone = structuredClone(snapshot);
  clone.activePresentationSet = clone.activePresentationSet
    ? {
        ...clone.activePresentationSet,
        presentations: clone.activePresentationSet.presentations.map((event) => {
          if (event.type === 'visualization.presented') {
            const presentation = { ...event.payload.presentation };
            if (presentation.format === 'sverlin-ir-v1') {
              delete presentation.provenance;
              delete presentation.targetDiagnostics;
            }
            return { ...event, payload: { ...event.payload, presentation } };
          }
          const payload = { ...event.payload };
          delete payload.provenance;
          delete payload.targetDiagnostics;
          return { ...event, payload };
        })
      }
    : undefined;
  if (clone.activeRender) {
    clone.activeRender = clone.activePresentationSet?.presentations.find(
      (event) => event.type === 'visualization.rendered'
    ) as typeof clone.activeRender;
  }
  return clone;
}
