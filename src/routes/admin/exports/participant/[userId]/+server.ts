import { error } from '@sveltejs/kit';

import { requireAdmin } from '$lib/server/authorization';
import { prepareSelectedDataExport } from '$lib/server/data-export-service';

import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ locals, params }) => {
  requireAdmin(locals);
  try {
    const prepared = await prepareSelectedDataExport({
      type: 'participant',
      participant: { type: 'user-id', value: params.userId }
    });
    return await prepared.response();
  } catch (cause) {
    error(409, cause instanceof Error ? cause.message : 'Participant export failed.');
  }
};
