import { describe, expect, it } from 'vitest';

import { e2eChatAdapterEnabled } from './e2e';

describe('deterministic E2E chat adapter gate', () => {
  it('requires both test bypass flags and cannot be enabled in production', () => {
    expect(
      e2eChatAdapterEnabled({
        NODE_ENV: 'test',
        SVERLIN_E2E_AUTH_BYPASS: 'true',
        SVERLIN_E2E_ASSISTANT_BYPASS: 'true'
      })
    ).toBe(true);
    expect(
      e2eChatAdapterEnabled({
        NODE_ENV: 'production',
        SVERLIN_E2E_AUTH_BYPASS: 'true',
        SVERLIN_E2E_ASSISTANT_BYPASS: 'true'
      })
    ).toBe(false);
    expect(
      e2eChatAdapterEnabled({
        SVERLIN_E2E_AUTH_BYPASS: 'true',
        SVERLIN_E2E_ASSISTANT_BYPASS: 'true'
      })
    ).toBe(false);
    expect(e2eChatAdapterEnabled({ NODE_ENV: 'test' })).toBe(false);
  });
});
