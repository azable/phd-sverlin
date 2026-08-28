import { building } from '$app/environment';
import { json, redirect, type Handle, type ServerInit } from '@sveltejs/kit';
import { svelteKitHandler } from 'better-auth/svelte-kit';

import { auth, resolvePrincipal, validateAuthenticationConfiguration } from '$lib/server/auth';
import { readMaintenanceStatus } from '$lib/server/maintenance-lock.js';

const safeMethods = new Set(['GET', 'HEAD', 'OPTIONS']);
const publicPaths = new Set([
  '/login',
  '/setup',
  '/api/health/live',
  '/api/health/ready',
  '/api/version'
]);
const operationalPaths = new Set(['/api/health/live', '/api/health/ready', '/api/version']);

/** Validate cloud configuration without starting process-owned runtime state. */
export const init: ServerInit = async () => {
  if (!building) validateAuthenticationConfiguration();
};

/** Populate Better Auth locals, enforce access, then mount its SvelteKit handler. */
export const handle: Handle = async ({ event, resolve }) => {
  if (operationalPaths.has(event.url.pathname)) {
    event.locals.session = null;
    event.locals.user = null;
    event.locals.principal = null;
    return resolve(event);
  }

  const testPrincipal = developmentTestPrincipal();
  if (testPrincipal) {
    event.locals.session = testPrincipal.session;
    event.locals.user = testPrincipal.user;
    event.locals.principal = testPrincipal;
  } else {
    const session = await auth.api.getSession({ headers: event.request.headers });
    event.locals.session = session?.session ?? null;
    event.locals.user = session?.user ?? null;
    event.locals.principal = await resolvePrincipal(session);
  }

  if (!event.locals.principal && !isPublicPath(event.url.pathname)) {
    if (event.url.pathname.startsWith('/api/')) {
      return json(
        { code: 'unauthenticated', error: 'Authentication is required or has expired.' },
        { status: 401, headers: { 'cache-control': 'private, no-store' } }
      );
    }
    const next = safeMethods.has(event.request.method.toUpperCase())
      ? `${event.url.pathname}${event.url.search}`
      : '/';
    redirect(303, `/login?next=${encodeURIComponent(next)}`);
  }

  if (
    isProjectMutation(event.request.method, event.url.pathname) &&
    !process.env.RAILWAY_ENVIRONMENT_ID
  ) {
    const maintenance = await readMaintenanceStatus();
    if (maintenance.locked) {
      return json(
        {
          code: 'app_locked',
          error: maintenance.reason || 'The application is temporarily read-only for maintenance.'
        },
        { status: 423, headers: { 'cache-control': 'private, no-store' } }
      );
    }
  }

  return testPrincipal ? resolve(event) : svelteKitHandler({ event, resolve, auth, building });
};

export function isProjectMutation(method: string, pathname: string): boolean {
  return (
    !safeMethods.has(method.toUpperCase()) && /^\/api\/(?:projects|admin)(?:\/|$)/.test(pathname)
  );
}

function isPublicPath(pathname: string) {
  return (
    publicPaths.has(pathname) || pathname.startsWith('/_app/') || pathname.startsWith('/api/auth/')
  );
}

/** Explicit non-production seam for project-focused browser tests. */
function developmentTestPrincipal() {
  if (process.env.NODE_ENV === 'production' || process.env.SVERLIN_E2E_AUTH_BYPASS !== 'true') {
    return null;
  }
  const now = new Date();
  return {
    kind: 'admin' as const,
    user: {
      id: 'sverlin-e2e-admin',
      name: 'Sverlin E2E administrator',
      email: 'e2e-admin@sverlin.invalid',
      emailVerified: true,
      image: null,
      role: 'admin',
      banned: false,
      banReason: null,
      banExpires: null,
      createdAt: now,
      updatedAt: now
    },
    session: {
      id: 'sverlin-e2e-session',
      userId: 'sverlin-e2e-admin',
      token: 'not-a-real-session-token',
      expiresAt: new Date(now.getTime() + 60 * 60 * 1000),
      ipAddress: null,
      userAgent: null,
      impersonatedBy: null,
      createdAt: now,
      updatedAt: now
    }
  };
}
