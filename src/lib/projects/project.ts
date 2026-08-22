import type {
  ArtifactId,
  ProjectDocument,
  ProjectEvent,
  ProjectEventId,
  ProjectSnapshot,
  ProjectSummary
} from './types';

export function projectHead(document: ProjectDocument) {
  return document.events.at(-1)!;
}

export function projectAt(
  document: ProjectDocument,
  requestedEventId: ProjectEventId = projectHead(document).eventId
): ProjectSnapshot {
  const cursorIndex = document.events.findIndex((event) => event.eventId === requestedEventId);
  if (cursorIndex < 0) throw new Error(`Unknown project event ${requestedEventId}.`);

  let title = '';
  let entryArtifactId = '';
  const artifacts: ProjectSnapshot['artifacts'] = {};
  const artifactVersionEventIds: Record<ArtifactId, ProjectEventId> = {};
  let activeRender: ProjectSnapshot['activeRender'];

  for (const event of document.events.slice(0, cursorIndex + 1)) {
    switch (event.type) {
      case 'project.created':
        title = event.payload.title;
        entryArtifactId = event.payload.entryArtifactId;
        break;
      case 'project.renamed':
        title = event.payload.title;
        break;
      case 'artifact.version-created':
        activeRender = undefined;
        for (const change of event.payload.changes) {
          if (change.operation === 'delete') {
            delete artifacts[change.artifactId];
            delete artifactVersionEventIds[change.artifactId];
          } else {
            artifacts[change.artifact.artifactId] = change.artifact;
            artifactVersionEventIds[change.artifact.artifactId] = event.eventId;
          }
        }
        break;
      case 'visualization.rendered':
        activeRender = event;
        break;
    }
  }

  return {
    projectId: document.projectId,
    eventId: requestedEventId,
    title,
    entryArtifactId,
    artifacts,
    artifactVersionEventIds,
    ...(activeRender ? { activeRender } : {})
  };
}

export function summarizeProject(document: ProjectDocument): ProjectSummary {
  const snapshot = projectAt(document);
  return {
    projectId: document.projectId,
    title: snapshot.title,
    updatedAt: projectHead(document).createdAt,
    eventCount: document.events.length
  };
}

export function eventLabel(event: ProjectEvent) {
  switch (event.type) {
    case 'project.created':
      return 'Project created';
    case 'project.renamed':
      return 'Project renamed';
    case 'feedback.submitted':
      return 'Feedback submitted';
    case 'ai.generation-requested':
      return `AI generation requested · attempt ${event.payload.attempt}`;
    case 'ai.generation-succeeded':
      return `AI generation completed · attempt ${event.payload.attempt}`;
    case 'ai.generation-failed':
      return `AI generation failed · attempt ${event.payload.attempt}`;
    case 'visualization.render-requested':
      return `Render requested · seed ${event.payload.seed}`;
    case 'compilation.requested':
      return 'Compilation requested';
    case 'compilation.succeeded':
      return 'Compilation succeeded';
    case 'compilation.failed':
      return 'Compilation failed';
    case 'artifact.version-created':
      return 'Artifact version created';
    case 'visualization.rendered':
      return `Visualization rendered · seed ${event.payload.seed}`;
    case 'assistant.responded':
      return 'Assistant responded';
    case 'system.notified':
      return 'System notice';
  }
}
