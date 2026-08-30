/** Central authorization helpers for project and administrative routes. */

import { error } from '@sveltejs/kit';
import { and, eq, isNull } from 'drizzle-orm';

import type { Principal } from '$lib/server/auth';
import { database } from '$lib/server/db';
import { projects } from '$lib/server/db/schema';

/** Require a fully resolved, unexpired principal. */
export function requirePrincipal(locals: App.Locals): Principal {
  if (!locals.principal) error(401, 'Authentication is required or has expired.');
  return locals.principal;
}

/** Require the passkey administrator. */
export function requireAdmin(locals: App.Locals): Extract<Principal, { kind: 'admin' }> {
  const principal = requirePrincipal(locals);
  if (principal.kind !== 'admin') error(403, 'Administrator access is required.');
  return principal;
}

/** Hide projects from participants who do not own them. Administrators may inspect all projects. */
export async function requireProjectAccess(
  locals: App.Locals,
  projectId: string
): Promise<Principal> {
  const principal = requirePrincipal(locals);
  if (principal.kind === 'admin' || process.env.SVERLIN_PROJECT_STORE !== 'postgres') {
    return principal;
  }
  const row = await database()
    .select({ id: projects.id })
    .from(projects)
    .where(
      and(
        eq(projects.id, projectId),
        eq(projects.ownerUserId, principal.user.id),
        isNull(projects.deletedAt)
      )
    )
    .limit(1);
  if (!row[0]) error(404, 'Project not found.');
  return principal;
}

/** Scope project lists to a participant; administrators receive every project. */
export function projectListOwner(principal: Principal): string | undefined {
  return principal.kind === 'participant' ? principal.user.id : undefined;
}

/** Preserve the project's real owner when an administrator queues work for it. */
export async function projectCommandOwner(
  principal: Principal,
  projectId: string
): Promise<string> {
  if (principal.kind === 'participant') return principal.user.id;
  const row = await database()
    .select({ ownerUserId: projects.ownerUserId })
    .from(projects)
    .where(and(eq(projects.id, projectId), isNull(projects.deletedAt)))
    .limit(1);
  if (!row[0]) error(404, 'Project not found.');
  return row[0].ownerUserId;
}
