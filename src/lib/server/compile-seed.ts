/**
 * Validation and random selection of compiler seeds.
 *
 * @packageDocumentation
 */

import { randomInt } from 'node:crypto';

const minSeed = 1;
const maxSeedExclusive = 2147483647;

/** Raised when a requested compile seed is outside the supported integer range. */
export class InvalidCompileSeedError extends Error {
  constructor() {
    super('Seed must be a positive integer that JavaScript can represent safely.');
    this.name = 'InvalidCompileSeedError';
  }
}

/** Validate a supplied seed or choose a random positive seed when it is absent. */
export function chooseCompileSeed(value: unknown): number {
  if (value === undefined || value === null || value === '') {
    return randomInt(minSeed, maxSeedExclusive);
  }

  const seed = typeof value === 'number' ? value : Number(value);
  if (!Number.isInteger(seed) || !Number.isSafeInteger(seed) || seed < minSeed) {
    throw new InvalidCompileSeedError();
  }

  return seed;
}
