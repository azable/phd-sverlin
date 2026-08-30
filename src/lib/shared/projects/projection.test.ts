import { describe, expect, it } from 'vitest';

import {
  InvalidProjectDocumentError,
  normalizeProjectEventV2,
  type ProjectEvent,
  type ProjectEventOf
} from './events';
import { normalizeProjectV2, parseProjectCommand, type ProjectDocument } from './model';
import { projectSnapshotAt, summarizeProject } from './projection';

const operationId = '12345678-1234-4123-8123-123456789abc';
const displaySetId = '22345678-1234-4234-8234-123456789abc';
const presentationId = '32345678-1234-4234-8234-123456789abc';
const hash = '0'.repeat(64);
const recorded = { text: '{}', sha256: hash, mediaType: 'application/json' };

describe('project model and projection', () => {
  it('accepts only version-two documents with stable 1-based event IDs', () => {
    const document = documentWithHistory();
    expect(normalizeProjectV2(document)).toEqual(document);
    expect(() => normalizeProjectV2({ ...document, schemaVersion: 1 })).toThrow(
      InvalidProjectDocumentError
    );
    expect(() =>
      normalizeProjectV2({
        ...document,
        events: document.events.map((event, index) => (index === 2 ? { ...event, id: 4 } : event))
      })
    ).toThrow(InvalidProjectDocumentError);
  });

  it('validates structured message references and compact visual selections', () => {
    expect(() =>
      normalizeProjectEventV2({ ...documentWithHistory().events[0], operationId: 'not-a-uuid' })
    ).toThrow(InvalidProjectDocumentError);

    expect(
      parseProjectCommand({
        type: 'feedback',
        operationId,
        expectedHead: 5,
        content: [
          { type: 'markdown', text: 'Prefer this element' },
          {
            type: 'element-ref',
            presentationId,
            presentationEvent: 5,
            step: 0,
            instances: [0]
          }
        ],
        focus: [2],
        presentationCount: 1
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
        source: recorded,
        sourceLabel: 'Main.sverlin',
        seed: 1,
        dslRevision: {
          contentSha256: hash,
          repositoryCommit: 'a'.repeat(40),
          workingTree: 'clean'
        }
      }
    };
    expect(normalizeProjectEventV2(request)).toEqual(request);
    expect(() =>
      normalizeProjectEventV2({
        ...request,
        payload: {
          ...request.payload,
          dslRevision: { ...request.payload.dslRevision, repositoryCommit: 'not-a-commit' }
        }
      })
    ).toThrow(InvalidProjectDocumentError);
  });

  it('replays historical source and clears stale presentations after an artifact edit', () => {
    const document = documentWithHistory();
    expect(projectSnapshotAt(document, 3).activePresentationSet?.presentations[0].id).toBe(3);
    expect(projectSnapshotAt(document, 4).activePresentationSet).toBeUndefined();
    expect(projectSnapshotAt(document, 2).artifacts['dsl-main']?.content.sha256).toBe(hash);
    expect(projectSnapshotAt(document).activePresentationSet?.presentations[0]).toMatchObject({
      id: 5,
      payload: { presentation: { source: { sha256: '1'.repeat(64) } } }
    });
    expect(summarizeProject(document).templateId).toBe('blank');
  });

  it('ignores message-only events when reconstructing state', () => {
    const document = documentWithHistory();
    const withResponse: ProjectDocument = {
      ...document,
      events: [
        ...document.events,
        event(6, 'assistant.responded', {
          content: [{ type: 'markdown', text: 'Done' }]
        })
      ]
    };
    expect(projectSnapshotAt(withResponse)).toEqual({ ...projectSnapshotAt(document), at: 6 });
  });
});

function documentWithHistory(): ProjectDocument {
  const edited = { ...recorded, text: 'edited', sha256: '1'.repeat(64) };
  return {
    schemaVersion: 2,
    projectId: 'project-test',
    events: [
      event(1, 'project.created', {
        title: 'Test',
        entryArtifactId: 'dsl-main',
        creation: { templateId: 'blank' }
      }),
      event(2, 'artifact.version-created', {
        origin: { kind: 'initial' },
        changes: [
          {
            operation: 'upsert',
            artifact: {
              artifactId: 'dsl-main',
              path: 'Main.sverlin',
              language: 'sverlin',
              content: { ...recorded, text: 'initial', mediaType: 'text/x-sverlin' }
            }
          }
        ]
      }),
      presented(3, recorded, '42345678-1234-4234-8234-123456789abc'),
      event(4, 'artifact.version-created', {
        origin: { kind: 'manual-edit' },
        changes: [
          {
            operation: 'upsert',
            artifact: {
              artifactId: 'dsl-main',
              path: 'Main.sverlin',
              language: 'sverlin',
              content: { ...edited, mediaType: 'text/x-sverlin' }
            }
          }
        ]
      }),
      presented(5, edited, presentationId)
    ]
  };
}

function presented(
  id: number,
  source: typeof recorded,
  idValue: string
): ProjectEventOf<'visualization.presented'> {
  return event(id, 'visualization.presented', {
    displaySetId,
    slot: 0,
    presentation: {
      presentationId: idValue,
      format: 'sverlin-ir-v1',
      stepSignature: 'one-step',
      seed: id,
      source,
      render: recorded
    }
  });
}

function event<Type extends ProjectEvent['type']>(
  id: number,
  type: Type,
  payload: ProjectEventOf<Type>['payload']
): ProjectEventOf<Type> {
  return {
    id,
    type,
    operationId,
    actor: { kind: 'system' },
    createdAt: `2026-01-01T00:00:${String(id).padStart(2, '0')}.000Z`,
    payload
  } as ProjectEventOf<Type>;
}
