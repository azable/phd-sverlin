import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  loadProjectResource: vi.fn(),
  accept: vi.fn(),
  requireMutation: vi.fn()
}));

vi.mock('$lib/server/projects/service', () => ({
  loadProjectResource: mocks.loadProjectResource
}));
vi.mock('$lib/server/projects/operations', () => ({
  projectOperationExecutor: { accept: mocks.accept }
}));
vi.mock('$lib/server/authorization', () => ({
  requireProjectAccess: vi.fn(async (locals) => locals.principal),
  requireProjectMutationAccess: mocks.requireMutation,
  projectListOwner: vi.fn(() => 'user-test')
}));

const operationId = '12345678-1234-4123-8123-123456789abc';

beforeEach(() => {
  Object.values(mocks).forEach((mock) => mock.mockReset().mockResolvedValue(undefined));
  mocks.accept.mockResolvedValue({
    projectId: 'project-test',
    operationId,
    acceptedEventId: 5
  });
  mocks.requireMutation.mockResolvedValue({});
  mocks.loadProjectResource.mockResolvedValue({
    document: { schemaVersion: 2, projectId: 'project-test', events: [] },
    projects: []
  });
});

describe('project JSON API', () => {
  it('accepts a validated command and returns its Timeline operation', async () => {
    const { POST } = await import('./+server');
    const response = await POST(
      request('POST', {
        type: 'rename',
        operationId,
        expectedHead: 4,
        title: 'Renamed'
      })
    );

    expect(response.status).toBe(202);
    await expect(response.json()).resolves.toEqual({
      projectId: 'project-test',
      operationId,
      acceptedEventId: 5
    });
    expect(mocks.accept).toHaveBeenCalledWith({
      projectId: 'project-test',
      operationId,
      expectedHead: 4,
      command: {
        type: 'rename',
        operationId,
        expectedHead: 4,
        title: 'Renamed'
      }
    });
  });

  it('returns structured client and conflict errors', async () => {
    const { POST } = await import('./+server');
    const invalid = await POST(request('POST', { type: 'render', seed: 1 }));
    expect(invalid.status).toBe(400);
    await expect(invalid.json()).resolves.toHaveProperty('error');

    const conflict = new Error('stale');
    conflict.name = 'ProjectConflictError';
    mocks.accept.mockRejectedValueOnce(conflict);
    const stale = await POST(
      request('POST', { type: 'render', operationId, expectedHead: 2, seed: 1 })
    );
    expect(stale.status).toBe(409);
    await expect(stale.json()).resolves.toEqual({ error: 'stale' });
  });

  it('passes the server-authoritative study deadline into asynchronous work', async () => {
    mocks.requireMutation.mockResolvedValueOnce({
      study: { deadlineAt: '2026-08-30T12:15:00.000Z' }
    });
    const { POST } = await import('./+server');

    const response = await POST(
      request('POST', {
        type: 'rename',
        operationId,
        expectedHead: 4,
        title: 'Renamed'
      })
    );

    expect(response.status).toBe(202);
    expect(mocks.accept).toHaveBeenCalledWith(
      expect.objectContaining({ deadlineAt: '2026-08-30T12:15:00.000Z' })
    );
  });

  it('accepts zero-based instance IDs in inline element references', async () => {
    const { POST } = await import('./+server');
    const response = await POST(
      request('POST', {
        type: 'feedback',
        operationId,
        expectedHead: 4,
        focus: [],
        content: [
          { type: 'markdown', text: 'Make this clearer' },
          {
            type: 'element-ref',
            presentationId: '12345678-1234-4123-8123-123456789ac1',
            presentationEvent: 3,
            step: 0,
            instances: [0]
          }
        ],
        presentationCount: 1
      })
    );

    expect(response.status).toBe(202);
    expect(mocks.accept).toHaveBeenCalledWith(
      expect.objectContaining({
        command: expect.objectContaining({
          content: expect.arrayContaining([
            expect.objectContaining({
              type: 'element-ref',
              presentationEvent: 3,
              instances: [0]
            })
          ])
        })
      })
    );
  });

  it('accepts focused selections from both candidates in a preference command', async () => {
    const { POST } = await import('./+server');
    const presentations = [
      '12345678-1234-4123-8123-123456789ac1',
      '12345678-1234-4123-8123-123456789ac2'
    ] as const;
    const visualSelections = [
      { presentationEvent: 3, step: 0, instances: [0, 2] },
      { presentationEvent: 4, step: 0, instances: [1] }
    ];
    const response = await POST(
      request('POST', {
        type: 'prefer',
        operationId,
        expectedHead: 4,
        presentations,
        preferred: presentations[0],
        step: 0,
        visualSelections
      })
    );

    expect(response.status).toBe(202);
    expect(mocks.accept).toHaveBeenCalledWith(
      expect.objectContaining({
        command: expect.objectContaining({ type: 'prefer', visualSelections })
      })
    );
  });

  it('rejects the former top-level visual-selection shape', async () => {
    const { POST } = await import('./+server');
    const response = await POST(
      request('POST', {
        type: 'feedback',
        operationId,
        expectedHead: 4,
        focus: [],
        selection: { presentationEvent: 3, step: 0, instances: [0] },
        content: [{ type: 'markdown', text: 'Legacy selection' }],
        presentationCount: 2
      })
    );

    expect(response.status).toBe(400);
    expect(mocks.accept).not.toHaveBeenCalled();
  });
});

function request(method: string, body: unknown) {
  const url = new URL('http://localhost/api/projects/project-test');
  return {
    locals: testLocals(),
    params: { projectId: 'project-test' },
    url,
    request: new Request(url, {
      method,
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body)
    })
  } as never;
}

function testLocals() {
  return {
    principal: {
      kind: 'participant',
      user: { id: 'user-test' },
      session: {},
      participant: {
        participantId: 'P001'
      }
    }
  };
}
