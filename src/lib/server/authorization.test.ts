import { describe, expect, it } from 'vitest';

import { projectListOwner, requireAdmin } from './authorization';

describe('authorization boundaries', () => {
  it('denies participant access to raw developer and administration surfaces', () => {
    const participant = locals('participant', 'participant-one');
    expect(() => requireAdmin(participant)).toThrow(expect.objectContaining({ status: 403 }));
    expect(projectListOwner(participant.principal!)).toBe('participant-one');
  });

  it('allows administrators to request unscoped project data', () => {
    const admin = locals('admin', 'admin-one');
    expect(requireAdmin(admin)).toMatchObject({ kind: 'admin', user: { id: 'admin-one' } });
    expect(projectListOwner(admin.principal!)).toBeUndefined();
  });
});

function locals(kind: 'participant' | 'admin', id: string): App.Locals {
  return {
    principal: {
      kind,
      user: { id },
      session: {},
      ...(kind === 'participant' ? { participant: { participantId: id } } : {})
    }
  } as unknown as App.Locals;
}
