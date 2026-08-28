import { fail } from '@sveltejs/kit';

import { requireAdmin } from '$lib/server/authorization';
import {
  createParticipant,
  listParticipants,
  resetParticipantPassword,
  setParticipantEnabled
} from '$lib/server/participants';
import { purgeParticipantResearchData, purgeStudyResearchData } from '$lib/server/research-data';

import type { Actions, PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals }) => {
  requireAdmin(locals);
  return { participants: await listParticipants() };
};

export const actions: Actions = {
  create: async ({ locals, request }) => {
    requireAdmin(locals);
    try {
      const form = await request.formData();
      const credentials = await createParticipant(
        String(form.get('participantId') ?? ''),
        request.headers
      );
      return {
        participantId: credentials.participantId,
        participantPassword: credentials.password
      };
    } catch (cause) {
      return fail(400, {
        error: cause instanceof Error ? cause.message : 'Participant creation failed.'
      });
    }
  },
  password: async ({ locals, request }) => {
    requireAdmin(locals);
    try {
      const form = await request.formData();
      const credentials = await resetParticipantPassword(
        String(form.get('id') ?? ''),
        request.headers
      );
      return {
        participantId: credentials.participantId,
        participantPassword: credentials.password
      };
    } catch (cause) {
      return fail(400, {
        error: cause instanceof Error ? cause.message : 'Password reset failed.'
      });
    }
  },
  access: async ({ locals, request }) => {
    requireAdmin(locals);
    try {
      const form = await request.formData();
      await setParticipantEnabled(
        String(form.get('id') ?? ''),
        String(form.get('enabled')) === 'true',
        request.headers
      );
      return { accessUpdated: true };
    } catch (cause) {
      return fail(400, { error: cause instanceof Error ? cause.message : 'Access update failed.' });
    }
  },
  purgeParticipant: async ({ locals, request }) => {
    requireAdmin(locals);
    try {
      const form = await request.formData();
      const userId = String(form.get('id') ?? '');
      const participantId = await purgeParticipantResearchData(
        userId,
        String(form.get('confirmation') ?? ''),
        request.headers
      );
      return { participantPurged: participantId };
    } catch (cause) {
      return fail(409, {
        error: cause instanceof Error ? cause.message : 'Participant deletion failed.'
      });
    }
  },
  purgeStudy: async ({ locals, request }) => {
    requireAdmin(locals);
    try {
      const form = await request.formData();
      if (form.get('confirmation') !== 'DELETE STUDY DATA') {
        return fail(400, { error: 'Enter DELETE STUDY DATA to confirm the purge.' });
      }
      const participantsPurged = await purgeStudyResearchData(request.headers);
      return { studyPurged: true, participantsPurged };
    } catch (cause) {
      return fail(409, { error: cause instanceof Error ? cause.message : 'Study purge failed.' });
    }
  }
};
