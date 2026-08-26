#!/usr/bin/env node

import { spawn } from 'node:child_process';
import { writeSync } from 'node:fs';
import path from 'node:path';

import { createCompileOutput } from '../src/lib/server/compiler/workspace-output.js';
import {
  CompilerNotReadyError,
  preparedCompilerEnvironment,
  readPreparedCompiler
} from '../src/lib/server/compiler/prepared-compiler.js';
import { compileRoot, repositoryRoot as repoRoot } from './compiler-environment.mjs';

let userArgs = dropLeadingSeparator(process.argv.slice(2));
const seed = readPositiveIntFlag(userArgs, '--seed') ?? undefined;
const authoredSourcePath = readFlagValue(userArgs, '--source');
const generatedOutput = readFlagValue(userArgs, '--output')
  ? null
  : seed
    ? await createCompileOutput({ owner: 'manual', seed })
    : null;

if (generatedOutput) {
  userArgs = [...userArgs, '--output', generatedOutput.outputPath];
}

if (authoredSourcePath && readFlagValue(userArgs, '--source-label') === null) {
  userArgs = [...userArgs, '--source-label', authoredSourcePath];
}

for (const flag of ['--source', '--output', '--emit-haskell']) {
  userArgs = resolvePathFlag(userArgs, flag, repoRoot);
}

try {
  const prepared = await readPreparedCompiler();
  const result = await runCompile(
    prepared.binaryPath,
    userArgs,
    compileRoot,
    preparedCompilerEnvironment(prepared)
  );
  process.exitCode = result.exitCode ?? signalExitCode(result.signal);
} catch (error) {
  if (error instanceof CompilerNotReadyError) {
    writeSync(
      2,
      `[sverlin:compiler-not-ready] ${error.message} Run \`pnpm run prepare:compiler\`.\n`
    );
    process.exitCode = 1;
  } else {
    throw error;
  }
}

/**
 * @param {string[]} args
 */
function dropLeadingSeparator(args) {
  return args[0] === '--' ? args.slice(1) : args;
}

/**
 * @param {string[]} args
 * @param {string} flag
 */
function readFlagValue(args, flag) {
  const index = args.indexOf(flag);
  if (index === -1) return null;

  const value = args[index + 1];
  return value && !value.startsWith('--') ? value : null;
}

/**
 * @param {string[]} args
 * @param {string} flag
 */
function readPositiveIntFlag(args, flag) {
  const value = readFlagValue(args, flag);
  if (value === null) return null;

  const parsedValue = Number(value);
  return Number.isSafeInteger(parsedValue) && parsedValue > 0 ? parsedValue : null;
}

/**
 * @param {string[]} args
 * @param {string} flag
 * @param {string} root
 */
function resolvePathFlag(args, flag, root) {
  const index = args.indexOf(flag);
  if (index === -1) return args;

  const value = args[index + 1];
  if (!value || value.startsWith('--') || path.isAbsolute(value)) return args;

  const resolved = [...args];
  resolved[index + 1] = path.resolve(root, value);
  return resolved;
}

/**
 * @param {string} command
 * @param {string[]} args
 * @param {string} cwd
 * @returns {Promise<{ exitCode: number | null, signal: NodeJS.Signals | null }>}
 */
function runCompile(command, args, cwd, env) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd,
      detached: process.platform !== 'win32',
      env,
      stdio: 'inherit'
    });

    /** @type {{ signal: NodeJS.Signals, handler: () => void }[]} */
    const forwardedSignals = ['SIGINT', 'SIGTERM'].map((signal) => ({
      signal,
      handler: () => {
        terminateCompile(child.pid, signal);
      }
    }));

    for (const { signal, handler } of forwardedSignals) {
      process.once(signal, handler);
    }

    child.on('error', reject);
    child.on('close', (exitCode, signal) => {
      for (const forwardedSignal of forwardedSignals) {
        process.removeListener(forwardedSignal.signal, forwardedSignal.handler);
      }

      resolve({ exitCode, signal });
    });
  });
}

/**
 * @param {number | undefined} pid
 * @param {NodeJS.Signals} signal
 */
function terminateCompile(pid, signal) {
  if (pid === undefined) return;

  try {
    process.kill(process.platform === 'win32' ? pid : -pid, signal);
  } catch {
    try {
      process.kill(pid, signal);
    } catch {
      // The process may already have exited between the forwarded signal and kill.
    }
  }
}

/**
 * @param {NodeJS.Signals | null} signal
 */
function signalExitCode(signal) {
  if (signal === 'SIGINT') return 130;
  if (signal === 'SIGTERM') return 143;
  return 1;
}
