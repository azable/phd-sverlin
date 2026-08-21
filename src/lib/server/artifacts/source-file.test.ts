import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { persistSourceArtifact } from './source-file';

let tempDir: string;

beforeEach(async () => {
  tempDir = await mkdtemp(path.join(tmpdir(), 'sverlin-source-file-test-'));
});

afterEach(async () => {
  await rm(tempDir, { recursive: true, force: true });
});

describe('persistSourceArtifact', () => {
  it('atomically replaces the requested source file', async () => {
    const sourceFile = path.join(tempDir, 'Main.sverlin');

    await persistSourceArtifact('program = do\n  pure ()\n', sourceFile);

    await expect(readFile(sourceFile, 'utf8')).resolves.toBe('program = do\n  pure ()\n');
  });

  it('allows independent source files to be written concurrently', async () => {
    const first = path.join(tempDir, 'First.sverlin');
    const second = path.join(tempDir, 'Second.sverlin');

    await Promise.all([
      persistSourceArtifact('program = first\n', first),
      persistSourceArtifact('program = second\n', second)
    ]);

    await expect(readFile(first, 'utf8')).resolves.toBe('program = first\n');
    await expect(readFile(second, 'utf8')).resolves.toBe('program = second\n');
  });
});
