import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({ createProjectSkeleton: vi.fn(), accept: vi.fn() }));

vi.mock('$lib/server/projects/service', () => ({
  createProjectSkeleton: mocks.createProjectSkeleton
}));
vi.mock('$lib/server/projects/operations', () => ({
  projectOperationExecutor: { accept: mocks.accept }
}));

beforeEach(() => {
  mocks.createProjectSkeleton.mockReset().mockResolvedValue({
    document: { projectId: 'project-created', events: [{}, {}] }
  });
  mocks.accept.mockReset().mockResolvedValue({
    projectId: 'project-created',
    operationId: '12345678-1234-4123-8123-123456789abc',
    acceptedEventId: 3
  });
});

describe('project creation API', () => {
  it('creates the requested project template', async () => {
    const { POST } = await import('./+server');
    const response = await POST(request({ templateId: 'linear-search' }));

    expect(response.status).toBe(202);
    await expect(response.json()).resolves.toEqual({
      projectId: 'project-created',
      operationId: '12345678-1234-4123-8123-123456789abc',
      acceptedEventId: 3
    });
    expect(mocks.createProjectSkeleton).toHaveBeenCalledWith(
      expect.objectContaining({
        creation: { templateId: 'linear-search' },
        ownerUserId: 'user-test',
        operationId: expect.any(String)
      })
    );
    expect(mocks.accept).toHaveBeenCalledWith(
      expect.objectContaining({
        projectId: 'project-created',
        expectedHead: 2,
        command: { type: 'initial-render', seed: expect.any(Number) }
      })
    );
  });

  it('uses the blank template for an empty request', async () => {
    const { POST } = await import('./+server');
    const response = await POST(request());

    expect(response.status).toBe(202);
    expect(mocks.createProjectSkeleton).toHaveBeenCalledWith(
      expect.objectContaining({
        creation: { templateId: 'blank' },
        ownerUserId: 'user-test'
      })
    );
  });

  it('rejects malformed and legacy mode requests before project creation', async () => {
    const { POST } = await import('./+server');
    const malformed = await POST(request({ mode: 'ai', exampleId: 'linear-search' }));
    const unknownTemplate = await POST(request({ templateId: 'not_known' }));

    expect(malformed.status).toBe(400);
    expect(unknownTemplate.status).toBe(400);
    expect(mocks.createProjectSkeleton).not.toHaveBeenCalled();
  });

  it('reports a syntactically valid template that is absent from the catalog', async () => {
    const { UnknownProjectTemplateError } = await import('$lib/server/projects/starter-catalog');
    mocks.createProjectSkeleton.mockRejectedValueOnce(
      new UnknownProjectTemplateError('missing-template')
    );
    const { POST } = await import('./+server');

    const response = await POST(request({ templateId: 'missing-template' }));

    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toEqual({
      error: 'Unknown project template: missing-template.'
    });
  });
});

function request(body?: unknown) {
  const url = new URL('http://localhost/api/projects');
  return {
    locals: testLocals(),
    request: new Request(url, {
      method: 'POST',
      ...(body === undefined
        ? {}
        : {
            headers: { 'content-type': 'application/json' },
            body: JSON.stringify(body)
          })
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
