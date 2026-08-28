import { error } from '@sveltejs/kit';

import { requireAdmin } from '$lib/server/authorization';
import { prepareStudyResearchExport } from '$lib/server/research-data';

import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ locals }) => {
  requireAdmin(locals);
  try {
    const prepared = await prepareStudyResearchExport();
    return await prepared.response();
  } catch (cause) {
    error(409, cause instanceof Error ? cause.message : 'Study export failed.');
  }
};
