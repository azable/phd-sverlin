import { randomInt } from 'node:crypto';

const minSeed = 1;
const maxSeedExclusive = 2147483647;

export class InvalidCompileSeedError extends Error {
  constructor() {
    super('Seed must be a positive integer that JavaScript can represent safely.');
    this.name = 'InvalidCompileSeedError';
  }
}

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
