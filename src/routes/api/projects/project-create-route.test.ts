import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({ createProject: vi.fn() }));

vi.mock('$lib/server/projects/service', () => ({ createProject: mocks.createProject }));

beforeEach(() => {
  mocks.createProject.mockReset().mockResolvedValue({ projectId: 'project-created' });
});

describe('project creation API', () => {
  it('creates the requested project template', async () => {
    const { POST } = await import('./+server');
    const response = await POST(request({ templateId: 'linear-search' }));

    expect(response.status).toBe(201);
    await expect(response.json()).resolves.toEqual({ projectId: 'project-created' });
    expect(mocks.createProject).toHaveBeenCalledWith({
      creation: { templateId: 'linear-search' }
    });
  });

  it('uses the blank template for an empty request', async () => {
    const { POST } = await import('./+server');
    const response = await POST(request());

    expect(response.status).toBe(201);
    expect(mocks.createProject).toHaveBeenCalledWith({ creation: { templateId: 'blank' } });
  });

  it('rejects malformed and legacy mode requests before project creation', async () => {
    const { POST } = await import('./+server');
    const malformed = await POST(request({ mode: 'ai', exampleId: 'linear-search' }));
    const unknownTemplate = await POST(request({ templateId: 'not_known' }));

    expect(malformed.status).toBe(400);
    expect(unknownTemplate.status).toBe(400);
    expect(mocks.createProject).not.toHaveBeenCalled();
  });

  it('reports a syntactically valid template that is absent from the catalog', async () => {
    const { UnknownProjectTemplateError } = await import('$lib/server/projects/starter-catalog');
    mocks.createProject.mockRejectedValueOnce(new UnknownProjectTemplateError('missing-template'));
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
