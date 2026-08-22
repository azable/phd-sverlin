import { describe, expect, it } from 'vitest';

import {
  InvalidProjectDocumentError,
  normalizeProjectEventV1,
  type ProjectEvent,
  type ProjectEventOf
} from './events';
import { normalizeProjectV1, parseProjectCommand, type ProjectDocument } from './model';
import { projectEventChangesState, projectSnapshotAt } from './projection';

const operationId = '12345678-1234-4123-8123-123456789abc';
const hash = '0'.repeat(64);
const blob = { sha256: hash, byteLength: 0, mediaType: 'application/json' };

describe('project model and projection', () => {
  it('uses each event 1-based array position as its stable ID', () => {
    const document = documentWithHistory();
    expect(normalizeProjectV1(document)).toEqual(document);

    expect(() =>
      normalizeProjectV1({
        ...document,
        events: document.events.map((event, index) => (index === 2 ? { ...event, id: 4 } : event))
      })
    ).toThrow(InvalidProjectDocumentError);
    expect(() => normalizeProjectV1({ ...document, events: document.events.slice(1) })).toThrow(
      InvalidProjectDocumentError
    );
  });

  it('validates operation UUIDs, command focus, and compact visual references', () => {
    expect(() =>
      normalizeProjectEventV1({ ...documentWithHistory().events[0], operationId: 'not-a-uuid' })
    ).toThrow(InvalidProjectDocumentError);

    expect(
      parseProjectCommand({
        type: 'feedback',
        operationId,
        expectedHead: 4,
        text: 'Prefer these',
        focus: [2],
        selection: { render: 3, step: 0, instances: [1], judgement: 'preferred' },
        seed: 9
      })
    ).toMatchObject({ type: 'feedback', focus: [2] });
  });

  it('validates DSL content and repository revision metadata', () => {
    const request = {
      id: 2,
      operationId,
      actor: { kind: 'system' },
      createdAt: '2026-01-01T00:00:02.000Z',
      type: 'compilation.requested',
      payload: {
        purpose: 'manual-edit',
        input: 'committed-artifact',
        source: blob,
        sourceLabel: 'Main.sverlin',
        seed: 1,
        dslRevision: {
          contentSha256: hash,
          repositoryCommit: 'a'.repeat(40),
          workingTree: 'clean'
        }
      }
    };

    expect(normalizeProjectEventV1(request)).toEqual(request);
    expect(() =>
      normalizeProjectEventV1({
        ...request,
        payload: {
          ...request.payload,
          dslRevision: { ...request.payload.dslRevision, repositoryCommit: 'not-a-commit' }
        }
      })
    ).toThrow(InvalidProjectDocumentError);
  });

  it('replays historical source and clears stale renders after an artifact edit', () => {
    const document = documentWithHistory();

    expect(projectSnapshotAt(document, 3).activeRender?.id).toBe(3);
    expect(projectSnapshotAt(document, 4).activeRender).toBeUndefined();
    expect(projectSnapshotAt(document, 2).artifacts['dsl-main']?.content.sha256).toBe(hash);
    expect(projectSnapshotAt(document).activeRender).toMatchObject({
      id: 5,
      payload: { source: { sha256: '1'.repeat(64) } }
    });
  });

  it('classifies state-changing events from the state transition registry', () => {
    const events = documentWithHistory().events;
    expect(events.map(projectEventChangesState)).toEqual([true, true, true, true, true]);
    expect(
      projectEventChangesState(
        event(6, 'assistant.responded', {
          text: 'Done'
        })
      )
    ).toBe(false);
  });
});

function documentWithHistory(): ProjectDocument {
  return {
    schemaVersion: 1,
    projectId: 'project-test',
    events: [
      event(1, 'project.created', { title: 'Test', entryArtifactId: 'dsl-main' }),
      event(2, 'artifact.version-created', {
        origin: { kind: 'initial' },
        changes: [
          {
            operation: 'upsert',
            artifact: {
              artifactId: 'dsl-main',
              path: 'Main.sverlin',
              language: 'sverlin',
              content: { ...blob, mediaType: 'text/x-sverlin' }
            }
          }
        ]
      }),
      event(3, 'visualization.rendered', { seed: 1, source: blob, render: blob }),
      event(4, 'artifact.version-created', {
        origin: { kind: 'manual-edit' },
        changes: [
          {
            operation: 'upsert',
            artifact: {
              artifactId: 'dsl-main',
              path: 'Main.sverlin',
              language: 'sverlin',
              content: { ...blob, sha256: '1'.repeat(64), mediaType: 'text/x-sverlin' }
            }
          }
        ]
      }),
      event(5, 'visualization.rendered', {
        seed: 2,
        source: { ...blob, sha256: '1'.repeat(64) },
        render: { ...blob, sha256: '2'.repeat(64) }
      })
    ]
  } as ProjectDocument;
}

function event<Type extends ProjectEvent['type']>(
  id: number,
  type: Type,
  payload: ProjectEventOf<Type>['payload']
) {
  return {
    id,
    type,
    actor: { kind: 'system' as const },
    operationId,
    createdAt: `2026-01-01T00:00:0${id}.000Z`,
    payload
  } as ProjectEventOf<Type>;
}
