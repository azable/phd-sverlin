import { createHash } from 'node:crypto';

import { error } from '@sveltejs/kit';

import { requireProjectAccess } from '$lib/server/authorization';

import {
  projectRepository,
  ProjectNotFoundError,
  ProjectResourceNotFoundError
} from '$lib/server/projects/repository';

import type { RequestHandler } from './$types';

/** Serve one immutable compiler resource only when it is referenced by project history. */
export const GET: RequestHandler = async ({ params, locals }) => {
  try {
    await requireProjectAccess(locals, params.projectId);
    const document = await projectRepository.load(params.projectId);
    const reference = document.events
      .flatMap((event) => {
        if (event.type === 'visualization.presented') {
          return event.payload.presentation.format === 'sverlin-ir-v1'
            ? (event.payload.presentation.resources ?? [])
            : [];
        }
        return event.type === 'compilation.succeeded' || event.type === 'visualization.rendered'
          ? (event.payload.resources ?? [])
          : [];
      })
      .find(({ id }) => id === params.resourceId);
    if (!reference) error(404, 'Unknown project resource.');

    const bytes = await projectRepository.readResource(params.projectId, reference.id);
    if (bytes.byteLength !== reference.byteLength) {
      error(500, 'Stored project resource has an unexpected byte length.');
    }
    const sha256 = createHash('sha256').update(bytes).digest('hex');
    if (reference.id !== `sha256-${reference.sha256}` || sha256 !== reference.sha256) {
      error(500, 'Stored project resource failed SHA-256 verification.');
    }

    return new Response(Uint8Array.from(bytes).buffer, {
      headers: {
        'cache-control': 'private, max-age=300, immutable',
        'content-length': String(bytes.byteLength),
        'content-type': reference.mediaType,
        etag: `"${reference.sha256}"`,
        'x-content-type-options': 'nosniff'
      }
    });
  } catch (cause) {
    if (cause instanceof ProjectNotFoundError || cause instanceof ProjectResourceNotFoundError) {
      error(404, cause.message);
    }
    throw cause;
  }
};
