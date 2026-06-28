import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

import { describe, expect, it } from 'vitest';

import { acquireCompileLock } from './compile-lock.js';
import { compileVisualization, runCompile } from './compile-visualization';

describe('runCompile', () => {
  it('streams stdout and stderr chunks while the command runs', async () => {
    const stdoutChunks: string[] = [];
    const stderrChunks: string[] = [];

    const result = await runCompile(
      '/bin/bash',
      ['-c', 'printf out; printf err >&2'],
      process.cwd(),
      1_000,
      {
        onStdout: (chunk) => {
          stdoutChunks.push(chunk);
        },
        onStderr: (chunk) => {
          stderrChunks.push(chunk);
        }
      }
    );

    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe('out');
    expect(result.stderr).toBe('err');
    expect(stdoutChunks.join('')).toBe('out');
    expect(stderrChunks.join('')).toBe('err');
  });

  it('settles when a timed-out shell command leaves child processes behind', async () => {
    const startedAt = Date.now();
    const result = await runCompile('/bin/bash', ['-c', 'sleep 10 & wait'], process.cwd(), 100);

    expect(result.timedOut).toBe(true);
    expect(result.exitCode).toBe(null);
    expect(result.timeoutMs).toBe(100);
    expect(Date.now() - startedAt).toBeLessThan(3_000);
  });

  it('uses SVERLIN_COMPILE_TIMEOUT_MS when no explicit timeout is provided', async () => {
    const previousTimeout = process.env.SVERLIN_COMPILE_TIMEOUT_MS;
    process.env.SVERLIN_COMPILE_TIMEOUT_MS = '100';

    try {
      const result = await runCompile('/bin/bash', ['-c', 'sleep 10 & wait'], process.cwd());

      expect(result.timedOut).toBe(true);
      expect(result.timeoutMs).toBe(100);
    } finally {
      if (previousTimeout === undefined) {
        delete process.env.SVERLIN_COMPILE_TIMEOUT_MS;
      } else {
        process.env.SVERLIN_COMPILE_TIMEOUT_MS = previousTimeout;
      }
    }
  });
});

describe('compileVisualization', () => {
  it('returns 409 without spawning when the shared compile lock is held', async () => {
    const compileLockPathEnvVar = 'SVERLIN_COMPILE_LOCK_PATH';
    const workspaceOutputDirEnvVar = 'SVERLIN_OUTPUT_DIR';
    const previousLockPath = process.env[compileLockPathEnvVar];
    const previousOutputDir = process.env[workspaceOutputDirEnvVar];
    const tempDir = await mkdtemp(path.join(tmpdir(), 'sverlin-compile-lock-test-'));
    process.env[compileLockPathEnvVar] = path.join(tempDir, 'compile.lock');
    process.env[workspaceOutputDirEnvVar] = path.join(tempDir, 'outputs');

    const lockResult = await acquireCompileLock({
      owner: 'manual',
      cwd: process.cwd(),
      command: 'cabal',
      args: ['run', '-v0', 'compile-app'],
      outputPath: '/tmp/manual-compile.json'
    });

    expect(lockResult.acquired).toBe(true);
    if (!lockResult.acquired) throw new Error(lockResult.message);

    try {
      const result = await compileVisualization({ seed: 1, details: false });

      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.status).toBe(409);
        expect(result.error).toContain('Compile backend is already running');
        expect(result.lock?.owner).toBe('manual');
        expect(result.debug.outputPath).toMatch(
          /[\\/]seed-1[\\/]web-[^\\/]+[\\/]compiled-seed-1\.json$/
        );
        expect(result.debug.stderr).toContain('Compile backend is already running');
      }
    } finally {
      await lockResult.lock.release();

      if (previousLockPath === undefined) {
        delete process.env[compileLockPathEnvVar];
      } else {
        process.env[compileLockPathEnvVar] = previousLockPath;
      }

      if (previousOutputDir === undefined) {
        delete process.env[workspaceOutputDirEnvVar];
      } else {
        process.env[workspaceOutputDirEnvVar] = previousOutputDir;
      }

      await rm(tempDir, { recursive: true, force: true });
    }
  });
});
