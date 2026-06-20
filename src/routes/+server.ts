import { randomInt } from 'node:crypto';

import { json, type RequestHandler } from '@sveltejs/kit';

import { compileVisualization } from '$lib/server/compile-visualization';
import type { VisualizationFailure, VisualizationSuccess } from '$lib/visualization/types';

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

const minSeed = -2147483648;
const maxSeedExclusive = 2147483647;

export const POST: RequestHandler = async ({ request }) => {
  const parsedRequest = await readCompileRequest(request);

  if (!parsedRequest.ok) {
    return json(parsedRequest.body, { status: 400 });
  }

  const { seed, details } = parsedRequest;
  const result = await compileVisualization({ seed, details });

  if (!result.ok) {
    return json(failure(result.error, seed, details, result.debug), {
      status: result.status
    });
  }

  const body: VisualizationSuccess = {
    ok: true,
    trace: result.trace,
    seed,
    details,
    debug: result.debug
  };

  return json(body);
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
      ok: false,
      body: failure('Request body must be a JSON object.')
    };
  }

  const details = body.details === undefined ? false : body.details;

  if (typeof details !== 'boolean') {
    return {
      ok: false,
      body: failure('`details` must be a boolean when provided.')
    };
  }

  if (body.seed === undefined || body.seed === null) {
    return {
      ok: true,
      seed: randomInt(minSeed, maxSeedExclusive),
      details
    };
  }

  const seed = body.seed;

  if (typeof seed !== 'number' || !Number.isSafeInteger(seed)) {
    return {
      ok: false,
      body: failure('`seed` must be a safe integer when provided.')
    };
  }

  return {
    ok: true,
    seed,
    details
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function failure(
  error: string,
  seed?: number,
  details?: boolean,
  debug?: VisualizationFailure['debug']
): VisualizationFailure {
  return {
    ok: false,
    error,
    seed,
    details,
    debug
  };
}
