import type { ActionResult } from '@sveltejs/kit';

export type ParticipantCredentials = { participantId: string; password: string };

/** Return a safe, user-facing message for a failed enhanced form action. */
export function actionFailureMessage(result: ActionResult, fallback: string): string | undefined {
  if (result.type === 'success' || result.type === 'redirect') return undefined;
  if (result.type === 'failure') {
    const error =
      result.data && typeof result.data === 'object' && 'error' in result.data
        ? result.data.error
        : undefined;
    if (typeof error === 'string' && error.trim()) return error;
  }
  return fallback;
}

/** Read the one-time participant credentials returned by create and password-reset actions. */
export function participantCredentials(result: ActionResult): ParticipantCredentials | undefined {
  if (result.type !== 'success' || !result.data || typeof result.data !== 'object')
    return undefined;
  const participantId = 'participantId' in result.data ? result.data.participantId : undefined;
  const password =
    'participantPassword' in result.data ? result.data.participantPassword : undefined;
  return typeof participantId === 'string' && typeof password === 'string'
    ? { participantId, password }
    : undefined;
}
