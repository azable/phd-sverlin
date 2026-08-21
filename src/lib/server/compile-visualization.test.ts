import { describe, expect, it } from 'vitest';

import { compileCommand, compileVisualization, runCompile } from './compile-visualization';

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
  it('rejects a stale artifact revision before spawning Cabal', async () => {
    const result = await compileVisualization({ seed: 1, revision: 1 });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.status).toBe(409);
      expect(result.error).toContain('revision changed from 1 to 0');
      expect(result.debug.exitCode).toBe(null);
    }
  });

  it('passes an isolated source snapshot and its canonical label to the compiler', () => {
    const command = compileCommand(
      42,
      '/tmp/request-a/compiled.json',
      '/tmp/request-a/source/Main.sverlin',
      'Main.sverlin'
    );

    expect(command.command).toBe('node');
    expect(command.args.slice(0, 2)).toEqual(['scripts/run-compile.mjs', '--']);
    expect(command.args).toEqual(
      expect.arrayContaining([
        '--source',
        '/tmp/request-a/source/Main.sverlin',
        '--source-label',
        'Main.sverlin'
      ])
    );
  });
});
