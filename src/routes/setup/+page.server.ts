import { error, redirect } from '@sveltejs/kit';

import { adminSetupAvailable } from '$lib/server/auth';

import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals }) => {
  if (locals.principal) redirect(303, '/');
  if (!(await adminSetupAvailable())) error(404, 'Administrator setup is unavailable.');
};
