import { json } from '@sveltejs/kit';

import {
  defaultProjectCreation,
  InvalidProjectCreationError,
  parseProjectCreation
} from '$lib/shared/projects/creation';
import { createProject } from '$lib/server/projects/service';
import { UnknownProjectTemplateError } from '$lib/server/projects/starter-catalog';

import type { RequestHandler } from './$types';

/** Create a project and return its stable identifier. */
export const POST: RequestHandler = async ({ request }) => {
  try {
    const body = await request.text();
    const creation = body.trim() ? parseProjectCreation(JSON.parse(body)) : defaultProjectCreation;
    const document = await createProject({ creation });
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
