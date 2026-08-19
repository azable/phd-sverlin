import { spawn } from 'node:child_process';
import { readFile, rm } from 'node:fs/promises';

import type {
  CompileDebug,
  CompileLockHolder,
  CompiledVisualization
} from '$lib/visualization/types';

import { getArtifactSyncState } from './artifacts/store';
import { acquireCompileLock } from './compile-lock.js';
import { createCompileOutput } from './workspace-output.js';

export type CompileVisualizationOptions = {
  seed: number;
  details: boolean;
  revision: number;
  signal?: AbortSignal;
  onEvent?: (event: CompileVisualizationEvent) => void;
};

export type CompileVisualizationResult =
  | {
      ok: true;
      trace: CompiledVisualization;
      debug: CompileDebug;
    }
  | {
      ok: false;
      error: string;
      debug: CompileDebug;
      status: number;
      lock?: CompileLockHolder;
    };

export type CompileVisualizationEvent =
  | {
      type: 'started';
      debug: CompileDebug;
    }
  | {
      type: 'stdout';
      chunk: string;
      stdout: string;
    }
  | {
      type: 'stderr';
      chunk: string;
      stderr: string;
    }
  | {
      type: 'finished';
      debug: CompileDebug;
    };

type CompileRun = CompileDebug & {
  timedOut: boolean;
};

type RunCompileOptions = {
  signal?: AbortSignal;
  onStdout?: (chunk: string, stdout: string) => void;
  onStderr?: (chunk: string, stderr: string) => void;
};

const defaultCompileTimeoutMs = 300_000;
const timeoutKillGraceMs = 1_000;
const compileTimeoutEnvVar = 'SVERLIN_COMPILE_TIMEOUT_MS';

export async function compileVisualization({
  seed,
  details,
  revision,
  signal,
  onEvent
}: CompileVisualizationOptions): Promise<CompileVisualizationResult> {
  const cwd = process.cwd();
  const { outputDir, outputPath } = await createCompileOutput({ owner: 'web', seed });
  const { command, args } = compileCommand(seed, details, outputPath);

  const timeoutMs = readCompileTimeoutMs();
  const startedDebug: CompileDebug = {
    command,
    args,
    cwd,
    outputPath,
    timeoutMs,
    durationMs: 0,
    exitCode: null,
    stdout: '',
    stderr: ''
  };
  const lockResult = await acquireCompileLock({
    owner: 'web',
    cwd,
    command,
    args,
    seed,
    details,
    outputPath
  });

  if (!lockResult.acquired) {
    await rm(outputDir, { recursive: true, force: true });

    return {
      ok: false,
      error: lockResult.message,
      debug: { ...startedDebug, stderr: lockResult.message },
      status: 409,
      ...(lockResult.holder ? { lock: lockResult.holder } : {})
    };
  }

  try {
    const currentRevision = getArtifactSyncState().headRevision;
    if (revision !== currentRevision) {
      const error = `DSL source revision changed from ${revision} to ${currentRevision} before compilation started.`;
      await rm(outputDir, { recursive: true, force: true });
      return {
        ok: false,
        error,
        debug: { ...startedDebug, stderr: error },
        status: 409
      };
    }

    onEvent?.({
      type: 'started',
      debug: startedDebug
    });

    let debug = await runCompile(command, args, cwd, timeoutMs, {
      signal,
      onStdout: (chunk, stdout) => {
        onEvent?.({ type: 'stdout', chunk, stdout });
      },
      onStderr: (chunk, stderr) => {
        onEvent?.({ type: 'stderr', chunk, stderr });
      }
    });
    let compiledJson = '';

    try {
      compiledJson = await readFile(outputPath, 'utf8');
    } catch {
      compiledJson = '';
    }

    debug = { ...debug, outputPath };
    onEvent?.({ type: 'finished', debug });

    if (debug.error) {
      return {
        ok: false,
        error: debug.error,
        debug,
        status: 500
      };
    }

    if (debug.timedOut) {
      return {
        ok: false,
        error: `Compile backend timed out after ${formatDuration(timeoutMs)}.`,
        debug,
        status: 504
      };
    }

    if (debug.exitCode !== 0) {
      return {
        ok: false,
        error: `Compile backend exited with code ${debug.exitCode}.`,
        debug,
        status: 500
      };
    }

    try {
      return {
        ok: true,
        trace: JSON.parse(compiledJson) as CompiledVisualization,
        debug
      };
    } catch (err) {
      return {
        ok: false,
        error: `Compile backend wrote invalid JSON: ${
          err instanceof Error ? err.message : String(err)
        }`,
        debug,
        status: 502
      };
    }
  } finally {
    await lockResult.lock.release();
  }
}

export function runCompile(
  command: string,
  args: string[],
  cwd: string,
  timeoutMs = readCompileTimeoutMs(),
  options: RunCompileOptions = {}
): Promise<CompileRun> {
  return new Promise((resolve) => {
    const startedAt = Date.now();
    const child = spawn(command, args, {
      cwd,
      detached: process.platform !== 'win32',
      stdio: ['ignore', 'pipe', 'pipe']
    });
    let stdout = '';
    let stderr = '';
    let settled = false;
    let timedOut = false;
    let cancelled = false;
    let killTimer: ReturnType<typeof setTimeout> | undefined;
    let settleTimer: ReturnType<typeof setTimeout> | undefined;

    function terminate(signal: NodeJS.Signals) {
      terminateCompile(child.pid, signal);
    }

    function forceSettle(error?: string) {
      settle({
        command,
        args,
        cwd,
        timeoutMs,
        durationMs: Date.now() - startedAt,
        exitCode: null,
        stdout,
        stderr,
        error,
        timedOut
      });
    }

    const timer = setTimeout(() => {
      timedOut = true;
      terminate('SIGTERM');

      killTimer = setTimeout(() => {
        terminate('SIGKILL');
      }, timeoutKillGraceMs);

      settleTimer = setTimeout(() => {
        forceSettle();
      }, timeoutKillGraceMs * 2);
    }, timeoutMs);

    const abortCompile = () => {
      cancelled = true;
      terminate('SIGTERM');

      killTimer = setTimeout(() => {
        terminate('SIGKILL');
      }, timeoutKillGraceMs);

      settleTimer = setTimeout(() => {
        forceSettle('Compile backend was cancelled.');
      }, timeoutKillGraceMs * 2);
    };

    if (options.signal?.aborted) {
      abortCompile();
    } else {
      options.signal?.addEventListener('abort', abortCompile, { once: true });
    }

    function clearTimers() {
      clearTimeout(timer);
      if (killTimer) clearTimeout(killTimer);
      if (settleTimer) clearTimeout(settleTimer);
      options.signal?.removeEventListener('abort', abortCompile);
    }

    function settle(result: CompileRun) {
      if (settled) return;

      settled = true;
      clearTimers();
      resolve(result);
    }

    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');

    child.stdout.on('data', (chunk: string) => {
      stdout += chunk;
      options.onStdout?.(chunk, stdout);
    });

    child.stderr.on('data', (chunk: string) => {
      stderr += chunk;
      options.onStderr?.(chunk, stderr);
    });

    child.on('error', (err) => {
      settle({
        command,
        args,
        cwd,
        timeoutMs,
        durationMs: Date.now() - startedAt,
        exitCode: null,
        stdout,
        stderr,
        error: err.message,
        timedOut
      });
    });

    child.on('close', (exitCode) => {
      const error = cancelled ? 'Compile backend was cancelled.' : undefined;

      settle({
        command,
        args,
        cwd,
        timeoutMs,
        durationMs: Date.now() - startedAt,
        exitCode,
        stdout,
        stderr,
        error,
        timedOut
      });
    });
  });
}

function compileCommand(seed: number, details: boolean, outputPath: string) {
  const args = [
    'run',
    '-v0',
    'compile-app',
    '--builddir=compile/dist-newstyle',
    '--',
    '--output',
    outputPath,
    '--target',
    'ir-json',
    '--seed',
    String(seed)
  ];

  if (details) {
    args.push('--details');
  }

  return { command: 'cabal', args };
}

function terminateCompile(pid: number | undefined, signal: NodeJS.Signals) {
  if (pid === undefined) return;

  try {
    process.kill(process.platform === 'win32' ? pid : -pid, signal);
  } catch {
    try {
      process.kill(pid, signal);
    } catch {
      // The process may already have exited between the timeout and signal.
    }
  }
}

function readCompileTimeoutMs() {
  const rawValue = process.env[compileTimeoutEnvVar];
  if (!rawValue) return defaultCompileTimeoutMs;

  const parsedValue = Number(rawValue);
  if (!Number.isInteger(parsedValue) || parsedValue <= 0) {
    return defaultCompileTimeoutMs;
  }

  return parsedValue;
}

function formatDuration(timeoutMs: number) {
  return timeoutMs % 1_000 === 0 ? `${timeoutMs / 1_000}s` : `${timeoutMs}ms`;
}
