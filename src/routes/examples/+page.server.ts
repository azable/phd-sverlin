import { dev } from '$app/environment';
import { error } from '@sveltejs/kit';

import { requireAdmin } from '$lib/server/authorization';
import { listProjectTemplates } from '$lib/server/projects/starter-catalog';

import type { PageServerLoad } from './$types';

/** Offer the compiler-backed example sandbox only in local development. */
export const load: PageServerLoad = ({ locals }) => {
  if (!dev) error(404, 'Example previews are available in development only.');
  requireAdmin(locals);
  return { templates: listProjectTemplates() };
};
