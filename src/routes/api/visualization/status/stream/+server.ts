import { readActiveCompileLock } from '$lib/server/compile-lock.js';
import type { CompileStatus } from '$lib/visualization/types';

import type { RequestHandler } from './$types';

export const prerender = false;

const statusStreamIntervalMs = 500;

export const GET: RequestHandler = ({ request }) => {
  const encoder = new TextEncoder();
  let closed = false;
  let lastPayload = '';
  let timer: ReturnType<typeof setInterval> | null = null;
  let sending = false;

  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      function close() {
        if (closed) return;

        closed = true;
        if (timer !== null) {
          clearInterval(timer);
          timer = null;
        }
        request.signal.removeEventListener('abort', close);

        try {
          controller.close();
        } catch {
          // The client may have already closed the EventSource connection.
        }
      }

      async function sendStatus(force = false) {
        if (closed || sending) return;

        sending = true;
        try {
          const payload = JSON.stringify(await _readCompileStatus());
          if (!force && payload === lastPayload) return;

          lastPayload = payload;
          controller.enqueue(encoder.encode(`event: status\ndata: ${payload}\n\n`));
        } catch {
          close();
        } finally {
          sending = false;
        }
      }

      request.signal.addEventListener('abort', close, { once: true });
      await sendStatus(true);
      timer = setInterval(() => {
        void sendStatus();
      }, statusStreamIntervalMs);
    },
    cancel() {
      closed = true;
      if (timer !== null) {
        clearInterval(timer);
        timer = null;
      }
    }
  });

  return new Response(stream, {
    headers: {
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
      'Content-Type': 'text/event-stream; charset=utf-8',
      'X-Accel-Buffering': 'no'
    }
  });
};

export async function _readCompileStatus(): Promise<CompileStatus> {
  const lock = await readActiveCompileLock();
  return lock ? { running: true, ...lock } : { running: false };
}
