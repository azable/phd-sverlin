import { json } from '@sveltejs/kit';

import { readActiveCompileLock } from '$lib/server/compile-lock.js';
import type { CompileStatus } from '$lib/visualization/types';

import type { RequestHandler } from './$types';

export const prerender = false;

export const GET: RequestHandler = async () => {
  return json(await _readCompileStatus(), {
    headers: {
      'Cache-Control': 'no-store'
    }
  });
};

export async function _readCompileStatus(): Promise<CompileStatus> {
  const lock = await readActiveCompileLock();
  return lock ? { running: true, ...lock } : { running: false };
}
