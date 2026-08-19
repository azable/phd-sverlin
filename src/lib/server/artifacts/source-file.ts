import { randomUUID } from 'node:crypto';
import { rename, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';

import { acquireCompileLock } from '$lib/server/compile-lock.js';

export const dslSourcePath = 'compile/app/DSL/Main.hs' as const;

export class SourceArtifactBusyError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'SourceArtifactBusyError';
  }
}

/** Persist DSL.Main without exposing a partially written module to Cabal. */
export async function persistSourceArtifact(
  content: string,
  sourceFile = path.resolve(process.cwd(), dslSourcePath)
) {
  const lockResult = await acquireCompileLock({
    owner: 'source',
    cwd: process.cwd(),
    command: 'write-source-artifact',
    args: [dslSourcePath]
  });

  if (!lockResult.acquired) {
    throw new SourceArtifactBusyError(lockResult.message);
  }

  const temporaryFile = path.join(
    path.dirname(sourceFile),
    `.${path.basename(sourceFile)}.${randomUUID()}.tmp`
  );

  try {
    await writeFile(temporaryFile, content, { encoding: 'utf8', flag: 'wx' });
    await rename(temporaryFile, sourceFile);
  } finally {
    await rm(temporaryFile, { force: true });
    await lockResult.lock.release();
  }
}
