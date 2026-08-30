import { eq, getTableColumns } from 'drizzle-orm';
import { describe, expect, it } from 'vitest';

import { database } from './index';
import { account, session, studyEnrollments } from './schema';

describe('PostgreSQL relations', () => {
  it('constructs Better Auth joined session queries', () => {
    const query = database().query.session.findFirst({
      where: eq(session.token, 'session-token'),
      with: { user: true }
    });

    expect(query.toSQL().sql).toContain('auth_user');
  });

  it('includes Better Auth 1.7 issuer-scoped account identity', () => {
    const columns = getTableColumns(account);

    expect(columns).toHaveProperty('issuer');
    expect(account.issuer.notNull).toBe(true);
  });

  it('stores a participant gift-card URL outside project Timelines', () => {
    expect(getTableColumns(studyEnrollments)).toHaveProperty('giftCardUrl');
    expect(studyEnrollments.giftCardUrl.notNull).toBe(false);
  });
});
