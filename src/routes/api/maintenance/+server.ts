import { json } from '@sveltejs/kit';

import { readMaintenanceStatus } from '$lib/server/maintenance-lock.js';

import type { RequestHandler } from './$types';

/** Report whether project mutations are temporarily disabled. */
export const GET: RequestHandler = async () =>
  json(await readMaintenanceStatus(), {
    headers: { 'cache-control': 'no-store' }
  });
