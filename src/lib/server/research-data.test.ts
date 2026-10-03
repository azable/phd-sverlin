import { describe, expect, it } from 'vitest';

import { participantPurgeConfirmation } from './research-data-lifecycle';

describe('research data verification', () => {
  it('requires an exact participant-specific purge confirmation', () => {
    expect(participantPurgeConfirmation('P-104')).toBe('DELETE P-104');
  });
});
