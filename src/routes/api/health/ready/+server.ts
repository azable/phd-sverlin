import { json, type RequestHandler } from '@sveltejs/kit';

import { runtimeReadiness } from '$lib/server/runtime-state';

export const GET: RequestHandler = async () => {
  const readiness = await runtimeReadiness();
  return json(
    { status: readiness.ready ? 'ready' : 'not-ready' },
    {
      status: readiness.ready ? 200 : 503,
      headers: { 'cache-control': 'no-store' }
    }
  );
};
