import { createHash } from 'node:crypto';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import type { NewProjectEvent } from '$lib/shared/projects/events';
import type { ProjectDocument } from '$lib/shared/projects/model';

const mocks = vi.hoisted(() => ({ load: vi.fn(), readResource: vi.fn() }));

vi.mock('$lib/server/authorization', () => ({ requireProjectAccess: vi.fn() }));
vi.mock('$lib/server/projects/repository', async (importOriginal) => ({
  ...(await importOriginal<typeof import('$lib/server/projects/repository')>()),
  projectRepository: { load: mocks.load, readResource: mocks.readResource }
}));

const operationId = '12345678-1234-4123-8123-123456789abc';

beforeEach(() => {
  mocks.load.mockReset();
  mocks.readResource.mockReset();
});

describe('project compiler resources', () => {
  it('serves only referenced immutable bytes with their exact media type', async () => {
    const { GET } = await import('./+server');
    const bytes = new TextEncoder().encode('font bytes');
    const sha256 = createHash('sha256').update(bytes).digest('hex');
    const resource = {
      id: `sha256-${sha256}`,
      kind: 'fontResource' as const,
      sha256,
      mediaType: 'font/ttf',
      byteLength: bytes.byteLength,
      bytes
    };
    mocks.load.mockResolvedValue({
      ...rootDocument(),
      events: [...rootDocument().events, { ...compilationEvent(resource), id: 2 }]
    });
    mocks.readResource.mockResolvedValue(bytes);

    const response = await GET({
      locals: testLocals(),
      params: { projectId: 'resource-test', resourceId: resource.id }
    } as Parameters<typeof GET>[0]);

    expect(response.status).toBe(200);
    expect(response.headers.get('content-type')).toBe('font/ttf');
    expect(response.headers.get('cache-control')).toContain('immutable');
    expect(new Uint8Array(await response.arrayBuffer())).toEqual(bytes);
  });
});

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

function rootDocument(): ProjectDocument {
  return {
    schemaVersion: 1,
    projectId: 'resource-test',
    events: [
      {
        id: 1,
        type: 'project.created',
        actor: { kind: 'user' },
        operationId,
        createdAt: '2026-01-01T00:00:00.000Z',
        payload: { title: 'Resource test', entryArtifactId: 'dsl-main' }
      }
    ]
  };
}

function compilationEvent(resource: {
  id: string;
  kind: 'fontResource';
  sha256: string;
  mediaType: string;
  byteLength: number;
}): NewProjectEvent<'compilation.succeeded'> {
  const recorded = { text: '', sha256: '0'.repeat(64), mediaType: 'text/plain' };
  return {
    type: 'compilation.succeeded',
    actor: { kind: 'system' },
    operationId,
    createdAt: '2026-01-01T00:00:01.000Z',
    payload: {
      durationMs: 1,
      stdout: recorded,
      stderr: recorded,
      render: { ...recorded, mediaType: 'application/json' },
      resources: [resource]
    }
  };
}
