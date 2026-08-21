import { randomInt } from 'node:crypto';

import { getArtifactSyncState } from '$lib/server/artifacts/store';
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
      revision: number;
    }
  | {
      ok: false;
      error: string;
      status: number;
    };

const minSeed = 1;
const maxSeedExclusive = 2147483647;

export const GET: RequestHandler = ({ request, url }) => {
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
          status: parsedQuery.status,
          error: parsedQuery.error
        } satisfies CompileStreamFailure);
        close();
        return;
      }

      const { seed, revision } = parsedQuery;
      const abortCompile = () => abortController.abort();
      request.signal.addEventListener('abort', abortCompile, { once: true });

      send('status', {
        ok: true,
        status: 'starting',
        seed,
        revision
      } satisfies CompileStreamStatus);

      void (async () => {
        try {
          const result = await compileVisualization({
            seed,
            revision,
            signal: abortController.signal,
            onEvent(event) {
              if (event.type === 'started') {
                send('status', {
                  ok: true,
                  status: 'running',
                  seed,
                  revision,
                  debug: event.debug
                } satisfies CompileStreamStatus);
              } else if (event.type === 'stdout') {
                send('stdout', {
                  ok: true,
                  chunk: event.chunk
                } satisfies CompileStreamOutput);
              } else if (event.type === 'stderr') {
                send('stderr', {
                  ok: true,
                  chunk: event.chunk
                } satisfies CompileStreamOutput);
              } else {
                send('status', {
                  ok: true,
                  status: 'complete',
                  seed,
                  revision,
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
              trace: result.trace,
              seed,
              revision
            } satisfies CompileStreamSuccess);
          } else {
            send('error', {
              ok: false,
              status: result.status,
              error: result.error,
              seed,
              revision,
              debug: result.debug
            } satisfies CompileStreamFailure);
          }
        } catch (err) {
          if (!abortController.signal.aborted) {
            send('error', {
              ok: false,
              status: 500,
              error: err instanceof Error ? err.message : String(err),
              seed,
              revision
            } satisfies CompileStreamFailure);
          }
        } finally {
          request.signal.removeEventListener('abort', abortCompile);
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
  const revisionValue = url.searchParams.get('revision');
  const revision =
    revisionValue === null ? getArtifactSyncState().headRevision : Number(revisionValue);

  if (!Number.isSafeInteger(revision) || revision < 0) {
    return {
      ok: false,
      status: 400,
      error: '`revision` must be a non-negative safe integer when provided.'
    };
  }

  const seedValue = url.searchParams.get('seed');

  if (seedValue === null || seedValue === '') {
    return {
      ok: true,
      seed: randomInt(minSeed, maxSeedExclusive),
      revision
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
    revision
  };
}
