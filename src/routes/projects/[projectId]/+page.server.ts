import { randomUUID } from 'node:crypto';

import { fail, redirect } from '@sveltejs/kit';

import { projectHead } from '$lib/projects/project';
import type {
  FeedbackAttachment,
  ProjectActionAck,
  ProjectCommandResult
} from '$lib/projects/types';
import { chooseCompileSeed, InvalidCompileSeedError } from '$lib/server/compile-seed';
import { submitProjectFeedback } from '$lib/server/projects/commands';
import {
  projectRepository,
  ProjectConflictError,
  ProjectNotFoundError
} from '$lib/server/projects/repository';
import {
  createProject,
  loadProjectPage,
  renameProject,
  renderProject,
  restoreProjectArtifacts,
  updateProjectArtifact
} from '$lib/server/projects/service';

import type { Actions, PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ params, url }) => {
  try {
    return {
      ...(await loadProjectPage(params.projectId, url.searchParams.get('at') ?? undefined)),
      projects: await projectRepository.list()
    };
  } catch (error) {
    if (error instanceof ProjectNotFoundError) redirect(307, '/');
    throw error;
  }
};

export const actions = {
  newProject: async () => {
    const project = await createProject();
    redirect(303, `/projects/${project.document.projectId}`);
  },
  rename: async ({ params, request }) => {
    const data = await request.formData();
    try {
      const correlationId = readCorrelationId(data);
      return actionAck(
        await renameProject({
          projectId: params.projectId,
          expectedHeadEventId: requiredString(data, 'expectedHeadEventId'),
          title: requiredString(data, 'title'),
          correlationId
        }),
        correlationId
      );
    } catch (error) {
      return actionFailure(error);
    }
  },
  feedback: async ({ params, request }) => {
    const data = await request.formData();
    try {
      const correlationId = readCorrelationId(data);
      return actionAck(
        await submitProjectFeedback({
          projectId: params.projectId,
          expectedHeadEventId: requiredString(data, 'expectedHeadEventId'),
          text: optionalString(data, 'text'),
          attachments: readAttachments(data),
          seed: chooseCompileSeed(data.get('seed')),
          correlationId
        }),
        correlationId
      );
    } catch (error) {
      return actionFailure(error);
    }
  },
  saveArtifact: async ({ params, request }) => {
    const data = await request.formData();
    try {
      const correlationId = readCorrelationId(data);
      return actionAck(
        await updateProjectArtifact({
          projectId: params.projectId,
          expectedHeadEventId: requiredString(data, 'expectedHeadEventId'),
          artifactId: requiredString(data, 'artifactId'),
          content: requiredSource(data, 'content'),
          seed: chooseCompileSeed(data.get('seed')),
          correlationId
        }),
        correlationId
      );
    } catch (error) {
      return actionFailure(error);
    }
  },
  render: async ({ params, request }) => {
    const data = await request.formData();
    try {
      const correlationId = readCorrelationId(data);
      return actionAck(
        await renderProject({
          projectId: params.projectId,
          expectedHeadEventId: requiredString(data, 'expectedHeadEventId'),
          seed: chooseCompileSeed(data.get('seed')),
          correlationId
        }),
        correlationId
      );
    } catch (error) {
      return actionFailure(error);
    }
  },
  restore: async ({ params, request }) => {
    const data = await request.formData();
    try {
      const correlationId = readCorrelationId(data);
      return actionAck(
        await restoreProjectArtifacts({
          projectId: params.projectId,
          expectedHeadEventId: requiredString(data, 'expectedHeadEventId'),
          restoredFromEventId: requiredString(data, 'restoredFromEventId'),
          seed: chooseCompileSeed(data.get('seed')),
          correlationId
        }),
        correlationId
      );
    } catch (error) {
      return actionFailure(error);
    }
  }
} satisfies Actions;

function requiredString(data: FormData, key: string) {
  const value = data.get(key);
  if (typeof value !== 'string' || !value.trim()) throw new Error(`Missing ${key}.`);
  return value.trim();
}

function optionalString(data: FormData, key: string) {
  const value = data.get(key);
  return typeof value === 'string' && value.trim() ? value.trim() : undefined;
}

function requiredSource(data: FormData, key: string) {
  const value = data.get(key);
  if (typeof value !== 'string' || !value.trim()) throw new Error(`Missing ${key}.`);
  return value;
}

function readAttachments(data: FormData): FeedbackAttachment[] {
  const value = data.get('attachments');
  if (typeof value !== 'string' || !value) return [];
  const parsed = JSON.parse(value) as unknown;
  if (!Array.isArray(parsed)) throw new Error('Feedback attachments must be an array.');
  return parsed as FeedbackAttachment[];
}

function readCorrelationId(data: FormData) {
  const value = data.get('correlationId');
  if (value === null || value === '') return randomUUID();
  if (
    typeof value !== 'string' ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
  ) {
    throw new Error('Invalid project action correlation ID.');
  }
  return value;
}

function actionAck(result: ProjectCommandResult, correlationId: string): ProjectActionAck {
  return { correlationId, headEventId: projectHead(result.document).eventId };
}

function actionFailure(error: unknown) {
  if (error instanceof InvalidCompileSeedError) return fail(400, { error: error.message });
  if (
    error instanceof ProjectConflictError ||
    (error instanceof Error && error.name === 'ProjectConflictError')
  ) {
    return fail(409, { error: error.message });
  }
  return fail(422, {
    error: error instanceof Error ? error.message : 'Project operation failed.'
  });
}
