import { beforeEach, describe, expect, it, vi } from 'vitest';

const persistSourceArtifact = vi.hoisted(() => vi.fn());

vi.mock('$lib/server/artifacts/source-file', async (importOriginal) => ({
  ...(await importOriginal<typeof import('$lib/server/artifacts/source-file')>()),
  persistSourceArtifact
}));

import { SourceArtifactBusyError } from '$lib/server/artifacts/source-file';
import { resetArtifactToInitial, getArtifactSyncState } from '$lib/server/artifacts/store';
import { GET, PATCH } from './[artifactId]/+server';

function patchEvent(request: Request) {
  return {
    params: { artifactId: 'dsl-main' },
    request
  } as Parameters<typeof PATCH>[0];
}

describe('artifact API', () => {
  beforeEach(async () => {
    persistSourceArtifact.mockReset();
    persistSourceArtifact.mockResolvedValue(undefined);
    await resetArtifactToInitial();
  });

  it('returns the complete audit state and records a manual revision', async () => {
    const initial = getArtifactSyncState();
    const content = `${initial.current.content}\n\n-- manual revision`;

    const response = await PATCH(
      patchEvent(
        new Request('http://localhost/api/artifacts/dsl-main', {
          method: 'PATCH',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ content, baseRevision: initial.headRevision, reason: 'test edit' })
        })
      )
    );
    const state = await response.json();

    expect(response.status).toBe(200);
    expect(state.current.content).toBe(content);
    expect(state.events.at(-1).source).toEqual({
      kind: 'manual',
      actor: 'user',
      reason: 'test edit'
    });
    expect(persistSourceArtifact).toHaveBeenLastCalledWith(content);

    const fullResponse = await GET({
      params: { artifactId: 'dsl-main' },
      url: new URL('http://localhost/api/artifacts/dsl-main')
    } as Parameters<typeof GET>[0]);
    const fullState = await fullResponse.json();
    expect(fullState.events).toHaveLength(initial.events.length + 1);
  });

  it('returns the latest state when a patch has a stale base revision', async () => {
    const initial = getArtifactSyncState();
    const request = (content: string, baseRevision: number) =>
      PATCH(
        patchEvent(
          new Request('http://localhost/api/artifacts/dsl-main', {
            method: 'PATCH',
            headers: { 'content-type': 'application/json' },
            body: JSON.stringify({ content, baseRevision })
          })
        )
      );

    const first = await request(`${initial.current.content}\n\n-- first`, initial.headRevision);
    expect(first.status).toBe(200);

    const conflict = await request(`${initial.current.content}\n\n-- stale`, initial.headRevision);
    const payload = await conflict.json();

    expect(conflict.status).toBe(409);
    expect(payload.state.headRevision).toBe(initial.headRevision + 1);
    expect(payload.state.events).toHaveLength(initial.events.length + 1);
  });

  it('rejects source that does not satisfy the DSL boundary', async () => {
    const initial = getArtifactSyncState();
    const response = await PATCH(
      patchEvent(
        new Request('http://localhost/api/artifacts/dsl-main', {
          method: 'PATCH',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ content: 'not Haskell', baseRevision: initial.headRevision })
        })
      )
    );

    expect(response.status).toBe(422);
  });

  it('keeps the current revision when the source file is locked', async () => {
    const initial = getArtifactSyncState();
    persistSourceArtifact.mockRejectedValueOnce(
      new SourceArtifactBusyError('Compile backend is already running.')
    );

    const response = await PATCH(
      patchEvent(
        new Request('http://localhost/api/artifacts/dsl-main', {
          method: 'PATCH',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({
            content: `${initial.current.content}\n\n-- blocked`,
            baseRevision: initial.headRevision
          })
        })
      )
    );

    expect(response.status).toBe(423);
    expect(getArtifactSyncState()).toMatchObject({
      headRevision: initial.headRevision,
      current: { content: initial.current.content }
    });
  });
});
