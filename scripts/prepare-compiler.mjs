#!/usr/bin/env node

import { spawn } from 'node:child_process';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  compilerWorkspaceLockPath,
  compilerSourceFingerprint,
  repositoryRoot,
  writePreparedCompiler
} from '../src/lib/server/compiler/prepared-compiler.js';

const compileRoot = path.join(repositoryRoot, 'compile');

if (process.platform !== 'win32' && process.env.SVERLIN_COMPILER_LOCK_HELD !== '1') {
  const lockPath = compilerWorkspaceLockPath();
  await mkdir(path.dirname(lockPath), { recursive: true });
  const locked = await run(
    'flock',
    ['--exclusive', '--no-fork', lockPath, process.execPath, fileURLToPath(import.meta.url)],
    {
      captureStdout: false,
      cwd: process.cwd(),
      env: { ...process.env, SVERLIN_COMPILER_LOCK_HELD: '1' }
    }
  );
  process.exit(locked.exitCode);
}

const beforeBuild = await compilerSourceFingerprint();
const build = await run('stack', ['build', 'compile:compile-app', '--jobs=1'], {
  captureStdout: false
});
if (build.exitCode !== 0) process.exit(build.exitCode);

const installRoot = await run('stack', ['path', '--local-install-root'], {
  captureStdout: true
});
if (installRoot.exitCode !== 0) process.exit(installRoot.exitCode);

const binaryPath = path.join(installRoot.stdout.trim(), 'bin', 'compile-app');
const ghcEnvironment = await stackGhcEnvironment();
const afterBuild = await compilerSourceFingerprint();
if (beforeBuild !== afterBuild) {
  console.error('Compiler inputs changed during preparation; run prepare:compiler again.');
  process.exit(1);
}

await writePreparedCompiler(binaryPath, afterBuild, ghcEnvironment);
console.log(`Prepared compiler: ${binaryPath}`);

function run(command, args, options) {
  return new Promise((resolve) => {
    const child = spawn(command, args, {
      cwd: options.cwd ?? compileRoot,
      detached: process.platform !== 'win32',
      env: options.env ?? process.env,
      stdio: ['ignore', options.captureStdout ? 'pipe' : 'inherit', 'inherit']
    });
    let stdout = '';
    child.stdout?.setEncoding('utf8');
    child.stdout?.on('data', (chunk) => {
      stdout += chunk;
    });
    child.on('error', (error) => {
      console.error(error.message);
      resolve({ exitCode: 1, stdout });
    });
    child.on('close', (exitCode, signal) => {
      resolve({ exitCode: exitCode ?? signalExitCode(signal), stdout });
    });
  });
}

async function stackGhcEnvironment() {
  const [snapshotDb, localDb, packages] = await Promise.all([
    run('stack', ['path', '--snapshot-pkg-db'], { captureStdout: true }),
    run('stack', ['path', '--local-pkg-db'], { captureStdout: true }),
    run('stack', ['exec', '--', 'ghc-pkg', 'field', '*', 'id', '--simple-output'], {
      captureStdout: true
    })
  ]);
  for (const result of [snapshotDb, localDb, packages]) {
    if (result.exitCode !== 0) process.exit(result.exitCode);
  }
  return [
    'clear-package-db',
    'global-package-db',
    `package-db ${snapshotDb.stdout.trim()}`,
    `package-db ${localDb.stdout.trim()}`,
    ...packages.stdout
      .trim()
      .split(/\s+/)
      .map((packageId) => `package-id ${packageId}`),
    ''
  ].join('\n');
}

function signalExitCode(signal) {
  if (signal === 'SIGINT') return 130;
  if (signal === 'SIGTERM') return 143;
  if (signal === 'SIGKILL') return 137;
  return 1;
}
