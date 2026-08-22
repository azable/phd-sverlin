import { redirect } from '@sveltejs/kit';

import { projectRepository } from '$lib/server/projects/repository';
import { createProject } from '$lib/server/projects/service';

import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async () => {
  const projects = await projectRepository.list();
  const projectId = projects[0]?.projectId ?? (await createProject()).projectId;
  redirect(307, `/projects/${projectId}`);
};
