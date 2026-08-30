import { afterEach, expect, it } from 'vitest';
import { eq } from 'drizzle-orm';

import { adminSetupAvailable } from '$lib/server/auth';
import { database } from '$lib/server/db';
import { user } from '$lib/server/db/schema';

const enabled = Boolean(process.env.DATABASE_URL) && process.env.SVERLIN_RUN_POSTGRES_TESTS === '1';
const testAdminId = 'admin-setup-availability-test';

afterEach(async () => {
  if (!enabled) return;
  await database().delete(user).where(eq(user.id, testAdminId));
});

it.skipIf(!enabled)('offers setup only while no administrator exists', async () => {
  expect(await adminSetupAvailable()).toBe(true);

  await database().insert(user).values({
    id: testAdminId,
    name: 'Setup test administrator',
    email: 'setup-test-admin@sverlin.invalid',
    emailVerified: true,
    role: 'admin'
  });

  expect(await adminSetupAvailable()).toBe(false);
});
