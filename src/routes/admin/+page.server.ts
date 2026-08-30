import { fail, redirect } from '@sveltejs/kit';

import { requireAdmin } from '$lib/server/authorization';
import {
  createParticipant,
  listParticipants,
  resetParticipantPassword,
  setParticipantGiftCardUrl,
  setParticipantEnabled
} from '$lib/server/participants';
import { projectRepository } from '$lib/server/projects/repository';
import { createProject } from '$lib/server/projects/service';
import { purgeParticipantResearchData, purgeStudyResearchData } from '$lib/server/research-data';
import {
  InvalidStudyPreviewError,
  studyPreviewOptions,
  studyPreviewOption,
  studyPreviewProjectUrl
} from '$lib/server/study-preview';

import type { Actions, PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals }) => {
  const principal = requireAdmin(locals);
  const participants = await listParticipants();
  const [allProjects, ...participantProjects] = await Promise.all([
    projectRepository.list(),
    ...participants.map((participant) => projectRepository.list(participant.id))
  ]);
  const ownerByProjectId = new Map(
    participantProjects.flatMap((projects, index) =>
      projects.map((project) => [project.projectId, participants[index].participantId] as const)
    )
  );
  return {
    previewOptions: studyPreviewOptions().map(
      ({ key, name, label, renderer, layout, durationSeconds }) => ({
        key,
        name,
        label,
        renderer,
        layout,
        durationSeconds
      })
    ),
    allProjects: allProjects.map((project) => ({
      ...project,
      ownerLabel: ownerByProjectId.get(project.projectId) ?? principal.user.name ?? 'Administrator'
    })),
    participants: participants.map((participant, index) => ({
      ...participant,
      projectCount: participantProjects[index].length,
      projects: participantProjects[index]
    }))
  };
};

export const actions: Actions = {
  createPreview: async ({ locals, request }) => {
    const principal = requireAdmin(locals);
    let projectId: string;
    let previewKey: string;
    try {
      const form = await request.formData();
      const option = studyPreviewOption(String(form.get('previewKey') ?? ''));
      previewKey = option.key;
      const document = await createProject({
        ownerUserId: principal.user.id,
        title: `Preview · ${option.name}`,
        creation: { templateId: option.templateId, renderer: option.renderer },
        presentationCount: option.presentationCount
      });
      projectId = document.projectId;
    } catch (cause) {
      return fail(cause instanceof InvalidStudyPreviewError ? 400 : 500, {
        error: cause instanceof Error ? cause.message : 'Study preview creation failed.'
      });
    }
    redirect(303, studyPreviewProjectUrl(projectId, previewKey, Date.now()));
  },
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
  giftCard: async ({ locals, request }) => {
    requireAdmin(locals);
    try {
      const form = await request.formData();
      const userId = String(form.get('id') ?? '');
      const giftCardUrl =
        form.get('clearGiftCard') === 'true' ? '' : String(form.get('giftCardUrl') ?? '');
      await setParticipantGiftCardUrl(userId, giftCardUrl);
      return { giftCardUpdated: userId };
    } catch (cause) {
      return fail(400, {
        error: cause instanceof Error ? cause.message : 'Gift-card update failed.'
      });
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
