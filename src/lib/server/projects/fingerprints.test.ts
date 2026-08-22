import { describe, expect, it } from 'vitest';

import { readDslRevision } from './fingerprints';

describe('DSL revision', () => {
  it('combines exact source identity with the available Git revision', async () => {
    const revision = await readDslRevision();

    expect(revision).toBeDefined();
    if (!revision) throw new Error('Expected the repository DSL sources to be available.');
    expect(revision.contentSha256).toMatch(/^[a-f0-9]{64}$/);
    expect(revision.workingTree).toMatch(/^(clean|dirty|unknown)$/);
    if (revision.repositoryCommit) {
      expect(revision.repositoryCommit).toMatch(/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/);
    }
  });
});
