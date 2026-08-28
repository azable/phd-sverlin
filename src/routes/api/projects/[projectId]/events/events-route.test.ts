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
  projectRoot = await mkdtemp(path.join(tmpdir(), 'sverlin-event-route-test-'));
  process.env.SVERLIN_PROJECT_DIR = projectRoot;
});

afterEach(async () => {
  delete process.env.SVERLIN_PROJECT_DIR;
  await rm(projectRoot, { recursive: true, force: true });
});

describe('project event delta', () => {
  it('resumes from a durable event position without duplicates', async () => {
    const { projectRepository } = await import('$lib/server/projects/repository');
    const { GET } = await import('./+server');
    await projectRepository.create(rootDocument());
    await projectRepository.append('stream-test', 1, [renameEvent('A')]);

    const url = new URL('http://localhost/api/projects/stream-test/events?after=0');
    const response = await GET({
      locals: testLocals(),
      params: { projectId: 'stream-test' },
      url
    } as Parameters<typeof GET>[0]);
    await expect(response.json()).resolves.toMatchObject({
      after: 0,
      head: 2,
      events: [{ id: 1 }, { id: 2, payload: { title: 'A' } }]
    });

    await projectRepository.append('stream-test', 2, [renameEvent('B')]);
    const nextUrl = new URL('http://localhost/api/projects/stream-test/events?after=2');
    const next = await GET({
      locals: testLocals(),
      params: { projectId: 'stream-test' },
      url: nextUrl
    } as Parameters<typeof GET>[0]);
    await expect(next.json()).resolves.toMatchObject({
      after: 2,
      head: 3,
      events: [{ id: 3, payload: { title: 'B' } }]
    });
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
    projectId: 'stream-test',
    events: [
      {
        id: 1,
        type: 'project.created',
        actor: { kind: 'user' },
        operationId,
        createdAt: '2026-01-01T00:00:00.000Z',
        payload: { title: 'Stream test', entryArtifactId: 'dsl-main' }
      }
    ]
  };
}

function renameEvent(title: string): NewProjectEvent<'project.renamed'> {
  return {
    type: 'project.renamed',
    actor: { kind: 'user' },
    operationId,
    createdAt: '2026-01-01T00:00:01.000Z',
    payload: { previousTitle: 'Stream test', title }
  };
}
