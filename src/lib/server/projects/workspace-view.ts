import type {
  ProjectDocument,
  ProjectSummary,
  WorkspaceResource
} from '$lib/shared/projects/model';
import type { PresentationLayout, WorkspaceView } from '$lib/shared/presentations';

/** Build an authorized workspace response around the complete retained Timeline. */
export function projectWorkspace(options: {
  document: ProjectDocument;
  projects: ProjectSummary[];
  view: WorkspaceView;
  layout: PresentationLayout;
  readOnly?: boolean;
  study?: WorkspaceResource['study'];
  at?: number;
}): WorkspaceResource {
  return {
    schemaVersion: 1,
    projectId: options.document.projectId,
    document: options.document,
    view: options.view,
    layout: options.layout,
    readOnly: options.readOnly ?? options.at !== undefined,
    projects: options.projects,
    ...(options.study ? { study: options.study } : {})
  };
}
