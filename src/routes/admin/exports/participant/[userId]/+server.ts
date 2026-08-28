import { error } from '@sveltejs/kit';

import { requireAdmin } from '$lib/server/authorization';
import { prepareParticipantResearchExport } from '$lib/server/research-data';

import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ locals, params }) => {
  requireAdmin(locals);
  try {
    const prepared = await prepareParticipantResearchExport(params.userId);
    return await prepared.response();
  } catch (cause) {
    error(409, cause instanceof Error ? cause.message : 'Participant export failed.');
  }
};
