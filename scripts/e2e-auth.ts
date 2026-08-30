import { createHmac } from 'node:crypto';

export const e2eAuthSecret = 'sverlin-e2e-better-auth-secret-2026';
export const e2eSessionToken = 'sverlin-e2e-session-token';

// One hour comfortably covers compiler preparation and the browser suite without
// leaving the disposable test-database session valid beyond the test process.
const e2eSessionLifetimeMs = 60 * 60 * 1_000;

export function e2eSessionExpiresAt(): Date {
  return new Date(Date.now() + e2eSessionLifetimeMs);
}

export function e2eSessionCookieValue(): string {
  const signature = createHmac('sha256', e2eAuthSecret).update(e2eSessionToken).digest('base64');
  return `${e2eSessionToken}.${signature}`;
}
