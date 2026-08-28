import { requireProjectAccess } from '$lib/server/authorization';
import { listProjectTemplates } from '$lib/server/projects/starter-catalog';

import type { PageServerLoad } from './$types';

/** Supply immutable project-template metadata to the creation dialog. */
export const load: PageServerLoad = async ({ locals, params }) => {
  const principal = await requireProjectAccess(locals, params.projectId);
  return {
    authEnabled: true,
    isAdmin: principal.kind === 'admin',
    templates: listProjectTemplates()
  };
};
