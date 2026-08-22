import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { NewProjectEvent, ProjectDocument } from '$lib/projects/types';

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

describe('project event stream', () => {
  it('resumes from zero and delivers each durable append once', async () => {
    const { projectRepository } = await import('$lib/server/projects/repository');
    const { GET } = await import('./+server');
    await projectRepository.create(rootDocument());
    await projectRepository.append('stream-test', 1, [renameEvent('A')]);

    const abort = new AbortController();
    const url = new URL('http://localhost/api/projects/stream-test/events?after=0');
    const request = new Request(url, { signal: abort.signal });
    const response = await GET({
      params: { projectId: 'stream-test' },
      request,
      url
    } as Parameters<typeof GET>[0]);
    const reader = response.body!.getReader();

    const catchup = await readThrough(reader, 'event: ready');
    expect(catchup).toContain('id: 1');
    expect(catchup).toContain('id: 2');
    expect(catchup).toContain('"title":"A"');

    await projectRepository.append('stream-test', 2, [renameEvent('B')]);
    const live = await readThrough(reader, 'id: 3');
    expect(live).toContain('"title":"B"');

    abort.abort();
    await reader.cancel();
  });
});

async function readThrough(reader: ReadableStreamDefaultReader<Uint8Array>, expected: string) {
  const decoder = new TextDecoder();
  let text = '';
  while (!text.includes(expected)) {
    const chunk = await reader.read();
    if (chunk.done) break;
    text += decoder.decode(chunk.value, { stream: true });
  }
  return text;
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
