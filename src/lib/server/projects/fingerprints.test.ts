import { execFile } from 'node:child_process';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { promisify } from 'node:util';

import { afterEach, describe, expect, it, vi } from 'vitest';

import {
  dslContractInputPaths,
  fingerprintRepositoryFiles
} from '$lib/server/repository-fingerprints.js';
import { readDslRevision } from './fingerprints';

const execFileAsync = promisify(execFile);
const roots: string[] = [];
const expectedContractPaths = [
  'compile/app/Sverlin/Source.hs',
  'compile/src/Sverlin.hs',
  'compile/src/Sverlin/Linear.hs',
  'src/lib/server/chat-bots/sverlin-assistant/dsl-api-index.md'
] as const;

afterEach(async () => {
  vi.restoreAllMocks();
  await Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true })));
});

describe('DSL revision', () => {
  it('uses the exact authored-contract path set', () => {
    expect(dslContractInputPaths).toEqual(expectedContractPaths);
  });

  it('combines exact contract identity with the available Git revision', async () => {
    const revision = await readDslRevision();

    expect(revision).toBeDefined();
    if (!revision) throw new Error('Expected the repository DSL contract to be available.');
    expect(revision.contentSha256).toMatch(/^[a-f0-9]{64}$/);
    expect(revision.workingTree).toMatch(/^(clean|dirty|unknown)$/);
    if (revision.repositoryCommit) {
      expect(revision.repositoryCommit).toMatch(/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/);
    }
  });

  it.each(expectedContractPaths)('tracks authored contract input %s', async (relativePath) => {
    const root = await fixtureRoot();
    const before = await fingerprintRepositoryFiles(root, dslContractInputPaths);
    await writeFile(path.join(root, relativePath), `changed ${relativePath}\n`);

    expect(await fingerprintRepositoryFiles(root, dslContractInputPaths)).not.toBe(before);
  });

  it('ignores prompt guidance and compiler implementation sources', async () => {
    const root = await fixtureRoot();
    const before = await fingerprintRepositoryFiles(root, dslContractInputPaths);
    await writeFile(
      path.join(root, 'src/lib/server/chat-bots/sverlin-assistant/dsl-interface.md'),
      'changed prompt reference\n'
    );
    await writeFile(
      path.join(root, 'compile/src/Sverlin/Internal/Render.hs'),
      'changed implementation\n'
    );

    expect(await fingerprintRepositoryFiles(root, dslContractInputPaths)).toBe(before);
  });

  it('uses the contract inputs as the Git dirty-state pathspec', async () => {
    const root = await fixtureRoot();
    await initializeGitRepository(root);
    expect((await readDslRevision(root))?.workingTree).toBe('clean');

    await writeFile(
      path.join(root, 'src/lib/server/chat-bots/sverlin-assistant/dsl-interface.md'),
      'changed prompt reference\n'
    );
    expect((await readDslRevision(root))?.workingTree).toBe('clean');

    await writeFile(path.join(root, expectedContractPaths[3]), 'changed generated API\n');
    expect((await readDslRevision(root))?.workingTree).toBe('dirty');
  });

  it('does not manufacture a digest when a contract path is missing', async () => {
    const root = await fixtureRoot();
    await rm(path.join(root, expectedContractPaths[0]));
    vi.spyOn(console, 'error').mockImplementation(() => undefined);

    await expect(readDslRevision(root)).resolves.toBeUndefined();
  });
});

async function fixtureRoot(): Promise<string> {
  const root = await mkdtemp(path.join(tmpdir(), 'sverlin-dsl-revision-test-'));
  roots.push(root);
  for (const relativePath of expectedContractPaths) {
    const destination = path.join(root, relativePath);
    await mkdir(path.dirname(destination), { recursive: true });
    await writeFile(destination, `fixture ${relativePath}\n`);
  }
  for (const relativePath of [
    'src/lib/server/chat-bots/sverlin-assistant/dsl-interface.md',
    'compile/src/Sverlin/Internal/Render.hs'
  ]) {
    const destination = path.join(root, relativePath);
    await mkdir(path.dirname(destination), { recursive: true });
    await writeFile(destination, `fixture ${relativePath}\n`);
  }
  return root;
}

async function initializeGitRepository(root: string): Promise<void> {
  await execFileAsync('git', ['init', '--quiet'], { cwd: root });
  await execFileAsync('git', ['add', '.'], { cwd: root });
  await execFileAsync(
    'git',
    [
      '-c',
      'user.name=Sverlin Test',
      '-c',
      'user.email=sverlin@example.invalid',
      'commit',
      '--quiet',
      '-m',
      'fixture'
    ],
    { cwd: root }
  );
}
