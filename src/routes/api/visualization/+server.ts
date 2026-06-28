import { randomInt, randomUUID } from 'node:crypto';

import { compileVisualization } from '$lib/server/compile-visualization';
import type {
  CompileStreamFailure,
  CompileStreamOutput,
  CompileStreamStatus,
  CompileStreamSuccess
} from '$lib/visualization/types';

import type { RequestHandler } from './$types';

export const prerender = false;

type CompileQuery =
  | {
      ok: true;
      seed: number;
      details: boolean;
    }
  | {
      ok: false;
      error: string;
      status: number;
    };

const minSeed = 1;
const maxSeedExclusive = 2147483647;

let activeJobId: string | null = null;

export const GET: RequestHandler = ({ request, url }) => {
  const jobId = randomUUID();
  const parsedQuery = _readCompileQuery(url);
  const abortController = new AbortController();
  const encoder = new TextEncoder();

  let closed = false;

  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      function send(event: string, data: unknown) {
        if (closed) return;

        try {
          controller.enqueue(encoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`));
        } catch {
          abortController.abort();
        }
      }

      function close() {
        if (closed) return;

        closed = true;
        controller.close();
      }

      if (!parsedQuery.ok) {
        send('error', {
          ok: false,
          jobId,
          status: parsedQuery.status,
          error: parsedQuery.error
        } satisfies CompileStreamFailure);
        close();
        return;
      }

      if (activeJobId !== null) {
        send('error', {
          ok: false,
          jobId,
          status: 409,
          error: `Compile backend is already running job ${activeJobId}.`
        } satisfies CompileStreamFailure);
        close();
        return;
      }

      activeJobId = jobId;
      const { seed, details } = parsedQuery;
      const abortCompile = () => abortController.abort();
      request.signal.addEventListener('abort', abortCompile, { once: true });

      send('status', {
        ok: true,
        jobId,
        status: 'starting',
        seed,
        details
      } satisfies CompileStreamStatus);

      void (async () => {
        try {
          const result = await compileVisualization({
            seed,
            details,
            signal: abortController.signal,
            onEvent(event) {
              if (event.type === 'started') {
                send('status', {
                  ok: true,
                  jobId,
                  status: 'running',
                  seed,
                  details,
                  debug: event.debug
                } satisfies CompileStreamStatus);
              } else if (event.type === 'stdout') {
                send('stdout', {
                  ok: true,
                  jobId,
                  chunk: event.chunk
                } satisfies CompileStreamOutput);
              } else if (event.type === 'stderr') {
                send('stderr', {
                  ok: true,
                  jobId,
                  chunk: event.chunk
                } satisfies CompileStreamOutput);
              } else {
                send('status', {
                  ok: true,
                  jobId,
                  status: 'complete',
                  seed,
                  details,
                  debug: event.debug
                } satisfies CompileStreamStatus);
              }
            }
          });

          if (abortController.signal.aborted) {
            return;
          }

          if (result.ok) {
            send('trace', {
              ok: true,
              jobId,
              trace: result.trace,
              seed,
              details,
              debug: result.debug
            } satisfies CompileStreamSuccess);
          } else {
            send('error', {
              ok: false,
              jobId,
              status: result.status,
              error: result.error,
              seed,
              details,
              debug: result.debug
            } satisfies CompileStreamFailure);
          }
        } catch (err) {
          if (!abortController.signal.aborted) {
            send('error', {
              ok: false,
              jobId,
              status: 500,
              error: err instanceof Error ? err.message : String(err),
              seed,
              details
            } satisfies CompileStreamFailure);
          }
        } finally {
          request.signal.removeEventListener('abort', abortCompile);

          if (activeJobId === jobId) {
            activeJobId = null;
          }

          close();
        }
      })();
    },
    cancel() {
      abortController.abort();
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

export function _readCompileQuery(url: URL): CompileQuery {
  const details = readBoolean(url.searchParams.get('details'));

  if (details === null) {
    return {
      ok: false,
      status: 400,
      error: '`details` must be `true` or `false` when provided.'
    };
  }

  const seedValue = url.searchParams.get('seed');

  if (seedValue === null || seedValue === '') {
    return {
      ok: true,
      seed: randomInt(minSeed, maxSeedExclusive),
      details
    };
  }

  const seed = Number(seedValue);

  if (!Number.isInteger(seed) || !Number.isSafeInteger(seed) || seed < minSeed) {
    return {
      ok: false,
      status: 400,
      error: '`seed` must be a positive safe integer when provided.'
    };
  }

  return {
    ok: true,
    seed,
    details
  };
}

function readBoolean(value: string | null): boolean | null {
  if (value === null) return false;
  if (value === 'true') return true;
  if (value === 'false') return false;

  return null;
}
