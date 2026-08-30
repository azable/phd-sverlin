import { json } from '@sveltejs/kit';

import { projectInspectionContext, projectListOwner } from '$lib/server/authorization';
import { projectWorkspace } from '$lib/server/projects/workspace-view';
import { loadProjectResource } from '$lib/server/projects/service';
import { studyRunState } from '$lib/server/study';
import type { PresentationLayout } from '$lib/shared/presentations';

import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ locals, params, url }) => {
  const inspection = await projectInspectionContext(locals, params.projectId);
  const { principal } = inspection;
  const developerRequested = url.searchParams.get('view') === 'developer';
  const view = principal.kind === 'admin' && developerRequested ? 'developer' : 'participant';
  const requestedLayout = url.searchParams.get('layout');
  let layout: PresentationLayout = requestedLayout === 'comparison' ? 'comparison' : 'single';
  let study;
  if (inspection.study) {
    const state = await studyRunState(inspection.study.runId);
    const flowPhase = state.flow.phases.find(({ phase }) => phase.id === inspection.study?.phaseId);
    if (flowPhase?.phase.kind === 'task') {
      layout = flowPhase.phase.condition.workspace.layout;
      study = {
        phaseId: flowPhase.phase.id,
        deadlineAt: flowPhase.deadlineAt,
        status:
          flowPhase.status === 'ready-to-continue'
            ? ('expired' as const)
            : flowPhase.status === 'completed'
              ? ('complete' as const)
              : ('active' as const)
      };
    }
  }
  const resource = await loadProjectResource(params.projectId, projectListOwner(principal));
  return json(
    projectWorkspace({
      document: resource.document,
      projects: resource.projects,
      view,
      layout,
      readOnly: inspection.readOnly,
      userAuthorLabel: principal.kind === 'admin' ? (inspection.participantLabel ?? 'You') : 'You',
      ...(study ? { study } : {})
    })
  );
};
