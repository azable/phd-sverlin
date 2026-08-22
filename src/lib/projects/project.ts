import type { EventId, ProjectDocument, ProjectSnapshot, ProjectSummary } from './types';

export function projectHead(document: ProjectDocument) {
  return document.events.at(-1)!;
}

export function projectAt(
  document: ProjectDocument,
  at: EventId = projectHead(document).id
): ProjectSnapshot {
  if (at < 1 || at > document.events.length) throw new Error(`Unknown project event ${at}.`);

  let title = '';
  let entryArtifactId = '';
  const artifacts: ProjectSnapshot['artifacts'] = {};
  let activeRender: ProjectSnapshot['activeRender'];

  for (const event of document.events.slice(0, at)) {
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
          if (change.operation === 'delete') delete artifacts[change.artifactId];
          else artifacts[change.artifact.artifactId] = change.artifact;
        }
        break;
      case 'visualization.rendered':
        activeRender = event;
        break;
    }
  }

  return {
    at,
    title,
    entryArtifactId,
    artifacts,
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
