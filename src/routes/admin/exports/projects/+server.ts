import { error } from '@sveltejs/kit';

import { requireAdmin } from '$lib/server/authorization';
import { prepareSelectedDataExport } from '$lib/server/data-export-service';
import { ProjectNotFoundError } from '$lib/server/projects/repository';

import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ locals, url }) => {
  requireAdmin(locals);
  const projectId = url.searchParams.get('projectId')?.trim() || undefined;
  try {
    const prepared = await prepareSelectedDataExport({
      type: 'projects',
      ...(projectId ? { projectId } : {})
    });
    return await prepared.response();
  } catch (cause) {
    if (cause instanceof ProjectNotFoundError) error(404, cause.message);
    error(409, cause instanceof Error ? cause.message : 'Project data export failed.');
  }
};
