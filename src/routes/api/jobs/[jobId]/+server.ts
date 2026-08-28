import { json } from '@sveltejs/kit';

import { projectListOwner, requirePrincipal } from '$lib/server/authorization';
import { readProjectJob } from '$lib/server/projects/jobs';

import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ locals, params }) => {
  const principal = requirePrincipal(locals);
  const job = await readProjectJob(params.jobId, projectListOwner(principal));
  if (!job) return json({ error: 'Project job not found.' }, { status: 404 });
  return json(job, { headers: { 'cache-control': 'private, no-store' } });
};
