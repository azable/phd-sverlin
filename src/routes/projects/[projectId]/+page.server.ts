import { error, fail, redirect } from '@sveltejs/kit';

import { requireAdmin, requireProjectAccess } from '$lib/server/authorization';
import { projectRepository } from '$lib/server/projects/repository';
import { listProjectTemplates } from '$lib/server/projects/starter-catalog';
import { participantStudyState } from '$lib/server/study';
import {
  adminPreviewTask,
  InvalidStudyPreviewError,
  studyPreviewOption,
  studyPreviewProjectUrl
} from '$lib/server/study-preview';

import type { Actions, PageServerLoad } from './$types';

/** Supply immutable project-template metadata to the creation dialog. */
export const load: PageServerLoad = async ({ locals, params, url }) => {
  const principal = await requireProjectAccess(locals, params.projectId);
  const previewKey = url.searchParams.get('studyPreview');
  const previewStartedAt = url.searchParams.get('previewStartedAt');
  if ((previewKey || previewStartedAt) && principal.kind !== 'admin') {
    error(403, 'Study previews require administrator access.');
  }
  let preview;
  if (previewKey || previewStartedAt) {
    if (!previewKey || !previewStartedAt) error(400, 'Incomplete study preview URL.');
    try {
      preview = adminPreviewTask(previewKey, previewStartedAt);
    } catch (cause) {
      if (cause instanceof InvalidStudyPreviewError) error(400, cause.message);
      throw cause;
    }
  }
  const participantStudy =
    principal.kind === 'participant' ? await participantStudyState(principal.user.id) : undefined;
  return {
    authEnabled: true,
    isAdmin: principal.kind === 'admin',
    templates: principal.kind === 'admin' ? listProjectTemplates() : [],
    study:
      preview ??
      (participantStudy?.phase.kind === 'task' && participantStudy.projectId === params.projectId
        ? {
            context: 'participant' as const,
            phaseId: participantStudy.phase.id,
            title: participantStudy.phase.instructions.title,
            prompt: participantStudy.phase.instructions.prompt,
            deadlineAt: participantStudy.deadlineAt,
            expired: participantStudy.expired,
            layout: participantStudy.phase.condition.workspace.layout
          }
        : undefined)
  };
};

export const actions: Actions = {
  restartPreview: async ({ locals, params, request }) => {
    requireAdmin(locals);
    try {
      await projectRepository.load(params.projectId);
      const form = await request.formData();
      const option = studyPreviewOption(String(form.get('previewKey') ?? ''));
      redirect(303, studyPreviewProjectUrl(params.projectId, option.key, Date.now()));
    } catch (cause) {
      if (cause instanceof InvalidStudyPreviewError) return fail(400, { error: cause.message });
      throw cause;
    }
  }
};
