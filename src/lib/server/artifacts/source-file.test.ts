import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { acquireCompileLock } from '$lib/server/compile-lock.js';
import { persistSourceArtifact, SourceArtifactBusyError } from './source-file';

const compileLockPathEnvVar = 'SVERLIN_COMPILE_LOCK_PATH';
let previousLockPath: string | undefined;
let tempDir: string;

beforeEach(async () => {
  previousLockPath = process.env[compileLockPathEnvVar];
  tempDir = await mkdtemp(path.join(tmpdir(), 'sverlin-source-file-test-'));
  process.env[compileLockPathEnvVar] = path.join(tempDir, 'compile.lock');
});

afterEach(async () => {
  if (previousLockPath === undefined) {
    delete process.env[compileLockPathEnvVar];
  } else {
    process.env[compileLockPathEnvVar] = previousLockPath;
  }
  await rm(tempDir, { recursive: true, force: true });
});

describe('persistSourceArtifact', () => {
  it('atomically replaces the requested source file', async () => {
    const sourceFile = path.join(tempDir, 'Main.hs');

    await persistSourceArtifact('module DSL.Main where\n', sourceFile);

    await expect(readFile(sourceFile, 'utf8')).resolves.toBe('module DSL.Main where\n');
  });

  it('does not write while the compile lock is held', async () => {
    const lockResult = await acquireCompileLock({
      owner: 'manual',
      cwd: process.cwd(),
      command: 'cabal',
      args: ['run', 'compile-app']
    });
    expect(lockResult.acquired).toBe(true);
    if (!lockResult.acquired) throw new Error(lockResult.message);

    try {
      await expect(
        persistSourceArtifact('module DSL.Main where\n', path.join(tempDir, 'Main.hs'))
      ).rejects.toBeInstanceOf(SourceArtifactBusyError);
    } finally {
      await lockResult.lock.release();
    }
  });
});
