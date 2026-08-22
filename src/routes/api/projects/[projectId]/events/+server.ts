import { error } from '@sveltejs/kit';

import type { ProjectEvent } from '$lib/projects/types';
import { projectRepository, ProjectNotFoundError } from '$lib/server/projects/repository';

import type { RequestHandler } from './$types';

const encoder = new TextEncoder();
const heartbeatIntervalMs = 15_000;

export const GET: RequestHandler = async ({ params, request, url }) => {
  const after = readAfter(request, url);
  const queued: ProjectEvent[] = [];
  let deliver: ((events: ProjectEvent[]) => void) | undefined;
  const unsubscribe = projectRepository.subscribe(params.projectId, (events) => {
    if (deliver) deliver(events);
    else queued.push(...events);
  });

  let document;
  try {
    document = await projectRepository.load(params.projectId);
  } catch (cause) {
    unsubscribe();
    if (cause instanceof ProjectNotFoundError) error(404, cause.message);
    throw cause;
  }

  if (after > document.events.length) {
    unsubscribe();
    error(409, 'The requested project event position is ahead of the project head.');
  }

  let cleanup = unsubscribe;
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      let closed = false;
      let lastId = after;
      const send = (value: string) => {
        if (!closed) controller.enqueue(encoder.encode(value));
      };
      const heartbeat = setInterval(() => send(': keepalive\n\n'), heartbeatIntervalMs);
      const close = () => {
        if (closed) return;
        closed = true;
        clearInterval(heartbeat);
        unsubscribe();
        request.signal.removeEventListener('abort', close);
        try {
          controller.close();
        } catch {
          // The runtime may already have closed the stream.
        }
      };
      cleanup = close;

      const sendEvent = (event: ProjectEvent) => {
        if (event.id <= lastId) return;
        if (event.id !== lastId + 1) return close();
        send(`event: project-event\nid: ${event.id}\ndata: ${JSON.stringify(event)}\n\n`);
        lastId = event.id;
      };

      [...document.events.filter(({ id }) => id > after), ...queued]
        .toSorted((left, right) => left.id - right.id)
        .forEach(sendEvent);
      deliver = (events) => events.forEach(sendEvent);
      send(
        `event: ready\ndata: ${JSON.stringify({
          schemaVersion: 1,
          projectId: document.projectId,
          head: lastId
        })}\n\n`
      );

      request.signal.addEventListener('abort', close, { once: true });
      if (request.signal.aborted) close();
    },
    cancel() {
      cleanup();
    }
  });

  return new Response(stream, {
    headers: {
      'cache-control': 'no-cache, no-transform',
      connection: 'keep-alive',
      'content-type': 'text/event-stream; charset=utf-8',
      'x-accel-buffering': 'no'
    }
  });
};

function readAfter(request: Request, url: URL) {
  const value = request.headers.get('last-event-id') ?? url.searchParams.get('after') ?? '0';
  const id = Number(value);
  if (!Number.isSafeInteger(id) || id < 0) error(400, 'Invalid project event position.');
  return id;
}
