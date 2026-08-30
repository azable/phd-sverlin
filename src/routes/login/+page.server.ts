import { redirect } from '@sveltejs/kit';

import { adminSetupAvailable, safeReturnPath } from '$lib/server/auth';

import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals, url }) => {
  const next = safeReturnPath(url.searchParams.get('next'));
  if (locals.principal) redirect(303, next);
  if (await adminSetupAvailable()) redirect(303, '/setup');
  return { next };
};
