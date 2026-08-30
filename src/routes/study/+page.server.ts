import { fail, redirect } from '@sveltejs/kit';

import { requirePrincipal } from '$lib/server/authorization';
import {
  continueParticipantStudy,
  participantCompletionGiftCardUrl,
  participantStudyState
} from '$lib/server/study';

import type { Actions, PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals }) => {
  const principal = requirePrincipal(locals);
  if (principal.kind === 'admin') redirect(303, '/');
  const state = await participantStudyState(principal.user.id);
  if (state.phase.kind === 'task' && state.projectId && !state.expired) {
    redirect(303, `/projects/${state.projectId}`);
  }
  return {
    state,
    giftCardUrl:
      state.phase.kind === 'completion'
        ? await participantCompletionGiftCardUrl(principal.user.id)
        : undefined
  };
};

export const actions: Actions = {
  default: async ({ locals }) => {
    const principal = requirePrincipal(locals);
    if (principal.kind === 'admin') redirect(303, '/');
    let state;
    try {
      state = await continueParticipantStudy(principal.user.id);
    } catch (cause) {
      return fail(409, {
        error: cause instanceof Error ? cause.message : 'The study could not continue.'
      });
    }
    if (state.phase.kind === 'task' && state.projectId) {
      redirect(303, `/projects/${state.projectId}`);
    }
    return { continued: true };
  }
};
