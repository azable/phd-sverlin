import { describe, expect, it } from 'vitest';

import { projectAt } from './project';
import { InvalidProjectDocumentError, normalizeProjectEventV1, normalizeProjectV1 } from './schema';
import type { BlobRef, ProjectDocument, ProjectEvent } from './types';

const hash = '0'.repeat(64);
const blob: BlobRef = {
  sha256: hash,
  byteLength: 0,
  mediaType: 'text/plain',
  encoding: 'utf-8'
};

describe('normalizeProjectV1', () => {
  it('accepts additive v1 fields while preserving the known event contract', () => {
    const document = {
      ...rootDocument(),
      experimentalProjectField: true,
      events: [
        {
          ...rootDocument().events[0],
          experimentalEventField: 'kept',
          payload: {
            ...rootDocument().events[0].payload,
            experimentalPayloadField: 42
          }
        }
      ]
    };

    const normalized = normalizeProjectV1(document) as ProjectDocument & {
      experimentalProjectField: boolean;
    };
    expect(normalized.experimentalProjectField).toBe(true);
    expect(normalized.events[0]).toMatchObject({ experimentalEventField: 'kept' });
    expect(normalized.events[0].payload).toMatchObject({ experimentalPayloadField: 42 });
  });

  it('rejects malformed nested payloads and non-linear chains', () => {
    const malformed = rootDocument();
    malformed.events.push({
      eventId: 'feedback',
      sequence: 3,
      parentEventId: 'not-the-head',
      type: 'feedback.submitted',
      actor: { kind: 'user' },
      correlationId: 'correlation',
      createdAt: '2026-01-01T00:00:01.000Z',
      payload: {
        attachments: [{ kind: 'timeline-reference', eventIds: [], relationship: 'maybe' }]
      }
    } as unknown as ProjectEvent);

    expect(() => normalizeProjectV1(malformed)).toThrow(InvalidProjectDocumentError);
  });
});

describe('normalizeProjectEventV1', () => {
  it('validates a standalone streamed event payload', () => {
    const event = rootDocument().events[0];
    expect(normalizeProjectEventV1(event)).toEqual(event);
    expect(() =>
      normalizeProjectEventV1({ ...event, payload: { title: '', entryArtifactId: '' } })
    ).toThrow(InvalidProjectDocumentError);
  });
});

describe('projectAt', () => {
  it('reconstructs historical artifacts and never pairs a changed artifact with a stale render', () => {
    const root = rootDocument().events[0];
    const artifact = event('artifact', 1, root.eventId, 'artifact.version-created', {
      origin: { kind: 'initial' },
      changes: [
        {
          operation: 'upsert',
          artifact: {
            artifactId: 'dsl-main',
            path: 'Main.sverlin',
            language: 'sverlin',
            content: blob,
            contentSha256: hash
          }
        }
      ]
    });
    const rendered = event('render', 2, artifact.eventId, 'visualization.rendered', {
      renderRequestEventId: 'render-request',
      compilationEventId: 'compile',
      artifactVersionEventId: artifact.eventId,
      artifactVersions: { 'dsl-main': artifact.eventId },
      seed: 1,
      render: blob,
      renderSha256: hash,
      sourceSha256: hash,
      cacheHit: false
    });
    const edit = event('edit', 3, rendered.eventId, 'artifact.version-created', {
      origin: { kind: 'manual-edit' },
      changes: [
        {
          operation: 'upsert',
          artifact: {
            artifactId: 'dsl-main',
            path: 'Main.sverlin',
            language: 'sverlin',
            content: { ...blob, sha256: '1'.repeat(64) },
            contentSha256: '1'.repeat(64)
          }
        }
      ]
    });
    const document = { ...rootDocument(), events: [root, artifact, rendered, edit] };

    expect(projectAt(document, rendered.eventId).activeRender?.eventId).toBe(rendered.eventId);
    expect(projectAt(document, edit.eventId).activeRender).toBeUndefined();
    expect(projectAt(document, artifact.eventId).artifacts['dsl-main']?.contentSha256).toBe(hash);
  });
});

function rootDocument(): ProjectDocument {
  return {
    schemaVersion: 1,
    projectId: 'project-test',
    events: [
      {
        eventId: 'root',
        sequence: 0,
        parentEventId: null,
        type: 'project.created',
        actor: { kind: 'user' },
        correlationId: 'correlation',
        createdAt: '2026-01-01T00:00:00.000Z',
        payload: { title: 'Test project', entryArtifactId: 'dsl-main' }
      }
    ]
  };
}

function event(
  eventId: string,
  sequence: number,
  parentEventId: string,
  type: ProjectEvent['type'],
  payload: ProjectEvent['payload']
) {
  return {
    eventId,
    sequence,
    parentEventId,
    type,
    actor: { kind: 'system' as const },
    correlationId: 'correlation',
    createdAt: `2026-01-01T00:00:0${sequence}.000Z`,
    payload
  } as ProjectEvent;
}
