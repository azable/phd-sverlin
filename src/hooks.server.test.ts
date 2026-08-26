import { describe, expect, it } from 'vitest';

import { isProjectMutation } from './hooks.server';

describe('project maintenance boundary', () => {
  it('covers current and future project mutations while leaving reads available', () => {
    expect(isProjectMutation('POST', '/api/projects')).toBe(true);
    expect(isProjectMutation('POST', '/api/projects/id')).toBe(true);
    expect(isProjectMutation('DELETE', '/api/projects/id/resources/value')).toBe(true);
    expect(isProjectMutation('GET', '/api/projects/id')).toBe(false);
    expect(isProjectMutation('POST', '/api/maintenance')).toBe(false);
  });
});
