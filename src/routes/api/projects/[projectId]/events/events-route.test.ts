import { beforeEach, describe, expect, it, vi } from 'vitest';

import type { NewProjectEvent } from '$lib/shared/projects/events';
import type { ProjectDocument } from '$lib/shared/projects/model';

const mocks = vi.hoisted(() => ({ eventsAfter: vi.fn() }));

vi.mock('$lib/server/authorization', () => ({
  requireAdmin: vi.fn(),
  requireProjectAccess: vi.fn()
}));
vi.mock('$lib/server/projects/repository', async (importOriginal) => ({
  ...(await importOriginal<typeof import('$lib/server/projects/repository')>()),
  projectRepository: { eventsAfter: mocks.eventsAfter }
}));

const operationId = '12345678-1234-4123-8123-123456789abc';

beforeEach(() => {
  mocks.eventsAfter.mockReset();
});

describe('project event delta', () => {
  it('resumes from a durable event position without duplicates', async () => {
    const { GET } = await import('./+server');
    mocks.eventsAfter.mockResolvedValueOnce([
      rootDocument().events[0],
      { ...renameEvent('A'), id: 2 }
    ]);

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

    mocks.eventsAfter.mockResolvedValueOnce([{ ...renameEvent('B'), id: 3 }]);
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
