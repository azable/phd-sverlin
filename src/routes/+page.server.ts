import { redirect } from '@sveltejs/kit';

import { requirePrincipal } from '$lib/server/authorization';
import { projectRepository } from '$lib/server/projects/repository';
import { listProjectTemplates } from '$lib/server/projects/starter-catalog';

import type { PageServerLoad } from './$types';

/** Keep administrators on the project landing page; participants enter their assigned flow. */
export const load: PageServerLoad = async ({ locals }) => {
  const principal = requirePrincipal(locals);
  if (principal.kind === 'participant') redirect(307, '/study');
  const projects = await projectRepository.list(principal.user.id);
  return {
    isAdmin: principal.kind === 'admin',
    projects,
    templates: listProjectTemplates()
  };
};
