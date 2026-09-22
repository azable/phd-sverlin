import { building } from '$app/environment';
import { json, redirect, type Handle, type ServerInit } from '@sveltejs/kit';
import { svelteKitHandler } from 'better-auth/svelte-kit';

import {
  adminSetupAvailable,
  auth,
  resolvePrincipal,
  validateAuthenticationConfiguration
} from '$lib/server/auth';
import { initializeRuntime, shutdownRuntime } from '$lib/server/runtime-state';

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
  if (building) return;
  validateAuthenticationConfiguration();
  await initializeRuntime();
  process.once('sveltekit:shutdown', () => void shutdownRuntime());
};

/** Populate Better Auth locals, enforce access, then mount its SvelteKit handler. */
export const handle: Handle = async ({ event, resolve }) => {
  if (operationalPaths.has(event.url.pathname)) {
    event.locals.session = null;
    event.locals.user = null;
    event.locals.principal = null;
    return resolve(event);
  }

  const session = await auth.api.getSession({ headers: event.request.headers });
  event.locals.session = session?.session ?? null;
  event.locals.user = session?.user ?? null;
  event.locals.principal = await resolvePrincipal(session);

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
    if (await adminSetupAvailable()) redirect(303, '/setup');
    redirect(303, `/login?next=${encodeURIComponent(next)}`);
  }

  return svelteKitHandler({ event, resolve, auth, building });
};

function isPublicPath(pathname: string) {
  return (
    publicPaths.has(pathname) || pathname.startsWith('/_app/') || pathname.startsWith('/api/auth/')
  );
}
