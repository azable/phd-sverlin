import { createHash } from 'node:crypto';

import { describe, expect, it } from 'vitest';

import { verifyExportResource } from './data-export';
import { participantPurgeConfirmation } from './research-data-lifecycle';

describe('research data verification', () => {
  it('requires an exact participant-specific purge confirmation', () => {
    expect(participantPurgeConfirmation('P-104')).toBe('DELETE P-104');
  });

  it('accepts bytes matching immutable resource metadata', () => {
    const bytes = Buffer.from('verified research resource');
    const digest = createHash('sha256').update(bytes).digest('hex');
    expect(() =>
      verifyExportResource(bytes, {
        resourceId: `sha256-${digest}`,
        sha256: digest,
        byteLength: bytes.byteLength
      })
    ).not.toThrow();
  });

  it('rejects truncated or substituted resources', () => {
    const expected = createHash('sha256').update('expected').digest('hex');
    expect(() =>
      verifyExportResource(Buffer.from('wrong'), {
        resourceId: `sha256-${expected}`,
        sha256: expected,
        byteLength: Buffer.byteLength('expected')
      })
    ).toThrow(/byte length|SHA-256/);
  });
});
