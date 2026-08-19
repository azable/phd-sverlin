import { json } from '@sveltejs/kit';

import { updateArtifactFromManualEdit } from '$lib/server/artifacts/service';
import { getArtifactSyncState } from '$lib/server/artifacts/store';

import type { RequestHandler } from './$types';

const artifactId = 'dsl-main';

export const GET: RequestHandler = ({ params, url }) => {
  if (params.artifactId !== artifactId)
    return json({ error: 'Unknown artifact.' }, { status: 404 });

  const afterText = url.searchParams.get('after');
  const after = afterText === null ? undefined : Number(afterText);
  if (after !== undefined && (!Number.isSafeInteger(after) || after < 0)) {
    return json({ error: '`after` must be a non-negative integer.' }, { status: 400 });
  }

  return json(getArtifactSyncState(after));
};

export const PATCH: RequestHandler = async ({ params, request }) => {
  if (params.artifactId !== artifactId)
    return json({ error: 'Unknown artifact.' }, { status: 404 });

  const body = (await request.json().catch(() => null)) as {
    content?: unknown;
    baseRevision?: unknown;
    reason?: unknown;
  } | null;
  if (
    body === null ||
    typeof body.content !== 'string' ||
    !Number.isSafeInteger(body.baseRevision) ||
    (typeof body.reason !== 'undefined' && typeof body.reason !== 'string')
  ) {
    return json({ error: 'Expected content, baseRevision, and optional reason.' }, { status: 400 });
  }

  try {
    return json(
      updateArtifactFromManualEdit(
        body.content,
        body.baseRevision as number,
        body.reason as string | undefined
      )
    );
  } catch (error) {
    if (error instanceof Error && error.name === 'ArtifactConflictError') {
      return json({ error: error.message, state: getArtifactSyncState() }, { status: 409 });
    }
    return json(
      { error: error instanceof Error ? error.message : 'Artifact update failed.' },
      { status: 422 }
    );
  }
};
