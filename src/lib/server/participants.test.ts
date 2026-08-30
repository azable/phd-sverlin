import { describe, expect, it } from 'vitest';

import { normalizeGiftCardUrl } from './participants';

describe('gift-card URLs', () => {
  it('normalizes an optional static HTTPS link', () => {
    expect(normalizeGiftCardUrl('')).toBeUndefined();
    expect(normalizeGiftCardUrl('  https://gift.example/card/abc  ')).toBe(
      'https://gift.example/card/abc'
    );
  });

  it('rejects unsafe or malformed URLs', () => {
    expect(() => normalizeGiftCardUrl('not a URL')).toThrow('valid gift-card URL');
    expect(() => normalizeGiftCardUrl('http://gift.example/card')).toThrow('must use HTTPS');
    expect(() => normalizeGiftCardUrl('https://user:secret@gift.example/card')).toThrow(
      'embedded credentials'
    );
    expect(() => normalizeGiftCardUrl(`https://gift.example/${'a'.repeat(2_100)}`)).toThrow(
      'cannot exceed 2048'
    );
  });
});
