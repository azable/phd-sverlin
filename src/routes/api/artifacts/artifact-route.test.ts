import { beforeEach, describe, expect, it } from 'vitest';

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
    await resetArtifactToInitial();
  });

  it('starts from the minimal in-memory Sverlin example', () => {
    const initial = getArtifactSyncState();

    expect(initial.current).toMatchObject({
      id: 'dsl-main',
      path: 'Main.sverlin',
      language: 'sverlin'
    });
    expect(initial.current.content).toContain('program :: Choreography ()');
    expect(initial.current.content).toContain('program = return ()');
    expect(initial.current.content).toContain('visualization :: VisualizationBuilder ()');
    expect(initial.current.content).toContain('visualization = return ()');
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

  it('accepts syntax errors so the compiler can return canonical diagnostics', async () => {
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

    expect(response.status).toBe(200);
  });

  it('keeps the current revision when source validation fails', async () => {
    const initial = getArtifactSyncState();

    const response = await PATCH(
      patchEvent(
        new Request('http://localhost/api/artifacts/dsl-main', {
          method: 'PATCH',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({
            content: `${initial.current.content}\0`,
            baseRevision: initial.headRevision
          })
        })
      )
    );

    expect(response.status).toBe(422);
    expect(getArtifactSyncState()).toMatchObject({
      headRevision: initial.headRevision,
      current: { content: initial.current.content }
    });
  });
});
