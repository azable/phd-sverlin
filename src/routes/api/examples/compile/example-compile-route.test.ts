import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  requireAdmin: vi.fn(),
  generate: vi.fn(),
  getProjectTemplate: vi.fn()
}));

vi.mock('$lib/server/authorization', () => ({ requireAdmin: mocks.requireAdmin }));
vi.mock('$lib/server/compiler', () => ({ visualizationService: { generate: mocks.generate } }));
vi.mock('$lib/server/projects/starter-catalog', () => ({
  getProjectTemplate: mocks.getProjectTemplate,
  UnknownProjectTemplateError: class UnknownProjectTemplateError extends Error {}
}));

beforeEach(() => {
  mocks.requireAdmin.mockReset();
  mocks.generate.mockReset();
  mocks.getProjectTemplate.mockReset().mockReturnValue({
    id: 'linear-search',
    file: 'LinearSearch.sverlin',
    source: 'render = do\n  width (by 800)'
  });
});

function event(body: unknown) {
  return {
    locals: {},
    request: new Request('http://localhost/api/examples/compile', {
      method: 'POST',
      body: JSON.stringify(body)
    })
  };
}

describe('direct example compilation', () => {
  it('compiles the catalogued source and sends only fonts used by the visualization', async () => {
    mocks.generate.mockResolvedValueOnce({
      ok: true,
      visualization: {
        elements: [
          {
            content: {
              kind: 'plainTextContent',
              textLayout: { layoutFont: { instanceResourceId: 'font-1' } }
            }
          }
        ]
      },
      resources: [
        {
          id: 'font-1',
          kind: 'fontResource',
          mediaType: 'font/ttf',
          bytes: new Uint8Array([1, 2])
        },
        {
          id: 'text-1',
          kind: 'textRunResource',
          mediaType: 'application/octet-stream',
          bytes: new Uint8Array([3])
        }
      ]
    });
    const { POST } = await import('./+server');

    const response = await POST(event({ exampleId: 'linear-search', seed: 7 }) as never);
    expect(response.status).toBe(200);
    expect(response.headers.get('cache-control')).toBe('private, no-store');
    expect(mocks.generate).toHaveBeenCalledWith(
      expect.objectContaining({
        source: { name: 'LinearSearch.sverlin', content: 'render = do\n  width (by 800)' },
        seed: 7
      })
    );
    expect(await response.json()).toMatchObject({
      exampleId: 'linear-search',
      seed: 7,
      fonts: [{ id: 'font-1', mediaType: 'font/ttf', base64: 'AQI=' }]
    });
  });

  it('rejects arbitrary source names and returns compiler diagnostics', async () => {
    const { POST } = await import('./+server');
    const unknown = await POST(event({ exampleId: 'blank' }) as never);
    expect(unknown.status).toBe(400);
    expect(mocks.generate).not.toHaveBeenCalled();

    mocks.generate.mockResolvedValueOnce({
      ok: false,
      error: 'Compile failed',
      failureKind: 'source',
      diagnostics: [{ message: 'Line 3: unknown symbol' }]
    });
    const failed = await POST(event({ exampleId: 'linear-search', seed: 7 }) as never);
    expect(failed.status).toBe(422);
    expect(await failed.json()).toMatchObject({ error: 'Line 3: unknown symbol' });
  });

  it('does not deliver an incomplete font bundle', async () => {
    mocks.generate.mockResolvedValueOnce({
      ok: true,
      visualization: {
        elements: [
          {
            content: {
              kind: 'plainTextContent',
              textLayout: { layoutFont: { instanceResourceId: 'missing-font' } }
            }
          }
        ]
      },
      resources: []
    });
    const { POST } = await import('./+server');
    await expect(
      POST(event({ exampleId: 'linear-search', seed: 7 }) as never)
    ).rejects.toMatchObject({
      status: 502
    });
  });
});
