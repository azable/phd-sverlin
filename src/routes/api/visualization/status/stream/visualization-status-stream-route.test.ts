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
  tempDir = await mkdtemp(path.join(tmpdir(), 'sverlin-status-stream-route-test-'));
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

describe('_readCompileStatus stream helper', () => {
  it('reports active compile lock metadata for stream payloads', async () => {
    const lock = await acquireCompileLock({
      owner: 'bench',
      cwd: process.cwd(),
      command: 'cabal',
      args: ['run', '-v0', 'compile-app'],
      seed: 1988735004,
      details: true,
      outputPath: '/tmp/bench-stream.json'
    });

    expect(lock.acquired).toBe(true);
    if (!lock.acquired) throw new Error(lock.message);

    try {
      const status = await _readCompileStatus();

      expect(status.running).toBe(true);
      if (status.running) {
        expect(status.owner).toBe('bench');
        expect(status.seed).toBe(1988735004);
        expect(status.outputPath).toBe('/tmp/bench-stream.json');
      }
    } finally {
      await lock.lock.release();
    }
  });
});
