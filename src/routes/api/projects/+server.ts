import { json } from '@sveltejs/kit';

import { createProject } from '$lib/server/projects/service';

import type { RequestHandler } from './$types';

/** Create a project and return its stable identifier. */
export const POST: RequestHandler = async () => {
  const document = await createProject();
  return json({ projectId: document.projectId }, { status: 201 });
};
