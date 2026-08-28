import { randomInt, randomUUID } from 'node:crypto';

import { json } from '@sveltejs/kit';

import {
  defaultProjectCreation,
  InvalidProjectCreationError,
  parseProjectCreation
} from '$lib/shared/projects/creation';
import { createProjectJob } from '$lib/server/projects/jobs';
import { usesPostgresProjectStore } from '$lib/server/projects/repository';
import { createProject, createProjectSkeleton } from '$lib/server/projects/service';
import { requirePrincipal } from '$lib/server/authorization';
import { UnknownProjectTemplateError } from '$lib/server/projects/starter-catalog';

import type { RequestHandler } from './$types';

/** Create a project and return its stable identifier. */
export const POST: RequestHandler = async ({ request, locals }) => {
  try {
    const principal = requirePrincipal(locals);
    const body = await request.text();
    const creation = body.trim() ? parseProjectCreation(JSON.parse(body)) : defaultProjectCreation;
    if (usesPostgresProjectStore) {
      const operationId = randomUUID();
      const { document } = await createProjectSkeleton({
        creation,
        ownerUserId: principal.user.id
      });
      const job = await createProjectJob({
        projectId: document.projectId,
        ownerUserId: principal.user.id,
        operationId,
        expectedHead: document.events.length,
        command: { type: 'initial-render', seed: randomInt(1, 2147483647) }
      });
      return json(
        { projectId: document.projectId, jobId: job.id, status: 'queued' },
        { status: 202 }
      );
    }
    const document = await createProject({ creation, ownerUserId: principal.user.id });
    return json({ projectId: document.projectId }, { status: 201 });
  } catch (cause) {
    if (
      cause instanceof SyntaxError ||
      cause instanceof InvalidProjectCreationError ||
      cause instanceof UnknownProjectTemplateError
    ) {
      return json({ error: cause.message }, { status: 400 });
    }
    return json(
      { error: cause instanceof Error ? cause.message : 'Project creation failed.' },
      { status: 500 }
    );
  }
};
