/** Participant provisioning built on Better Auth's username and admin plugins. */

import { createHash, randomBytes } from 'node:crypto';

import { and, count, desc, eq, isNotNull, isNull } from 'drizzle-orm';

import { auth } from '$lib/server/auth';
import { database } from '$lib/server/db';
import { projects, studyEnrollments, user } from '$lib/server/db/schema';
import { enrollParticipant } from '$lib/server/study';

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
  giftCardUrl?: string;
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
      giftCardUrl: studyEnrollments.giftCardUrl,
      createdAt: user.createdAt
    })
    .from(user)
    .leftJoin(projects, and(eq(projects.ownerUserId, user.id), isNull(projects.deletedAt)))
    .leftJoin(studyEnrollments, eq(studyEnrollments.userId, user.id))
    .where(and(eq(user.role, 'user'), isNotNull(user.username)))
    .groupBy(user.id, studyEnrollments.giftCardUrl)
    .orderBy(desc(user.createdAt));

  return rows.map((row) => ({
    id: row.id,
    participantId: row.participantId || row.username || row.id,
    enabled: !row.banned,
    projectCount: row.projectCount,
    ...(row.giftCardUrl ? { giftCardUrl: row.giftCardUrl } : {}),
    createdAt: row.createdAt
  }));
}

/** Assign or clear the static gift-card URL revealed after study completion. */
export async function setParticipantGiftCardUrl(userId: string, value: string): Promise<void> {
  await findParticipant(userId);
  const giftCardUrl = normalizeGiftCardUrl(value);
  const updated = await database()
    .update(studyEnrollments)
    .set({ giftCardUrl: giftCardUrl ?? null })
    .where(eq(studyEnrollments.userId, userId))
    .returning({ userId: studyEnrollments.userId });
  if (!updated[0]) throw new Error('The participant is not enrolled in the study.');
}

/** Normalize an optional HTTPS gift-card URL without fetching third-party content. */
export function normalizeGiftCardUrl(value: string): string | undefined {
  const candidate = value.trim();
  if (!candidate) return undefined;
  if (candidate.length > 2_048) throw new Error('Gift-card URLs cannot exceed 2048 characters.');
  let parsed: URL;
  try {
    parsed = new URL(candidate);
  } catch {
    throw new Error('Enter a valid gift-card URL.');
  }
  if (parsed.protocol !== 'https:') throw new Error('Gift-card URLs must use HTTPS.');
  if (parsed.username || parsed.password) {
    throw new Error('Gift-card URLs cannot contain embedded credentials.');
  }
  return parsed.toString();
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

  try {
    await enrollParticipant(result.user.id);
  } catch (cause) {
    await auth.api.removeUser({ headers, body: { userId: result.user.id } }).catch(() => undefined);
    throw cause;
  }

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
