import { readFile } from 'node:fs/promises';
import path from 'node:path';

import { json, type RequestHandler } from '@sveltejs/kit';

import { runtimeRoot } from '$lib/server/runtime-config';
import { modeCatalog } from '$lib/modes/catalog';

export const GET: RequestHandler = async () => {
  const packageFile = JSON.parse(
    await readFile(path.join(runtimeRoot(), 'package.json'), 'utf8')
  ) as { version?: unknown };
  return json(
    {
      version: typeof packageFile.version === 'string' ? packageFile.version : 'unknown',
      buildSha: process.env.SVERLIN_BUILD_SHA?.trim() || 'development',
      modes: Object.keys(modeCatalog)
    },
    { headers: { 'cache-control': 'no-store' } }
  );
};
