import { chmod, mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

import { afterEach, describe, expect, it } from 'vitest';

import {
  compilerSourceFingerprint,
  CompilerNotReadyError,
  readPreparedCompiler,
  writePreparedCompiler
} from './prepared-compiler.js';

const roots: string[] = [];

afterEach(async () => {
  await Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true })));
});

describe('prepared compiler descriptor', () => {
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
});

async function fixtureRoot(): Promise<string> {
  const root = await mkdtemp(path.join(tmpdir(), 'sverlin-compiler-test-'));
  roots.push(root);
  for (const directory of [
    '.devcontainer',
    'compile/app',
    'compile/cbits',
    'compile/fonts',
    'compile/src',
    'compile/vendor'
  ]) {
    await mkdir(path.join(root, directory), { recursive: true });
  }
  await writeFile(path.join(root, '.devcontainer', 'cabal.config'), 'repository hackage\n');
  await writeFile(path.join(root, 'compile', 'cabal.project'), 'packages: .\n');
  await writeFile(path.join(root, 'compile', 'compile.cabal'), 'name: compile\n');
  await writeFile(path.join(root, 'compile', 'src', 'Fixture.hs'), 'module Fixture where\nx = 1\n');
  return root;
}

async function prepareFixture(root: string) {
  const binary = path.join(root, 'compiler');
  await writeFile(binary, '#!/bin/sh\nexit 0\n');
  await chmod(binary, 0o700);
  const fingerprint = await compilerSourceFingerprint(root);
  return writePreparedCompiler(binary, fingerprint, 'package-id compile-0.0.1\n', root);
}
