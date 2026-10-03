import { describe, expect, it } from 'vitest';

import { mainStudy } from '$lib/studies/main';
import { parseStudyInteractionBatch } from './interactions';

describe('project interaction contracts', () => {
  it('accepts one versioned project-associated batch', () => {
    const value = fixtureBatch();

    expect(parseStudyInteractionBatch(value)).toEqual(value);
  });

  it('rejects unallowlisted browser data', () => {
    const value = fixtureBatch() as Record<string, unknown>;
    value.cookie = 'must never be captured';

    expect(() => parseStudyInteractionBatch(value)).toThrow();
  });

  it('accepts a metadata-only terminal batch and rejects an empty open batch', () => {
    const value = fixtureBatch();
    value.events = [];

    expect(
      parseStudyInteractionBatch({
        ...value,
        terminal: {
          clientStoppedAt: '2026-08-30T10:01:00.000Z',
          recordedThrough: 0
        }
      })
    ).toMatchObject({ events: [], terminal: { recordedThrough: 0 } });
    expect(() => parseStudyInteractionBatch(value)).toThrow();
  });
});

function fixtureBatch() {
  return {
    session: {
      id: '12345678-1234-4123-8123-123456789abc',
      projectId: 'project-one',
      schemaVersion: 1 as const,
      clientStartedAt: '2026-08-30T10:00:00.000Z',
      timeOrigin: 1,
      initialViewport: { width: 1280, height: 720, devicePixelRatio: 1 },
      applicationVersion: '0.0.1',
      capture: mainStudy.interactionCapture!
    },
    events: [
      {
        sequence: 1,
        elapsedMs: 10,
        clientOccurredAt: '2026-08-30T10:00:00.010Z',
        projectHead: 3,
        kind: 'document.lifecycle' as const,
        payload: { state: 'focused' as const }
      }
    ]
  };
}
