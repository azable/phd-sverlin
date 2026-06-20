import { spawn } from 'node:child_process';
import path from 'node:path';

import type { CompileDebug, CompiledTrace } from '$lib/visualization/types';

export type CompileVisualizationOptions = {
  seed: number;
  details: boolean;
};

export type CompileVisualizationResult =
  | {
      ok: true;
      trace: CompiledTrace;
      debug: CompileDebug;
    }
  | {
      ok: false;
      error: string;
      debug: CompileDebug;
      status: number;
    };

type CompileRun = CompileDebug & {
  timedOut: boolean;
};

const compileTimeoutMs = 15_000;

export async function compileVisualization({
  seed,
  details
}: CompileVisualizationOptions): Promise<CompileVisualizationResult> {
  const cwd = process.cwd();
  const command = path.join(cwd, 'compile.sh');
  const args = ['--json', '--seed', String(seed)];

  if (details) {
    args.push('--details');
  }

  const debug = await runCompile(command, args, cwd);

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
      error: 'Compile backend timed out.',
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
      trace: JSON.parse(debug.stdout) as CompiledTrace,
      debug
    };
  } catch (err) {
    return {
      ok: false,
      error: `Compile backend returned invalid JSON: ${
        err instanceof Error ? err.message : String(err)
      }`,
      debug,
      status: 502
    };
  }
}

function runCompile(command: string, args: string[], cwd: string): Promise<CompileRun> {
  return new Promise((resolve) => {
    const startedAt = Date.now();
    const child = spawn(command, args, {
      cwd,
      stdio: ['ignore', 'pipe', 'pipe']
    });
    let stdout = '';
    let stderr = '';
    let settled = false;
    let timedOut = false;

    const timer = setTimeout(() => {
      timedOut = true;
      child.kill('SIGTERM');
    }, compileTimeoutMs);

    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');

    child.stdout.on('data', (chunk: string) => {
      stdout += chunk;
    });

    child.stderr.on('data', (chunk: string) => {
      stderr += chunk;
    });

    child.on('error', (err) => {
      if (settled) return;

      settled = true;
      clearTimeout(timer);
      resolve({
        command,
        args,
        cwd,
        durationMs: Date.now() - startedAt,
        exitCode: null,
        stdout,
        stderr,
        error: err.message,
        timedOut
      });
    });

    child.on('close', (exitCode) => {
      if (settled) return;

      settled = true;
      clearTimeout(timer);
      resolve({
        command,
        args,
        cwd,
        durationMs: Date.now() - startedAt,
        exitCode,
        stdout,
        stderr,
        timedOut
      });
    });
  });
}
