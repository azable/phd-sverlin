import { json } from '@sveltejs/kit';

import { projectListOwner, requireProjectAccess } from '$lib/server/authorization';
import { projectWorkspace } from '$lib/server/projects/workspace-view';
import { loadProjectResource } from '$lib/server/projects/service';
import { participantStudyState } from '$lib/server/study';
import type { PresentationLayout } from '$lib/shared/presentations';

import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ locals, params, url }) => {
  const principal = await requireProjectAccess(locals, params.projectId);
  const developerRequested = url.searchParams.get('view') === 'developer';
  const view = principal.kind === 'admin' && developerRequested ? 'developer' : 'participant';
  const requestedLayout = url.searchParams.get('layout');
  let layout: PresentationLayout = requestedLayout === 'comparison' ? 'comparison' : 'single';
  let study;
  let readOnly = false;
  if (principal.kind === 'participant') {
    const state = await participantStudyState(principal.user.id);
    if (state.phase.kind === 'task' && state.projectId === params.projectId) {
      layout = state.phase.condition.workspace.layout;
      readOnly = state.expired;
      study = {
        phaseId: state.phase.id,
        deadlineAt: state.deadlineAt,
        status: state.expired ? ('expired' as const) : ('active' as const)
      };
    } else {
      readOnly = true;
    }
  }
  const resource = await loadProjectResource(params.projectId, projectListOwner(principal));
  return json(
    projectWorkspace({
      document: resource.document,
      projects: resource.projects,
      view,
      layout,
      readOnly,
      ...(study ? { study } : {})
    })
  );
};
