import { fail, redirect } from '@sveltejs/kit';

import { requireAdmin } from '$lib/server/authorization';
import { adminStudyPreviewState, forceStudyPreview } from '$lib/server/study';

import type { Actions, PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals, params }) => {
  const principal = requireAdmin(locals);
  const state = await adminStudyPreviewState(params.runId, principal.user.id);
  if (!state.completed && state.phase.kind === 'task' && state.projectId) {
    redirect(303, `/projects/${encodeURIComponent(state.projectId)}`);
  }
  return { state };
};

export const actions: Actions = {
  default: async ({ locals, params }) => {
    const principal = requireAdmin(locals);
    let destination: string | undefined;
    try {
      const state = await forceStudyPreview(params.runId, principal.user.id);
      if (!state.completed && state.phase.kind === 'task' && state.projectId) {
        destination = `/projects/${encodeURIComponent(state.projectId)}`;
      }
    } catch (cause) {
      return fail(409, {
        error: cause instanceof Error ? cause.message : 'The preview could not advance.'
      });
    }
    if (destination) redirect(303, destination);
    return { advanced: true };
  }
};
