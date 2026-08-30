import type { ActionResult } from '@sveltejs/kit';

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
