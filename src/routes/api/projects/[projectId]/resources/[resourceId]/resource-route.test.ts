import { createHash } from 'node:crypto';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { NewProjectEvent } from '$lib/shared/projects/events';
import type { ProjectDocument } from '$lib/shared/projects/model';

const operationId = '12345678-1234-4123-8123-123456789abc';
let projectRoot: string;

beforeEach(async () => {
  vi.resetModules();
  projectRoot = await mkdtemp(path.join(tmpdir(), 'sverlin-resource-route-test-'));
  process.env.SVERLIN_PROJECT_DIR = projectRoot;
});

afterEach(async () => {
  delete process.env.SVERLIN_PROJECT_DIR;
  await rm(projectRoot, { recursive: true, force: true });
});

describe('project compiler resources', () => {
  it('serves only referenced immutable bytes with their exact media type', async () => {
    const { projectRepository } = await import('$lib/server/projects/repository');
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
    await projectRepository.create(rootDocument());
    await projectRepository.append('resource-test', 1, [compilationEvent(resource)], [resource]);

    const response = await GET({
      params: { projectId: 'resource-test', resourceId: resource.id }
    } as Parameters<typeof GET>[0]);

    expect(response.status).toBe(200);
    expect(response.headers.get('content-type')).toBe('font/ttf');
    expect(response.headers.get('cache-control')).toContain('immutable');
    expect(new Uint8Array(await response.arrayBuffer())).toEqual(bytes);
  });
});

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
