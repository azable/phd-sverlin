import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { ProjectEvent, ProjectEventOf } from '$lib/shared/projects/events';
import type { ProjectDocument, ProjectResource } from '$lib/shared/projects/model';

import { ProjectSession } from './project-session.svelte';

const navigation = vi.hoisted(() => ({ goto: vi.fn() }));

vi.mock('$app/navigation', () => navigation);

const operationId = '12345678-1234-4123-8123-123456789abc';
const externalOperationId = '22345678-1234-4234-8234-123456789abc';
const sessions: ProjectSession[] = [];
let fetchMock: ReturnType<typeof vi.fn>;

class FakeEventSource {
  static instances: FakeEventSource[] = [];

  readonly close = vi.fn();
  readonly url: string;
  readonly #listeners = new Map<string, Set<(event: Event) => void>>();

  constructor(url: string | URL) {
    this.url = String(url);
    FakeEventSource.instances.push(this);
  }

  addEventListener(type: string, listener: EventListener): void {
    const listeners = this.#listeners.get(type) ?? new Set();
    listeners.add(listener);
    this.#listeners.set(type, listeners);
  }

  emit(type: string, event?: ProjectEvent): void {
    const message = event
      ? ({ data: JSON.stringify(event) } as MessageEvent<string>)
      : (new Event(type) as MessageEvent<string>);
    for (const listener of this.#listeners.get(type) ?? []) listener(message);
  }
}

beforeEach(() => {
  fetchMock = vi.fn();
  vi.stubGlobal('fetch', fetchMock);
  vi.stubGlobal('EventSource', FakeEventSource);
  FakeEventSource.instances = [];
  navigation.goto.mockReset();
});

afterEach(() => {
  for (const session of sessions.splice(0)) session.dispose();
  vi.unstubAllGlobals();
});

describe('ProjectSession', () => {
  it('installs a command resource without navigating, reloading, or reconnecting', async () => {
    const initial = projectResource([createdEvent()], 'Initial');
    const renamed = renamedEvent(2, operationId, 'Initial', 'Renamed');
    const resulting = projectResource([...initial.document.events, renamed], 'Renamed');
    fetchMock
      .mockResolvedValueOnce(maintenanceResponse(false))
      .mockResolvedValueOnce(response(initial))
      .mockResolvedValueOnce(response(resulting));

    const session = createSession();
    await session.open();
    const source = FakeEventSource.instances[0];

    await expect(session.runCommand({ type: 'rename', title: 'Renamed' })).resolves.toBe(true);

    expect(session.snapshot.title).toBe('Renamed');
    expect(session.head).toBe(2);
    expect(session.atHead).toBe(true);
    expect(fetchMock).toHaveBeenCalledTimes(3);
    expect(FakeEventSource.instances).toEqual([source]);
    expect(navigation.goto).not.toHaveBeenCalled();
  });

  it('follows streamed events at the head while keeping local history pinned', async () => {
    const initial = projectResource([createdEvent()], 'Initial');
    const responseEvent = assistantEvent(2);
    fetchMock
      .mockResolvedValueOnce(maintenanceResponse(false))
      .mockResolvedValueOnce(response(initial));

    const session = createSession();
    await session.open();
    const previousResource = session.resource;
    FakeEventSource.instances[0].emit('project-event', responseEvent);

    expect(session.resource).not.toBe(previousResource);
    expect(session.events).toHaveLength(2);
    expect(session.snapshot.at).toBe(2);
    expect(session.atHead).toBe(true);

    session.select(1);
    expect(session.atHead).toBe(false);
    FakeEventSource.instances[0].emit(
      'project-event',
      renamedEvent(3, externalOperationId, 'Initial', 'External')
    );

    expect(session.events).toHaveLength(3);
    expect(session.snapshot.at).toBe(1);
    expect(session.snapshot.title).toBe('Initial');
    expect(session.atHead).toBe(false);
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(FakeEventSource.instances).toHaveLength(1);
  });

  it('projects external state-changing events without hydration fetches', async () => {
    const initial = projectResource([createdEvent()], 'Initial');
    const renamed = renamedEvent(2, externalOperationId, 'Initial', 'External');
    fetchMock
      .mockResolvedValueOnce(maintenanceResponse(false))
      .mockResolvedValueOnce(response(initial));

    const session = createSession();
    await session.open();
    FakeEventSource.instances[0].emit('project-event', renamed);

    expect(session.snapshot.title).toBe('External');
    expect(session.atHead).toBe(true);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('creates a project from an explicit template and preserves Dev detail', async () => {
    fetchMock.mockResolvedValueOnce(
      new Response(JSON.stringify({ projectId: 'dev-project' }), {
        status: 201,
        headers: { 'content-type': 'application/json' }
      })
    );
    const session = createSession();

    await session.createProject({ templateId: 'linear-search' }, true);

    const request = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(request[0]).toBe('/api/projects');
    expect(JSON.parse(String(request[1].body))).toEqual({
      templateId: 'linear-search'
    });
    expect(navigation.goto).toHaveBeenCalledWith('/projects/dev-project?dev=1');
    expect(session.creating).toBe(false);
  });

  it('releases project creation state after a server failure', async () => {
    fetchMock.mockResolvedValueOnce(
      new Response(JSON.stringify({ error: 'Compiler unavailable.' }), {
        status: 503,
        headers: { 'content-type': 'application/json' }
      })
    );
    const session = createSession();

    await expect(session.createProject({ templateId: 'blank' })).resolves.toBe(false);

    expect(session.creating).toBe(false);
    expect(session.error).toBe('Compiler unavailable.');
    expect(navigation.goto).not.toHaveBeenCalled();
  });

  it('blocks project creation and commands locally while maintenance is locked', async () => {
    const initial = projectResource([createdEvent()], 'Initial');
    fetchMock
      .mockResolvedValueOnce(maintenanceResponse(true))
      .mockResolvedValueOnce(response(initial));
    const session = createSession();
    await session.open();

    expect(session.maintenanceLocked).toBe(true);
    await expect(session.createProject({ templateId: 'blank' })).resolves.toBe(false);
    await expect(session.runCommand({ type: 'rename', title: 'Blocked' })).resolves.toBe(false);
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(session.snapshot.title).toBe('Initial');
  });
});

function createSession(): ProjectSession {
  const session = new ProjectSession('project-test');
  sessions.push(session);
  return session;
}

function response(resource: ProjectResource): Response {
  return new Response(JSON.stringify(resource), {
    headers: { 'content-type': 'application/json' }
  });
}

function maintenanceResponse(locked: boolean): Response {
  return new Response(
    JSON.stringify(
      locked
        ? { locked: true, lockedAt: '2026-01-01T00:00:00.000Z', reason: 'Test maintenance' }
        : { locked: false }
    ),
    { headers: { 'content-type': 'application/json' } }
  );
}

function projectResource(events: ProjectEvent[], title: string): ProjectResource {
  const document: ProjectDocument = {
    schemaVersion: 1,
    projectId: 'project-test',
    events
  };
  return {
    document,
    projects: [
      {
        projectId: document.projectId,
        title,
        updatedAt: events.at(-1)!.createdAt,
        eventCount: events.length,
        templateId: 'blank'
      }
    ]
  };
}

function createdEvent(): ProjectEventOf<'project.created'> {
  return {
    id: 1,
    type: 'project.created',
    actor: { kind: 'user' },
    operationId,
    createdAt: '2026-01-01T00:00:01.000Z',
    payload: { title: 'Initial', entryArtifactId: 'dsl-main' }
  };
}

function renamedEvent(
  id: number,
  eventOperationId: string,
  previousTitle: string,
  title: string
): ProjectEventOf<'project.renamed'> {
  return {
    id,
    type: 'project.renamed',
    actor: { kind: 'user' },
    operationId: eventOperationId,
    createdAt: `2026-01-01T00:00:0${id}.000Z`,
    payload: { previousTitle, title }
  };
}

function assistantEvent(id: number): ProjectEventOf<'assistant.responded'> {
  return {
    id,
    type: 'assistant.responded',
    actor: { kind: 'assistant', botId: 'ai-assistant' },
    operationId,
    createdAt: `2026-01-01T00:00:0${id}.000Z`,
    payload: { text: 'Done' }
  };
}
