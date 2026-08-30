import { readFile } from 'node:fs/promises';
import path from 'node:path';

import { json, type RequestHandler } from '@sveltejs/kit';

import { visualizationService } from '$lib/server/compiler';
import { runtimeRoot } from '$lib/server/runtime-config';
import { runtimeReadiness } from '$lib/server/runtime-state';

/** Run a real isolated compilation when an authenticated operator requests a deep check. */
export const POST: RequestHandler = async () => {
  const readiness = await runtimeReadiness(true);
  if (!readiness.ready) return json(readiness, { status: 503 });
  const source = await readFile(path.join(runtimeRoot(), 'examples', 'Minimal.sverlin'), 'utf8');
  const result = await visualizationService.generate({
    source: { name: 'Minimal.sverlin', content: source },
    seed: 1
  });
  if (!result.ok) {
    return json(
      {
        ok: false,
        error: result.error,
        failureKind: result.failureKind,
        durationMs: result.execution.durationMs
      },
      {
        status: result.failureKind === 'source' ? 422 : 503,
        headers: { 'cache-control': 'no-store' }
      }
    );
  }
  return json(
    {
      ok: true,
      durationMs: result.execution.durationMs,
      compilerSourceSha256: result.compilerSourceSha256,
      provenance: result.provenance
    },
    { headers: { 'cache-control': 'no-store' } }
  );
};
