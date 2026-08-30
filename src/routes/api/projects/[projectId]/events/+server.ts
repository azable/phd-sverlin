import { error, json } from '@sveltejs/kit';

import { requireProjectAccess } from '$lib/server/authorization';
import {
  projectRepository,
  ProjectConflictError,
  ProjectNotFoundError
} from '$lib/server/projects/repository';

import type { RequestHandler } from './$types';

/** Return an immutable Timeline suffix for durable client polling. */
export const GET: RequestHandler = async ({ params, locals, url }) => {
  await requireProjectAccess(locals, params.projectId);
  const after = readAfter(url);
  try {
    const events = await projectRepository.eventsAfter(params.projectId, after);
    return json(
      { schemaVersion: 2, projectId: params.projectId, after, head: after + events.length, events },
      { headers: { 'cache-control': 'private, no-store' } }
    );
  } catch (cause) {
    if (cause instanceof ProjectNotFoundError) {
      return json({ error: cause.message }, { status: 404 });
    }
    if (cause instanceof ProjectConflictError) {
      return json(
        { error: 'The requested event position is ahead of the project head.' },
        { status: 409 }
      );
    }
    throw cause;
  }
};

function readAfter(url: URL) {
  const id = Number(url.searchParams.get('after') ?? '0');
  if (!Number.isSafeInteger(id) || id < 0) {
    error(400, 'Invalid project event position.');
  }
  return id;
}
