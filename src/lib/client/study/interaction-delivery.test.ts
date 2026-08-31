import { describe, expect, it, vi } from 'vitest';

import type { StudyInteractionEventInput } from '$lib/shared/study/interactions';
import { mainStudyV1 } from '$lib/shared/study/main-v1';

import { ProjectInteractionDelivery } from './interaction-delivery';
import {
  ResilientInteractionOutbox,
  type StoredInteractionEvent,
  type StoredInteractionSession
} from './interaction-outbox';

describe('participant interaction delivery', () => {
  it('retains a final session after a failed request and completes it on a later drain', async () => {
    const outbox = new ResilientInteractionOutbox();
    const stored = session('12345678-1234-4123-8123-123456789abc', 'participant-one', 1);
    await outbox.putSession(stored);
    await outbox.putEvent(event(stored.session.id, 1), 10_000);
    const fetch = vi
      .fn<typeof globalThis.fetch>()
      .mockResolvedValueOnce(new Response(null, { status: 503 }))
      .mockResolvedValueOnce(success(1, true));
    const delivery = new ProjectInteractionDelivery({
      participantId: 'participant-one',
      outbox,
      fetch
    });

    await delivery.flush();
    expect(await outbox.events(stored.session.id)).toHaveLength(1);
    expect(await outbox.sessions()).toHaveLength(1);

    await delivery.flush();
    expect(await outbox.events(stored.session.id)).toHaveLength(0);
    expect(await outbox.sessions()).toHaveLength(0);
    expect(JSON.parse(fetch.mock.calls[1]![1]!.body as string)).toMatchObject({
      terminal: stored.terminal,
      events: [{ sequence: 1 }]
    });
  });

  it('drains every tab owned by the participant without touching another participant', async () => {
    const outbox = new ResilientInteractionOutbox();
    const first = session('12345678-1234-4123-8123-123456789abc', 'participant-one', 1);
    const second = session('12345678-1234-4123-8123-123456789abd', 'participant-one', 1);
    const foreign = session('12345678-1234-4123-8123-123456789abe', 'participant-two', 1);
    for (const stored of [first, second, foreign]) {
      await outbox.putSession(stored);
      await outbox.putEvent(event(stored.session.id, 1), 10_000);
    }
    const fetch = vi.fn<typeof globalThis.fetch>(async () => success(1, true));

    await new ProjectInteractionDelivery({
      participantId: 'participant-one',
      outbox,
      fetch
    }).flush();

    expect(fetch).toHaveBeenCalledTimes(2);
    expect((await outbox.sessions()).map(({ participantId }) => participantId)).toEqual([
      'participant-two'
    ]);
    expect(await outbox.events(foreign.session.id)).toHaveLength(1);
  });

  it('replaces only a rejected event and preserves its sequence', async () => {
    const outbox = new ResilientInteractionOutbox();
    const stored = session('12345678-1234-4123-8123-123456789abc', 'participant-one', 1);
    await outbox.putSession(stored);
    await outbox.putEvent(event(stored.session.id, 1), 10_000);
    const bodies: Array<Record<string, unknown>> = [];
    const fetch = vi.fn<typeof globalThis.fetch>(async (_input, init) => {
      bodies.push(JSON.parse(init!.body as string) as Record<string, unknown>);
      return bodies.length === 1
        ? Response.json(
            { error: 'invalid', code: 'invalid-event', invalidEventIndex: 0 },
            { status: 400 }
          )
        : success(1, true);
    });

    await new ProjectInteractionDelivery({
      participantId: 'participant-one',
      outbox,
      fetch
    }).flush();

    expect(fetch).toHaveBeenCalledTimes(2);
    expect(bodies[1]).toMatchObject({
      events: [
        {
          sequence: 1,
          kind: 'recorder.dropped',
          payload: { reason: 'invalid-record' }
        }
      ]
    });
    expect(await outbox.sessions()).toHaveLength(0);
  });

  it('delivers terminal metadata even when every event was acknowledged earlier', async () => {
    const outbox = new ResilientInteractionOutbox();
    const stored = session('12345678-1234-4123-8123-123456789abc', 'participant-one', 0);
    await outbox.putSession(stored);
    const fetch = vi.fn<typeof globalThis.fetch>(async () => success(0, true));

    await new ProjectInteractionDelivery({
      participantId: 'participant-one',
      outbox,
      fetch
    }).flush();

    expect(JSON.parse(fetch.mock.calls[0]![1]!.body as string)).toMatchObject({
      terminal: stored.terminal,
      events: []
    });
    expect(await outbox.sessions()).toHaveLength(0);
  });

  it('splits an oversized batch without dropping either valid record', async () => {
    const outbox = new ResilientInteractionOutbox();
    const stored = session('12345678-1234-4123-8123-123456789abc', 'participant-one', 2);
    await outbox.putSession(stored);
    await outbox.putEvent(event(stored.session.id, 1), 10_000);
    await outbox.putEvent(event(stored.session.id, 2), 10_000);
    const delivered: number[][] = [];
    const fetch = vi.fn<typeof globalThis.fetch>(async (_input, init) => {
      const body = JSON.parse(init!.body as string) as { events: Array<{ sequence: number }> };
      delivered.push(body.events.map(({ sequence }) => sequence));
      if (body.events.length > 1) {
        return Response.json({ error: 'large', code: 'body-too-large' }, { status: 413 });
      }
      return success(body.events[0]!.sequence, body.events[0]!.sequence === 2);
    });

    await new ProjectInteractionDelivery({
      participantId: 'participant-one',
      outbox,
      fetch
    }).flush();

    expect(delivered).toEqual([[1, 2], [1], [2]]);
    expect(await outbox.sessions()).toHaveLength(0);
  });

  it('runs a queued terminal flush after an earlier request already started', async () => {
    const outbox = new ResilientInteractionOutbox();
    const stored = session('12345678-1234-4123-8123-123456789abc', 'participant-one', 1);
    const terminal = stored.terminal!;
    delete stored.terminal;
    await outbox.putSession(stored);
    await outbox.putEvent(event(stored.session.id, 1), 10_000);
    let resolveFirst!: (response: Response) => void;
    const firstResponse = new Promise<Response>((resolve) => (resolveFirst = resolve));
    const bodies: Array<{ events: unknown[]; terminal?: unknown }> = [];
    const fetch = vi.fn<typeof globalThis.fetch>(async (_input, init) => {
      bodies.push(JSON.parse(init!.body as string) as (typeof bodies)[number]);
      return bodies.length === 1 ? firstResponse : success(1, true);
    });
    const delivery = new ProjectInteractionDelivery({
      participantId: 'participant-one',
      outbox,
      fetch
    });

    const firstFlush = delivery.flush();
    await vi.waitFor(() => expect(fetch).toHaveBeenCalledTimes(1));
    await outbox.finalize(stored.session.id, terminal);
    const finalFlush = delivery.flush(true);
    resolveFirst(success(1, false));
    await Promise.all([firstFlush, finalFlush]);

    expect(bodies).toEqual([
      expect.objectContaining({ events: [expect.objectContaining({ sequence: 1 })] }),
      expect.objectContaining({ events: [], terminal })
    ]);
    expect(await outbox.sessions()).toHaveLength(0);
  });
});

function session(
  id: string,
  participantId: string,
  recordedThrough: number
): StoredInteractionSession {
  return {
    participantId,
    session: {
      id,
      projectId: `project-${id.at(-1)}`,
      schemaVersion: 1,
      clientStartedAt: '2026-08-30T10:00:00.000Z',
      timeOrigin: 1,
      initialViewport: { width: 1280, height: 720, devicePixelRatio: 1 },
      applicationVersion: '0.0.1',
      capture: mainStudyV1.interactionCapture!
    },
    terminal: {
      clientStoppedAt: '2026-08-30T10:01:00.000Z',
      recordedThrough
    }
  };
}

function event(sessionId: string, sequence: number): StoredInteractionEvent {
  const value: StudyInteractionEventInput = {
    sequence,
    elapsedMs: sequence,
    clientOccurredAt: `2026-08-30T10:00:00.00${sequence}Z`,
    projectHead: 1,
    kind: 'document.lifecycle',
    payload: { state: 'focused' }
  };
  return {
    sessionId,
    sequence,
    event: value,
    byteLength: new TextEncoder().encode(JSON.stringify(value)).byteLength
  };
}

function success(acceptedThrough: number, deliveryComplete: boolean): Response {
  return Response.json({
    acceptedThrough,
    serverReceivedAt: '2026-08-30T10:01:01.000Z',
    terminalAccepted: true,
    deliveryComplete
  });
}
