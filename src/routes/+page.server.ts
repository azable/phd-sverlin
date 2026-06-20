import { randomInt } from 'node:crypto';

import { fail } from '@sveltejs/kit';

import { compileVisualization } from '$lib/server/compile-visualization';
import type { VisualizationFailure, VisualizationSuccess } from '$lib/visualization/types';

import type { Actions } from './$types';

export const prerender = false;

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

export const actions: Actions = {
  regenerate: async ({ request }) => {
    const parsedRequest = await readCompileRequest(request);

    if (!parsedRequest.ok) {
      return fail(400, parsedRequest.body);
    }

    const { seed, details } = parsedRequest;
    const result = await compileVisualization({ seed, details });

    if (!result.ok) {
      return fail(result.status, failure(result.error, seed, details, result.debug));
    }

    const body: VisualizationSuccess = {
      ok: true,
      trace: result.trace,
      seed,
      details,
      debug: result.debug
    };

    return body;
  }
};

async function readCompileRequest(request: Request): Promise<ParsedCompileRequest> {
  let formData: FormData;

  try {
    formData = await request.formData();
  } catch {
    return {
      ok: false,
      body: failure('Request body must be form data.')
    };
  }

  const detailsValue = formData.get('details');
  const details = readBoolean(detailsValue);

  if (details === null) {
    return {
      ok: false,
      body: failure('`details` must be `true` or `false` when provided.')
    };
  }

  const seedValue = formData.get('seed');

  if (seedValue === null || seedValue === '') {
    return {
      ok: true,
      seed: randomInt(minSeed, maxSeedExclusive),
      details
    };
  }

  if (typeof seedValue !== 'string') {
    return {
      ok: false,
      body: failure('`seed` must be a string integer when provided.')
    };
  }

  const seed = Number(seedValue);

  if (!Number.isInteger(seed) || !Number.isSafeInteger(seed)) {
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

function readBoolean(value: FormDataEntryValue | null): boolean | null {
  if (value === null) return false;
  if (value === 'true') return true;
  if (value === 'false') return false;

  return null;
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
