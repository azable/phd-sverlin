import type { ProjectEvent, ProjectEventType } from './types';

const hydrationPolicy = {
  'project.created': false,
  'project.renamed': true,
  'feedback.submitted': false,
  'ai.generation-requested': false,
  'ai.generation-succeeded': false,
  'ai.generation-failed': false,
  'visualization.render-requested': false,
  'compilation.requested': false,
  'compilation.succeeded': false,
  'compilation.failed': false,
  'artifact.version-created': true,
  'visualization.rendered': true,
  'assistant.responded': false,
  'system.notified': false
} satisfies Record<ProjectEventType, boolean>;

export function projectEventNeedsHydration(event: ProjectEvent) {
  return hydrationPolicy[event.type];
}
