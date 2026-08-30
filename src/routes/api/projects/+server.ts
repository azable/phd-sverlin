import { randomInt, randomUUID } from 'node:crypto';

import { json } from '@sveltejs/kit';

import {
  defaultProjectCreation,
  InvalidProjectCreationError,
  parseProjectCreation
} from '$lib/shared/projects/creation';
import { projectOperationExecutor } from '$lib/server/projects/operations';
import { createProjectSkeleton } from '$lib/server/projects/service';
import { requireAdmin } from '$lib/server/authorization';
import { UnknownProjectTemplateError } from '$lib/server/projects/starter-catalog';

import type { RequestHandler } from './$types';

/** Create a project and return its stable identifier. */
export const POST: RequestHandler = async ({ request, locals }) => {
  try {
    const principal = requireAdmin(locals);
    const body = await request.text();
    const creation = body.trim() ? parseProjectCreation(JSON.parse(body)) : defaultProjectCreation;
    const operationId = randomUUID();
    const { document } = await createProjectSkeleton({
      creation,
      ownerUserId: principal.user.id,
      operationId
    });
    if (creation.templateId === 'blank') {
      return json({ projectId: document.projectId }, { status: 201 });
    }
    const accepted = await projectOperationExecutor.accept({
      projectId: document.projectId,
      operationId,
      expectedHead: document.events.length,
      command: { type: 'initial-render', seed: randomInt(1, 2147483647) }
    });
    return json(accepted, { status: 202 });
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
