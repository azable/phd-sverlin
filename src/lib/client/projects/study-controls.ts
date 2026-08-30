/** Whether the current viewer owns the workflow represented by the timeout dialog. */
export function shouldShowPhaseExpiredDialog(
  isAdmin: boolean,
  context: 'participant' | 'admin-preview'
): boolean {
  return !isAdmin || context === 'admin-preview';
}
