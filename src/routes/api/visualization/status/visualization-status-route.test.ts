import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { acquireCompileLock } from '$lib/server/compile-lock.js';

import { _readCompileStatus } from './+server';

const compileLockPathEnvVar = 'SVERLIN_COMPILE_LOCK_PATH';

let previousLockPath: string | undefined;
let tempDir: string;

beforeEach(async () => {
  previousLockPath = process.env[compileLockPathEnvVar];
  tempDir = await mkdtemp(path.join(tmpdir(), 'sverlin-status-route-test-'));
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

describe('_readCompileStatus', () => {
  it('reports inactive when no compile lock exists', async () => {
    await expect(_readCompileStatus()).resolves.toEqual({ running: false });
  });

  it('reports the public compile lock holder when active', async () => {
    const lock = await acquireCompileLock({
      owner: 'bench',
      cwd: process.cwd(),
      command: 'cabal',
      args: ['run', '-v0', 'compile-app'],
      seed: 320994595,
      outputPath: '/tmp/bench-compile.json'
    });

    expect(lock.acquired).toBe(true);
    if (!lock.acquired) throw new Error(lock.message);

    try {
      const status = await _readCompileStatus();

      expect(status.running).toBe(true);
      if (status.running) {
        expect(status.owner).toBe('bench');
        expect(status.command).toBe('cabal');
        expect(status.seed).toBe(320994595);
        expect(status.outputPath).toBe('/tmp/bench-compile.json');
      }
    } finally {
      await lock.lock.release();
    }
  });
});
