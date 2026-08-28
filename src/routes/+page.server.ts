import { redirect } from '@sveltejs/kit';

import { projectListOwner, requirePrincipal } from '$lib/server/authorization';
import { projectRepository } from '$lib/server/projects/repository';
import { listProjectTemplates } from '$lib/server/projects/starter-catalog';

import type { PageServerLoad } from './$types';

/** Redirect the application root to the newest project, creating one when necessary. */
export const load: PageServerLoad = async ({ locals }) => {
  const principal = requirePrincipal(locals);
  const projects = await projectRepository.list(projectListOwner(principal));
  if (projects[0]) redirect(307, `/projects/${projects[0].projectId}`);
  return {
    isAdmin: principal.kind === 'admin',
    templates: listProjectTemplates()
  };
};
