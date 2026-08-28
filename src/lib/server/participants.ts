/** Participant provisioning built on Better Auth's username and admin plugins. */

import { createHash, randomBytes } from 'node:crypto';

import { and, count, desc, eq, isNotNull, isNull } from 'drizzle-orm';

import { auth } from '$lib/server/auth';
import { database } from '$lib/server/db';
import { projects, user } from '$lib/server/db/schema';

export type IssuedParticipantCredentials = {
  userId: string;
  participantId: string;
  password: string;
};

export type ParticipantListItem = {
  id: string;
  participantId: string;
  enabled: boolean;
  projectCount: number;
  createdAt: Date;
};

/** List participant accounts with project counts, never credential secrets. */
export async function listParticipants(): Promise<ParticipantListItem[]> {
  const rows = await database()
    .select({
      id: user.id,
      participantId: user.name,
      username: user.username,
      banned: user.banned,
      projectCount: count(projects.id),
      createdAt: user.createdAt
    })
    .from(user)
    .leftJoin(projects, and(eq(projects.ownerUserId, user.id), isNull(projects.deletedAt)))
    .where(and(eq(user.role, 'user'), isNotNull(user.username)))
    .groupBy(user.id)
    .orderBy(desc(user.createdAt));

  return rows.map((row) => ({
    id: row.id,
    participantId: row.participantId || row.username || row.id,
    enabled: !row.banned,
    projectCount: row.projectCount,
    createdAt: row.createdAt
  }));
}

/** Create a participant and return the generated password exactly once. */
export async function createParticipant(
  participantId: string,
  headers: Headers
): Promise<IssuedParticipantCredentials> {
  const code = normalizeParticipantId(participantId);
  const password = generatePassword();
  const emailHash = createHash('sha256').update(code.toLowerCase()).digest('hex');
  const result = await auth.api.createUser({
    headers,
    body: {
      email: `${emailHash}@participants.sverlin.invalid`,
      password,
      name: code,
      role: 'user',
      data: { username: code }
    }
  });

  return { userId: result.user.id, participantId: code, password };
}

/** Replace a participant password and revoke their existing sessions. */
export async function resetParticipantPassword(
  userId: string,
  headers: Headers
): Promise<IssuedParticipantCredentials> {
  const row = await findParticipant(userId);
  const password = generatePassword();
  await auth.api.setUserPassword({ headers, body: { userId, newPassword: password } });
  await auth.api.revokeUserSessions({ headers, body: { userId } });
  return { userId, participantId: row.name || row.username || row.id, password };
}

/** Enable or disable a participant using Better Auth's built-in ban state. */
export async function setParticipantEnabled(
  userId: string,
  enabled: boolean,
  headers: Headers
): Promise<void> {
  await findParticipant(userId);
  if (enabled) {
    await auth.api.unbanUser({ headers, body: { userId } });
  } else {
    await auth.api.banUser({
      headers,
      body: { userId, banReason: 'Participant access disabled by the researcher.' }
    });
  }
}

async function findParticipant(userId: string) {
  const rows = await database()
    .select({ id: user.id, name: user.name, username: user.username })
    .from(user)
    .where(and(eq(user.id, userId), eq(user.role, 'user'), isNotNull(user.username)))
    .limit(1);
  if (!rows[0]) throw new Error('Participant not found.');
  return rows[0];
}

function generatePassword(): string {
  return randomBytes(18).toString('base64url');
}

function normalizeParticipantId(value: string): string {
  const participantId = value.trim();
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(participantId)) {
    throw new Error('Participant ID must use 1–128 letters, numbers, hyphens, or underscores.');
  }
  return participantId;
}
