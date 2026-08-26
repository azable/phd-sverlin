#!/usr/bin/env node

import { spawn } from 'node:child_process';

import {
  compilerSourceFingerprint,
  writePreparedCompiler
} from '../src/lib/server/compiler/prepared-compiler.js';
import { cabalConfig, cabalEnvironment, compileRoot } from './compiler-environment.mjs';

const beforeBuild = await compilerSourceFingerprint();
const common = [`--config-file=${cabalConfig}`];
const build = await run('cabal', [...common, 'build', '-v0', '--jobs=1', 'compile-app'], {
  captureStdout: false
});
if (build.exitCode !== 0) process.exit(build.exitCode);

const listed = await run('cabal', [...common, 'list-bin', '-v0', 'compile-app'], {
  captureStdout: true
});
if (listed.exitCode !== 0) process.exit(listed.exitCode);

const binaryPath = listed.stdout.trim();
const ghcEnvironment = await run(
  'cabal',
  [...common, 'exec', '-v0', '--', 'bash', '-c', 'cat "$GHC_ENVIRONMENT"'],
  { captureStdout: true }
);
if (ghcEnvironment.exitCode !== 0) process.exit(ghcEnvironment.exitCode);
const afterBuild = await compilerSourceFingerprint();
if (beforeBuild !== afterBuild) {
  console.error('Compiler inputs changed during preparation; run prepare:compiler again.');
  process.exit(1);
}

await writePreparedCompiler(binaryPath, afterBuild, ghcEnvironment.stdout);
console.log(`Prepared compiler: ${binaryPath}`);

function run(command, args, options) {
  return new Promise((resolve) => {
    const child = spawn(command, args, {
      cwd: compileRoot,
      detached: process.platform !== 'win32',
      env: cabalEnvironment,
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

function signalExitCode(signal) {
  if (signal === 'SIGINT') return 130;
  if (signal === 'SIGTERM') return 143;
  if (signal === 'SIGKILL') return 137;
  return 1;
}
