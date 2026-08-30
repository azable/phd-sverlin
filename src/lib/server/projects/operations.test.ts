import { randomUUID } from 'node:crypto';

import { describe, expect, it } from 'vitest';

import type { ProjectDocument } from '$lib/shared/projects/model';
import { projectOperation } from '$lib/shared/projects/operations';

import { MemoryProjectRepository } from './memory-repository.test-support';
import { ProjectOperationExecutor } from './operations';

describe('ProjectOperationExecutor', () => {
  it('records accepted and completed boundaries around an injected command', async () => {
    const repository = new MemoryProjectRepository();
    const projectId = randomUUID();
    const operationId = randomUUID();
    await repository.create(rootDocument(projectId, randomUUID()), 'owner');
    const executor = new ProjectOperationExecutor(
      repository,
      { acquire: async () => ({ release: async () => undefined }) },
      async ({ projectId: id, expectedHead, operationId: correlation }) => {
        const appended = await repository.append(id, expectedHead, [
          {
            type: 'project.renamed',
            actor: { kind: 'user' },
            operationId: correlation,
            createdAt: new Date().toISOString(),
            payload: { previousTitle: 'Initial', title: 'Renamed' }
          }
        ]);
        return { document: appended.document, appendedEvents: appended.events };
      }
    );

    const accepted = await executor.accept({
      projectId,
      operationId,
      expectedHead: 1,
      command: { type: 'initial-render', seed: 1 }
    });
    expect(accepted.acceptedEventId).toBe(2);
    await terminal(repository, projectId, operationId);

    const operation = projectOperation(await repository.load(projectId), operationId);
    expect(operation).toMatchObject({ kind: 'initial-render', status: 'completed' });
  });

  it('converts command-domain failures into a terminal operation failure', async () => {
    const repository = new MemoryProjectRepository();
    const projectId = randomUUID();
    const operationId = randomUUID();
    await repository.create(rootDocument(projectId, randomUUID()), 'owner');
    const executor = new ProjectOperationExecutor(
      repository,
      { acquire: async () => ({ release: async () => undefined }) },
      async ({ projectId: id, expectedHead, operationId: correlation }) => {
        const appended = await repository.append(id, expectedHead, [
          {
            type: 'system.notified',
            actor: { kind: 'system' },
            operationId: correlation,
            createdAt: new Date().toISOString(),
            payload: { severity: 'error', message: 'Candidate rejected.' }
          }
        ]);
        return { document: appended.document, appendedEvents: appended.events };
      }
    );

    await executor.accept({
      projectId,
      operationId,
      expectedHead: 1,
      command: {
        type: 'feedback',
        operationId,
        expectedHead: 1,
        text: 'Change it.',
        focus: [],
        presentationCount: 1
      }
    });
    await terminal(repository, projectId, operationId);

    expect(
      projectOperation(await repository.load(projectId), operationId)?.terminalEvent
    ).toMatchObject({
      type: 'operation.failed',
      payload: { failureKind: 'domain', message: 'Candidate rejected.' }
    });
  });

  it('cancels and safely rebases over a background refill before accepting participant work', async () => {
    const repository = new MemoryProjectRepository();
    const projectId = randomUUID();
    const refillId = randomUUID();
    const participantId = randomUUID();
    await repository.create(rootDocument(projectId, randomUUID()), 'owner');
    const executor = new ProjectOperationExecutor(
      repository,
      { acquire: async () => ({ release: async () => undefined }) },
      async ({ projectId: id, expectedHead, operationId, command, signal }) => {
        if (command.type === 'presentation-refill') {
          await new Promise<void>((_resolve, reject) => {
            signal.addEventListener('abort', () => reject(signal.reason), { once: true });
          });
        }
        const appended = await repository.append(id, expectedHead, [
          {
            type: 'project.renamed',
            actor: { kind: 'user' },
            operationId,
            createdAt: new Date().toISOString(),
            payload: { previousTitle: 'Initial', title: 'Participant change' }
          }
        ]);
        return { document: appended.document, appendedEvents: appended.events };
      }
    );

    const refill = await executor.accept({
      projectId,
      operationId: refillId,
      expectedHead: 1,
      command: { type: 'presentation-refill', target: 4 },
      actor: 'system'
    });
    expect(refill.acceptedEventId).toBe(2);
    const participant = await executor.accept({
      projectId,
      operationId: participantId,
      expectedHead: 2,
      command: { type: 'initial-render', seed: 1 }
    });
    await terminal(repository, projectId, participantId);

    const document = await repository.load(projectId);
    expect(projectOperation(document, refillId)?.terminalEvent).toMatchObject({
      type: 'operation.failed',
      payload: { failureKind: 'cancelled' }
    });
    expect(document.events[1].actor).toEqual({ kind: 'system' });
    expect(participant.acceptedEventId).toBe(4);
    expect(projectOperation(document, participantId)?.status).toBe('completed');
  });

  it('gives capacity held by another project refill to participant work', async () => {
    const repository = new MemoryProjectRepository();
    const refillProjectId = randomUUID();
    const participantProjectId = randomUUID();
    const refillId = randomUUID();
    const participantId = randomUUID();
    await repository.create(rootDocument(refillProjectId, randomUUID()), 'owner');
    await repository.create(rootDocument(participantProjectId, randomUUID()), 'owner');
    const executor = new ProjectOperationExecutor(
      repository,
      { acquire: async () => ({ release: async () => undefined }) },
      async ({ projectId, expectedHead, operationId, command, signal }) => {
        if (command.type === 'presentation-refill') {
          await new Promise<void>((_resolve, reject) => {
            signal.addEventListener('abort', () => reject(signal.reason), { once: true });
          });
        }
        const appended = await repository.append(projectId, expectedHead, [
          {
            type: 'project.renamed',
            actor: { kind: 'user' },
            operationId,
            createdAt: new Date().toISOString(),
            payload: { previousTitle: 'Initial', title: 'Participant change' }
          }
        ]);
        return { document: appended.document, appendedEvents: appended.events };
      },
      1
    );

    await executor.accept({
      projectId: refillProjectId,
      operationId: refillId,
      expectedHead: 1,
      command: { type: 'presentation-refill', target: 4 }
    });
    await executor.accept({
      projectId: participantProjectId,
      operationId: participantId,
      expectedHead: 1,
      command: { type: 'initial-render', seed: 1 }
    });
    await terminal(repository, participantProjectId, participantId);

    expect(projectOperation(await repository.load(refillProjectId), refillId)).toMatchObject({
      status: 'failed',
      terminalEvent: {
        payload: { failureKind: 'cancelled', message: 'Superseded by participant activity.' }
      }
    });
    expect(
      projectOperation(await repository.load(participantProjectId), participantId)?.status
    ).toBe('completed');
  });
});

function rootDocument(projectId: string, operationId: string): ProjectDocument {
  return {
    schemaVersion: 1,
    projectId,
    events: [
      {
        id: 1,
        type: 'project.created',
        actor: { kind: 'user' },
        operationId,
        createdAt: '2026-08-30T00:00:00.000Z',
        payload: { title: 'Initial', entryArtifactId: 'dsl-main' }
      }
    ]
  };
}

async function terminal(
  repository: MemoryProjectRepository,
  projectId: string,
  operationId: string
): Promise<void> {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    const operation = projectOperation(await repository.load(projectId), operationId);
    if (operation?.status === 'completed' || operation?.status === 'failed') return;
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
  throw new Error('Operation did not become terminal.');
}
