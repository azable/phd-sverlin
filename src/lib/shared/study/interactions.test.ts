import { describe, expect, it } from 'vitest';

import { mainStudyV1 } from './main-v1';
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
      capture: mainStudyV1.interactionCapture!
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
