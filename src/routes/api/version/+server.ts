import { readFile } from 'node:fs/promises';
import path from 'node:path';

import { json, type RequestHandler } from '@sveltejs/kit';

import { runtimeRoot } from '$lib/server/runtime-config';
import { runtimeReadiness } from '$lib/server/runtime-state';

export const GET: RequestHandler = async () => {
  const packageFile = JSON.parse(
    await readFile(path.join(runtimeRoot(), 'package.json'), 'utf8')
  ) as { version?: unknown };
  const readiness = await runtimeReadiness();
  return json(
    {
      version: typeof packageFile.version === 'string' ? packageFile.version : 'unknown',
      buildSha:
        process.env.RENDER_GIT_COMMIT?.trim() ||
        process.env.SVERLIN_BUILD_SHA?.trim() ||
        'development',
      compilerSourceSha256: readiness.compiler?.sourceSha256
    },
    { headers: { 'cache-control': 'no-store' } }
  );
};
