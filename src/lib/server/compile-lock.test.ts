import { spawn } from 'node:child_process';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import {
  acquireCompileLock,
  readActiveCompileLock,
  readCompileLock,
  releaseCompileLock
} from './compile-lock.js';

const compileLockPathEnvVar = 'SVERLIN_COMPILE_LOCK_PATH';

let previousLockPath: string | undefined;
let tempDir: string;

beforeEach(async () => {
  previousLockPath = process.env[compileLockPathEnvVar];
  tempDir = await mkdtemp(path.join(tmpdir(), 'sverlin-lock-test-'));
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

describe('compile lock', () => {
  it('prevents a second acquisition while held', async () => {
    const first = await acquireCompileLock(lockOptions('manual'));
    expect(first.acquired).toBe(true);
    if (!first.acquired) throw new Error(first.message);

    const second = await acquireCompileLock(lockOptions('web'));
    expect(second.acquired).toBe(false);

    if (!second.acquired) {
      expect(second.holder?.owner).toBe('manual');
      expect(second.holder?.seed).toBe(42);
      expect(second.message).toContain('Compile backend is already running');
    }

    expect(await first.lock.release()).toBe(true);

    const third = await acquireCompileLock(lockOptions('web'));
    expect(third.acquired).toBe(true);
    if (third.acquired) {
      await third.lock.release();
    }
  });

  it('does not release a lock when the token does not match', async () => {
    const first = await acquireCompileLock(lockOptions('manual'));
    expect(first.acquired).toBe(true);
    if (!first.acquired) throw new Error(first.message);

    const released = await releaseCompileLock({
      ...first.lock,
      info: { ...first.lock.info, token: 'different-token' }
    });

    expect(released).toBe(false);
    expect(await readCompileLock()).not.toBeNull();
    expect(await first.lock.release()).toBe(true);
  });

  it('cleans up stale locks from dead processes', async () => {
    const lockPath = process.env[compileLockPathEnvVar];
    if (!lockPath) throw new Error('test lock path was not configured');

    await writeFile(
      lockPath,
      `${JSON.stringify(
        {
          token: 'stale-token',
          owner: 'manual',
          pid: 99_999_999,
          startedAt: new Date(0).toISOString(),
          cwd: process.cwd(),
          command: 'cabal',
          args: ['run']
        },
        null,
        2
      )}\n`,
      'utf8'
    );

    const acquired = await acquireCompileLock(lockOptions('web'));
    expect(acquired.acquired).toBe(true);

    if (acquired.acquired) {
      expect(acquired.lock.info.owner).toBe('web');
      await acquired.lock.release();
    }
  });

  it('accepts legacy lock files while discarding details metadata', async () => {
    const lockPath = process.env[compileLockPathEnvVar];
    if (!lockPath) throw new Error('test lock path was not configured');

    await writeFile(
      lockPath,
      `${JSON.stringify({
        token: 'legacy-token',
        owner: 'manual',
        pid: process.pid,
        startedAt: new Date(0).toISOString(),
        cwd: process.cwd(),
        command: 'cabal',
        args: ['run'],
        details: true
      })}\n`,
      'utf8'
    );

    const lock = await readCompileLock();
    expect(lock?.token).toBe('legacy-token');
    expect(lock).not.toHaveProperty('details');
  });

  it('reports active locks and removes stale locks when reading active status', async () => {
    const lockPath = process.env[compileLockPathEnvVar];
    if (!lockPath) throw new Error('test lock path was not configured');

    const lock = await acquireCompileLock(lockOptions('bench'));
    expect(lock.acquired).toBe(true);
    if (!lock.acquired) throw new Error(lock.message);

    expect((await readActiveCompileLock())?.owner).toBe('bench');
    expect((await readActiveCompileLock())?.seed).toBe(42);
    await lock.lock.release();

    await writeFile(
      lockPath,
      `${JSON.stringify(
        {
          token: 'stale-token',
          owner: 'manual',
          pid: 99_999_999,
          startedAt: new Date(0).toISOString(),
          cwd: process.cwd(),
          command: 'cabal',
          args: ['run']
        },
        null,
        2
      )}\n`,
      'utf8'
    );

    expect(await readActiveCompileLock()).toBeNull();
    expect(await readCompileLock()).toBeNull();
  });

  it('makes the manual compile wrapper fail fast when a compile lock is held', async () => {
    const lockPath = process.env[compileLockPathEnvVar];
    if (!lockPath) throw new Error('test lock path was not configured');

    const lock = await acquireCompileLock(lockOptions('web'));
    expect(lock.acquired).toBe(true);
    if (!lock.acquired) throw new Error(lock.message);

    try {
      const result = await runNodeScript([
        'scripts/run-compile.mjs',
        '--output',
        '/tmp/unused.json'
      ]);

      expect(result.exitCode).toBe(75);
      expect((await readCompileLock())?.token).toBe(lock.lock.info.token);
    } finally {
      await lock.lock.release();
    }
  });
});

function lockOptions(owner: string) {
  return {
    owner,
    cwd: process.cwd(),
    command: 'cabal',
    args: ['run', '-v0', 'compile-app'],
    seed: 42
  };
}

function runNodeScript(args: string[]) {
  return new Promise<{ exitCode: number | null; stdout: string; stderr: string }>(
    (resolve, reject) => {
      const child = spawn(process.execPath, args, {
        cwd: process.cwd(),
        env: process.env,
        stdio: ['ignore', 'pipe', 'pipe']
      });
      let stdout = '';
      let stderr = '';

      child.stdout.setEncoding('utf8');
      child.stderr.setEncoding('utf8');
      child.stdout.on('data', (chunk: string) => {
        stdout += chunk;
      });
      child.stderr.on('data', (chunk: string) => {
        stderr += chunk;
      });
      child.on('error', reject);
      child.on('close', (exitCode) => {
        setImmediate(() => {
          resolve({ exitCode, stdout, stderr });
        });
      });
    }
  );
}
