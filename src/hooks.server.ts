import { json, type Handle } from '@sveltejs/kit';

import { readMaintenanceStatus } from '$lib/server/maintenance-lock.js';

const safeMethods = new Set(['GET', 'HEAD', 'OPTIONS']);

/** Reject every project mutation while the persistent application lock is present. */
export const handle: Handle = async ({ event, resolve }) => {
  if (isProjectMutation(event.request.method, event.url.pathname)) {
    const maintenance = await readMaintenanceStatus();
    if (maintenance.locked) {
      return json(
        {
          code: 'app_locked',
          error: maintenance.reason || 'The application is temporarily read-only for maintenance.'
        },
        { status: 423 }
      );
    }
  }
  return resolve(event);
};

/** Identify mutation requests covered by the application maintenance boundary. */
export function isProjectMutation(method: string, pathname: string): boolean {
  return !safeMethods.has(method.toUpperCase()) && /^\/api\/projects(?:\/|$)/.test(pathname);
}
