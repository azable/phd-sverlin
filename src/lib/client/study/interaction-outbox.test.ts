import { describe, expect, it } from 'vitest';

import type { StudyInteractionEventInput } from '$lib/shared/study/interactions';
import { mainStudyV1 } from '$lib/shared/study/main-v1';

import { ResilientInteractionOutbox, type StoredInteractionEvent } from './interaction-outbox';

describe('project interaction outbox', () => {
  it('acknowledges ordered records without affecting another session', async () => {
    const outbox = new ResilientInteractionOutbox();
    await outbox.putSession({ session: session('12345678-1234-4123-8123-123456789abc') });
    await outbox.putSession({ session: session('12345678-1234-4123-8123-123456789abd') });
    await outbox.putEvent(stored('12345678-1234-4123-8123-123456789abc', lifecycle(1)), 10_000);
    await outbox.putEvent(stored('12345678-1234-4123-8123-123456789abc', lifecycle(2)), 10_000);
    await outbox.putEvent(stored('12345678-1234-4123-8123-123456789abd', lifecycle(1)), 10_000);

    await outbox.acknowledge('12345678-1234-4123-8123-123456789abc', 1);

    expect(
      (await outbox.events('12345678-1234-4123-8123-123456789abc')).map((x) => x.sequence)
    ).toEqual([2]);
    expect(await outbox.events('12345678-1234-4123-8123-123456789abd')).toHaveLength(1);
  });

  it('compacts pointer paths to sequence-preserving dropped records first', async () => {
    const outbox = new ResilientInteractionOutbox();
    const sessionId = '12345678-1234-4123-8123-123456789abc';
    await outbox.putSession({ session: session(sessionId) });
    const pointer: StudyInteractionEventInput = {
      sequence: 1,
      elapsedMs: 1,
      clientOccurredAt: '2026-08-30T10:00:00.001Z',
      projectHead: 1,
      kind: 'pointer.path',
      payload: {
        pointerType: 'mouse',
        points: Array.from({ length: 32 }, (_, index) => ({
          offsetMs: index,
          clientX: index,
          clientY: index,
          normalizedX: index / 32,
          normalizedY: index / 32
        }))
      }
    };

    const result = await outbox.putEvent(stored(sessionId, pointer), 600);
    const [retained] = await outbox.events(sessionId);

    expect(result.stored).toBe(true);
    expect(result.dropped).toEqual({ 'pointer.path': 1 });
    expect(retained?.sequence).toBe(1);
    expect(retained?.event.kind).toBe('recorder.dropped');
  });
});

function session(id: string) {
  return {
    id,
    projectId: 'project-one',
    schemaVersion: 1 as const,
    clientStartedAt: '2026-08-30T10:00:00.000Z',
    timeOrigin: 1,
    initialViewport: { width: 1280, height: 720, devicePixelRatio: 1 },
    applicationVersion: '0.0.1',
    capture: mainStudyV1.interactionCapture!
  };
}

function lifecycle(sequence: number): StudyInteractionEventInput {
  return {
    sequence,
    elapsedMs: sequence,
    clientOccurredAt: `2026-08-30T10:00:00.00${sequence}Z`,
    projectHead: 1,
    kind: 'document.lifecycle',
    payload: { state: 'focused' }
  };
}

function stored(sessionId: string, event: StudyInteractionEventInput): StoredInteractionEvent {
  return {
    sessionId,
    sequence: event.sequence,
    event,
    byteLength: new TextEncoder().encode(JSON.stringify(event)).byteLength
  };
}
