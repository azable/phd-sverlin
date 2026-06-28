import { describe, expect, it } from 'vitest';

import { runCompile } from './compile-visualization';

describe('runCompile', () => {
  it('settles when a timed-out shell command leaves child processes behind', async () => {
    const startedAt = Date.now();
    const result = await runCompile('/bin/bash', ['-c', 'sleep 10 & wait'], process.cwd(), 100);

    expect(result.timedOut).toBe(true);
    expect(result.exitCode).toBe(null);
    expect(Date.now() - startedAt).toBeLessThan(3_000);
  });
});
