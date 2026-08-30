import { json } from '@sveltejs/kit';

import { requireAdmin } from '$lib/server/authorization';
import { listParticipants } from '$lib/server/participants';

import type { RequestHandler } from './$types';

/** Lightweight near-live participant progress snapshot for the visible admin page. */
export const GET: RequestHandler = async ({ locals }) => {
  requireAdmin(locals);
  return json({ participants: await listParticipants() });
};
