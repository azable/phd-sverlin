import { describe, expect, it } from 'vitest';

import { _readCompileQuery } from './+server';

describe('_readCompileQuery', () => {
  it('accepts seed and details query parameters', () => {
    expect(
      _readCompileQuery(
        new URL('http://localhost/api/visualization?seed=42&details=true&revision=7')
      )
    ).toEqual({
      ok: true,
      seed: 42,
      details: true,
      revision: 7
    });
  });

  it('generates a random seed when seed is omitted', () => {
    const result = _readCompileQuery(new URL('http://localhost/api/visualization'));

    expect(result.ok).toBe(true);

    if (result.ok) {
      expect(Number.isInteger(result.seed)).toBe(true);
      expect(result.seed).toBeGreaterThan(0);
      expect(result.details).toBe(false);
      expect(result.revision).toBe(0);
    }
  });

  it('rejects invalid seed and details query parameters', () => {
    expect(_readCompileQuery(new URL('http://localhost/api/visualization?seed=bad'))).toEqual({
      ok: false,
      status: 400,
      error: '`seed` must be a positive safe integer when provided.'
    });
    expect(_readCompileQuery(new URL('http://localhost/api/visualization?seed=-1'))).toEqual({
      ok: false,
      status: 400,
      error: '`seed` must be a positive safe integer when provided.'
    });
    expect(_readCompileQuery(new URL('http://localhost/api/visualization?seed=0'))).toEqual({
      ok: false,
      status: 400,
      error: '`seed` must be a positive safe integer when provided.'
    });
    expect(_readCompileQuery(new URL('http://localhost/api/visualization?details=bad'))).toEqual({
      ok: false,
      status: 400,
      error: '`details` must be `true` or `false` when provided.'
    });
    expect(_readCompileQuery(new URL('http://localhost/api/visualization?revision=-1'))).toEqual({
      ok: false,
      status: 400,
      error: '`revision` must be a non-negative safe integer when provided.'
    });
  });
});
