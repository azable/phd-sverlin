import { redirect } from '@sveltejs/kit';

import { safeReturnPath } from '$lib/server/auth';

import type { PageServerLoad } from './$types';

export const load: PageServerLoad = ({ locals, url }) => {
  const next = safeReturnPath(url.searchParams.get('next'));
  if (locals.principal) redirect(303, next);
  return { next };
};
