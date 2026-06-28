import { describe, expect, it } from 'vitest';

import { _readCompileQuery } from './+server';

describe('_readCompileQuery', () => {
  it('accepts seed and details query parameters', () => {
    expect(
      _readCompileQuery(new URL('http://localhost/api/visualization?seed=42&details=true'))
    ).toEqual({
      ok: true,
      seed: 42,
      details: true
    });
  });

  it('generates a random seed when seed is omitted', () => {
    const result = _readCompileQuery(new URL('http://localhost/api/visualization'));

    expect(result.ok).toBe(true);

    if (result.ok) {
      expect(Number.isInteger(result.seed)).toBe(true);
      expect(result.details).toBe(false);
    }
  });

  it('rejects invalid seed and details query parameters', () => {
    expect(_readCompileQuery(new URL('http://localhost/api/visualization?seed=bad'))).toEqual({
      ok: false,
      status: 400,
      error: '`seed` must be a safe integer when provided.'
    });
    expect(_readCompileQuery(new URL('http://localhost/api/visualization?details=bad'))).toEqual({
      ok: false,
      status: 400,
      error: '`details` must be `true` or `false` when provided.'
    });
  });
});
