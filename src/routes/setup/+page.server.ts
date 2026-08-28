import { error, redirect } from '@sveltejs/kit';

import { adminSetupAvailable } from '$lib/server/auth';

import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals, url }) => {
  if (locals.principal) redirect(303, '/');
  const setupToken = url.searchParams.get('token');
  if (!(await adminSetupAvailable(setupToken))) error(404, 'Administrator setup is unavailable.');
  return { setupToken: setupToken! };
};
