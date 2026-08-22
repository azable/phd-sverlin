import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  loadProjectResource: vi.fn(),
  renameProject: vi.fn(),
  renderProject: vi.fn(),
  restoreProjectArtifacts: vi.fn(),
  updateProjectArtifact: vi.fn(),
  submitProjectFeedback: vi.fn()
}));

vi.mock('$lib/server/projects/service', () => mocks);
vi.mock('$lib/server/projects/commands', () => ({
  submitProjectFeedback: mocks.submitProjectFeedback
}));

const operationId = '12345678-1234-4123-8123-123456789abc';

beforeEach(() => {
  Object.values(mocks).forEach((mock) => mock.mockReset().mockResolvedValue(undefined));
  mocks.loadProjectResource.mockResolvedValue({
    document: { schemaVersion: 1, projectId: 'project-test', events: [] },
    projects: []
  });
});

describe('project JSON API', () => {
  it('dispatches a validated command and returns the authoritative project resource', async () => {
    const { POST } = await import('./+server');
    const response = await POST(
      request('POST', {
        type: 'rename',
        operationId,
        expectedHead: 4,
        title: 'Renamed'
      })
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      document: { projectId: 'project-test' }
    });
    expect(mocks.renameProject).toHaveBeenCalledWith({
      projectId: 'project-test',
      operationId,
      expectedHead: 4,
      title: 'Renamed'
    });
    expect(mocks.loadProjectResource).toHaveBeenCalledWith('project-test');
  });

  it('returns structured client and conflict errors', async () => {
    const { POST } = await import('./+server');
    const invalid = await POST(request('POST', { type: 'render', seed: 1 }));
    expect(invalid.status).toBe(400);
    await expect(invalid.json()).resolves.toHaveProperty('error');

    const conflict = new Error('stale');
    conflict.name = 'ProjectConflictError';
    mocks.renderProject.mockRejectedValueOnce(conflict);
    const stale = await POST(
      request('POST', { type: 'render', operationId, expectedHead: 2, seed: 1 })
    );
    expect(stale.status).toBe(409);
    await expect(stale.json()).resolves.toEqual({ error: 'stale' });
  });
});

function request(method: string, body: unknown) {
  const url = new URL('http://localhost/api/projects/project-test');
  return {
    params: { projectId: 'project-test' },
    url,
    request: new Request(url, {
      method,
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body)
    })
  } as never;
}
