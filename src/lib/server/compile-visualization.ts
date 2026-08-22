import { spawn } from 'node:child_process';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';

import type {
  CompileDebug,
  CompiledVisualization,
  CompileFailureKind,
  CompilerDiagnostic
} from '$lib/visualization/types';

import { classifyCompileFailure, parseCompilerDiagnostics } from './compiler-diagnostics';
import { createCompileOutput } from './workspace-output.js';

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
      diagnostics: CompilerDiagnostic[];
      failureKind?: CompileFailureKind;
    };

export type CompileSourceOptions = {
  sourceContent: string;
  sourceLabel: string;
  seed: number;
  owner: string;
  signal?: AbortSignal;
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

export async function compileSource({
  sourceContent,
  sourceLabel,
  seed,
  owner,
  signal
}: CompileSourceOptions): Promise<CompileVisualizationResult> {
  const cwd = process.cwd();
  let outputPath: string;
  let sourcePath: string;

  try {
    const output = await createCompileOutput({ owner, seed });
    outputPath = output.outputPath;
    sourcePath = path.join(output.outputDir, 'source', 'Main.sverlin');
    await mkdir(path.dirname(sourcePath), { recursive: true });
    await writeFile(sourcePath, sourceContent, 'utf8');
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const debug = emptyCompileDebug(cwd, message);
    return {
      ok: false,
      error: message,
      debug,
      status: 500,
      diagnostics: diagnosticsForFailure(debug, message),
      failureKind: 'infrastructure'
    };
  }

  const { command, args } = compileCommand(seed, outputPath, sourcePath, sourceLabel);

  const timeoutMs = readCompileTimeoutMs();
  let debug = await runCompile(command, args, cwd, timeoutMs, {
    signal
  });
  let compiledJson = '';

  try {
    compiledJson = await readFile(outputPath, 'utf8');
  } catch {
    compiledJson = '';
  }

  debug = { ...debug, outputPath };
  if (debug.error) {
    const diagnostics = diagnosticsForFailure(debug, debug.error);
    return {
      ok: false,
      error: debug.error,
      debug,
      status: 500,
      diagnostics,
      failureKind: classifyCompileFailure(debug)
    };
  }

  if (debug.timedOut) {
    const error = `Compile backend timed out after ${formatDuration(timeoutMs)}.`;
    return {
      ok: false,
      error,
      debug,
      status: 504,
      diagnostics: diagnosticsForFailure(debug, error),
      failureKind: 'timeout'
    };
  }

  if (debug.exitCode !== 0) {
    const error = `Compile backend exited with code ${debug.exitCode}.`;
    return {
      ok: false,
      error,
      debug,
      status: 500,
      diagnostics: diagnosticsForFailure(debug, error),
      failureKind: classifyCompileFailure(debug)
    };
  }

  try {
    return {
      ok: true,
      trace: JSON.parse(compiledJson) as CompiledVisualization,
      debug
    };
  } catch (err) {
    const error = `Compile backend wrote invalid JSON: ${
      err instanceof Error ? err.message : String(err)
    }`;
    return {
      ok: false,
      error,
      debug,
      status: 502,
      diagnostics: diagnosticsForFailure(debug, error),
      failureKind: 'invalid-output'
    };
  }
}

function diagnosticsForFailure(debug: CompileDebug, fallback: string) {
  const parsed = parseCompilerDiagnostics(debug.stderr);
  return parsed.length > 0
    ? parsed
    : [{ severity: 'unknown' as const, message: fallback, raw: fallback }];
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

export function compileCommand(
  seed: number,
  outputPath: string,
  sourcePath: string,
  sourceLabel: string
) {
  const args = [
    'scripts/run-compile.mjs',
    '--',
    '--source',
    sourcePath,
    '--source-label',
    sourceLabel,
    '--output',
    outputPath,
    '--target',
    'ir-json',
    '--details',
    '--seed',
    String(seed)
  ];

  return { command: 'node', args };
}

function emptyCompileDebug(cwd: string, error: string): CompileDebug {
  return {
    command: 'node',
    args: [],
    cwd,
    durationMs: 0,
    exitCode: null,
    stdout: '',
    stderr: error
  };
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
