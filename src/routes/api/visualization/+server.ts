import { spawn } from 'node:child_process';
import { randomInt } from 'node:crypto';
import path from 'node:path';

import { json, type RequestHandler } from '@sveltejs/kit';

import type {
  CompileDebug,
  CompiledTrace,
  VisualizationFailure,
  VisualizationSuccess
} from '$lib/visualization/types';

export const prerender = false;

type CompileRequest = {
  seed?: unknown;
  details?: unknown;
};

type ParsedCompileRequest =
  | {
      ok: true;
      seed: number;
      details: boolean;
    }
  | {
      ok: false;
      body: VisualizationFailure;
    };

type CompileRun = CompileDebug & {
  timedOut: boolean;
};

const minSeed = -2147483648;
const maxSeedExclusive = 2147483647;
const compileTimeoutMs = 60_000;

export const POST: RequestHandler = async ({ request }) => {
  const parsedRequest = await readCompileRequest(request);

  if (!parsedRequest.ok) {
    return json(parsedRequest.body, { status: 400 });
  }

  const { seed, details } = parsedRequest;
  const cwd = process.cwd();
  const command = path.join(cwd, 'compile.sh');
  const args = ['--json', '--seed', String(seed)];

  if (details) {
    args.push('--details');
  }

  const debug = await runCompile(command, args, cwd);

  if (debug.error) {
    return json(failure(debug.error, seed, details, debug), { status: 500 });
  }

  if (debug.timedOut) {
    return json(failure('Compile backend timed out.', seed, details, debug), {
      status: 504
    });
  }

  if (debug.exitCode !== 0) {
    return json(
      failure(`Compile backend exited with code ${debug.exitCode}.`, seed, details, debug),
      { status: 500 }
    );
  }

  try {
    const trace = JSON.parse(debug.stdout) as CompiledTrace;
    const body: VisualizationSuccess = {
      ok: true,
      trace,
      seed,
      details,
      debug
    };

    return json(body);
  } catch (err) {
    return json(
      failure(
        `Compile backend returned invalid JSON: ${err instanceof Error ? err.message : String(err)}`,
        seed,
        details,
        debug
      ),
      { status: 502 }
    );
  }
};

async function readCompileRequest(request: Request): Promise<ParsedCompileRequest> {
  let body: CompileRequest;

  try {
    body = (await request.json()) as CompileRequest;
  } catch {
    body = {};
  }

  if (!isRecord(body)) {
    return {
      ok: false as const,
      body: failure('Request body must be a JSON object.')
    };
  }

  const details = body.details === undefined ? false : body.details;

  if (typeof details !== 'boolean') {
    return {
      ok: false as const,
      body: failure('`details` must be a boolean when provided.')
    };
  }

  if (body.seed === undefined || body.seed === null) {
    return {
      ok: true as const,
      seed: randomInt(minSeed, maxSeedExclusive),
      details
    };
  }

  const seed = body.seed;

  if (typeof seed !== 'number' || !Number.isSafeInteger(seed)) {
    return {
      ok: false as const,
      body: failure('`seed` must be a safe integer when provided.')
    };
  }

  return {
    ok: true as const,
    seed,
    details
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
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

function failure(
  error: string,
  seed?: number,
  details?: boolean,
  debug?: CompileDebug
): VisualizationFailure {
  return {
    ok: false,
    error,
    seed,
    details,
    debug
  };
}
