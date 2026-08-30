import { requireProjectAccess } from '$lib/server/authorization';
import { listProjectTemplates } from '$lib/server/projects/starter-catalog';
import { participantStudyState } from '$lib/server/study';

import type { PageServerLoad } from './$types';

/** Supply immutable project-template metadata to the creation dialog. */
export const load: PageServerLoad = async ({ locals, params }) => {
  const principal = await requireProjectAccess(locals, params.projectId);
  const study =
    principal.kind === 'participant' ? await participantStudyState(principal.user.id) : undefined;
  return {
    authEnabled: true,
    isAdmin: principal.kind === 'admin',
    templates: principal.kind === 'admin' ? listProjectTemplates() : [],
    study:
      study?.phase.kind === 'task' && study.projectId === params.projectId
        ? {
            phaseId: study.phase.id,
            title: study.phase.instructions.title,
            prompt: study.phase.instructions.prompt,
            deadlineAt: study.deadlineAt,
            expired: study.expired,
            layout: study.phase.condition.workspace.layout
          }
        : undefined
  };
};
