/** Central authorization helpers for project and administrative routes. */

import { error } from '@sveltejs/kit';
import { and, eq, isNull } from 'drizzle-orm';

import type { Principal } from '$lib/server/auth';
import { database } from '$lib/server/db';
import { projects, user } from '$lib/server/db/schema';
import {
  assertParticipantStudyMutation,
  studyProjectContext,
  type StudyProjectContext
} from '$lib/server/study';

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
  if (principal.kind === 'admin') return principal;
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

export type ProjectInspectionContext = {
  principal: Principal;
  ownerUserId: string;
  participantLabel?: string;
  study?: StudyProjectContext;
  readOnly: boolean;
};

/** Resolve the owner, study association, and authoritative inspection mode for a project. */
export async function projectInspectionContext(
  locals: App.Locals,
  projectId: string
): Promise<ProjectInspectionContext> {
  const principal = await requireProjectAccess(locals, projectId);
  const [owner, study] = await Promise.all([
    projectOwner(projectId),
    studyProjectContext(projectId)
  ]);
  const participantLabel =
    owner.role === 'user' && owner.username
      ? owner.name || owner.username || owner.ownerUserId
      : undefined;
  const readOnly =
    principal.kind === 'admin'
      ? !!participantLabel ||
        study?.mode === 'participant' ||
        (study?.mode === 'preview' &&
          (!study.isCurrent ||
            !study.active ||
            study.expired ||
            study.ownerUserId !== principal.user.id))
      : !study || !study.isCurrent || !study.active || study.expired;
  return {
    principal,
    ownerUserId: owner.ownerUserId,
    ...(participantLabel ? { participantLabel } : {}),
    ...(study ? { study } : {}),
    readOnly
  };
}

/** Enforce project mutation policy for every principal before accepting a command. */
export async function requireProjectMutationAccess(
  locals: App.Locals,
  projectId: string
): Promise<ProjectInspectionContext> {
  const context = await projectInspectionContext(locals, projectId);
  if (context.principal.kind === 'participant') {
    await assertParticipantStudyMutation(context.principal, projectId);
    return context;
  }
  if (context.readOnly) error(403, 'Participant research data is read-only for administrators.');
  return context;
}

/** Scope project lists to a participant; administrators receive every project. */
export function projectListOwner(principal: Principal): string | undefined {
  return principal.kind === 'participant' ? principal.user.id : undefined;
}

async function projectOwner(projectId: string) {
  const [row] = await database()
    .select({
      ownerUserId: projects.ownerUserId,
      name: user.name,
      username: user.username,
      role: user.role
    })
    .from(projects)
    .innerJoin(user, eq(user.id, projects.ownerUserId))
    .where(and(eq(projects.id, projectId), isNull(projects.deletedAt)))
    .limit(1);
  if (!row) error(404, 'Project not found.');
  return row;
}
