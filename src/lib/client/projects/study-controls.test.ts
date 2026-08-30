import { describe, expect, it } from 'vitest';

import { shouldShowPhaseExpiredDialog } from './study-controls';

describe('study workspace controls', () => {
  it('does not give participant progression controls to an inspecting administrator', () => {
    expect(shouldShowPhaseExpiredDialog(true, 'participant')).toBe(false);
  });

  it('keeps progression controls for participants and admin-owned previews', () => {
    expect(shouldShowPhaseExpiredDialog(false, 'participant')).toBe(true);
    expect(shouldShowPhaseExpiredDialog(true, 'admin-preview')).toBe(true);
  });
});
