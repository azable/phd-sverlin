import { error } from '@sveltejs/kit';

import { requireAdmin } from '$lib/server/authorization';
import { prepareStudyResearchExport } from '$lib/server/research-data';

import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ locals, url }) => {
  requireAdmin(locals);
  const studyId = url.searchParams.get('studyId')?.trim();
  const versionValue = url.searchParams.get('version')?.trim();
  if (!!studyId !== !!versionValue) error(400, 'Study ID and version must be supplied together.');
  const version = versionValue ? Number(versionValue) : undefined;
  if (version !== undefined && (!Number.isSafeInteger(version) || version <= 0)) {
    error(400, 'Study version must be a positive integer.');
  }
  try {
    const prepared = await prepareStudyResearchExport(
      studyId && version !== undefined ? { id: studyId, version } : undefined
    );
    return await prepared.response();
  } catch (cause) {
    error(409, cause instanceof Error ? cause.message : 'Study export failed.');
  }
};
