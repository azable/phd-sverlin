import { error } from '@sveltejs/kit';

import { prepareAnalysisExport } from '$lib/server/analysis-export';
import { requireAdmin } from '$lib/server/authorization';
import { ProjectNotFoundError } from '$lib/server/projects/repository';

import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ locals, url }) => {
  requireAdmin(locals);
  const projectId = url.searchParams.get('projectId')?.trim() || undefined;
  try {
    const prepared = await prepareAnalysisExport(projectId);
    return await prepared.response();
  } catch (cause) {
    if (cause instanceof ProjectNotFoundError) error(404, cause.message);
    error(409, cause instanceof Error ? cause.message : 'Analysis export failed.');
  }
};
