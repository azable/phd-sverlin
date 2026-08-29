import { chmod, mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

import { afterEach, describe, expect, it } from 'vitest';

import {
  compilerSourceFingerprint,
  CompilerNotReadyError,
  isUnsupportedDirectorySyncError,
  readPreparedCompiler,
  writePreparedCompiler
} from './prepared-compiler.js';

const roots: string[] = [];

afterEach(async () => {
  await Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true })));
});

describe('prepared compiler descriptor', () => {
  it.each(['EINVAL', 'ENOTSUP', 'EBADF'])(
    'accepts unsupported directory fsync error %s',
    (code) => {
      expect(
        isUnsupportedDirectorySyncError(Object.assign(new Error('fsync failed'), { code }))
      ).toBe(true);
    }
  );

  it('does not suppress unexpected directory fsync errors', () => {
    expect(
      isUnsupportedDirectorySyncError(Object.assign(new Error('fsync failed'), { code: 'EIO' }))
    ).toBe(false);
  });

  it('rejects a missing descriptor', async () => {
    const root = await fixtureRoot();
    await expect(readPreparedCompiler(root)).rejects.toBeInstanceOf(CompilerNotReadyError);
  });

  it('rejects an invalid descriptor', async () => {
    const root = await fixtureRoot();
    const descriptor = path.join(root, '.cache', 'sverlin', 'compiler.json');
    await mkdir(path.dirname(descriptor), { recursive: true });
    await writeFile(descriptor, '{"schemaVersion":1}', 'utf8');

    await expect(readPreparedCompiler(root)).rejects.toThrow(
      'The prepared compiler descriptor is invalid.'
    );
  });

  it('accepts a valid descriptor for the current repository inputs', async () => {
    const root = await fixtureRoot();
    const prepared = await prepareFixture(root);

    await expect(readPreparedCompiler(root)).resolves.toEqual(prepared);
  });

  it('rejects a descriptor after compiler inputs change', async () => {
    const root = await fixtureRoot();
    await prepareFixture(root);
    await writeFile(
      path.join(root, 'compile', 'src', 'Fixture.hs'),
      'module Fixture where\nx = 2\n'
    );

    await expect(readPreparedCompiler(root)).rejects.toThrow(
      'Compiler inputs changed after the binary was prepared.'
    );
  });

  it('rejects a descriptor after Stack replaces the local compiler package unit', async () => {
    const root = await fixtureRoot();
    const prepared = await prepareFixture(root);
    await rm(path.join(root, 'pkgdb', 'compile-0.0.1-fixture.conf'));

    await expect(readPreparedCompiler(root)).rejects.toThrow(
      'Prepared compiler package registration changed; prepare the compiler again.'
    );
    expect(prepared.sourceSha256).toBe(await compilerSourceFingerprint(root));
  });

  it('ignores Stack work products when checking compiler inputs', async () => {
    const root = await fixtureRoot();
    const prepared = await prepareFixture(root);
    const generated = path.join(root, 'compile', 'vendor', '.stack-work', 'cache');
    await mkdir(path.dirname(generated), { recursive: true });
    await writeFile(generated, 'generated\n');

    await expect(readPreparedCompiler(root)).resolves.toEqual(prepared);
  });
});

async function fixtureRoot(): Promise<string> {
  const root = await mkdtemp(path.join(tmpdir(), 'sverlin-compiler-test-'));
  roots.push(root);
  for (const directory of [
    'compile/app',
    'compile/cbits',
    'compile/fonts',
    'compile/src',
    'compile/vendor'
  ]) {
    await mkdir(path.join(root, directory), { recursive: true });
  }
  await writeFile(path.join(root, 'compile', 'compile.cabal'), 'name: compile\n');
  await writeFile(path.join(root, 'compile', 'stack.yaml'), 'resolver: lts-24.52\n');
  await writeFile(path.join(root, 'compile', 'stack.yaml.lock'), 'snapshots: []\n');
  await writeFile(path.join(root, 'compile', 'src', 'Fixture.hs'), 'module Fixture where\nx = 1\n');
  return root;
}

async function prepareFixture(root: string) {
  const binary = path.join(root, 'compiler');
  const packageDatabase = path.join(root, 'pkgdb');
  await writeFile(binary, '#!/bin/sh\nexit 0\n');
  await chmod(binary, 0o700);
  await mkdir(packageDatabase);
  await writeFile(path.join(packageDatabase, 'compile-0.0.1-fixture.conf'), 'name: compile\n');
  const fingerprint = await compilerSourceFingerprint(root);
  return writePreparedCompiler(
    binary,
    fingerprint,
    `package-db ${packageDatabase}\npackage-id compile-0.0.1-fixture\n`,
    root
  );
}
